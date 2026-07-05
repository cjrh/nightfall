// Quick X11 screen capture test - captures frames and reports stats
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <thread>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XShm.h>
#include <sys/shm.h>

int main() {
    printf("=== X11 Capture Test ===\n");

    Display *display = XOpenDisplay(nullptr);
    if (!display) { fprintf(stderr, "Failed to open display\n"); return 1; }

    int screen = DefaultScreen(display);
    Window root = RootWindow(display, screen);
    XWindowAttributes attrs;
    XGetWindowAttributes(display, root, &attrs);

    printf("Screen: %dx%d depth=%d\n", attrs.width, attrs.height, attrs.depth);

    // Create SHM image
    XShmSegmentInfo shm_info;
    XImage *image = XShmCreateImage(display, DefaultVisual(display, screen),
                                     attrs.depth, ZPixmap, nullptr,
                                     &shm_info, attrs.width, attrs.height);
    if (!image) { fprintf(stderr, "XShmCreateImage failed\n"); return 1; }

    shm_info.shmid = shmget(IPC_PRIVATE, image->bytes_per_line * image->height, IPC_CREAT | 0777);
    if (shm_info.shmid < 0) { fprintf(stderr, "shmget failed\n"); return 1; }

    shm_info.shmaddr = (char *)shmat(shm_info.shmid, nullptr, 0);
    if (shm_info.shmaddr == (char *)-1) { fprintf(stderr, "shmat failed\n"); return 1; }

    shm_info.readOnly = false;
    image->data = shm_info.shmaddr;
    XShmAttach(display, &shm_info);
    XSync(display, false);
    shmctl(shm_info.shmid, IPC_RMID, nullptr);

    printf("SHM created: %d bytes, stride=%d bpp=%d\n",
           image->bytes_per_line * image->height,
           image->bytes_per_line, image->bits_per_pixel);

    // Capture 100 frames, measure timing
    int frames = 100;
    auto total_start = std::chrono::steady_clock::now();
    double min_ms = 9999, max_ms = 0, total_ms = 0;

    for (int i = 0; i < frames; i++) {
        auto t0 = std::chrono::steady_clock::now();
        XShmGetImage(display, root, image, 0, 0, AllPlanes);
        XSync(display, false);
        auto t1 = std::chrono::steady_clock::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
        total_ms += ms;
        if (ms < min_ms) min_ms = ms;
        if (ms > max_ms) max_ms = ms;

        // Save first frame
        if (i == 0) {
            uint32_t bgra_size = attrs.width * attrs.height * 4;
            uint8_t *contiguous = new uint8_t[bgra_size];
            for (int y = 0; y < attrs.height; y++)
                memcpy(contiguous + y * attrs.width * 4,
                       image->data + y * image->bytes_per_line,
                       attrs.width * 4);
            FILE *f = fopen("/tmp/x11_test_frame.bgra", "wb");
            if (f) { fwrite(contiguous, 1, bgra_size, f); fclose(f); }
            delete[] contiguous;
        }
    }

    auto total_elapsed = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - total_start).count();

    printf("\n=== Results (%d frames) ===\n", frames);
    printf("Total: %.1f ms (%.1f fps)\n", total_elapsed, frames * 1000.0 / total_elapsed);
    printf("Capture: min=%.2f ms  max=%.2f ms  avg=%.2f ms\n", min_ms, max_ms, total_ms / frames);
    printf("Frame size: %dx%d BGRA = %.1f MB\n", attrs.width, attrs.height,
           (attrs.width * attrs.height * 4) / (1024.0 * 1024.0));
    printf("Bandwidth: %.1f MB/s at 60fps\n", (attrs.width * attrs.height * 4 * 60) / (1024.0 * 1024.0));
    printf("First frame saved: /tmp/x11_test_frame.bgra (%d bytes)\n",
           attrs.width * attrs.height * 4);

    XShmDetach(display, &shm_info);
    XDestroyImage(image);
    shmdt(shm_info.shmaddr);
    XCloseDisplay(display);
    return 0;
}
