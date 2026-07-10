#include "mediacodec_native.h"

#ifdef __ANDROID__
#include "nf_log.h"
#include <cstring>
#include <dlfcn.h>
#include <unistd.h>

namespace godot {

namespace {
using AHardwareBufferGetIdFn = int (*)(const AHardwareBuffer *, uint64_t *);

AHardwareBufferGetIdFn get_hardware_buffer_id_fn() {
    static auto fn = reinterpret_cast<AHardwareBufferGetIdFn>(
        dlsym(RTLD_DEFAULT, "AHardwareBuffer_getId"));
    return fn;
}

bool query_hardware_buffer_id(AHardwareBuffer *buffer, uint64_t &out_id) {
    auto fn = get_hardware_buffer_id_fn();
    return buffer && fn && fn(buffer, &out_id) == 0 && out_id != 0;
}
} // namespace

AndroidMediaCodec::AndroidMediaCodec() = default;

AndroidMediaCodec::~AndroidMediaCodec() {
    shutdown();
}

bool AndroidMediaCodec::init(const char *mime, int width, int height) {
    width_ = width;
    height_ = height;

    // Create ImageReader with GPU sampling usage for direct Vulkan import
    media_status_t status = AImageReader_newWithUsage(
        width_, height_, AIMAGE_FORMAT_YUV_420_888,
        AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE | AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN | AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN, 4, &reader_);
    if (status != AMEDIA_OK || !reader_) {
        NF_LOGE("AndroidMediaCodec", "AImageReader_newWithUsage failed: %d", status);
        return false;
    }

    AImageReader_BufferRemovedListener listener{};
    listener.context = this;
    listener.onBufferRemoved = &AndroidMediaCodec::_on_buffer_removed;
    status = AImageReader_setBufferRemovedListener(reader_, &listener);
    if (status == AMEDIA_OK) {
        buffer_cache_supported_.store(true);
        NF_LOG("AndroidMediaCodec", "AHardwareBuffer import cache enabled (%s keys)",
               get_hardware_buffer_id_fn() ? "stable ID" : "opaque handle");
    } else {
        // Decoding remains available with the original per-frame import path.
        NF_LOGE("AndroidMediaCodec", "AHardwareBuffer import cache disabled; buffer listener failed: %d", status);
    }

    status = AImageReader_getWindow(reader_, &window_);
    if (status != AMEDIA_OK || !window_) {
        NF_LOGE("AndroidMediaCodec", "AImageReader_getWindow failed: %d", status);
        buffer_cache_supported_.store(false);
        AImageReader_delete(reader_);
        reader_ = nullptr;
        return false;
    }

    // Create and configure MediaCodec
    codec_ = AMediaCodec_createDecoderByType(mime);
    if (!codec_) {
        NF_LOGE("AndroidMediaCodec", "AMediaCodec_createDecoderByType failed for %s", mime);
        ANativeWindow_release(window_);
        window_ = nullptr;
        AImageReader_delete(reader_);
        reader_ = nullptr;
        return false;
    }

    // Configure with the ImageReader's ANativeWindow for Surface output
    AMediaFormat *format = AMediaFormat_new();
    AMediaFormat_setString(format, AMEDIAFORMAT_KEY_MIME, mime);
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_WIDTH, width);
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_HEIGHT, height);
    AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_MAX_INPUT_SIZE, width * height);

    status = AMediaCodec_configure(codec_, format, window_, nullptr, 0);
    AMediaFormat_delete(format);

    if (status != AMEDIA_OK) {
        NF_LOGE("AndroidMediaCodec", "AMediaCodec_configure failed: %d", status);
        AMediaCodec_delete(codec_);
        codec_ = nullptr;
        ANativeWindow_release(window_);
        window_ = nullptr;
        AImageReader_delete(reader_);
        reader_ = nullptr;
        return false;
    }

    status = AMediaCodec_start(codec_);
    if (status != AMEDIA_OK) {
        NF_LOGE("AndroidMediaCodec", "AMediaCodec_start failed: %d", status);
        AMediaCodec_delete(codec_);
        codec_ = nullptr;
        ANativeWindow_release(window_);
        window_ = nullptr;
        AImageReader_delete(reader_);
        reader_ = nullptr;
        return false;
    }

    started_.store(true);
    eos_.store(false);
    input_pts_counter_ = 0;
    NF_LOG("AndroidMediaCodec", "Initialized: %dx%d mime=%s", width, height, mime);
    return true;
}

void AndroidMediaCodec::shutdown() {
    started_.store(false);
    if (codec_) {
        // Send EOS to flush
        if (!eos_.load()) {
            ssize_t idx = AMediaCodec_dequeueInputBuffer(codec_, 1000);
            if (idx >= 0) {
                size_t buf_size;
                uint8_t *buf = AMediaCodec_getInputBuffer(codec_, (size_t)idx, &buf_size);
                if (buf) {
                    AMediaCodec_queueInputBuffer(codec_, (size_t)idx, 0, 0, 0,
                        AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
                }
            }
        }
        AMediaCodec_stop(codec_);
        AMediaCodec_delete(codec_);
        codec_ = nullptr;
    }
    if (window_) {
        ANativeWindow_release(window_);
        window_ = nullptr;
    }
    if (reader_) {
        buffer_cache_supported_.store(false);
        AImageReader_delete(reader_);
        reader_ = nullptr;
    }
    {
        std::lock_guard<std::mutex> lock(removed_buffers_mutex_);
        removed_buffer_ids_.clear();
    }
}

bool AndroidMediaCodec::get_buffer_id(AHardwareBuffer *buffer, uint64_t &out_id) const {
    return buffer_cache_supported_.load() && query_hardware_buffer_id(buffer, out_id);
}

void AndroidMediaCodec::take_removed_buffer_ids(std::vector<uint64_t> &out_ids) {
    std::lock_guard<std::mutex> lock(removed_buffers_mutex_);
    out_ids.swap(removed_buffer_ids_);
}

void AndroidMediaCodec::_on_buffer_removed(void *context, AImageReader *,
                                            AHardwareBuffer *buffer) {
    auto *self = static_cast<AndroidMediaCodec *>(context);
    if (!self || !self->buffer_cache_supported_.load()) return;

    uint64_t buffer_id = 0;
    if (!query_hardware_buffer_id(buffer, buffer_id)) {
        // API 26-30 have removal callbacks but no documented stable ID API.
        // Retained imported memory keeps this opaque handle alive, so use the
        // same best-effort identity as the decode path on those releases.
        buffer_id = (uint64_t)buffer;
    }

    std::lock_guard<std::mutex> lock(self->removed_buffers_mutex_);
    self->removed_buffer_ids_.push_back(buffer_id);
}

bool AndroidMediaCodec::feed_packet(const uint8_t *data, size_t size, int64_t pts) {
    if (!started_.load() || !codec_) return false;

    ssize_t idx = AMediaCodec_dequeueInputBuffer(codec_, 5000);
    if (idx < 0) {
        static int fail_count = 0;
        if (++fail_count <= 3)
            NF_LOGE("AndroidMediaCodec", "dequeueInputBuffer failed: %zd", (ssize_t)idx);
        return false;
    }

    size_t buf_size;
    uint8_t *buf = AMediaCodec_getInputBuffer(codec_, (size_t)idx, &buf_size);
    if (!buf || buf_size < size) {
        static int fail_count = 0;
        if (++fail_count <= 3)
            NF_LOGE("AndroidMediaCodec", "getInputBuffer failed: buf=%p size=%zu needed=%zu",
                   (void*)buf, (size_t)buf_size, size);
        return false;
    }

    memcpy(buf, data, size);
    uint32_t flags = 0;
    AMediaCodec_queueInputBuffer(codec_, (size_t)idx, 0, size, (uint64_t)pts, flags);
    return true;
}

bool AndroidMediaCodec::dequeue_frame(NativeDecodedFrame &out_frame, int64_t timeout_us) {
    if (!started_.load() || !codec_ || !reader_) return false;

    AMediaCodecBufferInfo info;
    ssize_t idx = AMediaCodec_dequeueOutputBuffer(codec_, &info, timeout_us);

    if (idx == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
        // Format changed - get new format
        AMediaFormat *fmt = AMediaCodec_getOutputFormat(codec_);
        if (fmt) {
            int32_t w = 0, h = 0;
            AMediaFormat_getInt32(fmt, AMEDIAFORMAT_KEY_WIDTH, &w);
            AMediaFormat_getInt32(fmt, AMEDIAFORMAT_KEY_HEIGHT, &h);
            if (w > 0) width_ = w;
            if (h > 0) height_ = h;
            NF_LOG("AndroidMediaCodec", "Output format changed: %dx%d", width_, height_);
            AMediaFormat_delete(fmt);
        }
        return false;
    }

    if (idx == AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED) {
        return false;
    }

    if (idx == AMEDIACODEC_INFO_TRY_AGAIN_LATER) {
        return false;
    }

    if (idx < 0) {
        return false;
    }

    if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) {
        eos_.store(true);
        return false;
    }

    // Render the output buffer to the ImageReader Surface
    AMediaCodec_releaseOutputBuffer(codec_, (size_t)idx, true);

    // Acquire the rendered image from ImageReader
    AImage *image = nullptr;
    media_status_t status = AImageReader_acquireLatestImage(reader_, &image);

    if (status == AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE) {
        // Image not ready yet - retry with short wait
        for (int retry = 0; retry < 10; retry++) {
            usleep(1000); // 1ms
            status = AImageReader_acquireLatestImage(reader_, &image);
            if (status == AMEDIA_OK && image) break;
        }
    }

    if (status != AMEDIA_OK || !image) {
        static int imgfail = 0;
        if (++imgfail <= 3)
            NF_LOGE("AndroidMediaCodec", "acquireLatestImage failed: %d", status);
        return false;
    }

    AHardwareBuffer *ahb = nullptr;
    status = AImage_getHardwareBuffer(image, &ahb);
    if (status != AMEDIA_OK || !ahb) {
        static int ahbfail = 0;
        if (++ahbfail <= 3)
            NF_LOGE("AndroidMediaCodec", "AImage_getHardwareBuffer failed: %d", status);
        AImage_delete(image);
        return false;
    }

    AHardwareBuffer_acquire(ahb); // Add our reference

    out_frame.buffer = ahb;
    out_frame.pts = info.presentationTimeUs;
    out_frame.width = width_;
    out_frame.height = height_;
    out_frame.image = image;

    static int frame_count = 0;
    if (++frame_count <= 5 || frame_count % 60 == 0)
        NF_LOG("AndroidMediaCodec", "Frame ready: %dx%d pts=%lld buf=%p",
               width_, height_, (long long)info.presentationTimeUs, (void*)ahb);

    return true;
}

void AndroidMediaCodec::release_frame(NativeDecodedFrame &frame) {
    if (frame.image) {
        AImage_delete(frame.image);
        frame.image = nullptr;
    }
    if (frame.buffer) {
        AHardwareBuffer_release(frame.buffer);
        frame.buffer = nullptr;
    }
}

} // namespace godot

#endif // __ANDROID__
