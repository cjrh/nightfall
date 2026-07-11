#include "video/decode_unit_queue.h"

#include <cassert>
#include <utility>

namespace {

godot::DecodeUnitQueue::DecodeUnit make_unit(int frame_number, bool is_idr = false) {
    godot::DecodeUnitQueue::DecodeUnit unit;
    unit.packet.reset(av_packet_alloc());
    assert(unit.packet);
    unit.frame_number = frame_number;
    unit.is_idr = is_idr;
    unit.presentation_time_us = frame_number * 1000;
    return unit;
}

void test_fifo_and_backpressure_return() {
    godot::DecodeUnitQueue queue(2);
    assert(queue.push(make_unit(1, true)).accepted);
    assert(queue.push(make_unit(2)).accepted);

    auto first = queue.pop();
    assert(first && first->frame_number == 1);
    assert(queue.return_front(std::move(*first)).accepted);

    first = queue.pop();
    auto second = queue.pop();
    assert(first && first->frame_number == 1);
    assert(second && second->frame_number == 2);
    assert(queue.empty());
}

void test_overflow_waits_for_idr() {
    godot::DecodeUnitQueue queue(2);
    assert(queue.push(make_unit(1, true)).accepted);
    assert(queue.push(make_unit(2)).accepted);

    const auto overflow = queue.push(make_unit(3));
    assert(!overflow.accepted);
    assert(overflow.request_idr);
    assert(overflow.dropped == 3);
    assert(queue.empty());
    assert(queue.awaiting_idr());

    const auto dependent = queue.push(make_unit(4));
    assert(!dependent.accepted);
    assert(!dependent.request_idr);
    assert(dependent.dropped == 1);

    const auto recovery = queue.push(make_unit(5, true));
    assert(recovery.accepted);
    assert(!queue.awaiting_idr());
    assert(queue.size() == 1);
    auto idr = queue.pop();
    assert(idr && idr->frame_number == 5);
}

void test_idr_replaces_full_backlog() {
    godot::DecodeUnitQueue queue(2);
    assert(queue.push(make_unit(1, true)).accepted);
    assert(queue.push(make_unit(2)).accepted);

    const auto recovery = queue.push(make_unit(3, true));
    assert(recovery.accepted);
    assert(!recovery.request_idr);
    assert(recovery.dropped == 2);
    assert(queue.size() == 1);

    auto idr = queue.pop();
    assert(idr && idr->frame_number == 3);
}

void test_requeue_is_bounded() {
    godot::DecodeUnitQueue queue(2);
    assert(queue.push(make_unit(1, true)).accepted);
    assert(queue.push(make_unit(2)).accepted);
    auto in_flight = queue.pop();
    assert(in_flight && in_flight->frame_number == 1);

    // A producer can fill the vacated slot while MediaCodec has no input slot.
    assert(queue.push(make_unit(3)).accepted);
    const auto requeue = queue.return_front(std::move(*in_flight));
    assert(!requeue.accepted);
    assert(requeue.request_idr);
    assert(requeue.dropped == 3);
    assert(queue.empty());
    assert(queue.awaiting_idr());
}

} // namespace

int main() {
    test_fifo_and_backpressure_return();
    test_overflow_waits_for_idr();
    test_idr_replaces_full_backlog();
    test_requeue_is_bounded();
}
