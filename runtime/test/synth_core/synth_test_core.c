/* synth_test_core.c — deterministic synthetic libretro core.
 *
 * NOT a real emulator. A minimal libretro ABI citizen used to verify
 * the ezCore runtime's input, reset, audio, frame, and lifecycle paths
 * without needing copyrighted ROMs.
 *
 *   - 256x240 @ 60fps, stereo s16 @ 44100 Hz
 *   - Requests XRGB8888 pixel format from the host
 *   - Frame: R channel = frame_counter & 0xFF, G = (frame_counter/2) & 0xFF,
 *     B increments every 16 frames
 *   - Audio: sample = 0x1000 ^ (button_state & 0x00FF) — deterministic,
 *     so button presses are verifiable in the audio output
 *   - Reset: zeroes frame_counter, audio_sample_counter
 *   - Serialize: 16-byte state blob
 */
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "libretro.h"

#define WIDTH 256
#define HEIGHT 240
#define FPS 60.0
#define SAMPLE_RATE 44100.0
#define FRAME_CAP (WIDTH * HEIGHT)
#define AUDIO_FRAMES_PER_RUN 480

struct synth_state {
    uint32_t frame_counter;
    uint32_t button_state;
    uint32_t audio_sample_counter;
    uint32_t magic; /* sentinel: 0x53594E54 "SYNT" */
};

static struct synth_state g_state = {0, 0, 0, 0x53594E54};

static void render_frame(uint32_t *buf) {
    uint8_t r = (uint8_t)(g_state.frame_counter & 0xFF);
    uint8_t g = (uint8_t)((g_state.frame_counter / 2) & 0xFF);
    uint8_t b = (uint8_t)((g_state.frame_counter / 16) & 0xFF);
    uint32_t pixel = ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
    for (int i = 0; i < FRAME_CAP; i++) {
        buf[i] = pixel;
    }
}

static retro_video_refresh_t     video_cb;
static retro_audio_sample_t      audio_sample_cb;
static retro_audio_sample_batch_t audio_batch_cb;
static retro_input_poll_t        input_poll_cb;
static retro_input_state_t       input_state_cb;
static retro_environment_t       env_cb;

void retro_init(void) { /* state already zeroed */ }

void retro_deinit(void) { }

unsigned retro_api_version(void) { return RETRO_API_VERSION; }

void retro_get_system_info(struct retro_system_info *info) {
    info->library_name     = "ezTest Synth";
    info->library_version  = "1.0.0";
    info->valid_extensions = "synth";
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
    if (fmt != RETRO_PIXEL_FORMAT_XRGB8888 &&
        fmt != RETRO_PIXEL_FORMAT_0RGB1555 &&
        fmt != RETRO_PIXEL_FORMAT_RGB565) {
        return false;
    }
    /* We render in XRGB8888, so request that format */
    (void)fmt;
    return true;
}

void retro_set_environment(retro_environment_t cb) {
    env_cb = cb;
    /* Request XRGB8888 format from the host */
    if (env_cb) {
        enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
        env_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);
    }
}

void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }

void retro_set_audio_sample(retro_audio_sample_t cb) { audio_sample_cb = cb; }

void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) {
    audio_batch_cb = cb;
}

void retro_set_input_poll(retro_input_poll_t cb) { input_poll_cb = cb; }

void retro_set_input_state(retro_input_state_t cb) { input_state_cb = cb; }

bool retro_load_game(const struct retro_game_info *game) {
    (void)game;
    g_state.frame_counter = 0;
    g_state.audio_sample_counter = 0;
    return true;
}

void retro_unload_game(void) { }

unsigned retro_get_region(void) { return RETRO_REGION_NTSC; }

void *retro_get_memory_data(unsigned id) { (void)id; return NULL; }
size_t retro_get_memory_size(unsigned id) { (void)id; return 0; }

void retro_reset(void) {
    g_state.frame_counter = 0;
    g_state.audio_sample_counter = 0;
}

void retro_run(void) {
    if (input_poll_cb) input_poll_cb();

    if (input_state_cb) {
        uint32_t mask = 0;
        for (unsigned id = 0; id < 16; id++) {
            if (input_state_cb(0, RETRO_DEVICE_JOYPAD, 0, id))
                mask |= (1u << id);
        }
        g_state.button_state = mask;
    }

    g_state.frame_counter++;

    uint8_t btn_lo = (uint8_t)(g_state.button_state & 0x00FF);
    int16_t sample = (int16_t)(0x1000 ^ btn_lo);

    static int16_t audio_buf[2048];
    for (size_t i = 0; i < AUDIO_FRAMES_PER_RUN; i++) {
        audio_buf[i * 2]     = sample;
        audio_buf[i * 2 + 1] = sample;
    }
    if (audio_batch_cb) audio_batch_cb(audio_buf, AUDIO_FRAMES_PER_RUN);
    else if (audio_sample_cb) {
        for (size_t i = 0; i < AUDIO_FRAMES_PER_RUN; i++)
            audio_sample_cb(audio_buf[i * 2], audio_buf[i * 2 + 1]);
    }
    g_state.audio_sample_counter += AUDIO_FRAMES_PER_RUN;

    if (video_cb) {
        static uint32_t frame_buf[FRAME_CAP];
        render_frame(frame_buf);
        video_cb(frame_buf, WIDTH, HEIGHT, (size_t)WIDTH * 4);
    }
}

size_t retro_serialize_size(void) { return sizeof(g_state); }

bool retro_serialize(void *data, size_t size) {
    if (size < sizeof(g_state)) return false;
    memcpy(data, &g_state, sizeof(g_state));
    return true;
}

bool retro_unserialize(const void *data, size_t size) {
    if (size < sizeof(g_state)) return false;
    memcpy(&g_state, data, sizeof(g_state));
    return true;
}

void retro_cheat_reset(void) { }

void retro_cheat_set(unsigned index, bool enabled, const char *code) {
    (void)index; (void)enabled; (void)code;
}

void retro_set_controller_port_device(unsigned port, unsigned device) {
    (void)port; (void)device;
}
