#pragma once

#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>

#ifdef NIGHTFALL_HAS_PIPEWIRE
#include <pipewire/pipewire.h>
#endif

namespace godot {

class PipeWireCapture {
public:
    struct FrameData {
        int plane_fds[4] = {-1, -1, -1, -1};
        uint32_t plane_offsets[4] = {0, 0, 0, 0};
        uint32_t plane_strides[4] = {0, 0, 0, 0};
        void *plane_datas[4] = {nullptr, nullptr, nullptr, nullptr};
        uint32_t n_planes = 0;
        uint32_t width = 0;
        uint32_t height = 0;
        uint32_t format = 0; // SPA_VIDEO_FORMAT_*
        uint64_t modifier = 0;
        void *spa_buf_ptr = nullptr; // Raw spa_buffer pointer for CPU-copy path
    };

    PipeWireCapture();
    ~PipeWireCapture();

    bool start(const std::string &restore_token = "");
    void stop();

    bool has_new_frame();
    bool get_latest_frame(FrameData &out_frame);
    void release_frame(void *spa_buf_ptr);

    std::string get_restore_token() const { return restore_token_; }

#ifdef NIGHTFALL_HAS_PIPEWIRE
    static void on_state_changed(void *data, int old, int state, const char *error);
    static void on_param_changed(void *data, uint32_t id, const struct spa_pod *param);
    static void on_process(void *data);
#endif

private:
#ifdef NIGHTFALL_HAS_PIPEWIRE
    void run_dbus_and_pw();

    struct pw_thread_loop *pw_loop_ = nullptr;
    struct pw_context *pw_context_ = nullptr;
    struct pw_core *pw_core_ = nullptr;
    struct pw_stream *pw_stream_ = nullptr;
    struct spa_hook *stream_listener_ = nullptr;

    std::thread worker_thread_;
    std::atomic<bool> running_{false};
    std::atomic<bool> connected_{false};

    // Buffer queue management
    std::mutex frame_mutex_;
    struct pw_buffer *current_buffer_ = nullptr;
    FrameData latest_frame_;
    bool has_new_frame_ = false;

    uint32_t negotiated_format_ = 0;
    uint64_t negotiated_modifier_ = 0;
    uint32_t width_ = 0;
    uint32_t height_ = 0;
#endif

    std::string restore_token_;
};

} // namespace godot
