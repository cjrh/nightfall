#include "pipewire_capture.h"
#include "dbus_portal.h"
#include "nf_log.h"

#ifdef NIGHTFALL_HAS_PIPEWIRE
#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>
#include <spa/param/video/type-info.h>
#include <spa/pod/builder.h>
#include <spa/debug/format.h>
#include <unistd.h>
#include <sys/mman.h>
#include <libdrm/drm_fourcc.h>

namespace godot {

static const struct pw_core_events core_events = {
    PW_VERSION_CORE_EVENTS,
    .info = nullptr,
    .done = nullptr,
    .ping = nullptr,
    .error = [](void *data, uint32_t id, int seq, int res, const char *message) {
        NF_LOG("PipeWireCapture", "Core error: id=%u, seq=%d, res=%d (%s): %s", id, seq, res, strerror(-res), message);
    },
};

static const struct pw_stream_events stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .destroy = nullptr,
    .state_changed = [](void *data, enum pw_stream_state old, enum pw_stream_state state, const char *error) {
        PipeWireCapture::on_state_changed(data, (int)old, (int)state, error);
    },
    .control_info = nullptr,
    .io_changed = nullptr,
    .param_changed = [](void *data, uint32_t id, const struct spa_pod *param) {
        PipeWireCapture::on_param_changed(data, id, param);
    },
    .process = [](void *data) {
        PipeWireCapture::on_process(data);
    },
    .drained = nullptr,
};

PipeWireCapture::PipeWireCapture() {
}

PipeWireCapture::~PipeWireCapture() {
    stop();
}

bool PipeWireCapture::start(const std::string &restore_token) {
    restore_token_ = restore_token;
    running_ = true;
    worker_thread_ = std::thread(&PipeWireCapture::run_dbus_and_pw, this);
    return true;
}

void PipeWireCapture::stop() {
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

bool PipeWireCapture::has_new_frame() {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    return has_new_frame_;
}

bool PipeWireCapture::get_latest_frame(FrameData &out_frame) {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    if (!has_new_frame_) return false;

    out_frame = latest_frame_;
    has_new_frame_ = false;
    return true;
}

void PipeWireCapture::release_frame(void *spa_buf_ptr) {
    if (!spa_buf_ptr) return;
    struct pw_buffer *buf = static_cast<struct pw_buffer *>(spa_buf_ptr);

    bool should_queue = false;
    {
        std::lock_guard<std::mutex> lock(frame_mutex_);
        if (current_buffer_ == buf) {
            current_buffer_ = nullptr;
            should_queue = true;
        }
    }

    if (should_queue && pw_loop_) {
        pw_thread_loop_lock(pw_loop_);
        pw_stream_queue_buffer(pw_stream_, buf);
        pw_thread_loop_unlock(pw_loop_);
    }
}

void PipeWireCapture::run_dbus_and_pw() {
    NF_LOG("PipeWireCapture", "Worker thread started, attempting D-Bus portal connection...");
    DBusPortal portal;
    if (!portal.init()) {
        NF_LOG("PipeWireCapture", "Portal init failed");
        return;
    }

    if (!portal.create_session()) {
        NF_LOG("PipeWireCapture", "Create session failed");
        return;
    }

    if (!portal.select_sources(restore_token_)) {
        NF_LOG("PipeWireCapture", "Select sources failed or cancelled");
        return;
    }

    std::vector<DBusPortal::StreamInfo> streams;
    std::string new_restore_token;
    if (!portal.start(streams, new_restore_token)) {
        NF_LOG("PipeWireCapture", "Start screencast failed");
        return;
    }

    if (streams.empty()) {
        NF_LOG("PipeWireCapture", "No streams returned from portal");
        return;
    }

    restore_token_ = new_restore_token;
    DBusPortal::StreamInfo target_stream = streams[0];
    NF_LOG("PipeWireCapture", "Target stream: node_id=%d, serial=%ld, %dx%d", 
           target_stream.node_id, target_stream.serial, target_stream.width, target_stream.height);

    int pw_fd = portal.open_pipewire_remote();
    if (pw_fd < 0) {
        NF_LOG("PipeWireCapture", "Failed to open PipeWire remote FD");
        return;
    }

    // Initialize PipeWire loop
    pw_init(nullptr, nullptr);
    pw_loop_ = pw_thread_loop_new("nightfall-pw-loop", nullptr);
    if (!pw_loop_) {
        close(pw_fd);
        return;
    }

    pw_context_ = pw_context_new(pw_thread_loop_get_loop(pw_loop_), nullptr, 0);
    if (!pw_context_) {
        pw_thread_loop_destroy(pw_loop_);
        close(pw_fd);
        return;
    }

    if (pw_thread_loop_start(pw_loop_) < 0) {
        NF_LOG("PipeWireCapture", "Failed to start PipeWire loop thread");
        pw_context_destroy(pw_context_);
        pw_thread_loop_destroy(pw_loop_);
        close(pw_fd);
        return;
    }

    pw_thread_loop_lock(pw_loop_);

    // Connect using our FD from the portal
    pw_core_ = pw_context_connect_fd(pw_context_, pw_fd, nullptr, 0);
    if (!pw_core_) {
        pw_thread_loop_unlock(pw_loop_);
        pw_context_destroy(pw_context_);
        pw_thread_loop_destroy(pw_loop_);
        return;
    }

    struct spa_hook core_listener;
    spa_zero(core_listener);
    pw_core_add_listener(pw_core_, &core_listener, &core_events, nullptr);

    // Set up stream properties
    struct pw_properties *props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Video",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE, "Screen",
        NULL
    );

    // Target object by serial (or node_id fallback)
    if (target_stream.serial > 0) {
        pw_properties_set(props, PW_KEY_TARGET_OBJECT, std::to_string(target_stream.serial).c_str());
    }

    pw_stream_ = pw_stream_new(pw_core_, "nightfall-screencast", props);
    if (!pw_stream_) {
        pw_thread_loop_unlock(pw_loop_);
        pw_context_destroy(pw_context_);
        pw_thread_loop_destroy(pw_loop_);
        return;
    }

    stream_listener_ = new spa_hook();
    pw_stream_add_listener(pw_stream_, stream_listener_, &stream_events, this);

    // Minimal test: single format with no modifiers, no ranges
    // If this is rejected, the issue is structural, not parameter-specific
    uint8_t pod_buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(pod_buffer, sizeof(pod_buffer));

    const struct spa_pod *params[1];
    params[0] = (const struct spa_pod *)spa_pod_builder_add_object(&b,
        SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
        SPA_FORMAT_mediaType,    SPA_POD_Id(SPA_MEDIA_TYPE_video),
        SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
        SPA_FORMAT_VIDEO_format, SPA_POD_Id(SPA_VIDEO_FORMAT_BGRx)
    );

    NF_LOG("PipeWireCapture", "Built minimal format pod (ptr=%p)", (void*)params[0]);

    // Connect stream
    int res = pw_stream_connect(
        pw_stream_,
        PW_DIRECTION_INPUT,
        PW_ID_ANY,
        (pw_stream_flags)(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS),
        params,
        (params[0] != nullptr) ? 1 : 0
    );

    if (res < 0) {
        NF_LOG("PipeWireCapture", "Stream connect failed: %d", res);
        pw_thread_loop_unlock(pw_loop_);
        return;
    }

    pw_thread_loop_unlock(pw_loop_);

    // Wait until stopped
    while (running_) {
        usleep(50000); // 50ms check
    }

    // Cleanup
    pw_thread_loop_stop(pw_loop_);

    pw_thread_loop_lock(pw_loop_);
    pw_stream_destroy(pw_stream_);
    if (stream_listener_) {
        delete stream_listener_;
        stream_listener_ = nullptr;
    }
    spa_hook_remove(&core_listener);
    pw_context_destroy(pw_context_);
    pw_thread_loop_unlock(pw_loop_);

    pw_thread_loop_destroy(pw_loop_);
    pw_loop_ = nullptr;

    portal.close_session();
    NF_LOG("PipeWireCapture", "Worker thread exited");
}

void PipeWireCapture::on_state_changed(void *data, int old, int state, const char *error) {
    PipeWireCapture *self = static_cast<PipeWireCapture*>(data);
    NF_LOG("PipeWireCapture", "Stream state changed from %d to %d (error: %s)", old, state, error ? error : "none");
    if (state == 3) { // PW_STREAM_STATE_STREAMING is 3
        self->connected_ = true;
    } else {
        self->connected_ = false;
    }
}

void PipeWireCapture::on_param_changed(void *data, uint32_t id, const struct spa_pod *param) {
    PipeWireCapture *self = static_cast<PipeWireCapture*>(data);
    const char *id_name = "unknown";
    switch (id) {
        case 0: id_name = "Invalid"; break;
        case 1: id_name = "PropInfo"; break;
        case 2: id_name = "Props"; break;
        case 3: id_name = "EnumFormat"; break;
        case 4: id_name = "Format"; break;
        case 5: id_name = "Buffers"; break;
        case 6: id_name = "Meta"; break;
        case 7: id_name = "IO"; break;
        case 15: id_name = "Profile"; break;
        case 17: id_name = "Route"; break;
        case 20: id_name = "Tag"; break;
        default: break;
    }
    NF_LOG("PipeWireCapture", "on_param_changed: id=%u (%s), param=%s",
           id, id_name, param ? "present" : "null");

    if (param == nullptr) {
        return;
    }

    if (id == 3 /* SPA_PARAM_EnumFormat */) {
        uint32_t media_type = 0, media_subtype = 0;
        if (spa_format_parse(param, &media_type, &media_subtype) >= 0) {
            NF_LOG("PipeWireCapture", "  EnumFormat: media_type=%u, media_subtype=%u",
                   media_type, media_subtype);
            if (media_subtype == SPA_MEDIA_SUBTYPE_raw) {
                struct spa_video_info_raw info = {};
                if (spa_format_video_raw_parse(param, &info) >= 0) {
                    NF_LOG("PipeWireCapture", "  -> Server offers: format=%d, modifier=0x%lx, size=%dx%d, framerate=%d/%d",
                           info.format, info.modifier, info.size.width, info.size.height,
                           info.framerate.num, info.framerate.denom);
                }
            }
        }
        return;
    }

    if (id != SPA_PARAM_Format) return;

    struct spa_video_info_raw info = {};
    if (spa_format_video_raw_parse(param, &info) < 0) {
        NF_LOG("PipeWireCapture", "on_param_changed: failed to parse video format");
        return;
    }

    self->negotiated_format_ = info.format;
    self->negotiated_modifier_ = info.modifier;
    self->width_ = info.size.width;
    self->height_ = info.size.height;

    bool has_modifier = (spa_pod_find_prop(param, nullptr, SPA_FORMAT_VIDEO_modifier) != nullptr);
    NF_LOG("PipeWireCapture", "Format negotiated: format=%d, modifier=0x%lx (has_modifier=%d), size=%dx%d, framerate=%d/%d",
           self->negotiated_format_, self->negotiated_modifier_, has_modifier,
           self->width_, self->height_, info.framerate.num, info.framerate.denom);

    if (has_modifier) {
        if (self->negotiated_modifier_ == DRM_FORMAT_MOD_LINEAR) {
            NF_LOG("PipeWireCapture", "Modifier is LINEAR - mmap will work");
        } else if (self->negotiated_modifier_ == DRM_FORMAT_MOD_INVALID) {
            NF_LOG("PipeWireCapture", "Modifier is INVALID (implicit) - mmap may be unsafe");
        } else {
            NF_LOG("PipeWireCapture", "Modifier is TILED (0x%lx) - mmap will produce garbled output!", self->negotiated_modifier_);
        }
    } else {
        NF_LOG("PipeWireCapture", "No modifier in negotiated format (SHM/system memory path)");
    }

    // Respond with supported buffer types
    uint8_t buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    const struct spa_pod *params[2];

    uint32_t blocks = 1; // Default
    if (info.format == SPA_VIDEO_FORMAT_NV12) blocks = 2;
    else if (info.format == SPA_VIDEO_FORMAT_I420) blocks = 3;

    params[0] = (const struct spa_pod *)spa_pod_builder_add_object(&b,
        SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
        SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(2, 2, 8),
        SPA_PARAM_BUFFERS_blocks, SPA_POD_Int(blocks),
        SPA_PARAM_BUFFERS_size, SPA_POD_Int(self->width_ * self->height_ * 4),
        SPA_PARAM_BUFFERS_align, SPA_POD_Int(16),
        SPA_PARAM_BUFFERS_dataType, SPA_POD_CHOICE_FLAGS_Int(
            (1 << SPA_DATA_MemFd) | (1 << SPA_DATA_MemPtr)
        )
    );

    pw_stream_update_params(self->pw_stream_, params, 1);
}

void PipeWireCapture::on_process(void *data) {
    PipeWireCapture *self = static_cast<PipeWireCapture*>(data);
    struct pw_buffer *buf = pw_stream_dequeue_buffer(self->pw_stream_);
    if (!buf) return;

    std::lock_guard<std::mutex> lock(self->frame_mutex_);

    // If we already hold a buffer, requeue it back to PipeWire
    if (self->current_buffer_) {
        pw_stream_queue_buffer(self->pw_stream_, self->current_buffer_);
    }

    self->current_buffer_ = buf;

    // Fill FrameData
    struct spa_buffer *spa_buf = buf->buffer;
    self->latest_frame_.n_planes = spa_buf->n_datas;
    self->latest_frame_.width = self->width_;
    self->latest_frame_.height = self->height_;
    self->latest_frame_.format = self->negotiated_format_;
    self->latest_frame_.modifier = self->negotiated_modifier_;
    self->latest_frame_.spa_buf_ptr = buf;

    for (uint32_t i = 0; i < spa_buf->n_datas && i < 4; i++) {
        struct spa_data *d = &spa_buf->datas[i];
        self->latest_frame_.plane_fds[i] = d->fd;
        self->latest_frame_.plane_offsets[i] = d->mapoffset;
        self->latest_frame_.plane_strides[i] = d->chunk->stride;
        self->latest_frame_.plane_datas[i] = d->data;
    }

    self->has_new_frame_ = true;
}

} // namespace godot

#else // NIGHTFALL_HAS_PIPEWIRE

namespace godot {
PipeWireCapture::PipeWireCapture() {}
PipeWireCapture::~PipeWireCapture() {}
bool PipeWireCapture::start(const std::string&) { return false; }
void PipeWireCapture::stop() {}
bool PipeWireCapture::has_new_frame() { return false; }
bool PipeWireCapture::get_latest_frame(FrameData&) { return false; }
void PipeWireCapture::release_frame(void*) {}
} // namespace godot

#endif // NIGHTFALL_HAS_PIPEWIRE
