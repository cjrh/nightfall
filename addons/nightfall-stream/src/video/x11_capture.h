#pragma once

#ifdef NIGHTFALL_HAS_X11
#include <X11/Xlib.h>
#include <X11/extensions/XShm.h>
#endif

#include <cstdint>
#include <atomic>
#include <mutex>
#include <thread>
#include <vector>

namespace godot {

class X11Capture {
public:
    struct FrameData {
        uint8_t *data = nullptr;
        uint32_t width = 0;
        uint32_t height = 0;
        uint32_t stride = 0; // bytes per row
    };

    X11Capture();
    ~X11Capture();

    bool start();
    void stop();

    bool has_new_frame() const;
    bool get_latest_frame(FrameData &out_frame);
    void release_frame();

    uint32_t get_width() const { return width_; }
    uint32_t get_height() const { return height_; }

private:
    void capture_loop();

#ifdef NIGHTFALL_HAS_X11
    ::Display *display_ = nullptr;
    XShmSegmentInfo shm_info_;
    XImage *image_ = nullptr;
    int screen_ = 0;
    int damage_event_base_ = 0;
    int damage_error_base_ = 0;
#endif

    std::thread worker_thread_;
    std::atomic<bool> running_{false};

    mutable std::mutex frame_mutex_;
    FrameData latest_frame_;
    bool has_new_frame_ = false;

    uint32_t width_ = 0;
    uint32_t height_ = 0;
};

} // namespace godot
