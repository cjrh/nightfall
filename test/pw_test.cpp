// PipeWire screencast negotiation test tool - v2 with proper D-Bus API
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <csignal>
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <chrono>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>
#include <spa/pod/builder.h>
#include <spa/debug/format.h>
#include <systemd/sd-bus.h>

#ifdef __has_include
#if __has_include(<libdrm/drm_fourcc.h>)
#include <libdrm/drm_fourcc.h>
#else
#include <drm/drm_fourcc.h>
#endif
#else
#include <libdrm/drm_fourcc.h>
#endif

// ============= D-Bus Portal =============
static sd_bus *bus = nullptr;
static std::string session_handle;

struct PortalResponse {
    std::atomic<bool> received{false};
    uint32_t code = 99;
    sd_bus_message *results = nullptr;
};

static int on_response_signal(sd_bus_message *m, void *userdata, sd_bus_error *err) {
    PortalResponse *resp = static_cast<PortalResponse *>(userdata);
    sd_bus_message_read(m, "u", &resp->code);
    sd_bus_message_enter_container(m, 'a', "{sv}");
    resp->results = sd_bus_message_ref(m);
    sd_bus_message_exit_container(m);
    resp->received = true;
    return 0;
}

static bool wait_for_response(PortalResponse &resp, const std::string &request_path, int timeout_s = 15) {
    std::string match_str = "type='signal',sender='org.freedesktop.portal.Desktop',path='"
        + request_path + "',interface='org.freedesktop.portal.Request',member='Response'";

    sd_bus_slot *slot = nullptr;
    sd_bus_add_match(bus, &slot, match_str.c_str(), on_response_signal, &resp);

    auto start = std::chrono::steady_clock::now();
    while (!resp.received) {
        if (std::chrono::duration_cast<std::chrono::seconds>(
                std::chrono::steady_clock::now() - start).count() > timeout_s)
            break;
        sd_bus_process(bus, nullptr);
        if (!resp.received) sd_bus_wait(bus, 100000);
    }
    sd_bus_slot_unref(slot);
    return resp.received && resp.code == 0;
}

static bool dbus_create_session() {
    sd_bus_message *m = nullptr, *reply = nullptr;
    sd_bus_message_new_method_call(bus, &m,
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.ScreenCast", "CreateSession");
    sd_bus_message_open_container(m, 'a', "{sv}");
    sd_bus_message_open_container(m, 'e', "sv");
    sd_bus_message_append(m, "s", "session_handle_token");
    sd_bus_message_open_container(m, 'v', "s");
    sd_bus_message_append(m, "s", "nightfall_pw_test");
    sd_bus_message_close_container(m); sd_bus_message_close_container(m);
    sd_bus_message_open_container(m, 'e', "sv");
    sd_bus_message_append(m, "s", "persist_mode");
    sd_bus_message_open_container(m, 'v', "s");
    sd_bus_message_append(m, "s", "transient");
    sd_bus_message_close_container(m); sd_bus_message_close_container(m);
    sd_bus_message_close_container(m);

    int r = sd_bus_call(bus, m, 0, nullptr, &reply);
    sd_bus_message_unref(m);
    if (r < 0) { fprintf(stderr, "CreateSession: %s\n", strerror(-r)); return false; }

    const char *handle = nullptr;
    r = sd_bus_message_read(reply, "o", &handle);
    sd_bus_message_unref(reply);
    if (r < 0) { fprintf(stderr, "CreateSession read: %s\n", strerror(-r)); return false; }
    session_handle = handle ? handle : "";
    printf("[PORTAL] Session handle: %s\n", session_handle.c_str());
    return !session_handle.empty();
}

static bool dbus_select_sources() {
    sd_bus_message *m = nullptr, *reply = nullptr;
    sd_bus_message_new_method_call(bus, &m,
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.ScreenCast", "SelectSources");
    sd_bus_message_append(m, "o", session_handle.c_str());
    sd_bus_message_open_container(m, 'a', "{sv}");
    sd_bus_message_open_container(m, 'e', "sv");
    sd_bus_message_append(m, "s", "types");
    sd_bus_message_open_container(m, 'v', "u");
    sd_bus_message_append(m, "u", 1); // MONITOR
    sd_bus_message_close_container(m); sd_bus_message_close_container(m);
    sd_bus_message_open_container(m, 'e', "sv");
    sd_bus_message_append(m, "s", "multiple");
    sd_bus_message_open_container(m, 'v', "b");
    sd_bus_message_append(m, "b", 0);
    sd_bus_message_close_container(m); sd_bus_message_close_container(m);
    sd_bus_message_close_container(m);

    int r = sd_bus_call(bus, m, 0, nullptr, &reply);
    sd_bus_message_unref(m);
    if (r < 0) { fprintf(stderr, "SelectSources: %s\n", strerror(-r)); return false; }

    const char *req_path = nullptr;
    r = sd_bus_message_read(reply, "o", &req_path);
    sd_bus_message_unref(reply);
    if (r < 0) { fprintf(stderr, "SelectSources read: %s\n", strerror(-r)); return false; }
    printf("[PORTAL] Waiting for user to select source (15s timeout)...\n");

    PortalResponse pr;
    if (!wait_for_response(pr, req_path, 15)) {
        fprintf(stderr, "SelectSources: user cancelled or timed out (code=%u)\n", pr.code);
        return false;
    }
    printf("[PORTAL] Sources selected OK\n");
    return true;
}

struct StreamInfo {
    uint32_t node_id = 0;
    uint64_t serial = 0;
    int width = 0, height = 0;
};

static bool dbus_start(std::vector<StreamInfo> &out_streams, std::string &out_token) {
    sd_bus_message *m = nullptr, *reply = nullptr;
    sd_bus_message_new_method_call(bus, &m,
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.ScreenCast", "Start");
    sd_bus_message_append(m, "os", session_handle.c_str(), "");
    sd_bus_message_open_container(m, 'a', "{sv}");
    sd_bus_message_open_container(m, 'e', "sv");
    sd_bus_message_append(m, "s", "handle_token");
    sd_bus_message_open_container(m, 'v', "s");
    sd_bus_message_append(m, "s", "nightfall_start");
    sd_bus_message_close_container(m); sd_bus_message_close_container(m);
    sd_bus_message_close_container(m);

    int r = sd_bus_call(bus, m, 0, nullptr, &reply);
    sd_bus_message_unref(m);
    if (r < 0) { fprintf(stderr, "Start: %s\n", strerror(-r)); return false; }

    const char *req_path = nullptr;
    r = sd_bus_message_read(reply, "o", &req_path);
    sd_bus_message_unref(reply);
    if (r < 0) { fprintf(stderr, "Start read: %s\n", strerror(-r)); return false; }

    PortalResponse pr;
    if (!wait_for_response(pr, req_path, 10)) {
        fprintf(stderr, "Start: failed (code=%u)\n", pr.code);
        return false;
    }

    if (!pr.results) { fprintf(stderr, "Start: no results\n"); return false; }

    sd_bus_message_enter_container(pr.results, 'a', "{sv}");
    while (sd_bus_message_enter_container(pr.results, 'e', "sv") > 0) {
        const char *key;
        sd_bus_message_read(pr.results, "s", &key);
        if (strcmp(key, "streams") == 0) {
            sd_bus_message_enter_container(pr.results, 'v', "a(ua{sv})");
            sd_bus_message_enter_container(pr.results, 'a', "(ua{sv})");
            while (sd_bus_message_enter_container(pr.results, 'r', "ua{sv}") > 0) {
                StreamInfo si;
                sd_bus_message_read(pr.results, "u", &si.node_id);
                sd_bus_message_enter_container(pr.results, 'a', "{sv}");
                while (sd_bus_message_enter_container(pr.results, 'e', "sv") > 0) {
                    const char *prop;
                    sd_bus_message_read(pr.results, "s", &prop);
                    sd_bus_message_enter_container(pr.results, 'v', "t");
                    sd_bus_message_read(pr.results, "t", &si.serial);
                    sd_bus_message_exit_container(pr.results);
                    sd_bus_message_exit_container(pr.results);
                }
                sd_bus_message_exit_container(pr.results);
                out_streams.push_back(si);
            }
            sd_bus_message_exit_container(pr.results);
            sd_bus_message_exit_container(pr.results);
        } else if (strcmp(key, "restore_token") == 0) {
            sd_bus_message_enter_container(pr.results, 'v', "s");
            sd_bus_message_read(pr.results, "s", &out_token);
            sd_bus_message_exit_container(pr.results);
        } else {
            sd_bus_message_enter_container(pr.results, 'v', nullptr);
            sd_bus_message_skip(pr.results, nullptr);
            sd_bus_message_exit_container(pr.results);
        }
        sd_bus_message_exit_container(pr.results);
    }
    sd_bus_message_exit_container(pr.results);
    sd_bus_message_unref(pr.results);

    printf("[PORTAL] Start OK: %zu streams, token=%s\n", out_streams.size(), out_token.c_str());
    for (auto &s : out_streams)
        printf("[PORTAL]   node_id=%u serial=%lu\n", s.node_id, (unsigned long)s.serial);
    return !out_streams.empty();
}

static int dbus_open_pw_remote() {
    sd_bus_message *m = nullptr, *reply = nullptr;
    sd_bus_message_new_method_call(bus, &m,
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.ScreenCast", "OpenPipeWireRemote");
    sd_bus_message_open_container(m, 'a', "{sv}");
    sd_bus_message_open_container(m, 'e', "sv");
    sd_bus_message_append(m, "s", "session_handle");
    sd_bus_message_open_container(m, 'v', "o");
    sd_bus_message_append(m, "o", session_handle.c_str());
    sd_bus_message_close_container(m); sd_bus_message_close_container(m);
    sd_bus_message_close_container(m);

    int r = sd_bus_call(bus, m, 0, nullptr, &reply);
    sd_bus_message_unref(m);
    if (r < 0) { fprintf(stderr, "OpenPipeWireRemote: %s\n", strerror(-r)); return false; }

    int pw_fd = -1;
    r = sd_bus_message_read(reply, "h", &pw_fd);
    sd_bus_message_unref(reply);
    if (r < 0 || pw_fd < 0) { fprintf(stderr, "Read PW FD failed\n"); return -1; }

    int dup_fd = fcntl(pw_fd, F_DUPFD_CLOEXEC, 0);
    printf("[PORTAL] PipeWire FD: %d\n", dup_fd);
    return dup_fd;
}

static void dbus_close() {
    sd_bus_unref(bus); bus = nullptr;
}

// ============= PipeWire =============
static struct pw_thread_loop *loop = nullptr;
static struct pw_context *context = nullptr;
static struct pw_core *core = nullptr;
static struct pw_stream *stream = nullptr;
static std::atomic<bool> running{false};
static std::atomic<bool> streaming{false};
static std::atomic<bool> format_received{false};
static int frame_count = 0;

static void on_pw_error(void*, uint32_t id, int seq, int res, const char *msg) {
    printf("[PW] error: id=%u seq=%d res=%d(%s): %s\n", id, seq, res, strerror(-res), msg ? msg : "");
}

static void on_stream_state(void *data, pw_stream_state old, pw_stream_state state, const char *error) {
    printf("[PW] state: %d -> %d (err=%s)\n", (int)old, (int)state, error ? error : "none");
    streaming = (state == PW_STREAM_STATE_STREAMING);
}

static void on_param_changed(void *data, uint32_t id, const struct spa_pod *param) {
    const char *names[] = {"Invalid","PropInfo","Props","EnumFormat","Format","Buffers","Meta","IO",
        "","","","","","","","Profile","","Route","","","Tag"};
    const char *id_name = (id < 21) ? names[id] : "?";
    printf("[PW] param_changed: id=%u (%s) param=%s\n", id, id_name, param ? "present" : "null");
    if (!param) return;

    if (id == SPA_PARAM_EnumFormat) {
        uint32_t mt=0, mst=0;
        spa_format_parse(param, &mt, &mst);
        printf("[PW]   EnumFormat: media_type=%u subtype=%u", mt, mst);
        if (mst == SPA_MEDIA_SUBTYPE_raw) {
            struct spa_video_info_raw info{};
            if (spa_format_video_raw_parse(param, &info) >= 0) {
                const char *fn = "?";
                if (info.format == SPA_VIDEO_FORMAT_BGRx) fn="BGRx";
                else if (info.format == SPA_VIDEO_FORMAT_BGRA) fn="BGRA";
                else if (info.format == SPA_VIDEO_FORMAT_RGBx) fn="RGBx";
                else if (info.format == SPA_VIDEO_FORMAT_RGBA) fn="RGBA";
                else if (info.format == SPA_VIDEO_FORMAT_NV12) fn="NV12";
                else if (info.format == SPA_VIDEO_FORMAT_YUY2) fn="YUY2";
                printf(" %s modifier=0x%lx %dx%d fps=%d/%d\n",
                    fn, (unsigned long)info.modifier,
                    info.size.width, info.size.height,
                    info.framerate.num, info.framerate.denom);
            }
        } else {
            printf("\n");
        }
        return;
    }
    if (id != SPA_PARAM_Format) return;

    struct spa_video_info_raw info{};
    if (spa_format_video_raw_parse(param, &info) < 0) return;
    format_received = true;

    bool has_mod = spa_pod_find_prop(param, nullptr, SPA_FORMAT_VIDEO_modifier) != nullptr;
    const char *fn = "?";
    if (info.format == SPA_VIDEO_FORMAT_BGRx) fn="BGRx";
    else if (info.format == SPA_VIDEO_FORMAT_BGRA) fn="BGRA";
    else if (info.format == SPA_VIDEO_FORMAT_RGBx) fn="RGBx";
    else if (info.format == SPA_VIDEO_FORMAT_RGBA) fn="RGBA";
    else if (info.format == SPA_VIDEO_FORMAT_NV12) fn="NV12";

    printf("[PW]   NEGOTIATED: %s modifier=0x%lx has_mod=%d %dx%d\n",
        fn, (unsigned long)info.modifier, has_mod, info.size.width, info.size.height);

    if (has_mod && info.modifier != DRM_FORMAT_MOD_LINEAR && info.modifier != DRM_FORMAT_MOD_INVALID) {
        printf("[PW]   ** TILED modifier - mmap will produce garbled output! **\n");
    }

    // Accept buffers
    uint8_t buf[1024];
    spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
    const spa_pod *params[1];
    uint32_t blocks = (info.format == SPA_VIDEO_FORMAT_NV12) ? 2 : 1;

    params[0] = (const spa_pod*)spa_pod_builder_add_object(&b,
        SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
        SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(2, 2, 8),
        SPA_PARAM_BUFFERS_blocks,  SPA_POD_Int(blocks),
        SPA_PARAM_BUFFERS_size,    SPA_POD_Int(info.size.width * info.size.height * 4),
        SPA_PARAM_BUFFERS_align,   SPA_POD_Int(16),
        SPA_PARAM_BUFFERS_dataType, SPA_POD_CHOICE_FLAGS_Int(
            (1 << SPA_DATA_MemFd) | (1 << SPA_DATA_MemPtr)
        )
    );
    pw_stream_update_params(stream, params, 1);
}

static void on_process(void *data) {
    struct pw_buffer *buf = pw_stream_dequeue_buffer(stream);
    if (!buf) return;
    frame_count++;

    struct spa_buffer *spa_buf = buf->buffer;
    if (frame_count <= 3) {
        printf("[PW] Frame #%d: n_datas=%u\n", frame_count, spa_buf->n_datas);
        for (uint32_t i = 0; i < spa_buf->n_datas && i < 4; i++) {
            struct spa_data *d = &spa_buf->datas[i];
            const char *dtype = (d->type == SPA_DATA_MemFd) ? "MemFd" :
                (d->type == SPA_DATA_DmaBuf) ? "DmaBuf" :
                (d->type == SPA_DATA_MemPtr) ? "MemPtr" : "?";
            printf("[PW]   data[%u]: type=%u(%s) fd=%d offset=%u stride=%d size=%u flags=%u\n",
                i, d->type, dtype, d->fd, d->mapoffset, d->chunk->stride, d->chunk->size, d->flags);
        }
    }
    if (frame_count == 1 && spa_buf->n_datas >= 1 && spa_buf->datas[0].data) {
        FILE *f = fopen("/tmp/pw_test_frame.raw", "wb");
        if (f) {
            size_t sz = spa_buf->datas[0].chunk->size;
            if (sz > 50*1024*1024) sz = 50*1024*1024;
            fwrite(spa_buf->datas[0].data, 1, sz, f);
            fclose(f);
            printf("[PW] Saved frame to /tmp/pw_test_frame.raw (%zu bytes)\n", sz);
        }
    }
    pw_stream_queue_buffer(stream, buf);
}

int main(int argc, char **argv) {
    printf("=== PipeWire Screencast Test v2 ===\n");
    printf("XDG_SESSION_TYPE=%s WAYLAND_DISPLAY=%s\n",
        getenv("XDG_SESSION_TYPE") ?: "unset",
        getenv("WAYLAND_DISPLAY") ?: "unset");

    // 1. Connect to session bus
    if (sd_bus_default(&bus) < 0) { fprintf(stderr, "session bus failed\n"); return 1; }
    printf("[PORTAL] Connected to session bus\n");

    // 2. CreateSession
    if (!dbus_create_session()) return 1;

    // 3. SelectSources (user must pick display)
    if (!dbus_select_sources()) return 1;

    // 4. Start
    std::vector<StreamInfo> streams;
    std::string token;
    if (!dbus_start(streams, token)) return 1;
    if (streams.empty()) { fprintf(stderr, "no streams\n"); return 1; }
    printf("[PORTAL] Restore token: %s\n", token.c_str());

    auto &tgt = streams[0];
    printf("[TEST] Target: node_id=%u serial=%lu\n", tgt.node_id, (unsigned long)tgt.serial);

    int pw_fd = dbus_open_pw_remote();
    if (pw_fd < 0) return 1;

    // 5. PipeWire
    pw_init(nullptr, nullptr);
    loop = pw_thread_loop_new("pw-test", nullptr);
    context = pw_context_new(pw_thread_loop_get_loop(loop), nullptr, 0);
    pw_thread_loop_start(loop);
    pw_thread_loop_lock(loop);

    core = pw_context_connect_fd(context, pw_fd, nullptr, 0);
    if (!core) { fprintf(stderr, "connect_fd failed\n"); pw_thread_loop_unlock(loop); return 1; }

    spa_hook core_hook;
    spa_zero(core_hook);
    static const pw_core_events ce = { PW_VERSION_CORE_EVENTS, .error = on_pw_error };
    pw_core_add_listener(core, &core_hook, &ce, nullptr);

    pw_properties *props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Video",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE, "Screen", nullptr);
    if (tgt.serial > 0)
        pw_properties_setf(props, PW_KEY_TARGET_OBJECT, "%lu", (unsigned long)tgt.serial);

    stream = pw_stream_new(core, "pw-test-stream", props);
    spa_hook stream_hook;
    static const pw_stream_events se = {
        PW_VERSION_STREAM_EVENTS,
        .state_changed = on_stream_state,
        .param_changed = on_param_changed,
        .process = on_process,
    };
    pw_stream_add_listener(stream, &stream_hook, &se, nullptr);

    // Propose formats
    uint8_t pod_buf[2048];
    spa_pod_builder b = SPA_POD_BUILDER_INIT(pod_buf, sizeof(pod_buf));
    const spa_pod *params[4]; int n = 0;

    params[n++] = (const spa_pod*)spa_pod_builder_add_object(&b,
        SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
        SPA_FORMAT_mediaType,    SPA_POD_Id(SPA_MEDIA_TYPE_video),
        SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
        SPA_FORMAT_VIDEO_format, SPA_POD_Id(SPA_VIDEO_FORMAT_BGRx));

    params[n++] = (const spa_pod*)spa_pod_builder_add_object(&b,
        SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
        SPA_FORMAT_mediaType,    SPA_POD_Id(SPA_MEDIA_TYPE_video),
        SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
        SPA_FORMAT_VIDEO_format, SPA_POD_Id(SPA_VIDEO_FORMAT_BGRA));

    params[n++] = (const spa_pod*)spa_pod_builder_add_object(&b,
        SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
        SPA_FORMAT_mediaType,    SPA_POD_Id(SPA_MEDIA_TYPE_video),
        SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
        SPA_FORMAT_VIDEO_format,   SPA_POD_Id(SPA_VIDEO_FORMAT_BGRx),
        SPA_FORMAT_VIDEO_modifier, SPA_POD_CHOICE_RANGE_Long(
            (int64_t)DRM_FORMAT_MOD_LINEAR,
            (int64_t)DRM_FORMAT_MOD_LINEAR,
            (int64_t)DRM_FORMAT_MOD_LINEAR));

    printf("[TEST] Proposing %d formats\n", n);
    int res = pw_stream_connect(stream, PW_DIRECTION_INPUT, PW_ID_ANY,
        (pw_stream_flags)(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS), params, n);
    pw_thread_loop_unlock(loop);

    if (res < 0) { fprintf(stderr, "connect failed: %d\n", res); return 1; }

    // Wait for format
    printf("[TEST] Waiting for negotiation (5s)...\n");
    for (int i = 0; i < 50 && !format_received; i++) usleep(100000);

    printf("[TEST] Format: %s\n", format_received ? "OK" : "TIMED OUT");

    // Collect frames
    running = true;
    for (int i = 0; i < 30 && running; i++) usleep(100000);
    running = false;

    printf("\n=== Results ===\nFrames: %d  Format: %s  Token: %s\n",
        frame_count, format_received ? "YES" : "NO", token.c_str());

    pw_thread_loop_stop(loop);
    pw_thread_loop_lock(loop);
    spa_hook_remove(&stream_hook);
    pw_stream_destroy(stream);
    spa_hook_remove(&core_hook);
    pw_context_destroy(context);
    pw_thread_loop_unlock(loop);
    pw_thread_loop_destroy(loop);

    dbus_close();
    printf("=== Done ===\n");
    return 0;
}
