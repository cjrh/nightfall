#include "x11_capture.h"
#include "nf_log.h"

#ifdef NIGHTFALL_HAS_X11
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XShm.h>
#include <sys/shm.h>
#include <cstdlib>
#include <cstring>
#include <chrono>

namespace godot {

X11Capture::X11Capture() = default;

X11Capture::~X11Capture() {
    stop();
}

bool X11Capture::start() {
    if (running_.load()) return true;

    display_ = XOpenDisplay(nullptr);
    if (!display_) {
        NF_LOGE("X11Capture", "Failed to open X display");
        return false;
    }

    screen_ = DefaultScreen(display_);
    Window root = RootWindow(display_, screen_);

    XWindowAttributes attrs;
    XGetWindowAttributes(display_, root, &attrs);
    width_ = attrs.width;
    height_ = attrs.height;

    NF_LOG("X11Capture", "Screen: %dx%d", width_, height_);

    if (width_ == 0 || height_ == 0) {
        NF_LOGE("X11Capture", "Invalid screen dimensions");
        XCloseDisplay(display_);
        display_ = nullptr;
        return false;
    }

    // Create shared memory XImage
    image_ = XShmCreateImage(display_, DefaultVisual(display_, screen_),
                             DefaultDepth(display_, screen_), ZPixmap, nullptr,
                             &shm_info_, width_, height_);
    if (!image_) {
        NF_LOGE("X11Capture", "XShmCreateImage failed");
        XCloseDisplay(display_);
        display_ = nullptr;
        return false;
    }

    shm_info_.shmid = shmget(IPC_PRIVATE, image_->bytes_per_line * image_->height,
                              IPC_CREAT | 0777);
    if (shm_info_.shmid < 0) {
        NF_LOGE("X11Capture", "shmget failed");
        XDestroyImage(image_);
        image_ = nullptr;
        XCloseDisplay(display_);
        display_ = nullptr;
        return false;
    }

    shm_info_.shmaddr = (char *)shmat(shm_info_.shmid, 0, 0);
    if (shm_info_.shmaddr == (char *)-1) {
        NF_LOGE("X11Capture", "shmat failed");
        XDestroyImage(image_);
        image_ = nullptr;
        XCloseDisplay(display_);
        display_ = nullptr;
        return false;
    }

    shm_info_.readOnly = false;
    image_->data = shm_info_.shmaddr;

    XShmAttach(display_, &shm_info_);
    XSync(display_, false);
    shmctl(shm_info_.shmid, IPC_RMID, 0); // mark for deletion after detach

    NF_LOG("X11Capture", "SHM created: %d bytes, %dx%d stride=%d",
           image_->bytes_per_line * image_->height,
           image_->width, image_->height, image_->bytes_per_line);

    running_.store(true);
    worker_thread_ = std::thread(&X11Capture::capture_loop, this);
    return true;
}

void X11Capture::stop() {
    running_.store(false);
    if (worker_thread_.joinable()) {
        worker_thread_.join();
    }

    if (image_) {
        XShmDetach(display_, &shm_info_);
        XDestroyImage(image_);
        image_ = nullptr;
        shmdt(shm_info_.shmaddr);
    }
    if (display_) {
        XCloseDisplay(display_);
        display_ = nullptr;
    }
    has_new_frame_ = false;
}

bool X11Capture::has_new_frame() const {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    return has_new_frame_;
}

bool X11Capture::get_latest_frame(FrameData &out_frame) {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    if (!has_new_frame_) return false;
    out_frame = latest_frame_;
    has_new_frame_ = false;
    return true;
}

void X11Capture::release_frame() {
    // X11 SHM frames don't need queue management - the next capture
    // overwrites the shared memory buffer. Nothing to do here.
}

void X11Capture::capture_loop() {
    Window root = RootWindow(display_, screen_);
    int frame_num = 0;
    auto last_report = std::chrono::steady_clock::now();

    while (running_.load()) {
        XShmGetImage(display_, root, image_, 0, 0, AllPlanes);

        XSync(display_, false);

        frame_num++;
        {
            std::lock_guard<std::mutex> lock(frame_mutex_);
            latest_frame_.data = (uint8_t *)image_->data;
            latest_frame_.width = width_;
            latest_frame_.height = height_;
            latest_frame_.stride = image_->bytes_per_line;
            has_new_frame_ = true;
        }

        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_report).count();
        if (elapsed >= 5000) {
            NF_LOG("X11Capture", "Captured %d frames in %lldms (%.1f fps)",
                   frame_num, (long long)elapsed, frame_num * 1000.0 / elapsed);
            frame_num = 0;
            last_report = now;
        }
    }
}

} // namespace godot

#else // NIGHTFALL_HAS_X11

namespace godot {
X11Capture::X11Capture() = default;
X11Capture::~X11Capture() = default;
bool X11Capture::start() { return false; }
void X11Capture::stop() {}
bool X11Capture::has_new_frame() const { return false; }
bool X11Capture::get_latest_frame(FrameData&) { return false; }
void X11Capture::release_frame() {}
} // namespace godot

#endif // NIGHTFALL_HAS_X11
