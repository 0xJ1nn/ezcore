/* synth_input_core.c — a libretro core that READS every input device.
 *
 * NOT a real emulator. Used by test_input_devices.c to prove that analog
 * sticks, analog triggers, the mouse, the keyboard (polled and by event
 * callback) and the pointer reach a core. Each frame it echoes what it read
 * into the audio stream, one value per sample, in this order:
 *
 *   0 left stick x (port 0)    1 left stick y (port 0)
 *   2 right stick x (port 1)   3 R2 as an analog button (port 0)
 *   4 mouse dx                 5 mouse dy
 *   6 mouse left               7 keyboard 'a' (polled)
 *   8 pointer x                9 pointer y
 *  10 pointer pressed         11 last keyboard event: down
 *  12 last keyboard event: keycode   13 keyboard events this frame
 *  14 mouse dx, read a second time this frame (must equal sample 4)
 *  15 1 if the host answered GET_INPUT_BITMASKS
 */
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "libretro.h"

static retro_environment_t env_cb;
static retro_video_refresh_t video_cb;
static retro_audio_sample_batch_t audio_batch_cb;
static retro_input_poll_t input_poll_cb;
static retro_input_state_t input_state_cb;

static bool g_bitmasks;
static int16_t g_kb_down, g_kb_code, g_kb_count;
static uint32_t g_fb[4 * 4];

static void on_key(bool down, unsigned keycode, uint32_t character,
                   uint16_t mods) {
  (void)character; (void)mods;
  g_kb_down = down ? 1 : 0;
  g_kb_code = (int16_t)keycode;
  g_kb_count++;
}

void retro_set_environment(retro_environment_t cb) {
  env_cb = cb;
  struct retro_keyboard_callback kb = {on_key};
  cb(RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK, &kb);
  g_bitmasks = cb(RETRO_ENVIRONMENT_GET_INPUT_BITMASKS, NULL);
}
void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
void retro_set_audio_sample(retro_audio_sample_t cb) { (void)cb; }
void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { audio_batch_cb = cb; }
void retro_set_input_poll(retro_input_poll_t cb) { input_poll_cb = cb; }
void retro_set_input_state(retro_input_state_t cb) { input_state_cb = cb; }

void retro_init(void) {}
void retro_deinit(void) {}
unsigned retro_api_version(void) { return RETRO_API_VERSION; }

void retro_get_system_info(struct retro_system_info *info) {
  memset(info, 0, sizeof(*info));
  info->library_name = "ezSynthInput";
  info->library_version = "1";
  info->valid_extensions = "bin";
  info->need_fullpath = true;
}

void retro_get_system_av_info(struct retro_system_av_info *info) {
  memset(info, 0, sizeof(*info));
  info->geometry.base_width = 4;
  info->geometry.base_height = 4;
  info->geometry.max_width = 4;
  info->geometry.max_height = 4;
  info->timing.fps = 60.0;
  info->timing.sample_rate = 48000.0;
}

void retro_set_controller_port_device(unsigned p, unsigned d) { (void)p; (void)d; }
void retro_reset(void) {}

void retro_run(void) {
  input_poll_cb();
  int16_t v[16];
  v[0] = input_state_cb(0, RETRO_DEVICE_ANALOG, RETRO_DEVICE_INDEX_ANALOG_LEFT, RETRO_DEVICE_ID_ANALOG_X);
  v[1] = input_state_cb(0, RETRO_DEVICE_ANALOG, RETRO_DEVICE_INDEX_ANALOG_LEFT, RETRO_DEVICE_ID_ANALOG_Y);
  v[2] = input_state_cb(1, RETRO_DEVICE_ANALOG, RETRO_DEVICE_INDEX_ANALOG_RIGHT, RETRO_DEVICE_ID_ANALOG_X);
  v[3] = input_state_cb(0, RETRO_DEVICE_ANALOG, RETRO_DEVICE_INDEX_ANALOG_BUTTON, RETRO_DEVICE_ID_JOYPAD_R2);
  v[4] = input_state_cb(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_X);
  v[5] = input_state_cb(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_Y);
  v[6] = input_state_cb(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_LEFT);
  v[7] = input_state_cb(0, RETRO_DEVICE_KEYBOARD, 0, RETROK_a);
  v[8] = input_state_cb(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_X);
  v[9] = input_state_cb(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_Y);
  v[10] = input_state_cb(0, RETRO_DEVICE_POINTER, 0, RETRO_DEVICE_ID_POINTER_PRESSED);
  v[11] = g_kb_down;
  v[12] = g_kb_code;
  v[13] = g_kb_count;
  v[14] = input_state_cb(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_X);
  v[15] = g_bitmasks ? 1 : 0;
  g_kb_count = 0;
  /* 8 stereo frames = 16 samples, one value each. */
  if (audio_batch_cb) audio_batch_cb(v, 8);
  if (video_cb) video_cb(g_fb, 4, 4, 16);
}

size_t retro_serialize_size(void) { return 0; }
bool retro_serialize(void *d, size_t s) { (void)d; (void)s; return false; }
bool retro_unserialize(const void *d, size_t s) { (void)d; (void)s; return false; }
void retro_cheat_reset(void) {}
void retro_cheat_set(unsigned i, bool e, const char *c) { (void)i; (void)e; (void)c; }
bool retro_load_game(const struct retro_game_info *g) { (void)g; return true; }
bool retro_load_game_special(unsigned t, const struct retro_game_info *g, size_t n) { (void)t; (void)g; (void)n; return false; }
void retro_unload_game(void) {}
unsigned retro_get_region(void) { return RETRO_REGION_NTSC; }
void *retro_get_memory_data(unsigned id) { (void)id; return NULL; }
size_t retro_get_memory_size(unsigned id) { (void)id; return 0; }
