#pragma once

#include <cstdint>

#define VIDEO_FORMAT_RAW_NV12     0x10000
#define VIDEO_FORMAT_MASK_RAW    0x10000

#define SCM_RAW_NV12             0x01000000

#define NF_CODEC_FAMILY_RAW     4

#pragma pack(push, 1)
struct RawFrameHeader {
    char magic[4];
    uint32_t frame_number;
    uint16_t width;
    uint16_t height;
    int64_t timestamp_ns;
    uint32_t y_size;
    uint32_t uv_size;
};
#pragma pack(pop)

static_assert(sizeof(RawFrameHeader) == 28, "RawFrameHeader must be 28 bytes");
