#pragma once

// FFmpeg internal struct definitions for MediaCodec AHardwareBuffer access.
// These mirror FFmpeg 7.1.x internals from:
//   libavcodec/mediacodecdec_common.h
//   libavcodec/mediacodec_wrapper.h (FFAMediaCodec)
// They are NOT part of FFmpeg's public API and may change between versions.

#include <stdint.h>
#include <stdatomic.h>
#include <stdbool.h>

extern "C" {
#include <libavcodec/avcodec.h>
}

// Mirrors libavcodec/mediacodecdec_common.h
typedef struct MediaCodecDecContext {
    AVCodecContext *avctx;
    atomic_int refcount;
    atomic_int hw_buffer_count;
    char *codec_name;
    struct FFAMediaCodec *codec;
    struct FFAMediaFormat *format;
    void *surface;
    int started;
    int draining;
    int flushing;
    int eos;
    int width, height;
    int stride, slice_height;
    int color_format;
    int crop_top, crop_bottom, crop_left, crop_right;
    int display_width, display_height;
    uint64_t output_buffer_count;
    ssize_t current_input_buffer;
    bool delay_flush;
    atomic_int serial;
    bool use_ndk_codec;
} MediaCodecDecContext;

// Mirrors libavcodec/mediacodecdec_common.h
typedef struct MediaCodecBuffer {
    MediaCodecDecContext *ctx;
    ssize_t index;
    int64_t pts;
    atomic_int released;
    int serial;
} MediaCodecBuffer;

// Mirrors libavcodec/mediacodec_wrapper.h -- this is a function pointer table
typedef struct FFAMediaCodec {
    const void *class_ptr;
    char *(*getName)(struct FFAMediaCodec *);
    // ... many function pointers omitted, we only need the vtable existence
    // to confirm the object type. Unused fields padded.
    uint8_t *(*getInputBuffer)(struct FFAMediaCodec *, size_t, size_t *);
    uint8_t *(*getOutputBuffer)(struct FFAMediaCodec *, size_t, size_t *);
    ssize_t (*dequeueInputBuffer)(struct FFAMediaCodec *, int64_t);
    int (*queueInputBuffer)(struct FFAMediaCodec *, size_t, off_t, size_t, uint64_t, uint32_t);
    ssize_t (*dequeueOutputBuffer)(struct FFAMediaCodec *, void *, int64_t);
    void *(*getOutputFormat)(struct FFAMediaCodec *);
    int (*releaseOutputBuffer)(struct FFAMediaCodec *, size_t, int);
    int (*releaseOutputBufferAtTime)(struct FFAMediaCodec *, size_t, int64_t);
    // ... remaining vtable entries are irrelevant
} FFAMediaCodec;

// The JNI-backed implementation of FFAMediaCodec.
// Mirrors libavcodec/mediacodec_wrapper.c
typedef struct FFAMediaCodecJni {
    FFAMediaCodec api;
    // struct JNIAMediaCodecFields jfields;  // ~100 bytes, padded
    char _padding1[256];
    void *object;       // jobject: Java android/media/MediaCodec instance
    void *buffer_info;  // jobject: Java android/media/MediaCodec$BufferInfo
    void *input_buffers;
    void *output_buffers;
} FFAMediaCodecJni;

// Get the Java MediaCodec jobject from AVCodecContext internals.
// Returns nullptr on failure.
static inline void *mediacodec_get_codec_object(AVCodecContext *avctx) {
    if (!avctx || !avctx->priv_data) return nullptr;
    MediaCodecDecContext *ctx = (MediaCodecDecContext *)avctx->priv_data;
    if (!ctx->codec) return nullptr;
    FFAMediaCodecJni *jni = (FFAMediaCodecJni *)ctx->codec;
    return jni->object;
}

// Get the buffer index from an AVFrame produced by MediaCodec.
// Returns -1 on failure.
static inline ssize_t mediacodec_get_buffer_index(AVFrame *frame) {
    if (!frame || !frame->data[3]) return -1;
    MediaCodecBuffer *buf = (MediaCodecBuffer *)frame->data[3];
    return buf->index;
}
