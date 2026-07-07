#include "texture_uploader.h"
#include "yuv_shader.h"
#include <godot_cpp/variant/utility_functions.hpp>

#include "nf_log.h"

using namespace godot;

TextureUploader::TextureUploader() {
    texture_mutex.instantiate();
}

TextureUploader::~TextureUploader() {
    cleanup();
}

void TextureUploader::set_active(bool nv12) {
    use_shader_conversion = true;
    is_nv12 = nv12;
}

void TextureUploader::ensure_shader_material() {
    if (shader_material.is_null()) {
        yuv_shader.instantiate();
        yuv_shader->set_code(YUV_SHADER_CODE);
        shader_material.instantiate();
        shader_material->set_shader(yuv_shader);
        shader_material->set_shader_parameter("is_semi_planar", false);
        shader_material->set_shader_parameter("is_nv12_rd", false);
        shader_material->set_shader_parameter("color_matrix_type", 3);
        shader_material->set_shader_parameter("color_range", 1);
        shader_material->set_shader_parameter("swap_uv", false);
    }
}

void TextureUploader::setup(int width, int height, int format, int colorspace, int color_range) {
    RenderingServer *rs = RenderingServer::get_singleton();
    if (rs) {
        rs->call_on_render_thread(callable_mp(this, &TextureUploader::_render_thread_setup).bind(width, height, format, colorspace, color_range));
    }
}

void TextureUploader::setup_bgra(int width, int height) {
    use_shader_conversion = true;
    is_nv12 = false;
    current_width = width;
    current_height = height;

    // Set shader params on main thread immediately so the ColorRect
    // (which shares this material) sees BGRA mode before first frame renders.
    if (shader_material.is_valid()) {
        shader_material->set_shader_parameter("is_semi_planar", false);
        shader_material->set_shader_parameter("is_nv12_rd", false);
        shader_material->set_shader_parameter("color_matrix_type", 3);
        shader_material->set_shader_parameter("color_range", 1);
        shader_material->set_shader_parameter("swap_uv", false);
    }

    RenderingServer *rs = RenderingServer::get_singleton();
    if (rs) {
        rs->call_on_render_thread(callable_mp(this, &TextureUploader::_render_thread_setup_bgra).bind(width, height));
    }
}

void TextureUploader::_render_thread_setup_bgra(int width, int height) {
    std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));

    RenderingServer *rs = RenderingServer::get_singleton();
    rd = rs ? rs->get_rendering_device() : nullptr;

    if (rd) {
        for (int i = 0; i < 3; i++) {
            rd_texture_wrappers[i].unref();
            if (rs_texture_rid[i].is_valid()) {
                rs->free_rid(rs_texture_rid[i]);
                rs_texture_rid[i] = RID();
            }
            if (rd_texture_rid[i].is_valid()) {
                rd->free_rid(rd_texture_rid[i]);
                rd_texture_rid[i] = RID();
            }
        }

        Ref<RDTextureFormat> tf;
        tf.instantiate();
        tf->set_width(width);
        tf->set_height(height);
        tf->set_depth(1);
        tf->set_array_layers(1);
        tf->set_format(RenderingDevice::DATA_FORMAT_R8G8B8A8_UNORM);
        tf->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
        tf->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);

        Ref<RDTextureView> tv;
        tv.instantiate();

        PackedByteArray data;
        data.resize(width * height * 4);
        data.fill(0);

        TypedArray<PackedByteArray> data_array;
        data_array.push_back(data);

        rd_texture_rid[0] = rd->texture_create(tf, tv, data_array);
        rs_texture_rid[0] = rs->texture_rd_create(rd_texture_rid[0]);

        if (rd_texture_wrappers[0].is_null()) {
            rd_texture_wrappers[0].instantiate();
        }
        rd_texture_wrappers[0]->set_texture_rd_rid(rd_texture_rid[0]);
    } else {
        plane_images[0] = Image::create(width, height, false, Image::FORMAT_RGBA8);
        plane_images[0]->fill(Color(0, 0, 0, 1));
        plane_textures[0] = ImageTexture::create_from_image(plane_images[0]);
    }

    if (yuv_shader.is_null()) {
        yuv_shader.instantiate();
        yuv_shader->set_code(YUV_SHADER_CODE);
    }
    if (shader_material.is_null()) {
        shader_material.instantiate();
        shader_material->set_shader(yuv_shader);
    }

    if (shader_material.is_valid()) {
        shader_material->set_shader_parameter("is_semi_planar", false);
        shader_material->set_shader_parameter("is_nv12_rd", false);
        shader_material->set_shader_parameter("color_matrix_type", 3);
        shader_material->set_shader_parameter("color_range", 1);
        shader_material->set_shader_parameter("swap_uv", false);

        if (rd) {
            shader_material->set_shader_parameter("tex_y", rd_texture_wrappers[0]);
        } else {
            shader_material->set_shader_parameter("tex_y", plane_textures[0]);
        }
    }
}

void TextureUploader::_render_thread_setup(int width, int height, int format, int colorspace, int color_range) {
    std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));
    AVPixelFormat av_format = (AVPixelFormat)format;
    AVColorSpace av_colorspace = (AVColorSpace)colorspace;
    AVColorRange av_color_range = (AVColorRange)color_range;

    RenderingServer *rs = RenderingServer::get_singleton();
    if (rd) {
        for (int i = 0; i < 3; i++) {
            rd_texture_wrappers[i].unref();
            if (rs_texture_rid[i].is_valid()) {
                rs->free_rid(rs_texture_rid[i]);
                rs_texture_rid[i] = RID();
            }
            if (rd_texture_rid[i].is_valid()) {
                rd->free_rid(rd_texture_rid[i]);
                rd_texture_rid[i] = RID();
            }
        }
    }

    is_nv12 = (av_format == AV_PIX_FMT_NV12);
    bool is_yuv420p = (av_format == AV_PIX_FMT_YUV420P);

    if (!is_nv12 && !is_yuv420p) {
        if (av_format == AV_PIX_FMT_NONE) {
            is_nv12 = true;
        } else {
            use_shader_conversion = false;
            return;
        }
    }

    use_shader_conversion = true;
    current_width = width;
    current_height = height;

    int y_w = width;
    int y_h = height;
    int uv_w = width / 2;
    int uv_h = height / 2;

    rd = rs->get_rendering_device();
    if (rd) {
        auto create_rd_texture = [&](int idx, int w, int h, RenderingDevice::DataFormat fmt) {
            Ref<RDTextureFormat> tf;
            tf.instantiate();
            tf->set_width(w);
            tf->set_height(h);
            tf->set_depth(1);
            tf->set_array_layers(1);
            tf->set_format(fmt);
            tf->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
            tf->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);

            Ref<RDTextureView> tv;
            tv.instantiate();

            PackedByteArray data;
            data.resize(w * h * (fmt == RenderingDevice::DATA_FORMAT_R8G8_UNORM ? 2 : 1));
            if (fmt == RenderingDevice::DATA_FORMAT_R8G8_UNORM || idx > 0)
                data.fill(128);
            else
                data.fill(0);

            TypedArray<PackedByteArray> data_array;
            data_array.push_back(data);

            rd_texture_rid[idx] = rd->texture_create(tf, tv, data_array);
            rs_texture_rid[idx] = rs->texture_rd_create(rd_texture_rid[idx]);

            if (rd_texture_wrappers[idx].is_null()) {
                rd_texture_wrappers[idx].instantiate();
            }
            rd_texture_wrappers[idx]->set_texture_rd_rid(rd_texture_rid[idx]);
        };

        create_rd_texture(0, y_w, y_h, RenderingDevice::DATA_FORMAT_R8_UNORM);
        create_rd_texture(1, is_nv12 ? y_w : uv_w, uv_h, RenderingDevice::DATA_FORMAT_R8_UNORM);
        create_rd_texture(2, uv_w, uv_h, RenderingDevice::DATA_FORMAT_R8_UNORM);
    } else {
        plane_images[0] = Image::create(y_w, y_h, false, Image::FORMAT_L8);
        plane_images[0]->fill(Color(0, 0, 0));
        plane_textures[0] = ImageTexture::create_from_image(plane_images[0]);

        plane_images[1] = Image::create(uv_w, uv_h, false, Image::FORMAT_L8);
        plane_images[1]->fill(Color(0.5, 0.5, 0.5));
        plane_textures[1] = ImageTexture::create_from_image(plane_images[1]);

        plane_images[2] = Image::create(uv_w, uv_h, false, Image::FORMAT_L8);
        plane_images[2]->fill(Color(0.5, 0.5, 0.5));
        plane_textures[2] = ImageTexture::create_from_image(plane_images[2]);
    }

    if (yuv_shader.is_null()) {
        yuv_shader.instantiate();
        yuv_shader->set_code(YUV_SHADER_CODE);
    }
    if (shader_material.is_null()) {
        shader_material.instantiate();
        shader_material->set_shader(yuv_shader);
    }

    int matrix_type = 1;
    if (av_colorspace == AVCOL_SPC_BT470BG || av_colorspace == AVCOL_SPC_SMPTE170M)
        matrix_type = 0;
    else if (av_colorspace == AVCOL_SPC_BT2020_NCL || av_colorspace == AVCOL_SPC_BT2020_CL)
        matrix_type = 2;
    else if (width < 1280 && height < 720)
        matrix_type = 0;

    int range_val = (av_color_range == AVCOL_RANGE_JPEG) ? 1 : 0;
    bool shader_semi = is_nv12 && !rd;

    if (shader_material.is_valid()) {
        shader_material->set_shader_parameter("is_semi_planar", shader_semi);
        shader_material->set_shader_parameter("is_nv12_rd", is_nv12 && rd);
        shader_material->set_shader_parameter("color_matrix_type", matrix_type);
        shader_material->set_shader_parameter("color_range", range_val);
        shader_material->set_shader_parameter("swap_uv", false);

        if (rd) {
            shader_material->set_shader_parameter("tex_y", rd_texture_wrappers[0]);
            shader_material->set_shader_parameter("tex_u", rd_texture_wrappers[1]);
            shader_material->set_shader_parameter("tex_v", rd_texture_wrappers[2]);
        } else {
            shader_material->set_shader_parameter("tex_y", plane_textures[0]);
            shader_material->set_shader_parameter("tex_u", plane_textures[1]);
            shader_material->set_shader_parameter("tex_v", plane_textures[2]);
        }
    }
}

void TextureUploader::update_colorspace(int colorspace, int color_range) {
    if (!shader_material.is_valid()) return;

    AVColorSpace av_cs = (AVColorSpace)colorspace;
    AVColorRange av_cr = (AVColorRange)color_range;

    int matrix_type = 1;
    if (av_cs == AVCOL_SPC_BT470BG || av_cs == AVCOL_SPC_SMPTE170M)
        matrix_type = 0;
    else if (av_cs == AVCOL_SPC_BT2020_NCL || av_cs == AVCOL_SPC_BT2020_CL)
        matrix_type = 2;

    int range_val = (av_cr == AVCOL_RANGE_JPEG) ? 1 : 0;

    shader_material->set_shader_parameter("color_matrix_type", matrix_type);
    shader_material->set_shader_parameter("color_range", range_val);
}

void TextureUploader::update_from_frame(AVFrame *frame) {
    if (!frame || !use_shader_conversion) return;

    static int upload_count = 0;
    upload_count++;
    if (upload_count <= 3 || upload_count % 60 == 0) {
        NF_LOG("TextureUploader", "Update #%d: %dx%d fmt=%d(%s) nv12=%d linesize=%d,%d,%d",
               upload_count, frame->width, frame->height, frame->format,
               av_get_pix_fmt_name((AVPixelFormat)frame->format),
               is_nv12, frame->linesize[0], frame->linesize[1], frame->linesize[2]);
    }

    RenderingServer *rs = RenderingServer::get_singleton();

    if (rd) {
        std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));

        auto upload_rd = [&](int idx, int av_idx, int w, int h, int bpp) {
            int src_stride = frame->linesize[av_idx];
            int dst_stride = w * bpp;
            int required_size = dst_stride * h;

            if (rd_texture_buffers[idx].size() != required_size)
                rd_texture_buffers[idx].resize(required_size);

            uint8_t *dst = rd_texture_buffers[idx].ptrw();
            uint8_t *src = frame->data[av_idx];

            if (src_stride == dst_stride) {
                memcpy(dst, src, required_size);
            } else {
                for (int i = 0; i < h; i++)
                    memcpy(dst + i * dst_stride, src + i * src_stride, dst_stride);
            }
        };

        upload_rd(0, 0, frame->width, frame->height, 1);

        if (is_nv12) {
            upload_rd(1, 1, frame->width, frame->height / 2, 1);
        } else {
            upload_rd(1, 1, frame->width / 2, frame->height / 2, 1);
            upload_rd(2, 2, frame->width / 2, frame->height / 2, 1);
        }

        pending_gpu_update.store(true);
    }

    if (rd) {
        rs->call_on_render_thread(callable_mp(this, &TextureUploader::perform_gpu_update));
        return;
    }

    auto upload_plane = [&](int gl_idx, int av_idx, int w, int h, int bpp) {
        Ref<Image> img = plane_images[gl_idx];
        Ref<ImageTexture> tex = plane_textures[gl_idx];
        if (img.is_null() || img->is_empty() || tex.is_null()) return;

        int src_stride = frame->linesize[av_idx];
        int dst_stride = w * bpp;
        int required_size = dst_stride * h;

        if (plane_buffers[gl_idx].size() != required_size)
            plane_buffers[gl_idx].resize(required_size);

        uint8_t *dst = plane_buffers[gl_idx].ptrw();
        uint8_t *src = frame->data[av_idx];

        if (src_stride == dst_stride) {
            memcpy(dst, src, required_size);
        } else {
            for (int i = 0; i < h; i++)
                memcpy(dst + i * dst_stride, src + i * src_stride, dst_stride);
        }

        img->set_data(w, h, false, (bpp == 2) ? Image::FORMAT_RG8 : Image::FORMAT_L8, plane_buffers[gl_idx]);
        if (img->is_empty()) return;
        rs->texture_2d_update(tex->get_rid(), img, 0);
    };

    upload_plane(0, 0, frame->width, frame->height, 1);
    if (is_nv12) {
        upload_plane(1, 1, frame->width / 2, frame->height / 2, 2);
    } else {
        upload_plane(1, 1, frame->width / 2, frame->height / 2, 1);
        upload_plane(2, 2, frame->width / 2, frame->height / 2, 1);
    }
}

void TextureUploader::update_from_raw_nv12(int width, int height, const uint8_t *data, uint32_t y_size, uint32_t uv_size) {
    if (!data || !use_shader_conversion) return;

    const uint8_t *y_data = data;
    const uint8_t *uv_data = data + y_size;

    RenderingServer *rs = RenderingServer::get_singleton();

    if (rd) {
        std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));

        int y_stride = width;
        int required_y = y_stride * height;
        if (rd_texture_buffers[0].size() != required_y)
            rd_texture_buffers[0].resize(required_y);
        memcpy(rd_texture_buffers[0].ptrw(), y_data, required_y);

        if (is_nv12) {
            int uv_stride = width;
            int required_uv = uv_stride * (height / 2);
            if (rd_texture_buffers[1].size() != required_uv)
                rd_texture_buffers[1].resize(required_uv);
            memcpy(rd_texture_buffers[1].ptrw(), uv_data, required_uv);
        } else {
            int uv_w = width / 2;
            int uv_h = height / 2;
            int required_u = uv_w * uv_h;
            int required_v = uv_w * uv_h;
            if (rd_texture_buffers[1].size() != required_u)
                rd_texture_buffers[1].resize(required_u);
            if (rd_texture_buffers[2].size() != required_v)
                rd_texture_buffers[2].resize(required_v);
            uint8_t *u_dst = rd_texture_buffers[1].ptrw();
            uint8_t *v_dst = rd_texture_buffers[2].ptrw();
            for (int i = 0; i < uv_w * uv_h; i++) {
                u_dst[i] = uv_data[i * 2];
                v_dst[i] = uv_data[i * 2 + 1];
            }
        }

        pending_gpu_update.store(true);
        rs->call_on_render_thread(callable_mp(this, &TextureUploader::perform_gpu_update));
        return;
    }

    int y_stride = width;
    if (plane_buffers[0].size() != (int)y_size)
        plane_buffers[0].resize(y_size);
    memcpy(plane_buffers[0].ptrw(), y_data, y_size);
    plane_images[0]->set_data(width, height, false, Image::FORMAT_L8, plane_buffers[0]);
    rs->texture_2d_update(plane_textures[0]->get_rid(), plane_images[0], 0);

    if (is_nv12) {
        int uv_h = height / 2;
        PackedByteArray uv_buf;
        uv_buf.resize(uv_size);
        memcpy(uv_buf.ptrw(), uv_data, uv_size);
        plane_images[1]->set_data(width / 2, uv_h, false, Image::FORMAT_RG8, uv_buf);
        rs->texture_2d_update(plane_textures[1]->get_rid(), plane_images[1], 0);
    } else {
        int uv_w = width / 2;
        int uv_h = height / 2;
        PackedByteArray u_buf, v_buf;
        u_buf.resize(uv_w * uv_h);
        v_buf.resize(uv_w * uv_h);
        for (int i = 0; i < uv_w * uv_h; i++) {
            u_buf.ptrw()[i] = uv_data[i * 2];
            v_buf.ptrw()[i] = uv_data[i * 2 + 1];
        }
        plane_images[1]->set_data(uv_w, uv_h, false, Image::FORMAT_L8, u_buf);
        rs->texture_2d_update(plane_textures[1]->get_rid(), plane_images[1], 0);
        plane_images[2]->set_data(uv_w, uv_h, false, Image::FORMAT_L8, v_buf);
        rs->texture_2d_update(plane_textures[2]->get_rid(), plane_images[2], 0);
    }
}

void TextureUploader::update_from_raw_bgra(int width, int height, const uint8_t *data, uint32_t data_size) {
    if (!data || !use_shader_conversion) return;

    RenderingServer *rs = RenderingServer::get_singleton();

    if (rd) {
        std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));

        int required = width * height * 4;
        if (rd_texture_buffers[0].size() != required)
            rd_texture_buffers[0].resize(required);

        int src_stride = width * 4;
        int dst_stride = width * 4;
        if (src_stride == dst_stride) {
            memcpy(rd_texture_buffers[0].ptrw(), data, required);
        } else {
            uint8_t *dst = rd_texture_buffers[0].ptrw();
            for (int i = 0; i < height; i++)
                memcpy(dst + i * dst_stride, data + i * src_stride, dst_stride);
        }

        pending_gpu_update.store(true);
        rs->call_on_render_thread(callable_mp(this, &TextureUploader::perform_gpu_update));
        return;
    }

    PackedByteArray bgra_buf;
    bgra_buf.resize(data_size);
    memcpy(bgra_buf.ptrw(), data, data_size);
    Ref<Image> img = Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, bgra_buf);
    if (img.is_valid() && !img->is_empty() && plane_textures[0].is_valid()) {
        rs->texture_2d_update(plane_textures[0]->get_rid(), img, 0);
    }
}

void TextureUploader::perform_gpu_update() {
    if (!rd) return;
    std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));
    if (pending_gpu_update.exchange(false)) {
        static int gpu_update_count = 0;
        if (++gpu_update_count <= 3) {
            NF_LOG("TextureUploader",
                "perform_gpu_update #%d: tex0=%d tex1=%d tex2=%d",
                gpu_update_count,
                rd_texture_rid[0].is_valid(), rd_texture_rid[1].is_valid(), rd_texture_rid[2].is_valid());
        }
        if (rd_texture_rid[0].is_valid())
            rd->texture_update(rd_texture_rid[0], 0, rd_texture_buffers[0]);
        if (rd_texture_rid[1].is_valid())
            rd->texture_update(rd_texture_rid[1], 0, rd_texture_buffers[1]);
        if (!is_nv12 && rd_texture_rid[2].is_valid())
            rd->texture_update(rd_texture_rid[2], 0, rd_texture_buffers[2]);
        new_frame_available_.store(true);
    }
}

void TextureUploader::cleanup() {
    RenderingServer *rs = RenderingServer::get_singleton();
    if (!rs) return;
    rs->call_on_render_thread(callable_mp(this, &TextureUploader::_render_thread_cleanup));
}

void TextureUploader::_render_thread_cleanup() {
    std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));
    RenderingServer *rs = RenderingServer::get_singleton();
    if (rd) {
        for (int i = 0; i < 3; i++) {
            rd_texture_wrappers[i].unref();
            if (rs_texture_rid[i].is_valid()) {
                rs->free_rid(rs_texture_rid[i]);
                rs_texture_rid[i] = RID();
            }
            if (rd_texture_rid[i].is_valid()) {
                rd->free_rid(rd_texture_rid[i]);
                rd_texture_rid[i] = RID();
            }
        }
        rd = nullptr;
    }
    use_shader_conversion = false;
}

void TextureUploader::_bind_methods() {
    ClassDB::bind_method(D_METHOD("setup", "width", "height", "format", "colorspace", "color_range"), &TextureUploader::setup);
    ClassDB::bind_method(D_METHOD("cleanup"), &TextureUploader::cleanup);
    ClassDB::bind_method(D_METHOD("get_shader_material"), &TextureUploader::get_shader_material);
    ClassDB::bind_method(D_METHOD("perform_gpu_update"), &TextureUploader::perform_gpu_update);
    ClassDB::bind_method(D_METHOD("consume_new_frame"), &TextureUploader::consume_new_frame);
}

bool TextureUploader::consume_new_frame() {
    return new_frame_available_.exchange(false);
}
