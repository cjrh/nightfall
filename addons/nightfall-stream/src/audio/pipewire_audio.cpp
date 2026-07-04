#include "pipewire_audio.h"
#include "audio/audio_renderer.h"
#include "nf_log.h"

#ifdef NIGHTFALL_HAS_PIPEWIRE
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/param/audio/type-info.h>
#include <spa/pod/builder.h>
#include <unistd.h>

namespace godot {

static const struct pw_stream_events audio_stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .destroy = nullptr,
    .state_changed = [](void *data, enum pw_stream_state old, enum pw_stream_state state, const char *error) {
        PipeWireAudio::on_state_changed(data, (int)old, (int)state, error);
    },
    .control_info = nullptr,
    .io_changed = nullptr,
    .param_changed = [](void *data, uint32_t id, const struct spa_pod *param) {
        PipeWireAudio::on_param_changed(data, id, param);
    },
    .process = [](void *data) {
        PipeWireAudio::on_process(data);
    },
    .drained = nullptr,
};

PipeWireAudio::PipeWireAudio(AudioRenderer *renderer) : renderer_(renderer) {
}

PipeWireAudio::~PipeWireAudio() {
    stop();
}

bool PipeWireAudio::start() {
    running_ = true;
    worker_thread_ = std::thread(&PipeWireAudio::run_pw, this);
    return true;
}

void PipeWireAudio::stop() {
    running_ = false;
#ifdef NIGHTFALL_HAS_PIPEWIRE
    if (pw_loop_) {
        pw_thread_loop_signal(pw_loop_, false);
    }
#endif
    if (worker_thread_.joinable()) {
        worker_thread_.join();
    }
}

void PipeWireAudio::run_pw() {
    pw_init(nullptr, nullptr);
    pw_loop_ = pw_thread_loop_new("nightfall-pw-audio", nullptr);
    if (!pw_loop_) return;

    pw_context_ = pw_context_new(pw_thread_loop_get_loop(pw_loop_), nullptr, 0);
    if (!pw_context_) {
        pw_thread_loop_destroy(pw_loop_);
        return;
    }

    pw_thread_loop_lock(pw_loop_);

    // Connect to system PipeWire
    pw_core_ = pw_context_connect(pw_context_, nullptr, 0);
    if (!pw_core_) {
        pw_thread_loop_unlock(pw_loop_);
        pw_context_destroy(pw_context_);
        pw_thread_loop_destroy(pw_loop_);
        return;
    }

    // Set up stream properties for desktop audio monitor capture
    struct pw_properties *props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE, "Music",
        PW_KEY_STREAM_CAPTURE_SINK, "true", // Capture what's playing on default sink
        NULL
    );

    pw_stream_ = pw_stream_new(pw_core_, "nightfall-desktop-audio", props);
    if (!pw_stream_) {
        pw_thread_loop_unlock(pw_loop_);
        pw_context_destroy(pw_context_);
        pw_thread_loop_destroy(pw_loop_);
        return;
    }

    stream_listener_ = new spa_hook();
    pw_stream_add_listener(pw_stream_, stream_listener_, &audio_stream_events, this);

    // Build format parameter (F32 stereo 48kHz)
    uint8_t buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));

    struct spa_audio_info_raw info = {};
    info.format = SPA_AUDIO_FORMAT_F32; // Interleaved Float 32
    info.rate = 48000;
    info.channels = 2;
    info.position[0] = SPA_AUDIO_CHANNEL_FL;
    info.position[1] = SPA_AUDIO_CHANNEL_FR;

    const struct spa_pod *params[1];
    params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);

    int res = pw_stream_connect(
        pw_stream_,
        PW_DIRECTION_INPUT,
        PW_ID_ANY,
        (pw_stream_flags)(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS),
        params,
        1
    );

    if (res < 0) {
        NF_LOG("PipeWireAudio", "Audio stream connect failed: %d", res);
        pw_thread_loop_unlock(pw_loop_);
        return;
    }

    pw_thread_loop_unlock(pw_loop_);

    if (pw_thread_loop_start(pw_loop_) < 0) {
        NF_LOG("PipeWireAudio", "Failed to start PipeWire audio thread");
        return;
    }

    while (running_) {
        usleep(50000);
    }

    pw_thread_loop_stop(pw_loop_);

    pw_thread_loop_lock(pw_loop_);
    pw_stream_destroy(pw_stream_);
    if (stream_listener_) {
        delete stream_listener_;
        stream_listener_ = nullptr;
    }
    pw_context_destroy(pw_context_);
    pw_thread_loop_unlock(pw_loop_);

    pw_thread_loop_destroy(pw_loop_);
    pw_loop_ = nullptr;
    NF_LOG("PipeWireAudio", "Audio worker thread exited");
}

void PipeWireAudio::on_state_changed(void *data, int old, int state, const char *error) {
    PipeWireAudio *self = static_cast<PipeWireAudio*>(data);
    NF_LOG("PipeWireAudio", "Audio stream state: %d -> %d (error: %s)", old, state, error ? error : "none");
    if (state == 3) { // PW_STREAM_STATE_STREAMING is 3
        self->connected_ = true;
    } else {
        self->connected_ = false;
    }
}

void PipeWireAudio::on_param_changed(void *data, uint32_t id, const struct ::spa_pod *param) {
}

void PipeWireAudio::on_process(void *data) {
    PipeWireAudio *self = static_cast<PipeWireAudio*>(data);
    struct pw_buffer *buf = pw_stream_dequeue_buffer(self->pw_stream_);
    if (!buf) return;

    struct spa_buffer *spa_buf = buf->buffer;
    struct spa_data *d = &spa_buf->datas[0];

    if (d->data && d->chunk->size > 0) {
        const float *audio_data = reinterpret_cast<const float*>(static_cast<uint8_t*>(d->data) + d->chunk->offset);
        uint32_t bytes = d->chunk->size;
        uint32_t frames = bytes / (sizeof(float) * 2); // 2 channels

        // Write directly to our AudioRenderer's miniaudio/platform backend
        if (self->renderer_) {
            self->renderer_->play_local_pcm(audio_data, frames);
        }
    }

    pw_stream_queue_buffer(self->pw_stream_, buf);
}

} // namespace godot

#else // NIGHTFALL_HAS_PIPEWIRE

namespace godot {
PipeWireAudio::PipeWireAudio(AudioRenderer*) {}
PipeWireAudio::~PipeWireAudio() {}
bool PipeWireAudio::start() { return false; }
void PipeWireAudio::stop() {}
} // namespace godot

#endif // NIGHTFALL_HAS_PIPEWIRE
