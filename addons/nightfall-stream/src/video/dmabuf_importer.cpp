#include "dmabuf_importer.h"
#include "nf_log.h"

#include <sys/mman.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/dma-buf.h>
#include <errno.h>

#ifdef NIGHTFALL_HAS_PIPEWIRE
#include <spa/param/video/raw.h>
#endif

extern "C" {
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
}

namespace godot {

DmaBufImporter::DmaBufImporter(Ref<TextureUploader> uploader) : uploader_(uploader) {
}

DmaBufImporter::~DmaBufImporter() {
    if (temp_buffer_) {
        free(temp_buffer_);
    }
}

bool DmaBufImporter::import_frame(const PipeWireCapture::FrameData &frame) {
    if (!uploader_.is_valid()) return false;

    long page_size = sysconf(_SC_PAGESIZE);
    uint8_t *mapped_planes[4] = {nullptr, nullptr, nullptr, nullptr};
    void *mmap_bases[4] = {nullptr, nullptr, nullptr, nullptr};
    size_t mmap_sizes[4] = {0, 0, 0, 0};

#ifdef NIGHTFALL_HAS_PIPEWIRE
    bool is_bgrx = (frame.format == SPA_VIDEO_FORMAT_BGRx);
    bool is_rgbx = (frame.format == SPA_VIDEO_FORMAT_RGBx);
    bool is_bgra = (frame.format == SPA_VIDEO_FORMAT_BGRA);
    bool is_rgba = (frame.format == SPA_VIDEO_FORMAT_RGBA);
    bool is_rgb_format = is_bgrx || is_rgbx || is_bgra || is_rgba;

    AVPixelFormat av_fmt = AV_PIX_FMT_NONE;
    if (frame.format == SPA_VIDEO_FORMAT_NV12) {
        av_fmt = AV_PIX_FMT_NV12;
    } else if (frame.format == SPA_VIDEO_FORMAT_I420) {
        av_fmt = AV_PIX_FMT_YUV420P;
    } else if (!is_rgb_format) {
        NF_LOG("DmaBufImporter", "Unsupported SPA format: %d", frame.format);
        return false;
    }
#else
    bool is_rgb_format = false;
    bool is_rgbx = false;
    bool is_rgba = false;
    AVPixelFormat av_fmt = AV_PIX_FMT_NONE;
    return false;
#endif

    for (uint32_t i = 0; i < frame.n_planes && i < 4; i++) {
        void *data_ptr = frame.plane_datas[i];
        if (data_ptr) {
            mapped_planes[i] = static_cast<uint8_t*>(data_ptr) + frame.plane_offsets[i];
            mmap_bases[i] = nullptr;
            mmap_sizes[i] = 0;
            continue;
        }

        int fd = frame.plane_fds[i];
        if (fd < 0) continue;

        uint32_t offset = frame.plane_offsets[i];
        uint32_t plane_h = frame.height;
        if (!is_rgb_format) {
            if (i > 0 && av_fmt == AV_PIX_FMT_NV12) plane_h /= 2;
            else if (i > 0 && av_fmt == AV_PIX_FMT_YUV420P) plane_h /= 2;
        }

        size_t plane_size = frame.plane_strides[i] * plane_h;

        uint32_t page_offset = offset & ~(page_size - 1);
        uint32_t alignment_offset = offset - page_offset;
        size_t map_size = plane_size + alignment_offset;

        void *map = mmap(nullptr, map_size, PROT_READ, MAP_SHARED, fd, page_offset);
        if (map == MAP_FAILED) {
            NF_LOG("DmaBufImporter", "Failed to mmap plane %d: fd=%d, offset=%d, error=%s",
                   i, fd, page_offset, strerror(errno));
            for (uint32_t j = 0; j < i; j++) {
                if (mmap_bases[j]) {
                    struct dma_buf_sync sync_end = {};
                    sync_end.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
                    ioctl(frame.plane_fds[j], DMA_BUF_IOCTL_SYNC, &sync_end);
                    munmap(mmap_bases[j], mmap_sizes[j]);
                }
            }
            return false;
        }

        struct dma_buf_sync sync_start = {};
        sync_start.flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ;
        int sync_ret = ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync_start);
        if (sync_ret < 0) {
            NF_LOG("DmaBufImporter", "DMA_BUF_IOCTL_SYNC START failed on plane %d: fd=%d, error=%s",
                   i, fd, strerror(errno));
        }

        mmap_bases[i] = map;
        mmap_sizes[i] = map_size;
        mapped_planes[i] = static_cast<uint8_t*>(map) + alignment_offset;
    }

    if (is_rgb_format) {
        bool needs_setup = (frame.width != last_width_ || frame.height != last_height_ || frame.format != last_format_);
        if (needs_setup) {
            uploader_->setup_bgra(frame.width, frame.height);
            last_width_ = frame.width;
            last_height_ = frame.height;
            last_format_ = frame.format;
        }

        uint32_t data_size = frame.plane_strides[0] * frame.height;
        const uint8_t *src = mapped_planes[0];
        int src_stride = frame.plane_strides[0];

        if (is_rgbx || is_rgba) {
            if (!temp_buffer_ || temp_buffer_size_ < (size_t)(frame.width * frame.height * 4)) {
                temp_buffer_size_ = (size_t)(frame.width * frame.height * 4);
                temp_buffer_ = (uint8_t *)realloc(temp_buffer_, temp_buffer_size_);
            }
            uint8_t *dst = temp_buffer_;
            int dst_stride = frame.width * 4;
            for (uint32_t y = 0; y < frame.height; y++) {
                const uint8_t *src_row = src + y * src_stride;
                uint8_t *dst_row = dst + y * dst_stride;
                for (uint32_t x = 0; x < frame.width; x++) {
                    dst_row[x * 4 + 0] = src_row[x * 4 + 2];
                    dst_row[x * 4 + 1] = src_row[x * 4 + 1];
                    dst_row[x * 4 + 2] = src_row[x * 4 + 0];
                    dst_row[x * 4 + 3] = 255;
                }
            }
            uploader_->update_from_raw_bgra(frame.width, frame.height, temp_buffer_, frame.width * frame.height * 4);
        } else {
            if (src_stride == (int)(frame.width * 4)) {
                uploader_->update_from_raw_bgra(frame.width, frame.height, src, data_size);
            } else {
                if (!temp_buffer_ || temp_buffer_size_ < (size_t)(frame.width * frame.height * 4)) {
                    temp_buffer_size_ = (size_t)(frame.width * frame.height * 4);
                    temp_buffer_ = (uint8_t *)realloc(temp_buffer_, temp_buffer_size_);
                }
                int dst_stride = frame.width * 4;
                for (uint32_t y = 0; y < frame.height; y++) {
                    memcpy(temp_buffer_ + y * dst_stride, src + y * src_stride, dst_stride);
                }
                uploader_->update_from_raw_bgra(frame.width, frame.height, temp_buffer_, frame.width * frame.height * 4);
            }
        }

        for (uint32_t i = 0; i < frame.n_planes && i < 4; i++) {
            if (mmap_bases[i]) {
                struct dma_buf_sync sync_end = {};
                sync_end.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
                ioctl(frame.plane_fds[i], DMA_BUF_IOCTL_SYNC, &sync_end);
                munmap(mmap_bases[i], mmap_sizes[i]);
            }
        }
        return true;
    }

    AVFrame *av_frame = av_frame_alloc();
    if (!av_frame) {
        for (uint32_t i = 0; i < frame.n_planes && i < 4; i++) {
            if (mmap_bases[i]) {
                struct dma_buf_sync sync_end = {};
                sync_end.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
                ioctl(frame.plane_fds[i], DMA_BUF_IOCTL_SYNC, &sync_end);
                munmap(mmap_bases[i], mmap_sizes[i]);
            }
        }
        return false;
    }

    av_frame->width = frame.width;
    av_frame->height = frame.height;
    av_frame->format = av_fmt;

    for (uint32_t i = 0; i < frame.n_planes && i < 4; i++) {
        av_frame->data[i] = mapped_planes[i];
        av_frame->linesize[i] = frame.plane_strides[i];
    }

    bool needs_setup = (frame.width != last_width_ || frame.height != last_height_ || frame.format != last_format_);
    if (needs_setup) {
        uploader_->setup(frame.width, frame.height, av_fmt, 1, 0);
        last_width_ = frame.width;
        last_height_ = frame.height;
        last_format_ = frame.format;
    }
    uploader_->update_from_frame(av_frame);

    av_frame_free(&av_frame);

    for (uint32_t i = 0; i < frame.n_planes && i < 4; i++) {
        if (mmap_bases[i]) {
            struct dma_buf_sync sync_end = {};
            sync_end.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
            ioctl(frame.plane_fds[i], DMA_BUF_IOCTL_SYNC, &sync_end);
            munmap(mmap_bases[i], mmap_sizes[i]);
        }
    }

    return true;
}

} // namespace godot
