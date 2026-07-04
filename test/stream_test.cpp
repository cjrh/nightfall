// Standalone CLI test: connects to Moonlight/Sunshine, decodes video, logs diagnostics.
// Usage: stream_test <server_ip> <rtsp_session_url>
// Build: added as separate CMake target in nightfall-stream CMakeLists.txt
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <csignal>
#include <atomic>
#include <thread>
#include <chrono>

extern "C" {
#include <Limelight.h>
#include <libavcodec/avcodec.h>
#include <libavutil/pixdesc.h>
}

static std::atomic<bool> running{false};
static std::atomic<bool> decoder_ready{false};
static std::atomic<int> frame_count{0};
static std::atomic<int> g_packet_count{0};
static AVCodecContext *g_ctx = nullptr;
static const AVCodec *g_codec = nullptr;
static bool g_is_hw = false;
static int g_width = 0, g_height = 0;

// --- Callbacks ---
static int dr_setup(int videoFormat, int width, int height, int redrawRate, void *context, int drFlags) {
    printf("[SETUP] videoFormat=0x%x %dx%d@%d fps drFlags=0x%x\n", videoFormat, width, height, redrawRate, drFlags);
    g_width = width;
    g_height = height;

    int codec_family = -1;
    if (videoFormat & VIDEO_FORMAT_MASK_H264) codec_family = 0;
    else if (videoFormat & VIDEO_FORMAT_MASK_H265) codec_family = 1;
    else if (videoFormat & VIDEO_FORMAT_MASK_AV1) codec_family = 2;
    if (codec_family < 0) return -1;

    const char *codec_names[] = {"h264", "hevc", "libdav1d"};
    g_codec = avcodec_find_decoder_by_name(codec_names[codec_family]);
    if (!g_codec) {
        // fallback
        AVCodecID ids[] = {AV_CODEC_ID_H264, AV_CODEC_ID_HEVC, AV_CODEC_ID_AV1};
        g_codec = avcodec_find_decoder(ids[codec_family]);
    }
    if (!g_codec) {
        fprintf(stderr, "[SETUP] Codec not found!\n");
        return -1;
    }
    printf("[SETUP] Using decoder: %s\n", g_codec->name);

    g_ctx = avcodec_alloc_context3(g_codec);
    if (!g_ctx) return -1;
    g_ctx->width = width;
    g_ctx->height = height;
    g_ctx->coded_width = width;
    g_ctx->coded_height = height;
    g_ctx->pix_fmt = AV_PIX_FMT_YUV420P;
    g_ctx->flags |= AV_CODEC_FLAG_LOW_DELAY;
    g_ctx->flags2 |= AV_CODEC_FLAG2_SHOW_ALL;
    g_ctx->thread_count = 4;

    int ret = avcodec_open2(g_ctx, g_codec, nullptr);
    if (ret < 0) {
        char err[128];
        av_strerror(ret, err, sizeof(err));
        fprintf(stderr, "[SETUP] avcodec_open2 failed: %s\n", err);
        return -1;
    }
    printf("[SETUP] Decoder opened successfully\n");
    decoder_ready.store(true);
    return 0;
}

static void dr_start() {
    printf("[STREAM] Decoder start\n");
}

static void dr_stop() {
    printf("[STREAM] Decoder stop\n");
    decoder_ready.store(false);
}

static void dr_cleanup() {
    printf("[STREAM] Decoder cleanup\n");
    if (g_ctx) {
        avcodec_free_context(&g_ctx);
        g_ctx = nullptr;
    }
    g_codec = nullptr;
    decoder_ready.store(false);
}

static int dr_submit(PDECODE_UNIT du) {
    if (!decoder_ready.load() || !g_ctx) return DR_OK;

    g_packet_count.fetch_add(1);
    static int submit_log = 0;
    if (++submit_log <= 5) {
        printf("[DECODE] Packet #%d: size=%d type=%s frame=%d\n",
               submit_log, du->fullLength,
               du->frameType == FRAME_TYPE_IDR ? "IDR" : "P",
               du->frameNumber);
    }

    AVPacket *pkt = av_packet_alloc();
    av_new_packet(pkt, du->fullLength);

    int offset = 0;
    PLENTRY entry = du->bufferList;
    while (entry) {
        if (offset + entry->length <= du->fullLength)
            memcpy(pkt->data + offset, entry->data, entry->length);
        offset += entry->length;
        entry = entry->next;
    }
    pkt->pts = du->presentationTimeUs;

    int ret = avcodec_send_packet(g_ctx, pkt);
    av_packet_free(&pkt);

    if (ret < 0 && ret != AVERROR(EAGAIN) && ret != AVERROR_EOF)
        return DR_OK;

    AVFrame *frame = av_frame_alloc();
    while (true) {
        ret = avcodec_receive_frame(g_ctx, frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) break;
        if (ret < 0) break;

        int fc = frame_count.fetch_add(1) + 1;
        if (fc <= 5 || fc % 60 == 0) {
            printf("[FRAME] #%d: pix_fmt=%d(%s) %dx%d linesize=%d,%d,%d colorspace=%d range=%d\n",
                   fc, frame->format,
                   av_get_pix_fmt_name((AVPixelFormat)frame->format),
                   frame->width, frame->height,
                   frame->linesize[0], frame->linesize[1], frame->linesize[2],
                   (int)frame->colorspace, (int)frame->color_range);
        }
    }
    av_frame_free(&frame);
    return DR_OK;
}

// --- Connection callbacks ---
static void cl_stage_starting(int stage) {
    printf("[STAGE] Starting: %s\n", LiGetStageName(stage));
}
static void cl_stage_complete(int stage) {
    printf("[STAGE] Complete: %s\n", LiGetStageName(stage));
}
static void cl_stage_failed(int stage, int err) {
    printf("[STAGE] FAILED: %s (error %d)\n", LiGetStageName(stage), err);
}
static void cl_started() {
    printf("[CONN] Connection started!\n");
    running.store(true);
}
static void cl_terminated(int err) {
    printf("[CONN] Terminated: error=%d\n", err);
    running.store(false);
}
static void cl_log(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    printf("[MLOG] ");
    vprintf(fmt, args);
    printf("\n");
    va_end(args);
}
static void cl_status(int status) {
    printf("[CONN] Status: %s\n", status == CONN_STATUS_OKAY ? "OK" : "POOR");
}
static void cl_hdr(bool enabled) {
    printf("[CONN] HDR: %s\n", enabled ? "ON" : "OFF");
}

static void sig_handler(int) {
    running.store(false);
}

int main(int argc, char **argv) {
    setbuf(stdout, NULL); // unbuffered
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <server_ip> <rtsp_session_url> <codec_mode_support_hex> [app_version]\n", argv[0]);
        return 1;
    }

    printf("=== Stream Test Client ===\n");
    printf("Server: %s\n", argv[1]);
    printf("Session: %s\n", argv[2]);

    signal(SIGINT, sig_handler);

    const char *appver = argc >= 5 ? argv[4] : "7.1.431.-1";

    SERVER_INFORMATION si{};
    LiInitializeServerInformation(&si);
    si.address = argv[1];
    si.rtspSessionUrl = argv[2];
    si.serverCodecModeSupport = (int)strtol(argv[3], nullptr, 0);
    si.serverInfoAppVersion = appver;

    STREAM_CONFIGURATION sc{};
    LiInitializeStreamConfiguration(&sc);
    sc.width = 1920;
    sc.height = 1080;
    sc.fps = 60;
    sc.bitrate = 20000;
    sc.packetSize = 1024;
    sc.streamingRemotely = STREAM_CFG_LOCAL;
    sc.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    sc.supportedVideoFormats = VIDEO_FORMAT_H265; // Only HEVC Main, not the full mask
    sc.colorSpace = COLORSPACE_REC_709;
    sc.colorRange = COLOR_RANGE_LIMITED;
    sc.encryptionFlags = ENCFLG_ALL;

    DECODER_RENDERER_CALLBACKS dr{};
    LiInitializeVideoCallbacks(&dr);
    dr.setup = dr_setup;
    dr.start = dr_start;
    dr.stop = dr_stop;
    dr.cleanup = dr_cleanup;
    dr.submitDecodeUnit = dr_submit;

    CONNECTION_LISTENER_CALLBACKS cl{};
    LiInitializeConnectionCallbacks(&cl);
    cl.stageStarting = cl_stage_starting;
    cl.stageComplete = cl_stage_complete;
    cl.stageFailed = cl_stage_failed;
    cl.connectionStarted = cl_started;
    cl.connectionTerminated = cl_terminated;
    cl.logMessage = cl_log;
    cl.connectionStatusUpdate = cl_status;
    cl.setHdrMode = cl_hdr;

    printf("[MAIN] Starting connection...\n");
    auto t0 = std::chrono::steady_clock::now();
    int ret = LiStartConnection(&si, &sc, &cl, &dr, nullptr, nullptr, 0, nullptr, 0);

    if (ret != 0) {
        fprintf(stderr, "[MAIN] LiStartConnection failed: %d\n", ret);
        return 1;
    }

    // Wait for connection or timeout
    auto start = std::chrono::steady_clock::now();
    while (!running.load() && std::chrono::steady_clock::now() - start < std::chrono::seconds(15)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    if (!running.load()) {
        printf("[MAIN] Connection failed or timed out (frames=%d packets=%d)\n",
               frame_count.load(), g_packet_count.load());
        LiStopConnection();
        return 1;
    }

    printf("[MAIN] Streaming... (Ctrl+C to stop)\n");
    // Run for up to 30 seconds
    auto stream_start = std::chrono::steady_clock::now();
    while (running.load() && std::chrono::steady_clock::now() - stream_start < std::chrono::seconds(30)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    printf("\n=== Results ===\n");
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - t0).count();
    printf("Duration: %lld ms\n", (long long)elapsed);
    printf("Frames decoded: %d\n", frame_count.load());
    printf("Decoder: %s\n", g_codec ? g_codec->name : "none");
    printf("Hardware: %s\n", g_is_hw ? "yes" : "no");
    printf("Resolution: %dx%d\n", g_width, g_height);

    LiStopConnection();
    printf("=== Done ===\n");
    return 0;
}
