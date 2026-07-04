#pragma once

#include "pipewire_capture.h"
#include "texture_uploader.h"
#include <godot_cpp/classes/ref.hpp>

namespace godot {

class DmaBufImporter {
public:
    DmaBufImporter(Ref<TextureUploader> uploader);
    ~DmaBufImporter();

    bool import_frame(const PipeWireCapture::FrameData &frame);

private:
    Ref<TextureUploader> uploader_;
    uint8_t *temp_buffer_ = nullptr;
    size_t temp_buffer_size_ = 0;
    uint32_t last_width_ = 0;
    uint32_t last_height_ = 0;
    uint32_t last_format_ = 0;
};

} // namespace godot
