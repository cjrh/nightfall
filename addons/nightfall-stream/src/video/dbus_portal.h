#pragma once

#include <cstdint>
#include <string>
#include <vector>

#ifdef NIGHTFALL_HAS_SYSTEMD
#include <systemd/sd-bus.h>
#endif

namespace godot {

class DBusPortal {
public:
    struct StreamInfo {
        uint32_t node_id = 0;
        uint64_t serial = 0;
        int width = 0;
        int height = 0;
        std::string id;
    };

    DBusPortal();
    ~DBusPortal();

    bool init();
    bool create_session();
    bool select_sources(const std::string &restore_token = "");
    bool start(std::vector<StreamInfo> &out_streams, std::string &out_restore_token);
    int open_pipewire_remote();
    void close_session();

    bool is_initialized() const { return initialized_; }
    uint32_t get_portal_version() const { return version_; }

private:
#ifdef NIGHTFALL_HAS_SYSTEMD
    struct sd_bus *bus_ = nullptr;
    std::string session_handle_;
    std::string sender_name_;
#endif
    bool initialized_ = false;
    uint32_t version_ = 0;
};

} // namespace godot
