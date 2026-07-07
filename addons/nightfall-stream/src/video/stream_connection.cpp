#include "stream_connection.h"
#include "ffmpeg_decoder.h"
#include "texture_uploader.h"
#include "audio/audio_renderer.h"
#include "input/input_bridge.h"
#include "video/depth_bridge.h"
#include "video/codec_defs.h"
#ifdef __ANDROID__
#include "video/mediacodec_internal.h"
#include "video/mediacodec_native.h"
#include <jni.h>
#include <android/hardware_buffer.h>
#include <media/NdkImageReader.h>
AHardwareBuffer *mediacodec_get_ahb(jobject media_codec_obj, ssize_t buffer_index);
#endif
#ifdef __ANDROID__
#include "video/mediacodec_internal.h"
#include <jni.h>
#include <android/hardware_buffer.h>
AHardwareBuffer *mediacodec_get_ahb(jobject media_codec_obj, ssize_t buffer_index);
#endif

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <cstring>

extern "C" {
#include <libavutil/pixdesc.h>
}

#include "nf_log.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/pixfmt.h>
#include <libavutil/frame.h>
}

#include <cstdarg>

using namespace godot;

StreamConnection *StreamConnection::active_instance_ = nullptr;

StreamConnection::StreamConnection() {
    decoder_.instantiate();
    uploader_.instantiate();
    audio_renderer_.instantiate();
    input_bridge_.instantiate();
    depth_bridge_.instantiate();
}

StreamConnection::~StreamConnection() {
    stop();
    if (h264_extradata_) {
        av_freep(&h264_extradata_);
        h264_extradata_size_ = 0;
    }
}

bool StreamConnection::_extract_h264_sps_pps(const uint8_t *data, int size,
                                               uint8_t **sps, int *sps_size,
                                               uint8_t **pps, int *pps_size) {
    *sps = nullptr; *sps_size = 0;
    *pps = nullptr; *pps_size = 0;

    int i = 0;
    while (i < size - 3) {
        int sc_size = 0;
        if (i + 3 < size && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1) {
            sc_size = 4;
        } else if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
            sc_size = 3;
        }

        if (sc_size > 0) {
            int nalu_start = i + sc_size;
            if (nalu_start >= size) break;

            int nalu_type = data[nalu_start] & 0x1f;

            int nalu_end = size;
            for (int j = nalu_start + 1; j < size - 2; j++) {
                if ((data[j] == 0 && data[j+1] == 0 && data[j+2] == 1) ||
                    (j + 3 < size && data[j] == 0 && data[j+1] == 0 && data[j+2] == 0 && data[j+3] == 1)) {
                    nalu_end = j;
                    while (nalu_end > nalu_start && data[nalu_end - 1] == 0) nalu_end--;
                    break;
                }
            }

            int nalu_len = nalu_end - nalu_start;

            if (nalu_type == 7 && !*sps) {
                *sps = (uint8_t *)av_malloc(nalu_len);
                memcpy(*sps, data + nalu_start, nalu_len);
                *sps_size = nalu_len;
            } else if (nalu_type == 8 && !*pps) {
                *pps = (uint8_t *)av_malloc(nalu_len);
                memcpy(*pps, data + nalu_start, nalu_len);
                *pps_size = nalu_len;
            }

            i = nalu_start;
            if (*sps && *pps) return true;
        } else {
            i++;
        }
    }

    return (*sps && *pps);
}

uint8_t *StreamConnection::_build_avcc_extradata(const uint8_t *sps, int sps_size,
                                                   const uint8_t *pps, int pps_size,
                                                   int *out_size) {
    int total = 8 + sps_size + 3 + pps_size;
    uint8_t *ed = (uint8_t *)av_mallocz(total + AV_INPUT_BUFFER_PADDING_SIZE);
    if (!ed) return nullptr;

    int pos = 0;
    ed[pos++] = 0x01;
    ed[pos++] = sps[0];
    ed[pos++] = sps[1];
    ed[pos++] = sps[2];
    ed[pos++] = 0xFF;
    ed[pos++] = 0xE1;
    ed[pos++] = (sps_size >> 8) & 0xFF;
    ed[pos++] = sps_size & 0xFF;
    memcpy(ed + pos, sps, sps_size);
    pos += sps_size;
    ed[pos++] = 0x01;
    ed[pos++] = (pps_size >> 8) & 0xFF;
    ed[pos++] = pps_size & 0xFF;
    memcpy(ed + pos, pps, pps_size);
    pos += pps_size;

    *out_size = pos;
    return ed;
}

void StreamConnection::_try_h264_hw_upgrade() {
    if (!h264_hw_upgrade_pending_.load() || h264_hw_upgraded_.load()) return;
    if (!h264_extradata_ || h264_extradata_size_ == 0) return;

    h264_hw_upgrade_pending_.store(false);

    int ret = decoder_->upgrade_to_mediacodec(h264_extradata_, h264_extradata_size_);
    if (ret == 0) {
        h264_hw_upgraded_.store(true);

        uploader_->setup(decoder_->get_video_width(), decoder_->get_video_height(),
                         AV_PIX_FMT_NV12,
                         (int)AVCOL_SPC_BT709,
                         (int)AVCOL_RANGE_UNSPECIFIED);

        LiRequestIdrFrame();

        call_deferred("emit_signal", "h264_hw_upgraded");
    } else {
        NF_LOGE("StreamConnection", "H.264 HW upgrade failed (%d)", ret);
    }

    av_freep(&h264_extradata_);
    h264_extradata_size_ = 0;
}

int StreamConnection::_cb_decoder_setup(int videoFormat, int width, int height, int redrawRate, void *context, int drFlags) {
    auto *self = active_instance_;
    if (!self) return -1;

    self->h264_hw_upgrade_pending_.store(false);
    self->h264_hw_upgraded_.store(false);
    if (self->h264_extradata_) {
        av_freep(&self->h264_extradata_);
        self->h264_extradata_size_ = 0;
    }

    self->active_video_format_ = videoFormat;
    NF_LOG("StreamConnection", "Decoder setup: format=0x%x %dx%d@%dfps local_capture=%d", videoFormat, width, height, redrawRate, self->local_capture_mode_);

    if (self->local_capture_mode_) {
        NF_LOG("StreamConnection", "Local capture mode: skipping Sunshine decoder/uploader setup");
        self->decoder_ready_.store(true);
        return 0;
    }

#ifdef __ANDROID__
    // Android: ONLY native NDK MediaCodec + ImageReader for zero-copy GPU decode.
    // No FFmpeg fallback. Must fail loudly if unavailable.
    if (videoFormat & VIDEO_FORMAT_MASK_H265) {
        self->native_codec_ = new AndroidMediaCodec();
        if (self->native_codec_->init("video/hevc", width, height)) {
            NF_LOG("StreamConnection", "Native MediaCodec created: %dx%d", width, height);
            uploader_->setup(width, height, AV_PIX_FMT_NV12, (int)AVCOL_SPC_BT709, (int)AVCOL_RANGE_UNSPECIFIED);
            self->decoder_ready_.store(true);
            return 0;
        }
        NF_LOGE("StreamConnection", "FATAL: Native MediaCodec init failed");
        delete self->native_codec_;
        self->native_codec_ = nullptr;
        return -1;
    }
    NF_LOGE("StreamConnection", "FATAL: Unsupported video format 0x%x on Android", videoFormat);
    return -1;
#else
    int ret = self->decoder_->setup(videoFormat, width, height, false);
    if (ret != 0) {
        NF_LOGE("StreamConnection", "Decoder setup FAILED: ret=%d", ret);
        return ret;
    }

    NF_LOG("StreamConnection", "Decoder opened: name=%s hw=%s raw=%s", 
           self->decoder_->get_decoder_name().utf8().get_data(),
           self->decoder_->is_hw_decode() ? "yes" : "no",
           self->decoder_->is_raw_decode() ? "yes" : "no");

    int pix_fmt = AV_PIX_FMT_YUV420P;
    if (self->decoder_->is_raw_decode()) {
        pix_fmt = AV_PIX_FMT_NV12;
    } else if (self->decoder_->is_hw_decode()) {
        pix_fmt = AV_PIX_FMT_NV12;
    }
    NF_LOG("StreamConnection", "Uploader setup: %dx%d pix_fmt=%d", width, height, pix_fmt);

    self->uploader_->setup(width, height,
                           pix_fmt,
                           (int)AVCOL_SPC_BT709,
                           (int)AVCOL_RANGE_UNSPECIFIED);

    self->decoder_ready_.store(true);
    return 0;
#endif
}

void StreamConnection::_cb_decoder_start() {
    NF_LOG("StreamConnection", "Decoder start");
}

void StreamConnection::_cb_decoder_stop() {
    NF_LOG("StreamConnection", "Decoder stop");
    auto *self = active_instance_;
    if (self) {
        self->decoder_ready_.store(false);
    }
}

void StreamConnection::_cb_decoder_cleanup() {
    NF_LOG("StreamConnection", "Decoder cleanup");
    auto *self = active_instance_;
    if (self) {
        if (!self->local_capture_mode_) {
            self->decoder_->cleanup();
            self->uploader_->cleanup();
        }
#ifdef __ANDROID__
        if (self->native_codec_) {
            self->native_codec_->shutdown();
            delete self->native_codec_;
            self->native_codec_ = nullptr;
        }
#endif
        self->decoder_ready_.store(false);
        self->h264_hw_upgrade_pending_.store(false);
        self->h264_hw_upgraded_.store(false);
        if (self->h264_extradata_) {
            av_freep(&self->h264_extradata_);
            self->h264_extradata_size_ = 0;
        }
    }
}

int StreamConnection::_cb_submit_decode_unit(PDECODE_UNIT decodeUnit) {
    auto *self = active_instance_;
    if (!self || !self->is_streaming_.load()) return DR_OK;

    static int submit_count = 0;
    submit_count++;
    if (submit_count <= 3) {
        NF_LOG("StreamConnection", "Submit DU #%d: size=%d type=%d frame=%d",
               submit_count, decodeUnit->fullLength, decodeUnit->frameType,
               decodeUnit->frameNumber);
    }

    if (self->local_capture_mode_) {
        return DR_OK;
    }

    AVPacket *pkt = av_packet_alloc();
    if (!pkt) return DR_OK;

    int ret = av_new_packet(pkt, decodeUnit->fullLength);
    if (ret < 0) {
        av_packet_free(&pkt);
        return DR_OK;
    }

    int offset = 0;
    PLENTRY entry = decodeUnit->bufferList;
    while (entry != nullptr) {
        if (offset + entry->length <= decodeUnit->fullLength) {
            memcpy(pkt->data + offset, entry->data, entry->length);
            offset += entry->length;
        }
        entry = entry->next;
    }

    pkt->pts = decodeUnit->presentationTimeUs;

#if defined(__ANDROID__)
    {
        auto *self = active_instance_;
        if (self && !self->h264_extradata_ && self->active_video_format_ == 0x1) {
            uint8_t *sps = nullptr, *pps = nullptr;
            int sps_size = 0, pps_size = 0;
            if (_extract_h264_sps_pps(pkt->data, pkt->size, &sps, &sps_size, &pps, &pps_size)) {
                self->h264_extradata_ = _build_avcc_extradata(sps, sps_size, pps, pps_size, &self->h264_extradata_size_);
                if (self->h264_extradata_) {
                    self->h264_hw_upgrade_pending_.store(true);
                }
                av_freep(&sps);
                av_freep(&pps);
            }
        }
    }
#endif

    auto now = std::chrono::steady_clock::now();
    auto now_us = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()).count();
    self->last_submit_time_us_.store(now_us);

    {
        std::lock_guard<std::mutex> lock(self->queue_mutex_);
        if (self->packet_queue_.size() > 512) {
            av_packet_free(&pkt);
            self->frames_dropped_.fetch_add(1);
            return DR_OK;
        }
        if (!self->decoder_->is_hw_decode() && self->packet_queue_.size() > 128) {
            self->_clear_packet_queue();
            LiRequestIdrFrame();
            av_packet_free(&pkt);
            self->frames_dropped_.fetch_add(1);
            return DR_NEED_IDR;
        }
        self->packet_queue_.push_back(pkt);
    }
    self->queue_cv_.notify_one();

    return DR_OK;
}

void StreamConnection::_cb_connection_started() {
    NF_LOG("StreamConnection", "Connection started");
    auto *self = active_instance_;
    if (self) {
        self->is_streaming_.store(true);
        self->call_deferred("emit_signal", "stream_started");
    }
}

void StreamConnection::_cb_connection_terminated(int errorCode) {
    NF_LOG("StreamConnection", "Connection terminated: %d", errorCode);
    auto *self = active_instance_;
    if (self) {
        if (self->local_capture_mode_ && (errorCode == ML_ERROR_NO_VIDEO_TRAFFIC || errorCode == ML_ERROR_NO_VIDEO_FRAME)) {
            NF_LOG("StreamConnection", "Bypassing video watchdog timeout in local capture mode");
            return;
        }
        self->is_streaming_.store(false);
        self->queue_cv_.notify_all();
        self->call_deferred("emit_signal", "stream_terminated", errorCode, get_error_string(errorCode));
    }
}

void StreamConnection::_cb_stage_starting(int stage) {
    NF_LOG("StreamConnection", "Stage starting: %s", LiGetStageName(stage));
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "stage_starting", String(LiGetStageName(stage)));
    }
}

void StreamConnection::_cb_stage_complete(int stage) {
    NF_LOG("StreamConnection", "Stage complete: %s", LiGetStageName(stage));
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "stage_complete", String(LiGetStageName(stage)));
    }
}

void StreamConnection::_cb_stage_failed(int stage, int errorCode) {
    NF_LOG("StreamConnection", "Stage failed: %s (error %d)", LiGetStageName(stage), errorCode);
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "stage_failed", String(LiGetStageName(stage)), errorCode);
    }
}

void StreamConnection::_cb_rumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "controller_rumble", (int)controllerNumber, (int)lowFreqMotor, (int)highFreqMotor);
    }
}

void StreamConnection::_cb_connection_status_update(int connectionStatus) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "connection_status_update", connectionStatus);
    }
}

void StreamConnection::_cb_set_hdr_mode(bool hdrEnabled) {
    auto *self = active_instance_;
    if (self) {
        Dictionary metadata;
        if (hdrEnabled) {
            SS_HDR_METADATA hdr_data;
            if (LiGetHdrMetadata(&hdr_data)) {
                Array primaries_x, primaries_y;
                primaries_x.push_back(hdr_data.displayPrimaries[0].x);
                primaries_x.push_back(hdr_data.displayPrimaries[1].x);
                primaries_x.push_back(hdr_data.displayPrimaries[2].x);
                primaries_y.push_back(hdr_data.displayPrimaries[0].y);
                primaries_y.push_back(hdr_data.displayPrimaries[1].y);
                primaries_y.push_back(hdr_data.displayPrimaries[2].y);
                metadata["display_primaries_x"] = primaries_x;
                metadata["display_primaries_y"] = primaries_y;
                metadata["white_point_x"] = hdr_data.whitePoint.x;
                metadata["white_point_y"] = hdr_data.whitePoint.y;
                metadata["min_display_luminance"] = hdr_data.minDisplayLuminance;
                metadata["max_display_luminance"] = hdr_data.maxDisplayLuminance;
                metadata["max_content_light_level"] = hdr_data.maxContentLightLevel;
                metadata["max_frame_average_light_level"] = hdr_data.maxFrameAverageLightLevel;
            }
        }
        self->call_deferred("emit_signal", "hdr_mode_changed", hdrEnabled, metadata);
    }
}

void StreamConnection::_cb_rumble_triggers(uint16_t controllerNumber, uint16_t leftTriggerMotor, uint16_t rightTriggerMotor) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "controller_trigger_rumble", (int)controllerNumber, (int)leftTriggerMotor, (int)rightTriggerMotor);
    }
}

void StreamConnection::_cb_set_motion_event_state(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "motion_event_requested", (int)controllerNumber, (int)motionType, (int)reportRateHz);
    }
}

void StreamConnection::_cb_set_controller_led(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "controller_led_set", (int)controllerNumber, (int)r, (int)g, (int)b);
    }
}

void StreamConnection::_cb_log_message(const char *format, ...) {
    va_list args;
    va_start(args, format);
    char buffer[2048];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "log_message", String(buffer));
    }
}

AVColorSpace StreamConnection::_resolve_frame_colorspace(AVFrame *frame) const {
    if (!frame) return AVCOL_SPC_BT709;

    bool hdr_trc = frame->color_trc == AVCOL_TRC_SMPTE2084 || frame->color_trc == AVCOL_TRC_ARIB_STD_B67;
    bool hdr_primaries = frame->color_primaries == AVCOL_PRI_BT2020;
    if (hdr_trc || hdr_primaries) {
        return AVCOL_SPC_BT2020_NCL;
    }

    AVColorSpace declared = (AVColorSpace)frame->colorspace;
    if (declared == AVCOL_SPC_UNSPECIFIED || declared == AVCOL_SPC_RGB) {
        if (active_video_format_ & VIDEO_FORMAT_MASK_RAW) {
            return AVCOL_SPC_BT709;
        }
        bool is_h264 = (active_video_format_ & VIDEO_FORMAT_MASK_H264) && !(active_video_format_ & (VIDEO_FORMAT_MASK_H265 | VIDEO_FORMAT_MASK_AV1));
#ifdef __ANDROID__
        if (is_h264) {
            return AVCOL_SPC_BT470BG;
        }
        return (frame->width >= 1280 || frame->height >= 720) ? AVCOL_SPC_BT709 : AVCOL_SPC_BT470BG;
#else
        if (is_h264) {
            return AVCOL_SPC_BT470BG;
        }
        return (frame->width <= 1024 && frame->height <= 576) ? AVCOL_SPC_BT470BG : AVCOL_SPC_BT709;
#endif
    }

    return declared;
}

void StreamConnection::_connection_thread_func() {
    DECODER_RENDERER_CALLBACKS drCallbacks{};
    LiInitializeVideoCallbacks(&drCallbacks);
    drCallbacks.setup = _cb_decoder_setup;
    drCallbacks.start = _cb_decoder_start;
    drCallbacks.stop = _cb_decoder_stop;
    drCallbacks.cleanup = _cb_decoder_cleanup;
    drCallbacks.submitDecodeUnit = _cb_submit_decode_unit;
    drCallbacks.capabilities = 0;

    AUDIO_RENDERER_CALLBACKS arCallbacks{};
    LiInitializeAudioCallbacks(&arCallbacks);
    arCallbacks.init = AudioRenderer::_cb_init;
    arCallbacks.start = AudioRenderer::_cb_start;
    arCallbacks.stop = AudioRenderer::_cb_stop;
    arCallbacks.cleanup = AudioRenderer::_cb_cleanup;
    arCallbacks.decodeAndPlaySample = AudioRenderer::_cb_decode_and_play_sample;
    arCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;

    CONNECTION_LISTENER_CALLBACKS clCallbacks{};
    LiInitializeConnectionCallbacks(&clCallbacks);
    clCallbacks.stageStarting = _cb_stage_starting;
    clCallbacks.stageComplete = _cb_stage_complete;
    clCallbacks.stageFailed = _cb_stage_failed;
    clCallbacks.connectionStarted = _cb_connection_started;
    clCallbacks.connectionTerminated = _cb_connection_terminated;
    clCallbacks.rumble = _cb_rumble;
    clCallbacks.connectionStatusUpdate = _cb_connection_status_update;
    clCallbacks.setHdrMode = _cb_set_hdr_mode;
    clCallbacks.rumbleTriggers = _cb_rumble_triggers;
    clCallbacks.setMotionEventState = _cb_set_motion_event_state;
    clCallbacks.setControllerLED = _cb_set_controller_led;
    clCallbacks.logMessage = _cb_log_message;

    // In local capture mode, skip audio entirely - audio is already on the machine
    PAUDIO_RENDERER_CALLBACKS arPtr = local_capture_mode_ ? nullptr : &arCallbacks;

    int ret = LiStartConnection(&server_info_, &stream_config_, &clCallbacks, &drCallbacks, arPtr, nullptr, 0, nullptr, 0);

    if (ret != 0) {
        is_streaming_.store(false);
        queue_cv_.notify_all();
        call_deferred("emit_signal", "stream_terminated", ret, get_error_string(ret));
    }
}

void StreamConnection::_decode_thread_func() {
    AVPacket *pkt = nullptr;

    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        queue_cv_.wait_for(lock, std::chrono::milliseconds(10000), [this] {
            return is_streaming_.load() || !packet_queue_.empty();
        });
        if (!is_streaming_.load()) return;
    }

    while (true) {
        {
            std::unique_lock<std::mutex> lock(queue_mutex_);
            queue_cv_.wait(lock, [this] {
                return !packet_queue_.empty() || !is_streaming_.load();
            });

            if (!is_streaming_.load() && packet_queue_.empty()) break;

            if (packet_queue_.empty()) continue;

            pkt = packet_queue_.front();
            packet_queue_.erase(packet_queue_.begin());
        }

        if (!pkt) continue;

#ifdef __ANDROID__
        if (native_codec_) {
            // Native MediaCodec path: feed raw packet data, get AHB frames
            int send_ret = native_codec_->feed_packet(pkt->data, (size_t)pkt->size, pkt->pts);
            av_packet_free(&pkt);
            if (!send_ret) continue;

            // Try to dequeue frames
            NativeDecodedFrame frame;
            while (native_codec_->dequeue_frame(frame, 1000)) {
                RenderingDevice *rd = RenderingServer::get_singleton()
                    ? RenderingServer::get_singleton()->get_rendering_device() : nullptr;
                if (rd && rd->has_method("texture_create_from_android_hardware_buffer") && frame.buffer) {
                    int usage = (int)(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT |
                                     RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT |
                                     RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
                    Variant tex_rid_var = rd->call("texture_create_from_android_hardware_buffer",
                        (uint64_t)frame.buffer,
                        (int)RenderingDevice::DATA_FORMAT_R8G8B8A8_UNORM,
                        frame.width, frame.height, usage);
                    RID tex_rid = tex_rid_var;
                    if (tex_rid.is_valid()) {
                        uploader_->ensure_shader_material();
                        uploader_->set_texture_from_native_rid(tex_rid, frame.width, frame.height);
                        frames_decoded_.fetch_add(1);

                        auto decode_done = std::chrono::steady_clock::now();
                        auto decode_done_us = std::chrono::duration_cast<std::chrono::microseconds>(
                            decode_done.time_since_epoch()).count();
                        int64_t submit_us = last_submit_time_us_.load();
                        if (submit_us > 0 && decode_done_us > submit_us)
                            last_frame_latency_us_.store((int)(decode_done_us - submit_us));

                        static int log_count = 0;
                        if (++log_count <= 5)
                            NF_LOG("StreamConnection", "Native GPU frame: %dx%d", frame.width, frame.height);
                    }
                }
                native_codec_->release_frame(frame);
            }
            continue; // Skip FFmpeg path
        }
#endif

        if (decoder_->is_raw_decode()) {
            if (pkt->size >= (int)sizeof(RawFrameHeader)) {
                RawFrameHeader hdr;
                memcpy(&hdr, pkt->data, sizeof(hdr));
                if (hdr.magic[0] == 'R' && hdr.magic[1] == 'A' && hdr.magic[2] == 'W' && hdr.magic[3] == 'F') {
                    int w = hdr.width;
                    int h = hdr.height;
                    uint32_t expected_y = (uint32_t)w * h;
                    uint32_t expected_uv = (uint32_t)w * (h / 2);
                    if (hdr.y_size == expected_y && hdr.uv_size == expected_uv &&
                        pkt->size >= (int)(sizeof(RawFrameHeader) + expected_y + expected_uv)) {
                        frames_decoded_.fetch_add(1);

                        auto decode_done = std::chrono::steady_clock::now();
                        auto decode_done_us = std::chrono::duration_cast<std::chrono::microseconds>(decode_done.time_since_epoch()).count();
                        int64_t submit_us = last_submit_time_us_.load();
                        if (submit_us > 0 && decode_done_us > submit_us) {
                            last_frame_latency_us_.store((int)(decode_done_us - submit_us));
                        }

                        if (current_colorspace_ != AVCOL_SPC_BT709) {
                            current_colorspace_ = AVCOL_SPC_BT709;
                            current_color_range_ = AVCOL_RANGE_UNSPECIFIED;
                            uploader_->update_colorspace((int)AVCOL_SPC_BT709, (int)AVCOL_RANGE_UNSPECIFIED);
                        }

                        const uint8_t *payload = pkt->data + sizeof(RawFrameHeader);
                        uploader_->update_from_raw_nv12(w, h, payload, hdr.y_size, hdr.uv_size);
                    }
                }
            }
            av_packet_free(&pkt);
            continue;
        }

        {
            AVCodecContext *ctx = decoder_->get_codec_context();
            if (!ctx) {
                av_packet_free(&pkt);
                continue;
            }

            if (decoder_->is_hw_decode() && ctx->codec_id == AV_CODEC_ID_H264) {
                int out_size = pkt->size + 1024;
                uint8_t *out = (uint8_t *)av_malloc(out_size + AV_INPUT_BUFFER_PADDING_SIZE);
                if (out) {
                    int out_pos = 0;
                    int i = 0;
                    while (i < pkt->size - 3) {
                        int sc_len = 0;
                        if (i + 3 < pkt->size && pkt->data[i] == 0 && pkt->data[i+1] == 0 && pkt->data[i+2] == 0 && pkt->data[i+3] == 1) {
                            sc_len = 4;
                        } else if (pkt->data[i] == 0 && pkt->data[i+1] == 0 && pkt->data[i+2] == 1) {
                            sc_len = 3;
                        }

                        if (sc_len == 0) { i++; continue; }

                        int nalu_start = i + sc_len;
                        int nalu_end = pkt->size;
                        for (int j = nalu_start + 1; j < pkt->size - 2; j++) {
                            if ((pkt->data[j] == 0 && pkt->data[j+1] == 0 && pkt->data[j+2] == 1) ||
                                (j + 3 < pkt->size && pkt->data[j] == 0 && pkt->data[j+1] == 0 && pkt->data[j+2] == 0 && pkt->data[j+3] == 1)) {
                                nalu_end = j;
                                break;
                            }
                        }

                        int nalu_len = nalu_end - nalu_start;
                        if (out_pos + 4 + nalu_len > out_size) break;

                        out[out_pos++] = (nalu_len >> 24) & 0xFF;
                        out[out_pos++] = (nalu_len >> 16) & 0xFF;
                        out[out_pos++] = (nalu_len >> 8) & 0xFF;
                        out[out_pos++] = nalu_len & 0xFF;
                        memcpy(out + out_pos, pkt->data + nalu_start, nalu_len);
                        out_pos += nalu_len;

                        i = nalu_end;
                    }

                    av_packet_unref(pkt);
                    av_new_packet(pkt, out_pos);
                    memcpy(pkt->data, out, out_pos);
                    av_freep(&out);
                }
            }

            int send_ret = avcodec_send_packet(ctx, pkt);

            av_packet_free(&pkt);

            if (send_ret < 0 && send_ret != AVERROR(EAGAIN) && send_ret != AVERROR_EOF) {
                continue;
            }

            while (true) {
                AVFrame *tmp = av_frame_alloc();
                int recv_ret = avcodec_receive_frame(ctx, tmp);

                if (recv_ret == AVERROR(EAGAIN) || recv_ret == AVERROR_EOF) {
                    av_frame_free(&tmp);
                    break;
                }
                if (recv_ret < 0) {
                    av_frame_free(&tmp);
                    break;
                }

                if (h264_hw_upgrade_pending_.load() && !h264_hw_upgraded_.load()) {
                    _try_h264_hw_upgrade();
                    if (h264_hw_upgraded_.load()) {
                        av_frame_free(&tmp);
                        break;
                    }
                }

                auto frame_count = frames_decoded_.fetch_add(1) + 1;

                auto decode_done = std::chrono::steady_clock::now();
                auto decode_done_us = std::chrono::duration_cast<std::chrono::microseconds>(decode_done.time_since_epoch()).count();
                int64_t submit_us = last_submit_time_us_.load();
                if (submit_us > 0 && decode_done_us > submit_us) {
                    last_frame_latency_us_.store((int)(decode_done_us - submit_us));
                }

                AVFrame *final_frame = tmp;
                AVFrame *sw_frame = nullptr;
                bool used_ahb = false;
                if (tmp->hw_frames_ctx) {
                    // AHardwareBuffer GPU-only path (Android, custom Godot build).
                    // No fallback — must succeed or frame is discarded.
#ifdef __ANDROID__
                    if (decoder_->get_codec_context()) {
                        jobject codec_obj = (jobject)mediacodec_get_codec_object(
                            decoder_->get_codec_context());
                        ssize_t buf_idx = mediacodec_get_buffer_index(tmp);
                        if (codec_obj && buf_idx >= 0) {
                            AHardwareBuffer *ahb = mediacodec_get_ahb(codec_obj, buf_idx);
                            if (ahb) {
                                AHardwareBuffer_Desc desc;
                                AHardwareBuffer_describe(ahb, &desc);
                                int w = desc.width;
                                int h = desc.height;

                                RenderingDevice *rd = RenderingServer::get_singleton()
                                    ? RenderingServer::get_singleton()->get_rendering_device()
                                    : nullptr;

                                if (rd && rd->has_method("texture_create_from_android_hardware_buffer")) {
                                    int usage = (int)(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
                                    Variant tex_rid_var = rd->call("texture_create_from_android_hardware_buffer",
                                        (uint64_t)ahb, (int)RenderingDevice::DATA_FORMAT_R8G8B8A8_UNORM, w, h, usage);
                                    RID tex_rid = tex_rid_var;
                                    if (tex_rid.is_valid()) {
                                        uploader_->ensure_shader_material();
                                        uploader_->set_texture_from_native_rid(tex_rid, w, h);
                                        used_ahb = true;
                                    } else {
                                        NF_LOGE("StreamConnection", "Tier1: texture_create_from_android_hardware_buffer returned invalid RID!");
                                    }
                                } else {
                                    NF_LOGE("StreamConnection", "Tier1: Godot API texture_create_from_android_hardware_buffer not available. Custom engine build required.");
                                }
                                AHardwareBuffer_release(ahb);
                            } else {
                                NF_LOGE("StreamConnection", "Tier1: mediacodec_get_ahb returned null");
                            }
                        } else {
                            NF_LOGE("StreamConnection", "Tier1: cannot get MediaCodec object or buffer index");
                        }
                    }
#endif
                    if (!used_ahb) {
                        // Fallback: av_hwframe_map/transfer (legacy path)
                        sw_frame = av_frame_alloc();
                        int transfer_ret = av_hwframe_map(sw_frame, tmp, AV_HWFRAME_MAP_READ);
                        if (transfer_ret < 0) {
                            transfer_ret = av_hwframe_transfer_data(sw_frame, tmp, 0);
                        }
                        if (transfer_ret >= 0) {
                            av_frame_copy_props(sw_frame, tmp);
                            final_frame = sw_frame;
                        } else {
                            av_frame_free(&sw_frame);
                            sw_frame = nullptr;
                        }
                    }
                }

                if (frame_count <= 5 || frame_count % 60 == 0) {
                    NF_LOG("StreamConnection", "Frame #%d: pix_fmt=%d(%s) %dx%d colorspace=%d range=%d hw=%s",
                           frame_count, final_frame->format,
                           av_get_pix_fmt_name((AVPixelFormat)final_frame->format),
                           final_frame->width, final_frame->height,
                           (int)final_frame->colorspace, (int)final_frame->color_range,
                           final_frame->hw_frames_ctx ? "yes" : "no");
                }

                AVColorSpace frame_cs = _resolve_frame_colorspace(final_frame);
                AVColorRange frame_cr = (AVColorRange)final_frame->color_range;
                if (frame_cs != current_colorspace_ || frame_cr != current_color_range_) {
                    current_colorspace_ = frame_cs;
                    current_color_range_ = frame_cr;
                    uploader_->update_colorspace((int)frame_cs, (int)frame_cr);
                }

                if (!used_ahb) {
                    uploader_->update_from_frame(final_frame);
                }

                if (sw_frame) {
                    av_frame_free(&sw_frame);
                }
                av_frame_free(&tmp);
            }
        }
    }

    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        _clear_packet_queue();
    }
}

void StreamConnection::_clear_packet_queue() {
    for (auto *p : packet_queue_) {
        av_packet_free(&p);
    }
    packet_queue_.clear();
}

void StreamConnection::start(const String &host, const Dictionary &server_info, const Dictionary &stream_config, bool disable_hw) {
    if (connection_thread_.joinable()) {
        is_streaming_.store(false);
        decoder_ready_.store(false);
        queue_cv_.notify_all();
        LiInterruptConnection();
        connection_thread_.join();
        LiStopConnection();
    }

    if (decode_thread_.joinable()) {
        decode_thread_.join();
    }

    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        _clear_packet_queue();
    }

    host_address_ = host;

    LiInitializeServerInformation(&server_info_);
    host_address_std_ = host.utf8().get_data();
    server_info_.address = host_address_std_.c_str();

    if (server_info.has("rtsp_session_url")) {
        rtsp_url_std_ = String(server_info["rtsp_session_url"]).utf8().get_data();
        server_info_.rtspSessionUrl = rtsp_url_std_.c_str();
    }
    if (server_info.has("server_app_version")) {
        app_version_std_ = String(server_info["server_app_version"]).utf8().get_data();
        server_info_.serverInfoAppVersion = app_version_std_.c_str();
    }
    if (server_info.has("server_gfe_version")) {
        gfe_version_std_ = String(server_info["server_gfe_version"]).utf8().get_data();
        server_info_.serverInfoGfeVersion = gfe_version_std_.c_str();
    }
    if (server_info.has("server_codec_mode_support")) {
        server_info_.serverCodecModeSupport = (int)server_info["server_codec_mode_support"];
    }

    LiInitializeStreamConfiguration(&stream_config_);
    stream_config_.width = (int)stream_config.get("width", 1920);
    stream_config_.height = (int)stream_config.get("height", 1080);
    stream_config_.fps = (int)stream_config.get("fps", 60);
    stream_config_.bitrate = (int)stream_config.get("bitrate", 20000);
    stream_config_.packetSize = (int)stream_config.get("packet_size", 1024);
    stream_config_.streamingRemotely = (int)stream_config.get("streaming_remotely", STREAM_CFG_AUTO);
    stream_config_.audioConfiguration = (int)stream_config.get("audio_configuration", AUDIO_CONFIGURATION_STEREO);
    stream_config_.supportedVideoFormats = (int)stream_config.get("supported_video_formats", VIDEO_FORMAT_MASK_H264);
    stream_config_.clientRefreshRateX100 = (int)stream_config.get("client_refresh_rate_x100", 0);
    stream_config_.colorSpace = (int)stream_config.get("color_space", COLORSPACE_REC_709);
    stream_config_.colorRange = (int)stream_config.get("color_range", COLOR_RANGE_LIMITED);
    stream_config_.encryptionFlags = (int)stream_config.get("encryption_flags", ENCFLG_ALL);

    NF_LOG("StreamConnection", "Starting stream: %dx%d@%d %dkbps fmt=0x%x colorspace=%d range=%d pkt=%d",
           stream_config_.width, stream_config_.height, stream_config_.fps,
           stream_config_.bitrate, stream_config_.supportedVideoFormats,
           stream_config_.colorSpace, stream_config_.colorRange,
           stream_config_.packetSize);

    if (stream_config.has("remote_input_aes_key")) {
        PackedByteArray key = stream_config["remote_input_aes_key"];
        if (key.size() == 16) {
            memcpy(stream_config_.remoteInputAesKey, key.ptr(), 16);
        }
    }
    if (stream_config.has("remote_input_aes_iv")) {
        PackedByteArray iv = stream_config["remote_input_aes_iv"];
        if (iv.size() == 16) {
            memcpy(stream_config_.remoteInputAesIv, iv.ptr(), 16);
        }
    }

    active_instance_ = this;
    AudioRenderer::active_instance_ = audio_renderer_.ptr();
    last_idr_request_ = std::chrono::steady_clock::now();

    connection_thread_ = std::thread(&StreamConnection::_connection_thread_func, this);
    decode_thread_ = std::thread(&StreamConnection::_decode_thread_func, this);
}

void StreamConnection::stop() {
    if (!is_streaming_.load() && !connection_thread_.joinable()) return;

    is_streaming_.store(false);
    decoder_ready_.store(false);
    queue_cv_.notify_all();

    LiInterruptConnection();

    if (connection_thread_.joinable()) {
        connection_thread_.join();
    }

    LiStopConnection();

    if (decode_thread_.joinable()) {
        decode_thread_.join();
    }

    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        _clear_packet_queue();
    }

    if (audio_renderer_.is_valid()) {
        audio_renderer_->cleanup();
    }

    active_instance_ = nullptr;
    AudioRenderer::active_instance_ = nullptr;
}

bool StreamConnection::is_streaming() const {
    return is_streaming_.load();
}

void StreamConnection::set_local_capture_mode(bool enabled) {
    local_capture_mode_ = enabled;
}

bool StreamConnection::get_local_capture_mode() const {
    return local_capture_mode_;
}

int StreamConnection::probe_video_format(int codec_preference, bool disable_hw) {
    if (!decoder_.is_valid()) return VIDEO_FORMAT_MASK_H264;
    return decoder_->probe_video_format(codec_preference, disable_hw);
}

Dictionary StreamConnection::probe_all_video_formats() {
    Dictionary result;
    if (!decoder_.is_valid()) {
        result["h264"] = true;
        result["hevc"] = false;
        result["av1"] = false;
        result["raw"] = true;
        return result;
    }
    int h264_mask = decoder_->probe_video_format(FfmpegDecoder::CODEC_FAMILY_H264, false);
    result["h264"] = (h264_mask & VIDEO_FORMAT_MASK_H264) != 0;

    int hevc_mask = decoder_->probe_video_format(FfmpegDecoder::CODEC_FAMILY_H265, false);
    result["hevc"] = (hevc_mask & VIDEO_FORMAT_MASK_H265) != 0;

    int av1_mask = decoder_->probe_video_format(FfmpegDecoder::CODEC_FAMILY_AV1, false);
    result["av1"] = (av1_mask & VIDEO_FORMAT_MASK_AV1) != 0;

    result["raw"] = true;
    return result;
}

int StreamConnection::get_server_codec_mode_support() const {
    return server_info_.serverCodecModeSupport;
}

Ref<FfmpegDecoder> StreamConnection::get_decoder() const {
    return decoder_;
}

Ref<TextureUploader> StreamConnection::get_texture_uploader() const {
    return uploader_;
}

Ref<ShaderMaterial> StreamConnection::get_shader_material() const {
    if (uploader_.is_valid()) {
        return uploader_->get_shader_material();
    }
    return nullptr;
}

Ref<AudioRenderer> StreamConnection::get_audio_renderer() const {
    return audio_renderer_;
}

Ref<InputBridge> StreamConnection::get_input_bridge() const {
    return input_bridge_;
}

Ref<DepthBridge> StreamConnection::get_depth_bridge() const {
    return depth_bridge_;
}

int StreamConnection::get_frames_dropped() const {
    return frames_dropped_.load();
}

int StreamConnection::get_frames_decoded() const {
    return frames_decoded_.load();
}

int StreamConnection::get_decode_queue_size() const {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    return (int)packet_queue_.size();
}

int StreamConnection::get_last_frame_latency_us() const {
    return last_frame_latency_us_.load();
}

String StreamConnection::get_decoder_name() const {
    if (decoder_.is_valid()) return decoder_->get_decoder_name();
    return "";
}

int StreamConnection::get_video_width() const {
    if (decoder_.is_valid()) return decoder_->get_video_width();
    return 0;
}

int StreamConnection::get_video_height() const {
    if (decoder_.is_valid()) return decoder_->get_video_height();
    return 0;
}

bool StreamConnection::is_hw_decode() const {
    if (decoder_.is_valid()) return decoder_->is_hw_decode();
    return false;
}

String StreamConnection::get_error_string(int error_code) {
    switch (error_code) {
        case ML_ERROR_GRACEFUL_TERMINATION:
            return "Connection terminated gracefully";
        case ML_ERROR_NO_VIDEO_TRAFFIC:
            return "Terminating connection due to lack of video traffic";
        case ML_ERROR_NO_VIDEO_FRAME:
            return "No video frame received";
        case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
            return "Unexpected early termination";
        case ML_ERROR_PROTECTED_CONTENT:
            return "Protected content detected";
        case ML_ERROR_FRAME_CONVERSION:
            return "Frame conversion error";
        default:
            if (error_code > 0)
                return "Connection error: " + String::num_int64(error_code);
            return "Unknown error (" + String::num_int64(error_code) + ")";
    }
}

void StreamConnection::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start", "host", "server_info", "stream_config", "disable_hw"), &StreamConnection::start, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("stop"), &StreamConnection::stop);
    ClassDB::bind_method(D_METHOD("is_streaming"), &StreamConnection::is_streaming);
    ClassDB::bind_method(D_METHOD("set_local_capture_mode", "enabled"), &StreamConnection::set_local_capture_mode);
    ClassDB::bind_method(D_METHOD("get_local_capture_mode"), &StreamConnection::get_local_capture_mode);
    ClassDB::bind_method(D_METHOD("probe_video_format", "codec_preference", "disable_hw"), &StreamConnection::probe_video_format);
    ClassDB::bind_method(D_METHOD("probe_all_video_formats"), &StreamConnection::probe_all_video_formats);
    ClassDB::bind_method(D_METHOD("get_server_codec_mode_support"), &StreamConnection::get_server_codec_mode_support);
    ClassDB::bind_method(D_METHOD("get_decoder"), &StreamConnection::get_decoder);
    ClassDB::bind_method(D_METHOD("get_texture_uploader"), &StreamConnection::get_texture_uploader);
    ClassDB::bind_method(D_METHOD("get_shader_material"), &StreamConnection::get_shader_material);
    ClassDB::bind_method(D_METHOD("get_audio_renderer"), &StreamConnection::get_audio_renderer);
    ClassDB::bind_method(D_METHOD("get_input_bridge"), &StreamConnection::get_input_bridge);
    ClassDB::bind_method(D_METHOD("get_depth_bridge"), &StreamConnection::get_depth_bridge);
    ClassDB::bind_method(D_METHOD("get_frames_dropped"), &StreamConnection::get_frames_dropped);
    ClassDB::bind_method(D_METHOD("get_frames_decoded"), &StreamConnection::get_frames_decoded);
    ClassDB::bind_method(D_METHOD("get_decode_queue_size"), &StreamConnection::get_decode_queue_size);
    ClassDB::bind_method(D_METHOD("get_last_frame_latency_us"), &StreamConnection::get_last_frame_latency_us);
    ClassDB::bind_method(D_METHOD("get_decoder_name"), &StreamConnection::get_decoder_name);
    ClassDB::bind_method(D_METHOD("get_video_width"), &StreamConnection::get_video_width);
    ClassDB::bind_method(D_METHOD("get_video_height"), &StreamConnection::get_video_height);
    ClassDB::bind_method(D_METHOD("is_hw_decode"), &StreamConnection::is_hw_decode);
    ClassDB::bind_static_method("StreamConnection", D_METHOD("get_error_string", "error_code"), &StreamConnection::get_error_string);

    ADD_SIGNAL(MethodInfo("stream_started"));
    ADD_SIGNAL(MethodInfo("stream_terminated", PropertyInfo(Variant::INT, "error_code"), PropertyInfo(Variant::STRING, "error_message")));
    ADD_SIGNAL(MethodInfo("stage_starting", PropertyInfo(Variant::STRING, "stage_name")));
    ADD_SIGNAL(MethodInfo("stage_complete", PropertyInfo(Variant::STRING, "stage_name")));
    ADD_SIGNAL(MethodInfo("stage_failed", PropertyInfo(Variant::STRING, "stage_name"), PropertyInfo(Variant::INT, "error_code")));
    ADD_SIGNAL(MethodInfo("controller_rumble", PropertyInfo(Variant::INT, "controller"), PropertyInfo(Variant::INT, "low_freq"), PropertyInfo(Variant::INT, "high_freq")));
    ADD_SIGNAL(MethodInfo("controller_trigger_rumble", PropertyInfo(Variant::INT, "controller"), PropertyInfo(Variant::INT, "left_motor"), PropertyInfo(Variant::INT, "right_motor")));
    ADD_SIGNAL(MethodInfo("motion_event_requested", PropertyInfo(Variant::INT, "controller"), PropertyInfo(Variant::INT, "motion_type"), PropertyInfo(Variant::INT, "rate_hz")));
    ADD_SIGNAL(MethodInfo("controller_led_set", PropertyInfo(Variant::INT, "controller"), PropertyInfo(Variant::INT, "r"), PropertyInfo(Variant::INT, "g"), PropertyInfo(Variant::INT, "b")));
    ADD_SIGNAL(MethodInfo("connection_status_update", PropertyInfo(Variant::INT, "status")));
    ADD_SIGNAL(MethodInfo("hdr_mode_changed", PropertyInfo(Variant::BOOL, "hdr_enabled"), PropertyInfo(Variant::DICTIONARY, "metadata")));
    ADD_SIGNAL(MethodInfo("log_message", PropertyInfo(Variant::STRING, "message")));
    ADD_SIGNAL(MethodInfo("h264_hw_upgraded"));
}
