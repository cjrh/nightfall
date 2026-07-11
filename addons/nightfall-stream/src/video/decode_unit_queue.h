#pragma once

extern "C" {
#include <libavcodec/packet.h>
}

#include <cstddef>
#include <cstdint>
#include <deque>
#include <memory>
#include <optional>
#include <utility>

namespace godot {

// Owns a small FIFO of compressed decode units and recovers safely from
// overload. Once any dependent unit is discarded, only a later IDR starts a
// new decodable sequence.
class DecodeUnitQueue {
public:
    static constexpr size_t kDefaultCapacity = 4;

    struct PacketDeleter {
        void operator()(AVPacket *packet) const {
            av_packet_free(&packet);
        }
    };

    using PacketPtr = std::unique_ptr<AVPacket, PacketDeleter>;

    struct DecodeUnit {
        PacketPtr packet;
        bool is_idr = false;
        int frame_number = 0;
        int64_t presentation_time_us = 0;
    };

    struct PushResult {
        bool accepted = false;
        bool request_idr = false;
        size_t dropped = 0;
    };

    explicit DecodeUnitQueue(size_t capacity = kDefaultCapacity)
        : capacity_(capacity) {}

    // Takes ownership of `unit`. On overflow, drops the obsolete reference
    // chain and accepts only the next IDR, rather than decoding stale work.
    PushResult push(DecodeUnit unit) {
        if (awaiting_idr_) {
            if (!unit.is_idr) {
                return {false, false, 1};
            }

            const size_t dropped = units_.size();
            units_.clear();
            awaiting_idr_ = false;
            units_.push_back(std::move(unit));
            return {true, false, dropped};
        }

        if (units_.size() < capacity_) {
            units_.push_back(std::move(unit));
            return {true, false, 0};
        }

        // A fresh IDR is independently decodable, so it can replace an old
        // backlog immediately. Other units require an IDR resynchronization.
        if (unit.is_idr) {
            const size_t dropped = units_.size();
            units_.clear();
            units_.push_back(std::move(unit));
            return {true, false, dropped};
        }

        const size_t dropped = units_.size() + 1;
        units_.clear();
        awaiting_idr_ = true;
        return {false, true, dropped};
    }

    std::optional<DecodeUnit> pop() {
        if (units_.empty()) {
            return std::nullopt;
        }

        DecodeUnit unit = std::move(units_.front());
        units_.pop_front();
        return unit;
    }

    // Restores a unit after decoder input backpressure. If producers filled
    // the vacated slot first, discard the stale sequence and request an IDR.
    PushResult return_front(DecodeUnit unit) {
        if (awaiting_idr_) {
            return {false, false, 1};
        }
        if (units_.size() < capacity_) {
            units_.push_front(std::move(unit));
            return {true, false, 0};
        }

        const size_t dropped = units_.size() + 1;
        units_.clear();
        awaiting_idr_ = true;
        return {false, true, dropped};
    }

    void clear() {
        units_.clear();
        awaiting_idr_ = false;
    }

    bool empty() const { return units_.empty(); }
    size_t size() const { return units_.size(); }
    bool awaiting_idr() const { return awaiting_idr_; }

private:
    const size_t capacity_;
    std::deque<DecodeUnit> units_;
    bool awaiting_idr_ = false;
};

} // namespace godot
