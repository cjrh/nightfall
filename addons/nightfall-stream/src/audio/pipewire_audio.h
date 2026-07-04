#pragma once

#include <thread>
#include <atomic>
#include <mutex>
#include <string>

#ifdef NIGHTFALL_HAS_PIPEWIRE
#include <pipewire/pipewire.h>
#endif

namespace godot {

class AudioRenderer;

class PipeWireAudio {
public:
    PipeWireAudio(AudioRenderer *renderer);
    ~PipeWireAudio();

    bool start();
    void stop();

#ifdef NIGHTFALL_HAS_PIPEWIRE
    static void on_state_changed(void *data, int old, int state, const char *error);
    static void on_param_changed(void *data, uint32_t id, const struct spa_pod *param);
    static void on_process(void *data);
#endif

private:
#ifdef NIGHTFALL_HAS_PIPEWIRE
    void run_pw();

    struct pw_thread_loop *pw_loop_ = nullptr;
    struct pw_context *pw_context_ = nullptr;
    struct pw_core *pw_core_ = nullptr;
    struct pw_stream *pw_stream_ = nullptr;
    struct spa_hook *stream_listener_ = nullptr;

    std::thread worker_thread_;
    std::atomic<bool> running_{false};
    std::atomic<bool> connected_{false};
#endif

    AudioRenderer *renderer_ = nullptr;
};

} // namespace godot
