/* crash_core.c — a libretro core that crashes on demand (P6 spike).
 *
 * Purpose: prove that a native core can fault at a chosen moment so the
 * supervisor's exit-code contract can be exercised against a real signal,
 * rather than a simulated one.
 *
 * The SAME binary serves both cases, controlled by one env var, so the test
 * matrix never needs two cores:
 *
 *   unset / "0"        run clean forever (frame counter drives the picture)
 *   N >= 1             write through a null pointer during retro_run on the
 *                      Nth frame  -> SIGSEGV on POSIX
 *
 *   EZCORE_CRASH_AFTER=<N>
 *
 * Only retro_run faults. retro_init / retro_load_game / retro_get_system_info
 * stay well-behaved so the core loads and boots through the existing dynload
 * path (runtime/src/dynload_posix.c) exactly like any real core, and the crash
 * lands mid-emulation where containment actually matters.
 *
 * Deliberately built with no external dependency beyond libretro.h, matching
 * the shape of runtime/test/synth_core/. Compiled by runtime/CMakeLists.txt as
 * the `crash_libretro` shared-library target.
 */
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "libretro.h"

#define WIDTH 256
#define HEIGHT 240
#define FPS 60.0
#define SAMPLE_RATE 44100.0
#define FRAME_CAP (WIDTH * HEIGHT)

/* Reads the fault trigger once, at load time. getenv returns a borrowed
 * pointer that stays valid for the process lifetime; we copy it so a later
 * free()/realloc of the environment cannot surprise us mid-frame. */
static long g_crash_after = 0;
static unsigned long g_frame = 0;
static bool g_fired = false;

static retro_video_refresh_t     video_cb;
static retro_audio_sample_batch_t audio_batch_cb;
static retro_environment_t       env_cb;

static void read_env_triggers(void) {
    const char *raw = getenv("EZCORE_CRASH_AFTER");
    if (raw == NULL || raw[0] == '\0') {
        g_crash_after = 0;
        return;
    }
    char *end = NULL;
    long value = strtol(raw, &end, 10);
    /* A malformed value means "never fault" rather than a hard abort: the
     * clean-run path must stay reachable from the same binary. */
    g_crash_after = (end != NULL && end != raw && value > 0) ? value : 0;
}

void retro_init(void) {
    g_frame = 0;
    g_fired = false;
}

void retro_deinit(void) { }

unsigned retro_api_version(void) { return RETRO_API_VERSION; }

void retro_get_system_info(struct retro_system_info *info) {
    info->library_name     = "ezCore Crash Probe";
    info->library_version  = "1.0.0";
    info->valid_extensions = "crash";
    info->need_fullpath    = false;
    info->block_extract    = false;
}

void retro_get_system_av_info(struct retro_system_av_info *av) {
    av->geometry.base_width   = WIDTH;
    av->geometry.base_height  = HEIGHT;
    av->geometry.max_width    = WIDTH;
    av->geometry.max_height  = HEIGHT;
    av->geometry.aspect_ratio = (float)WIDTH / (float)HEIGHT;
    av->timing.fps            = FPS;
    av->timing.sample_rate    = SAMPLE_RATE;
}

bool retro_set_pixel_format(unsigned fmt) {
    (void)fmt;
    return true; /* XRGB8888 is what we render */
}

void retro_set_environment(retro_environment_t cb) {
    env_cb = cb;
    if (env_cb) {
        enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
        env_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);
    }
}

void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
void retro_set_audio_sample(retro_audio_sample_t cb) { (void)cb; }
void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { audio_batch_cb = cb; }
void retro_set_input_poll(retro_input_poll_t cb) { (void)cb; }
void retro_set_input_state(retro_input_state_t cb) { (void)cb; }

bool retro_load_game(const struct retro_game_info *game) {
    (void)game;
    g_frame = 0;
    g_fired = false;
    read_env_triggers();
    return true;
}

void retro_unload_game(void) { }

unsigned retro_get_region(void) { return RETRO_REGION_NTSC; }

void *retro_get_memory_data(unsigned id) { (void)id; return NULL; }
size_t retro_get_memory_size(unsigned id) { (void)id; return 0; }

void retro_reset(void) {
    g_frame = 0;
    g_fired = false;
}

/* The fault. `volatile` qualifies the POINTER, not the pointee: that is
 * deliberate. A plain `volatile int *` would let the compiler see a NULL
 * target, treat the store as undefined behaviour, and delete it — the core
 * would then run clean and silently prove nothing. Marking the pointer itself
 * volatile forces a real load whose value the compiler cannot know, so the
 * store is genuinely reached and the process genuinely takes SIGSEGV. */
static int * volatile g_fault_target = NULL;

void retro_run(void) {
    g_frame++;

    /* Trigger after N frames, evaluated BEFORE any output so the crash is
     * cleanly attributable to this frame and not to a half-drawn frame. */
    if (g_crash_after > 0 && !g_fired && g_frame >= (unsigned long)g_crash_after) {
        g_fired = true;
        *g_fault_target = 1; /* SIGSEGV */
    }

    if (audio_batch_cb) {
        static int16_t audio_buf[480 * 2];
        memset(audio_buf, 0, sizeof(audio_buf));
        audio_batch_cb(audio_buf, 480);
    }

    if (video_cb) {
        static uint32_t frame_buf[FRAME_CAP];
        uint8_t r = (uint8_t)(g_frame & 0xFF);
        uint32_t pixel = ((uint32_t)r << 16);
        for (int i = 0; i < FRAME_CAP; i++) frame_buf[i] = pixel;
        video_cb(frame_buf, WIDTH, HEIGHT, (size_t)WIDTH * 4);
    }
}

size_t retro_serialize_size(void) { return sizeof(g_frame); }

bool retro_serialize(void *data, size_t size) {
    if (size < sizeof(g_frame)) return false;
    memcpy(data, &g_frame, sizeof(g_frame));
    return true;
}

bool retro_unserialize(const void *data, size_t size) {
    if (size < sizeof(g_frame)) return false;
    memcpy(&g_frame, data, sizeof(g_frame));
    return true;
}

void retro_set_controller_port_device(unsigned port, unsigned device) {
    (void)port; (void)device;
}
