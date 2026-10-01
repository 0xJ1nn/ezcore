/* synth_variables_core.c — minimal libretro core that READS its options.
 *
 * NOT a real emulator. Used by test_core_variables.c to prove that a value
 * the host sets with ezcore_set_core_option actually reaches the core.
 *
 * Every real core reads option values the same way: it declares them with
 * SET_CORE_OPTIONS_V2, then asks RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE each
 * frame and, when that reports a change, re-reads each key with
 * RETRO_ENVIRONMENT_GET_VARIABLE. This core does exactly that and echoes what
 * it saw into the audio stream, so the test observes the core's view of its
 * options rather than the runtime's stored copy:
 *
 *   stereo frame 0, left : option value seen by the core
 *     0x2000  GET_VARIABLE returned false (the host did not answer)
 *     0x2001  value "a"
 *     0x2002  value "b"
 *     0x200F  any other value
 *   stereo frame 0, right: what GET_VARIABLE_UPDATE reported this frame
 *     0x3000  not updated (or the host did not answer)
 *     0x3001  updated
 */
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "libretro.h"

static retro_environment_t env_cb;
static retro_video_refresh_t video_cb;
static retro_audio_sample_batch_t audio_batch_cb;
static retro_input_poll_t input_poll_cb;

static struct retro_core_option_v2_definition g_defs[] = {
   {
      .key           = "synth_mode",
      .desc          = "Mode",
      .values        = { { "a", NULL }, { "b", NULL }, { NULL, NULL } },
      .default_value = "a",
   },
   { .key = NULL },
};

static struct retro_core_options_v2 g_opts = { NULL, g_defs };

static int16_t g_value_sample = 0x2000;
static bool g_first_frame = true;
static uint32_t g_fb[4 * 4];

static int16_t read_mode(void) {
   struct retro_variable var = { "synth_mode", NULL };
   if (!env_cb(RETRO_ENVIRONMENT_GET_VARIABLE, &var) || !var.value)
      return 0x2000;
   if (strcmp(var.value, "a") == 0) return 0x2001;
   if (strcmp(var.value, "b") == 0) return 0x2002;
   return 0x200F;
}

void retro_set_environment(retro_environment_t cb) {
   env_cb = cb;
   unsigned version = 0;
   if (cb(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION, &version) &&
       version >= 2)
      cb(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2, &g_opts);
}
void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
void retro_set_audio_sample(retro_audio_sample_t cb) { (void)cb; }
void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) {
   audio_batch_cb = cb;
}
void retro_set_input_poll(retro_input_poll_t cb) { input_poll_cb = cb; }
void retro_set_input_state(retro_input_state_t cb) { (void)cb; }

void retro_init(void) { g_first_frame = true; }
void retro_deinit(void) {}
unsigned retro_api_version(void) { return RETRO_API_VERSION; }

void retro_get_system_info(struct retro_system_info *info) {
   memset(info, 0, sizeof(*info));
   info->library_name = "ezSynthVariables";
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

void retro_set_controller_port_device(unsigned port, unsigned device) {
   (void)port; (void)device;
}
void retro_reset(void) {}

void retro_run(void) {
   if (input_poll_cb) input_poll_cb();
   bool updated = false;
   if (!env_cb(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &updated))
      updated = false;
   /* A real core reads its options once at start, then only on update. */
   if (g_first_frame || updated) g_value_sample = read_mode();
   g_first_frame = false;

   int16_t audio[2 * 800];
   for (unsigned i = 0; i < 800; i++) {
      audio[2 * i] = g_value_sample;
      audio[2 * i + 1] = updated ? 0x3001 : 0x3000;
   }
   if (audio_batch_cb) audio_batch_cb(audio, 800);
   if (video_cb) video_cb(g_fb, 4, 4, 4 * sizeof(uint32_t));
}

size_t retro_serialize_size(void) { return 0; }
bool retro_serialize(void *data, size_t size) { (void)data; (void)size; return false; }
bool retro_unserialize(const void *data, size_t size) { (void)data; (void)size; return false; }
void retro_cheat_reset(void) {}
void retro_cheat_set(unsigned i, bool e, const char *c) { (void)i; (void)e; (void)c; }

bool retro_load_game(const struct retro_game_info *game) { (void)game; return true; }
bool retro_load_game_special(unsigned t, const struct retro_game_info *g, size_t n) {
   (void)t; (void)g; (void)n; return false;
}
void retro_unload_game(void) {}
unsigned retro_get_region(void) { return RETRO_REGION_NTSC; }
void *retro_get_memory_data(unsigned id) { (void)id; return NULL; }
size_t retro_get_memory_size(unsigned id) { (void)id; return 0; }
