/* synth_options_core.c — minimal libretro core that exercises the
 * core-options & capability env calls during retro_set_environment.
 *
 * NOT a real emulator. Used by test_core_options.c to verify the ezCore
 * runtime's P1b env_cb handlers and host option query API.
 *
 * All option / descriptor / memory data are static — the runtime must
 * deep-copy them.  The version received from
 * RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION determines whether V2 or
 * V1 (INTL) options are sent, making the round-trip observable: if the
 * host didn't answer the version query, no options are sent at all.
 *
 * retro_load_game zeroes all static data to prove the runtime's stored
 * copies are deep copies (not bare pointers into core memory).
 */
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>

#include "libretro.h"

/* ---- v2 core option definitions (sent via SET_CORE_OPTIONS_V2) ---- */
static struct retro_core_option_v2_definition g_option_defs[] = {
   {
      .key            = "test_region",
      .desc           = "Console Region",
      .desc_categorized = NULL,
      .info           = "Selects the emulated console region.",
      .info_categorized = NULL,
      .category_key   = NULL,
      .values         = {
         { "auto",  "Auto" },
         { "ntsc-u","NTSC-U" },
         { "pal",   "PAL" },
         { NULL, NULL },
      },
      .default_value  = "auto",
   },
   {
      .key            = "test_frameskip",
      .desc           = "Frameskip",
      .info           = "Skip frames for performance.",
      .values         = {
         { "disabled", NULL },
         { "enabled",  NULL },
         { NULL, NULL },
      },
      .default_value  = "disabled",
   },
   {
      .key = NULL,  /* terminator (zeroed struct) */
   }
};

static struct retro_core_options_v2 g_core_options_v2 = {
   .categories    = NULL,
   .definitions   = g_option_defs,
};

/* ---- v1 INTL option definitions (sent via SET_CORE_OPTIONS_INTL) ---- */
static struct retro_core_option_definition g_option_defs_v1[] = {
   {
      .key           = "test_region",
      .desc          = "Console Region",
      .info          = "Select the region.",
      .values        = {
         { "auto", NULL },
         { "pal",  NULL },
         { NULL, NULL },
      },
      .default_value = "auto",
   },
   {
      .key = NULL,  /* terminator */
   }
};

static struct retro_core_options_intl g_core_options_intl = {
   .us    = g_option_defs_v1,
   .local = NULL,
};

/* ---- Input descriptors ---- */
static struct retro_input_descriptor g_input_descs[] = {
   { 0, RETRO_DEVICE_JOYPAD, 0, RETRO_DEVICE_ID_JOYPAD_B,    "B Button"   },
   { 0, RETRO_DEVICE_JOYPAD, 0, RETRO_DEVICE_ID_JOYPAD_START, "Start"     },
   { 0, 0, 0, 0, NULL },  /* terminator */
};

/* ---- Controller info ---- */
static struct retro_controller_description g_controller_descs[] = {
   { "ezTest Gamepad", RETRO_DEVICE_JOYPAD },
   { NULL, 0 },  /* terminator */
};

static struct retro_controller_info g_controller_infos[] = {
   { g_controller_descs, 1 },
   { NULL, 0 },  /* terminator */
};

/* ---- Memory map ---- */
static struct retro_memory_descriptor g_mem_descs[] = {
   {
      .flags    = RETRO_MEMDESC_CONST | RETRO_MEMDESC_SYSTEM_RAM,
      .ptr      = NULL,
      .offset   = 0,
      .start    = 0x0000,
      .select   = 0xFFFF,
      .disconnect = 0,
      .len      = 0x2000,
      .addrspace = "RAM",
   },
   {
      .flags    = RETRO_MEMDESC_CONST,
      .ptr      = NULL,
      .offset   = 0,
      .start    = 0x8000,
      .select   = 0xFFFF,
      .disconnect = 0,
      .len      = 0x8000,
      .addrspace = "ROM",
   },
};

static struct retro_memory_map g_memory_map = {
   .descriptors       = g_mem_descs,
   .num_descriptors   = 2,
};

/* ---- Globals ---- */
static retro_environment_t g_env_cb;
static unsigned g_host_core_options_version = 0;

/* ---- Required libretro entry points ---- */

unsigned retro_api_version(void) { return RETRO_API_VERSION; }

void retro_get_system_info(struct retro_system_info *info) {
   info->library_name     = "ezTest Options";
   info->valid_extensions = "opt";
   info->need_fullpath    = false;
   info->block_extract    = false;
   info->library_version  = "1.0.0";
}

void retro_get_system_av_info(struct retro_system_av_info *av) {
   av->geometry.base_width   = 256;
   av->geometry.base_height  = 240;
   av->geometry.max_width    = 256;
   av->geometry.max_height   = 240;
   av->geometry.aspect_ratio = (float)256 / (float)240;
   av->timing.fps            = 60.0;
   av->timing.sample_rate    = 44100.0;
}

void retro_init(void) { }
void retro_deinit(void) { }

bool retro_load_game(const struct retro_game_info *game) {
   (void)game;
   /* Simulate the core freeing / reusing its option data after the host
    * has had a chance to copy it.  The runtime MUST have deep-copied
    * everything during env_cb, so its stored copies must remain valid. */
   memset(g_option_defs, 0, sizeof(g_option_defs));
   memset(g_option_defs_v1, 0, sizeof(g_option_defs_v1));
   memset(g_input_descs, 0, sizeof(g_input_descs));
   memset(g_controller_descs, 0, sizeof(g_controller_descs));
   memset(g_controller_infos, 0, sizeof(g_controller_infos));
   memset(g_mem_descs, 0, sizeof(g_mem_descs));
   g_host_core_options_version = 0;
   return true;
}

void retro_unload_game(void) { }
void retro_run(void) { }
void retro_reset(void) { }

/* Optional callback setters -- present so ezcore_load succeeds. */
void retro_set_video_refresh(retro_video_refresh_t cb) { (void)cb; }
void retro_set_audio_sample(retro_audio_sample_t cb) { (void)cb; }
void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { (void)cb; }
void retro_set_input_poll(retro_input_poll_t cb) { (void)cb; }
void retro_set_input_state(retro_input_state_t cb) { (void)cb; }

void retro_set_environment(retro_environment_t cb) {
   g_env_cb = cb;
   if (!g_env_cb) return;

   /* Pixel format (same as the main synth core) */
   enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
   g_env_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);

   /* Version round-trip: ask the host what core-options API version
    * it supports.  If the env call is unavailable (returns false) the
    * version stays 0 and V2 is skipped -- the test detects this. */
   g_host_core_options_version = 0;
   bool queried = g_env_cb(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION,
                           &g_host_core_options_version);
   if (queried && g_host_core_options_version >= 0x20000) {
      /* Host supports v2.  Exercise the v1 INTL handler first, then
       * send V2 -- which overwrites the INTL storage. */
      g_env_cb(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL,
               (void *)&g_core_options_intl);
      g_env_cb(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2,
               (void *)&g_core_options_v2);
   } else if (queried && g_host_core_options_version >= 0x10000) {
      /* Host supports only v1 -- send INTL definitions */
      g_env_cb(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL,
               (void *)&g_core_options_intl);
   }
   /* If version == 0 (unhandled), no options are sent */

   /* Input descriptors */
   g_env_cb(RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS,
            (void *)g_input_descs);

   /* Controller info */
   g_env_cb(RETRO_ENVIRONMENT_SET_CONTROLLER_INFO,
            (void *)g_controller_infos);

   /* Memory maps */
   g_env_cb(RETRO_ENVIRONMENT_SET_MEMORY_MAPS,
            (void *)&g_memory_map);
}
