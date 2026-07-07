#pragma once

#ifdef __ANDROID__
#include <media/NdkMediaCodec.h>
#include <media/NdkImageReader.h>
#include <android/hardware_buffer.h>
#include <android/native_window.h>
#include <atomic>
#include <mutex>
#include <queue>
#include <cstdint>

namespace godot {

struct NativeDecodedFrame {
    AHardwareBuffer *buffer = nullptr;
    int64_t pts = 0;
    int width = 0;
    int height = 0;
    AImage *image = nullptr; // Must keep alive until Vulkan import completes
};

class AndroidMediaCodec {
public:
    AndroidMediaCodec();
    ~AndroidMediaCodec();

    bool init(const char *mime, int width, int height);
    void shutdown();

    // Feed raw HEVC/H.264 data (call from decode thread)
    bool feed_packet(const uint8_t *data, size_t size, int64_t pts);

    // Try to get a decoded frame. Returns true if frame available.
    bool dequeue_frame(NativeDecodedFrame &out_frame, int64_t timeout_us = 5000);

    // Release a frame after Vulkan import. Call AImage_delete internally.
    void release_frame(NativeDecodedFrame &frame);

    bool is_initialized() const { return codec_ != nullptr; }

private:
    AMediaCodec *codec_ = nullptr;
    AImageReader *reader_ = nullptr;
    ANativeWindow *window_ = nullptr;
    int width_ = 0, height_ = 0;
    std::atomic<bool> started_{false};
    std::atomic<bool> eos_{false};
    int64_t input_pts_counter_ = 0;
};

} // namespace godot

#endif // __ANDROID__
