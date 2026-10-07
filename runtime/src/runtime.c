/* ezCore runtime — loads a libretro core dylib and forwards the session API.
 * Desktop/Android path: dynload seam at runtime after sha256 verification.
 * iOS path: cores are linked/bundled; ezcore_load resolves bundled symbols.
 *
 * Input: ezcore_reset() deliberately releases every held button (all four
 * ports) before dispatching retro_reset(). Frontends sample the pad
 * asynchronously, so a button still down at the instant the user taps reset
 * would otherwise stay latched in the session's input_buttons and the core
 * would read 1 for that bit on every subsequent frame — the character keeps
 * moving after a reset. Reset means a clean slate, input included.
 */
#include "ezcore_runtime.h"

/* P8: the GPU render-context seam (ADR-018, Option B).
 *
 * libretro_vulkan.h is vendored, but it includes <vulkan/vulkan.h> and the
 * project does not have the Vulkan SDK. Including it would make the RUNTIME
 * require the SDK at build time, which is the dependency the maintainer ruled
 * out. The one struct ezCORE needs from it is mirrored, pointer-for-pointer,
 * in ezcore_gpu_internal.h with the source line recorded. */
#include "ezcore_gpu.h"
#include "ezcore_gpu_internal.h"

#include "dynload.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libretro.h"

/* ---- Core options & capability storage (host-owned deep copies) ---- */

/* Core options API version reported to cores via GET_CORE_OPTIONS_VERSION.
 * 0x10000 = v1, 0x20000 = v2 (categories, intl). */
#define EZCORE_CORE_OPTIONS_VERSION 0x20000u

/* A deep-copied core option definition.  All char* fields are heap-owned
 * by the runtime; the values/labels arrays are NULL-terminated. */
struct ezcore_core_option {
  char *key;
  char *desc;
  char *value;          /* current value — a frontend-set selection    */
  char *default_value;  /* deep copy of the core's default_value       */
  char **values;        /* NULL-terminated array of deep-copied values */
  char **labels;        /* parallel array of labels (may hold NULL)    */
  unsigned num_values;  /* non-NULL entries in values/labels            */
};

/* A deep-copied retro_input_descriptor. */
struct ezcore_input_desc {
  unsigned port;
  unsigned device;
  unsigned index;
  unsigned id;
  char *description;
};

/* A deep-copied retro_controller_description. */
struct ezcore_controller_desc {
  char *desc;
  unsigned id;
};

/* One emulated input port with its supported device types. */
struct ezcore_controller_port {
  struct ezcore_controller_desc *types;  /* length == num_types           */
  unsigned num_types;
};

/* A deep-copied retro_memory_descriptor.  ptr is intentionally NOT
 * copied — it aliases core-owned memory valid for the session lifetime. */
struct ezcore_mem_desc {
  uint64_t flags;
  void *ptr;            /* core-owned — not freed by the runtime */
  size_t offset;
  size_t start;
  size_t select;
  size_t disconnect;
  size_t len;
  char *addrspace;      /* deep copy */
};

static char *ezcore_strdup(const char *s) {
  if (!s) return NULL;
  size_t len = strlen(s);
  char *copy = (char *)malloc(len + 1);
  if (copy) memcpy(copy, s, len + 1);
  return copy;
}

struct ezcore_session {
  void *handle;
  char core_path[1024];
  /* libretro entry points */
  void (*retro_init)(void);
  void (*retro_deinit)(void);
  unsigned (*retro_api_version)(void);
  void (*retro_get_system_info)(struct retro_system_info *);
  void (*retro_get_system_av_info)(struct retro_system_av_info *);
  bool (*retro_load_game)(const struct retro_game_info *);
  void (*retro_run)(void);
  void (*retro_reset)(void);
  /* Optional in practice (NULL-checked): where cores flush battery saves and
   * caches as a game closes. */
  void (*retro_unload_game)(void);
  /* Optional cheat entry points: NULL-checked at every call. */
  void (*retro_cheat_reset)(void);
  void (*retro_cheat_set)(unsigned, bool, const char *);
  /* Save states are core-optional: NULL-checked at every call. */
  size_t (*retro_serialize_size)(void);
  bool (*retro_serialize)(void *, size_t);
  bool (*retro_unserialize)(const void *, size_t);
  /* latest video frame (owned, XRGB8888) */
  uint32_t *frame;
  unsigned frame_w, frame_h;
  enum retro_pixel_format pixfmt;
  /* audio ring (stereo s16) */
  int16_t *audio;
  size_t audio_cap, audio_len;
  /* input state: per-port button bitmask (up to 4 ports) */
  uint32_t input_buttons[4];
  /* P3 devices. Analog: [port][stick: left/right][axis: x/y]. */
  int16_t analog[4][2][2];
  /* Mouse deltas the host reported since the last frame (pending), and the
   * snapshot every read during the current frame returns (frame). */
  int32_t mouse_pending_dx, mouse_pending_dy;
  int16_t mouse_frame_dx, mouse_frame_dy;
  uint32_t mouse_buttons; /* bit = RETRO_DEVICE_ID_MOUSE_* */
  uint8_t keys[(RETROK_LAST + 7) / 8];
  retro_keyboard_event_t keyboard_cb;
  int16_t pointer_x, pointer_y;
  bool pointer_pressed;
  char name[128];
  char version[64];
  bool game_loaded;
  bool inited;
  /* --- Core options & capability surface (host-owned deep copies) --- */
  struct ezcore_core_option *core_options;
  unsigned num_core_options;
  /* Raised when the host changes an option value; consumed (cleared) by the
   * core's next RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE. */
  bool core_options_dirty;
  struct ezcore_input_desc *input_descs;
  unsigned num_input_descs;
  struct ezcore_controller_port *controller_ports;
  unsigned num_controller_ports;
  struct ezcore_mem_desc *mem_descs;
  unsigned num_mem_descs;
  /* --- GPU render context (ADR-018, Option B) ---
   * The core's requested hw-render callback, kept verbatim so
   * GET_HW_RENDER_INTERFACE and SET_PROC_ADDRESS_CALLBACK can be answered from
   * the same source of truth. Owned by the core, not by us. */
  struct retro_hw_render_callback *hw_render_cb;
  /* The core's own extension lookup, announced through
   * SET_PROC_ADDRESS_CALLBACK (core -> frontend). Kept, never written. */
  struct retro_get_proc_address_interface core_proc_iface;
  /* The resolver the CORE shipped, captured before we install ours. Without
   * this, falling back to "the core's resolver" would call ourselves. */
  retro_hw_get_proc_address_t gpu_core_proc_address;
  /* The core's own context_reset / context_destroy, captured so the host shims
   * can chain to them. See hw_install_callbacks for why replacing rather than
   * chaining loses the core's GL resource creation entirely. */
  retro_hw_context_reset_t gpu_core_context_reset;
  retro_hw_context_reset_t gpu_core_context_destroy;
  struct ezcore_gpu_context *gpu;
  /* The interface we hand back from GET_HW_RENDER_INTERFACE, per API. GL and
   * Vulkan have DIFFERENT struct types behind the same tag, so one storage
   * slot is not enough and the core must be able to tell which it asked for. */
  struct retro_hw_render_interface hw_iface_gl;
  struct ezcore_hw_iface_vulkan hw_iface_vk;
  enum ezcore_gpu_api gpu_api;
  bool gpu_negotiated;
};

static ezcore_session *g_active = NULL;

/* ---- environment / callbacks (minimal v0 set; extended per TODO) ---- */

static char g_system_dir[1024] = {0};
static char g_save_dir[1024] = {0};

/* ---- GPU shims handed to the core through retro_hw_render_callback ----
 *
 * The core stores these pointers and calls them. They route to the session's
 * GPU context, so a core that asks for hardware rendering gets a context that
 * is real rather than one the host merely claimed to have.
 *
 * `context_reset` is the one that matters most: libretro.h:4153 guarantees
 * that all of the core's GL resources are invalid after it, so a host that
 * does not mark the session unnegotiated here would keep serving a stale
 * interface for a context the core has just torn down. */

/* Signatures are libretro's own (libretro.h:5782-5790), not approximations:
 *   retro_hw_context_reset_t           -> void (void)
 *   retro_hw_get_current_framebuffer_t -> uintptr_t (void)
 *   retro_hw_get_proc_address_t        -> RETRO_CALLCONV retro_proc_address_t(const char *sym)
 * The third RETURNS the address; the first draft of this file used the
 * `void (const char *, void **)` shape and would have handed every core a NULL
 * proc address. */

/* The core calls this after creating (or recreating) its GL resources. */
static void hw_context_reset(void) {
  if (!g_active || !g_active->gpu) return;
  ezcore_gpu_notify_reset(g_active->gpu);
  g_active->gpu_negotiated = true;
  /* Then the core's own, which is where it creates its GL resources. */
  if (g_active->gpu_core_context_reset) g_active->gpu_core_context_reset();
}

/* The core calls this before its resources are destroyed, when it can. */
static void hw_context_destroy(void) {
  if (g_active && g_active->gpu_core_context_destroy) {
    g_active->gpu_core_context_destroy();
  }
  if (!g_active) return;
  /* The context itself survives -- the host owns it and will hand it back on
   * the next reset -- but anything the core cached from the interface is now
   * stale, so un-negotiate. Destroying the context here would be wrong: a core
   * that calls context_destroy on a fullscreen toggle must get the same
   * context back, not a new one. */
  g_active->gpu_negotiated = false;
}

/* The framebuffer a core should render into. For GL this is a real GLuint FBO
 * name; for Vulkan it is the image index, which is NOT a texture id and must
 * never be used as one. */
static uintptr_t hw_get_current_framebuffer(void) {
  if (!g_active || !g_active->gpu) return 0;
  return (uintptr_t)ezcore_gpu_current_framebuffer(g_active->gpu);
}

/* Resolve a core entry point through OUR context, not only through the core's
 * own resolver. Some drivers expose extensions only via the context that is
 * current, and a core asking before context_reset has a current context would
 * otherwise get NULL for a function that does exist. */
static retro_proc_address_t hw_get_proc_address(const char *name) {
  if (!g_active || !g_active->gpu || !name) return NULL;
  void *ours = ezcore_gpu_get_proc_address(g_active->gpu, name);
  if (ours) return (retro_proc_address_t)ours;
  /* Fall back to the core's own resolver, and note the recursion guard: the
   * core's resolver is what we just installed, so calling it here would call
   * ourselves. Its ORIGINAL is preserved in gpu_core_proc_address. */
  if (g_active->gpu_core_proc_address) {
    return g_active->gpu_core_proc_address(name);
  }
  return NULL;
}

/* Install the shims into the callback the core handed us, so its
 * context_reset/context_destroy/get_current_framebuffer calls land on us.
 * Called once, immediately after SET_HW_RENDER succeeds. */
static void hw_install_callbacks(struct retro_hw_render_callback *cb) {
  if (!cb) return;
  /* CHAIN, do not replace. libretro's contract is that the FRONTEND calls
   * context_reset; the core installs a callback and expects the host to run
   * it. The first version of this file overwrote the core's hook with the
   * host's shim, so the core's own resource-creation step never ran and a core
   * that allocates its textures in context_reset rendered with no textures at
   * all -- while every host-side assertion still passed, because the host
   * believed it had negotiated. The host's shim runs FIRST (so the session is
   * marked negotiated before the core can ask for the interface), then the
   * core's original. */
  if (cb->context_reset != hw_context_reset) {
    g_active->gpu_core_context_reset = cb->context_reset;
    cb->context_reset = hw_context_reset;
  }
  if (cb->context_destroy != hw_context_destroy) {
    g_active->gpu_core_context_destroy = cb->context_destroy;
    cb->context_destroy = hw_context_destroy;
  }
  /* Capture the core's own resolver BEFORE overwriting it, and only if it is
   * not already one of ours. A core that calls SET_HW_RENDER again (a
   * fullscreen toggle, a resolution change) would otherwise have its resolver
   * replaced by our own and then "preserved" as such, making the fallback in
   * hw_get_proc_address call itself. */
  if (cb->get_proc_address != hw_get_proc_address) {
    g_active->gpu_core_proc_address = cb->get_proc_address;
  }
  /* The core may already have set these; ours must win, because the core's
   * own implementations (RetroArch's included) assume its own frontend. */
  cb->get_current_framebuffer = hw_get_current_framebuffer;
  cb->get_proc_address = hw_get_proc_address;
}

static void bridge_log(enum retro_log_level level, const char *fmt, ...) {
  (void)level;
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
}

/* Host-owned content directories. Defaults are CWD-relative; the embedding
 * app should call ezcore_set_dirs() before loading cores that save or need
 * system files (BIOS lives in the app-managed vault, never here). */
void ezcore_set_dirs(const char *system_dir, const char *save_dir) {
  if (system_dir) snprintf(g_system_dir, sizeof(g_system_dir), "%s", system_dir);
  if (save_dir) snprintf(g_save_dir, sizeof(g_save_dir), "%s", save_dir);
}

/* --- Free deep-copied capability storage in a session --- */

static void ezcore_free_core_options(ezcore_session *s) {
  if (!s->core_options) return;
  for (unsigned i = 0; i < s->num_core_options; i++) {
    struct ezcore_core_option *co = &s->core_options[i];
    free(co->key);
    free(co->desc);
    free(co->value);
    free(co->default_value);
    if (co->values) {
      for (unsigned j = 0; j < co->num_values; j++) free(co->values[j]);
      free(co->values);
    }
    if (co->labels) {
      for (unsigned j = 0; j < co->num_values; j++) free(co->labels[j]);
      free(co->labels);
    }
  }
  free(s->core_options);
  s->core_options = NULL;
  s->num_core_options = 0;
}

static void ezcore_free_input_descs(ezcore_session *s) {
  if (!s->input_descs) return;
  for (unsigned i = 0; i < s->num_input_descs; i++)
    free(s->input_descs[i].description);
  free(s->input_descs);
  s->input_descs = NULL;
  s->num_input_descs = 0;
}

static void ezcore_free_controller_ports(ezcore_session *s) {
  if (!s->controller_ports) return;
  for (unsigned i = 0; i < s->num_controller_ports; i++) {
    struct ezcore_controller_port *p = &s->controller_ports[i];
    if (p->types) {
      for (unsigned j = 0; j < p->num_types; j++) free(p->types[j].desc);
      free(p->types);
    }
  }
  free(s->controller_ports);
  s->controller_ports = NULL;
  s->num_controller_ports = 0;
}

static void ezcore_free_mem_descs(ezcore_session *s) {
  if (!s->mem_descs) return;
  for (unsigned i = 0; i < s->num_mem_descs; i++)
    free(s->mem_descs[i].addrspace);
  free(s->mem_descs);
  s->mem_descs = NULL;
  s->num_mem_descs = 0;
}

/* Releases everything a player can hold: buttons on all four ports, sticks,
 * mouse buttons and motion, keys and the pointer. Used at the game boundary
 * and on reset, for the stuck-input reasons noted at the top of this file.
 * The keyboard callback is a core registration, not input, and survives. */
static void clear_input(ezcore_session *s) {
  memset(s->input_buttons, 0, sizeof(s->input_buttons));
  memset(s->analog, 0, sizeof(s->analog));
  s->mouse_pending_dx = s->mouse_pending_dy = 0;
  s->mouse_frame_dx = s->mouse_frame_dy = 0;
  s->mouse_buttons = 0;
  memset(s->keys, 0, sizeof(s->keys));
  s->pointer_x = s->pointer_y = 0;
  s->pointer_pressed = false;
}

/* Deep-copy a v2 option set into the active session. Shared by
 * SET_CORE_OPTIONS_V2 and SET_CORE_OPTIONS_V2_INTL. */
static bool store_core_options_v2(const struct retro_core_options_v2 *opts) {
  /* Deep-copy a v2 option set into the session.  The core retains
   * ownership of all strings; we duplicate them so they survive
   * beyond the env_cb call. */
  if (!g_active) return false;
  ezcore_free_core_options(g_active);
  if (!opts || !opts->definitions) return true;
  /* definitions is terminated by a zeroed-out struct (key == NULL) */
  unsigned count = 0;
  while (count < 1024 && opts->definitions[count].key) count++;
  if (count == 0) return true;
  g_active->core_options =
      (struct ezcore_core_option *)calloc(count, sizeof(*g_active->core_options));
  if (!g_active->core_options) return false;
  g_active->num_core_options = count;
  for (unsigned i = 0; i < count; i++) {
    const struct retro_core_option_v2_definition *d = &opts->definitions[i];
    struct ezcore_core_option *co = &g_active->core_options[i];
    co->key = ezcore_strdup(d->key);
    co->desc = ezcore_strdup(d->desc);
    co->default_value = ezcore_strdup(d->default_value);
    co->value = ezcore_strdup(d->default_value); /* init current = default */
    /* values[] is terminated by { NULL, NULL } */
    unsigned nv = 0;
    while (nv < RETRO_NUM_CORE_OPTION_VALUES_MAX &&
           d->values[nv].value) nv++;
    co->num_values = nv;
    if (nv > 0) {
      co->values = (char **)calloc(nv + 1, sizeof(char *));
      co->labels = (char **)calloc(nv + 1, sizeof(char *));
      if (co->values && co->labels) {
        for (unsigned j = 0; j < nv; j++) {
          co->values[j] = ezcore_strdup(d->values[j].value);
          co->labels[j] = ezcore_strdup(d->values[j].label);
        }
      }
    }
  }
  return true;
}

static bool env_cb(unsigned cmd, void *data) {
  switch (cmd) {
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
      /* We keep the last decoded frame, so dupes are free. */
      if (data) *(bool *)data = true;
      return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
      /* Required at init by several cores (mupen64plus strncpy's this
       * without a NULL check — returning false segfaults them). */
      if (!g_system_dir[0]) snprintf(g_system_dir, sizeof(g_system_dir), ".");
      if (data) *(const char **)data = g_system_dir;
      return true;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
      if (!g_save_dir[0]) snprintf(g_save_dir, sizeof(g_save_dir), ".");
      if (data) *(const char **)data = g_save_dir;
      return true;
    case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
      if (!g_system_dir[0]) snprintf(g_system_dir, sizeof(g_system_dir), ".");
      if (data) *(const char **)data = g_system_dir;
      return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
      enum retro_pixel_format fmt = *(const enum retro_pixel_format *)data;
      if (fmt != RETRO_PIXEL_FORMAT_0RGB1555 &&
          fmt != RETRO_PIXEL_FORMAT_XRGB8888 &&
          fmt != RETRO_PIXEL_FORMAT_RGB565) {
        return false;
      }
      if (g_active) g_active->pixfmt = fmt;
      return true;
    }
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
      struct retro_log_callback *cb = data;
      if (cb) cb->log = bridge_log;
      return true;
    }
    case RETRO_ENVIRONMENT_SET_MESSAGE: {
      const struct retro_message *msg = data;
      if (msg && msg->msg) fprintf(stderr, "[core] %s\n", msg->msg);
      return true;
    }
    /* ---- P1b: core options & capability surface ---- */
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
      /* Core asks the host which options API version it supports.
       * We report v2, enabling SET_CORE_OPTIONS_V2 / V2_INTL. */
      if (data) *(unsigned *)data = EZCORE_CORE_OPTIONS_VERSION;
      return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
      return store_core_options_v2((const struct retro_core_options_v2 *)data);
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
      /* We report options version 2, which promises this call too. An
       * earlier version had no case for it, so every core built from the
       * standard libretro options template (PPSSPP among them) had all of
       * its options silently dropped and GET_VARIABLE failed for every key.
       * Like the v1 INTL case we keep the canonical US definitions; option
       * keys and values are language-independent. */
      const struct retro_core_options_v2_intl *intl = data;
      return store_core_options_v2(intl ? intl->us : NULL);
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
      /* v1 INTL variant.  We store the US (English) definitions using
       * the same internal representation as V2.  The translated `local`
       * set is intentionally not stored: the host option surface exposes
       * the canonical US strings so that option *keys* and *values*
       * (which must be language-independent) are queryable. */
      const struct retro_core_options_intl *opts_intl = data;
      if (!g_active) return false;
      ezcore_free_core_options(g_active);
      if (!opts_intl || !opts_intl->us) return true;
      /* us array is terminated by an entry with key == NULL */
      unsigned count = 0;
      while (count < 1024 && opts_intl->us[count].key) count++;
      if (count == 0) return true;
      g_active->core_options =
          (struct ezcore_core_option *)calloc(count, sizeof(*g_active->core_options));
      if (!g_active->core_options) return false;
      g_active->num_core_options = count;
      for (unsigned i = 0; i < count; i++) {
        const struct retro_core_option_definition *d = &opts_intl->us[i];
        struct ezcore_core_option *co = &g_active->core_options[i];
        co->key = ezcore_strdup(d->key);
        co->desc = ezcore_strdup(d->desc);
        co->default_value = ezcore_strdup(d->default_value);
        co->value = ezcore_strdup(d->default_value);
        unsigned nv = 0;
        while (nv < RETRO_NUM_CORE_OPTION_VALUES_MAX &&
               d->values[nv].value) nv++;
        co->num_values = nv;
        if (nv > 0) {
          co->values = (char **)calloc(nv + 1, sizeof(char *));
          co->labels = (char **)calloc(nv + 1, sizeof(char *));
          if (co->values && co->labels) {
            for (unsigned j = 0; j < nv; j++) {
              co->values[j] = ezcore_strdup(d->values[j].value);
              co->labels[j] = ezcore_strdup(d->values[j].label);
            }
          }
        }
      }
      return true;
    }
    case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK: {
      /* Keyboard-driven cores (DOS, computers) want key events, not only
       * polled state; ezcore_set_key delivers both. */
      const struct retro_keyboard_callback *kb = data;
      if (!g_active || !kb) return false;
      g_active->keyboard_cb = kb->callback;
      return true;
    }
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
      /* The joypad state already answers RETRO_DEVICE_ID_JOYPAD_MASK. */
      return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
      /* How a core reads an option value. Without this every core runs on
       * its own defaults whatever the host set. An unknown key is answered
       * "no such option" (value NULL, false) per libretro.h. */
      struct retro_variable *var = data;
      if (!g_active || !var || !var->key) return false;
      var->value = NULL;
      for (unsigned i = 0; i < g_active->num_core_options; i++) {
        const struct ezcore_core_option *co = &g_active->core_options[i];
        if (co->key && strcmp(co->key, var->key) == 0) {
          var->value = co->value;
          return co->value != NULL;
        }
      }
      return false;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
      /* Reports, then clears, whether any value changed since the last ask.
       * Clearing on read is the libretro contract: cores poll this every
       * frame and reconfigure when it is true. */
      if (!g_active || !data) return false;
      *(bool *)data = g_active->core_options_dirty;
      g_active->core_options_dirty = false;
      return true;
    }
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS: {
      /* Array is terminated by a zeroed-out descriptor (description == NULL). */
      const struct retro_input_descriptor *descs = data;
      if (!g_active) return false;
      ezcore_free_input_descs(g_active);
      if (!descs) return true;
      unsigned count = 0;
      while (count < 1024 && descs[count].description) count++;
      if (count == 0) return true;
      g_active->input_descs =
          (struct ezcore_input_desc *)calloc(count, sizeof(*g_active->input_descs));
      if (!g_active->input_descs) return false;
      g_active->num_input_descs = count;
      for (unsigned i = 0; i < count; i++) {
        g_active->input_descs[i].port = descs[i].port;
        g_active->input_descs[i].device = descs[i].device;
        g_active->input_descs[i].index = descs[i].index;
        g_active->input_descs[i].id = descs[i].id;
        g_active->input_descs[i].description = ezcore_strdup(descs[i].description);
      }
      return true;
    }
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO: {
      /* Array is terminated by a zeroed-out entry. */
      const struct retro_controller_info *infos = data;
      if (!g_active) return false;
      ezcore_free_controller_ports(g_active);
      if (!infos) return true;
      unsigned count = 0;
      while (count < 1024 && (infos[count].types || infos[count].num_types))
        count++;
      if (count == 0) return true;
      g_active->controller_ports =
          (struct ezcore_controller_port *)calloc(count, sizeof(*g_active->controller_ports));
      if (!g_active->controller_ports) return false;
      g_active->num_controller_ports = count;
      for (unsigned i = 0; i < count; i++) {
        unsigned nt = infos[i].num_types;
        g_active->controller_ports[i].num_types = nt;
        if (nt > 0 && infos[i].types) {
          g_active->controller_ports[i].types =
              (struct ezcore_controller_desc *)calloc(nt, sizeof(struct ezcore_controller_desc));
          for (unsigned j = 0; j < nt; j++) {
            g_active->controller_ports[i].types[j].desc =
                ezcore_strdup(infos[i].types[j].desc);
            g_active->controller_ports[i].types[j].id = infos[i].types[j].id;
          }
        }
      }
      return true;
    }
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS: {
      const struct retro_memory_map *map = data;
      if (!g_active) return false;
      ezcore_free_mem_descs(g_active);
      if (!map || !map->descriptors) return true;
      unsigned count = map->num_descriptors;
      if (count == 0) return true;
      g_active->mem_descs =
          (struct ezcore_mem_desc *)calloc(count, sizeof(*g_active->mem_descs));
      if (!g_active->mem_descs) return false;
      g_active->num_mem_descs = count;
      for (unsigned i = 0; i < count; i++) {
        const struct retro_memory_descriptor *md = &map->descriptors[i];
        g_active->mem_descs[i].flags = md->flags;
        /* ptr aliases core-owned memory; we store it but do NOT free it */
        g_active->mem_descs[i].ptr = md->ptr;
        g_active->mem_descs[i].offset = md->offset;
        g_active->mem_descs[i].start = md->start;
        g_active->mem_descs[i].select = md->select;
        g_active->mem_descs[i].disconnect = md->disconnect;
        g_active->mem_descs[i].len = md->len;
        g_active->mem_descs[i].addrspace = ezcore_strdup(md->addrspace);
      }
      return true;
    }
    /* ---- P8: GPU render context (ADR-018, Option B) ----
     *
     * These four answers are what unblocks a GL- or Vulkan-defaulting core.
     * Two of them are the reason this is not a one-liner:
     *
     *   SET_HW_RENDER must answer FALSE when no context can be made, so the
     *   core falls back to software. Answering true without a working context
     *   is the worst possible outcome: the core stops using its own renderer
     *   and renders into nothing.
     *
     *   GET_PREFERRED_HW_RENDER must not advertise a context type we cannot
     *   actually create, for the same reason. A core that trusts this and then
     *   gets a false from SET_HW_RENDER may not have a software path, so
     *   over-advertising here is a crash, not a downgrade.
     */
    case RETRO_ENVIRONMENT_SET_HW_RENDER: {
      if (!g_active || !data) return false;
      const struct retro_hw_render_callback *cb =
          (const struct retro_hw_render_callback *)data;

      enum ezcore_gpu_api api;
      switch (cb->context_type) {
        case RETRO_HW_CONTEXT_OPENGL:       api = EZCORE_GPU_OPENGL; break;
        case RETRO_HW_CONTEXT_OPENGLES2:    api = EZCORE_GPU_OPENGLES2; break;
        case RETRO_HW_CONTEXT_OPENGL_CORE:  api = EZCORE_GPU_OPENGL_CORE; break;
        case RETRO_HW_CONTEXT_OPENGLES3:    api = EZCORE_GPU_OPENGLES3; break;
        case RETRO_HW_CONTEXT_VULKAN:
          /* Refused until frames can be handed over. ezcore_gpu_vulkan.c makes
           * an instance and a device, but there is no set_image handoff and
           * no readback, so saying yes would leave the core drawing into
           * nothing -- Flycast then crashes on a renderer it never created.
           * Refusing sends it to its OpenGL path, which works. */
          fprintf(stderr, "[ezcore] SET_HW_RENDER vulkan refused: frame "
                          "handoff not implemented yet\n");
          return false;
        default: return false;   /* D3D/Metal/PS2: not offered, say so */
      }

      /* Create a context, replacing any previous one for this session. */
      ezcore_gpu_destroy(g_active->gpu);
      g_active->gpu = NULL;
      char err[192] = {0};
      enum ezcore_gpu_init_result r = ezcore_gpu_init(
          &g_active->gpu, api, cb->version_major, cb->version_minor, true, err,
          sizeof(err));
      if (r != EZCORE_GPU_INIT_OK) {
        /* Deliberately NOT logged as a failure: a machine with no GPU is a
         * normal state, and a core falling back to software is correct
         * behaviour. Set EZCORE_GPU_DEBUG to see why, when debugging. */
          fprintf(stderr, "[ezcore] SET_HW_RENDER %s refused: %s\n",
                  ezcore_gpu_api_name(api), err);
        return false;
      }
      g_active->gpu_api = api;
      g_active->hw_render_cb = (struct retro_hw_render_callback *)cb;
      g_active->gpu_negotiated = false;   /* no context_reset seen yet */
      hw_install_callbacks(g_active->hw_render_cb);
      return true;
    }
    case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER: {
      /* `data` is an OUT-PARAM (`unsigned *`): the frontend writes the context
       * type it prefers. An earlier version read it as an input and echoed it
       * back, but cores pass it uninitialised (Flycast: `u32 preferred;`), so
       * the answer depended on stack garbage. When it came back false Flycast
       * fell through to Vulkan, which we could not actually serve.
       *
       * Desktop GL first (what RetroArch's GL driver answers, and the path the
       * most cores are tested on), GLES3 where only that exists. Never Vulkan
       * while SET_HW_RENDER refuses it. Probing does not create a context. */
      if (!data) return false;
      if (ezcore_gpu_supported(EZCORE_GPU_OPENGL)) {
        *(unsigned *)data = RETRO_HW_CONTEXT_OPENGL;
        return true;
      }
      if (ezcore_gpu_supported(EZCORE_GPU_OPENGLES3)) {
        *(unsigned *)data = RETRO_HW_CONTEXT_OPENGLES3;
        return true;
      }
      return false;
    }
    case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE: {
      if (!g_active || !g_active->gpu || !data) return false;
      /* libretro.h:1638 requires context_reset to have been called before
       * this returns anything. Answering before then hands the core an
       * interface for a context it has not been told about. */
      if (!g_active->gpu_negotiated) return false;

      /* `data` is an OUT-PARAM ONLY: `const retro_hw_render_interface **`.
       * The first version of this file read `in->interface_type` out of it as
       * though the core had sent a struct in, but the core only passes a
       * pointer to receive one -- so it branched on uninitialised memory and
       * refused to answer a GLES3 core. The active API is already recorded in
       * the session from SET_HW_RENDER, so there is nothing to read. */
      if (g_active->gpu_api == EZCORE_GPU_VULKAN) {
        g_active->hw_iface_vk.interface_type = RETRO_HW_RENDER_INTERFACE_VULKAN;
        g_active->hw_iface_vk.interface_version =
            EZCORE_HW_RENDER_INTERFACE_VULKAN_VERSION;
        g_active->hw_iface_vk.get_device_proc_addr =
            ezcore_gpu_get_proc_address(g_active->gpu, "vkGetDeviceProcAddr");
        g_active->hw_iface_vk.get_instance_proc_addr =
            ezcore_gpu_get_proc_address(g_active->gpu, "vkGetInstanceProcAddr");
        g_active->hw_iface_vk.handle = g_active->gpu;
        *(struct retro_hw_render_interface **)data =
            (struct retro_hw_render_interface *)&g_active->hw_iface_vk;
        return true;
      }

      /* GL/GLES cores use the plain retro_hw_render_interface, and there is NO
       * retro_hw_render_interface_gl: the enum (libretro.h:3768-3801) is
       * Vulkan, D3D9/10/11/12 and GSkit-PS2 only. An earlier version tagged
       * the GL interface RETRO_HW_RENDER_INTERFACE_VULKAN, which would have
       * had a GL core cast our two-field struct to the Vulkan struct and read a
       * VkInstance out of bytes holding interface_version. */
      g_active->hw_iface_gl.interface_type = RETRO_HW_RENDER_INTERFACE_DUMMY;
      g_active->hw_iface_gl.interface_version = 0;
      *(struct retro_hw_render_interface **)data =
          (struct retro_hw_render_interface *)&g_active->hw_iface_gl;
      return true;
    }
    case RETRO_ENVIRONMENT_SET_PROC_ADDRESS_CALLBACK: {
      /* libretro.h: the CORE hands the frontend a lookup for the core's own
       * extensions (`const struct retro_get_proc_address_interface *`), and
       * "the frontend must maintain its own copy". An earlier version read
       * this backwards and wrote our GL resolver into the core's const
       * struct -- corrupting core memory in every core that announces one.
       * A core gets GL functions from retro_hw_render_callback's
       * get_proc_address, which hw_install_callbacks sets. */
      const struct retro_get_proc_address_interface *iface = data;
      if (!g_active || !iface) return false;
      g_active->core_proc_iface = *iface;
      return true;
    }
    default:
      return false;
  }
}

/* Copies a GPU-rendered frame (OpenGL / GLES) into s->frame as XRGB8888, so
 * the rest of the pipeline -- the player, screenshots, save-state checks --
 * sees it exactly like a software frame. Reads the framebuffer the core drew
 * into, then flips it when GL's origin is bottom-left (the libretro default).
 * Returns false when there is nothing to read (no negotiated GL context, or
 * a Vulkan core, whose frames arrive differently and are not handled yet). */
static bool hw_readback(ezcore_session *s, unsigned width, unsigned height) {
  if (!s->gpu || !s->gpu_negotiated) return false;
  if (ezcore_gpu_api_of(s->gpu) == EZCORE_GPU_VULKAN) return false;
  typedef void (*bindfb_t)(unsigned, unsigned);
  typedef void (*readpixels_t)(int, int, int, int, unsigned, unsigned, void *);
  typedef void (*pixelstore_t)(unsigned, int);
  bindfb_t bind = (bindfb_t)ezcore_gpu_get_proc_address(s->gpu, "glBindFramebuffer");
  readpixels_t read = (readpixels_t)ezcore_gpu_get_proc_address(s->gpu, "glReadPixels");
  pixelstore_t store = (pixelstore_t)ezcore_gpu_get_proc_address(s->gpu, "glPixelStorei");
  if (!bind || !read) return false;
  size_t n = (size_t)width * height;
  if (width != s->frame_w || height != s->frame_h || !s->frame) {
    free(s->frame);
    s->frame = malloc(n * 4);
    if (!s->frame) { s->frame_w = s->frame_h = 0; return false; }
    s->frame_w = width;
    s->frame_h = height;
  }
  uint8_t *rgba = malloc(n * 4);
  if (!rgba) return false;
  bind(0x8D40 /* GL_FRAMEBUFFER */, ezcore_gpu_current_framebuffer(s->gpu));
  if (store) store(0x0D05 /* GL_PACK_ALIGNMENT */, 1);
  /* GL_RGBA + GL_UNSIGNED_BYTE is the one combination GLES guarantees. */
  read(0, 0, (int)width, (int)height, 0x1908 /* GL_RGBA */,
       0x1401 /* GL_UNSIGNED_BYTE */, rgba);
  bool flip = !s->hw_render_cb || s->hw_render_cb->bottom_left_origin;
  for (unsigned y = 0; y < height; y++) {
    const uint8_t *src = rgba + (size_t)(flip ? height - 1 - y : y) * width * 4;
    uint32_t *dst = s->frame + (size_t)y * width;
    for (unsigned x = 0; x < width; x++, src += 4) {
      dst[x] = 0xFF000000u | ((uint32_t)src[0] << 16) |
               ((uint32_t)src[1] << 8) | src[2];
    }
  }
  free(rgba);
  return true;
}

static void video_cb(const void *data, unsigned width, unsigned height,
                     size_t pitch) {
  if (!g_active || !data || width == 0 || height == 0) return;
  ezcore_session *s = g_active;
  /* A GPU core passes this sentinel instead of pixels: the frame is in its
   * framebuffer. It is (void *)-1, so it must never be read as memory. */
  if (data == RETRO_HW_FRAME_BUFFER_VALID) {
    hw_readback(s, width, height);
    return;
  }
  if (width != s->frame_w || height != s->frame_h) {
    free(s->frame);
    s->frame = malloc((size_t)width * height * 4);
    if (!s->frame) return;
    s->frame_w = width;
    s->frame_h = height;
  }
  if (s->pixfmt == RETRO_PIXEL_FORMAT_XRGB8888) {
    const uint8_t *src = data;
    for (unsigned y = 0; y < height; y++) {
      memcpy(s->frame + (size_t)y * width,
             src + (size_t)y * pitch, (size_t)width * 4);
    }
    return;
  }
  /* 0RGB1555 / RGB565 -> XRGB8888 expansion. */
  const uint8_t *src = data;
  for (unsigned y = 0; y < height; y++) {
    const uint16_t *row = (const uint16_t *)(src + (size_t)y * pitch);
    for (unsigned x = 0; x < width; x++) {
      uint16_t p = row[x];
      unsigned r, g, b;
      if (s->pixfmt == RETRO_PIXEL_FORMAT_RGB565) {
        r = (p >> 11) & 0x1F;
        g = (p >> 5) & 0x3F;
        b = p & 0x1F;
        r = (r << 3) | (r >> 2);
        g = (g << 2) | (g >> 4);
        b = (b << 3) | (b >> 2);
      } else {
        r = (p >> 10) & 0x1F;
        g = (p >> 5) & 0x1F;
        b = p & 0x1F;
        r = (r << 3) | (r >> 2);
        g = (g << 3) | (g >> 2);
        b = (b << 3) | (b >> 2);
      }
      s->frame[(size_t)y * width + x] =
          (uint32_t)((r << 16) | (g << 8) | b);
    }
  }
}

static void audio_sample_cb(int16_t left, int16_t right) {
  if (!g_active) return;
  ezcore_session *s = g_active;
  if (s->audio_len + 1 > s->audio_cap) return; /* drop on overflow (v0) */
  s->audio[s->audio_len * 2] = left;
  s->audio[s->audio_len * 2 + 1] = right;
  s->audio_len++;
}

static size_t audio_batch_cb(const int16_t *data, size_t frames) {
  for (size_t i = 0; i < frames; i++)
    audio_sample_cb(data[i * 2], data[i * 2 + 1]);
  return frames;
}

static void input_poll_cb(void) {}

/* Answers a core's input queries from the state the host set. */
static int16_t input_state_cb(unsigned port, unsigned device,
                              unsigned index, unsigned id) {
  ezcore_session *s = g_active;
  if (!s || port >= 4) return 0;
  switch (device) {
    case RETRO_DEVICE_JOYPAD: {
      uint32_t mask = s->input_buttons[port];
      if (id < 16) return (int16_t)((mask >> id) & 1);
      /* RETRO_DEVICE_ID_JOYPAD_MASK: return full bitmask */
      if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)mask;
      return 0;
    }
    case RETRO_DEVICE_ANALOG:
      if (index == RETRO_DEVICE_INDEX_ANALOG_BUTTON) {
        /* Analog buttons (pressure triggers) follow the digital button:
         * pressed reads fully pulled. */
        if (id >= 16) return 0;
        return ((s->input_buttons[port] >> id) & 1) ? 0x7fff : 0;
      }
      if (index > 1 || id > 1) return 0;
      return s->analog[port][index][id];
    case RETRO_DEVICE_MOUSE:
      if (port != 0) return 0;
      if (id == RETRO_DEVICE_ID_MOUSE_X) return s->mouse_frame_dx;
      if (id == RETRO_DEVICE_ID_MOUSE_Y) return s->mouse_frame_dy;
      return id < 32 ? (int16_t)((s->mouse_buttons >> id) & 1) : 0;
    case RETRO_DEVICE_KEYBOARD:
      if (port != 0 || id >= RETROK_LAST) return 0;
      return (s->keys[id / 8] >> (id % 8)) & 1;
    case RETRO_DEVICE_POINTER:
      if (port != 0 || index != 0) return 0;
      if (id == RETRO_DEVICE_ID_POINTER_X) return s->pointer_x;
      if (id == RETRO_DEVICE_ID_POINTER_Y) return s->pointer_y;
      if (id == RETRO_DEVICE_ID_POINTER_PRESSED) return s->pointer_pressed;
      if (id == RETRO_DEVICE_ID_POINTER_COUNT) return s->pointer_pressed ? 1 : 0;
      return 0;
    default:
      return 0;
  }
}

/* ---- public API ---- */

int ezcore_abi_version(void) { return EZCORE_ABI_VERSION; }

#define LOAD_SYM(s, field, sym)                                  \
  do {                                                           \
    s->field = ez_dyn_sym(s->handle, sym);                       \
    if (!s->field) {                                             \
      snprintf(err, err_len, "core missing symbol: %s", sym);    \
      ez_dyn_close(s->handle);                                   \
      free(s);                                                   \
      return NULL;                                               \
    }                                                            \
  } while (0)

ezcore_session *ezcore_load(const char *core_path, char *err, size_t err_len) {
  ezcore_session *s = calloc(1, sizeof(*s));
  if (!s) return NULL;
  snprintf(s->core_path, sizeof(s->core_path), "%s", core_path);
  s->handle = ez_dyn_open(core_path, err, err_len);
  if (!s->handle) {
    free(s);
    return NULL;
  }
  LOAD_SYM(s, retro_init, "retro_init");
  LOAD_SYM(s, retro_deinit, "retro_deinit");
  LOAD_SYM(s, retro_api_version, "retro_api_version");
  LOAD_SYM(s, retro_get_system_info, "retro_get_system_info");
  LOAD_SYM(s, retro_get_system_av_info, "retro_get_system_av_info");
  LOAD_SYM(s, retro_load_game, "retro_load_game");
  LOAD_SYM(s, retro_run, "retro_run");
  LOAD_SYM(s, retro_reset, "retro_reset");
  s->retro_unload_game = ez_dyn_sym(s->handle, "retro_unload_game");
  /* Cheat entry points are core-optional; cores without cheat support still
   * need to load for video, audio, input, and save-state functionality. */
  s->retro_cheat_reset = ez_dyn_sym(s->handle, "retro_cheat_reset");
  s->retro_cheat_set = ez_dyn_sym(s->handle, "retro_cheat_set");
  /* Save-state entry points are core-optional (older cores may omit them). */
  s->retro_serialize_size = ez_dyn_sym(s->handle, "retro_serialize_size");
  s->retro_serialize = ez_dyn_sym(s->handle, "retro_serialize");
  s->retro_unserialize = ez_dyn_sym(s->handle, "retro_unserialize");

  if (s->retro_api_version() != 1) {
    snprintf(err, err_len, "unsupported libretro API version");
    ez_dyn_close(s->handle);
    free(s);
    return NULL;
  }
  struct retro_system_info info = {0};
  s->retro_get_system_info(&info);
  snprintf(s->name, sizeof(s->name), "%s",
           info.library_name ? info.library_name : "?");
  snprintf(s->version, sizeof(s->version), "%s",
           info.library_version ? info.library_version : "?");

  void (*set_env)(retro_environment_t) =
      ez_dyn_sym(s->handle, "retro_set_environment");
  void (*set_video)(retro_video_refresh_t) =
      ez_dyn_sym(s->handle, "retro_set_video_refresh");
  void (*set_audio)(retro_audio_sample_t) =
      ez_dyn_sym(s->handle, "retro_set_audio_sample");
  void (*set_audio_batch)(retro_audio_sample_batch_t) =
      ez_dyn_sym(s->handle, "retro_set_audio_sample_batch");
  void (*set_poll)(retro_input_poll_t) =
      ez_dyn_sym(s->handle, "retro_set_input_poll");
  void (*set_state)(retro_input_state_t) =
      ez_dyn_sym(s->handle, "retro_set_input_state");

  /* audio_cap is in FRAMES (stereo frame = 2 int16_t = 4 bytes).
   * Buffer bytes = audio_cap * 2 * sizeof(int16_t) = audio_cap * 4. */
  s->audio_cap = 8192;
  s->audio = malloc(s->audio_cap * 2 * sizeof(int16_t));
  if (!s->audio) {
    snprintf(err, err_len, "audio buffer alloc failed");
    ez_dyn_close(s->handle);
    free(s);
    return NULL;
  }
  s->pixfmt = RETRO_PIXEL_FORMAT_0RGB1555; /* libretro default */
  g_active = s;

  if (set_env) set_env(env_cb);

  /* QUIRK init-before-callbacks: Mesen's retro_set_video_refresh
   * dereferences its Console, which only exists after retro_init
   * (spec-violating, verified in Mesen/Libretro/libretro.cpp).
   * Every other core keeps the spec order. */
  bool early_init = info.library_name &&
                    strstr(info.library_name, "Mesen") != NULL;
  if (early_init) {
    s->retro_init();
    s->inited = true;
  }

  if (set_video) set_video(video_cb);
  if (set_audio) set_audio(audio_sample_cb);
  if (set_audio_batch) set_audio_batch(audio_batch_cb);
  if (set_poll) set_poll(input_poll_cb);
  if (set_state) set_state(input_state_cb);
  return s;
}

void ezcore_unload(ezcore_session *s) {
  if (!s) return;
  /* Teardown order, matching RetroArch's core_unload_game (the frontend
   * cores are written against), with this session active so any callback
   * the core makes during it reaches the right place:
   *   1. the core's hw context_destroy, while the context still exists --
   *      RetroArch runs it (video_driver_free_hw_context) before
   *      retro_unload_game. PPSSPP depends on that: it deletes its graphics
   *      context object in retro_unload_game, so a context_destroy after it
   *      dereferenced freed memory. (An earlier version called it second.)
   *   2. retro_unload_game -- cores flush battery saves and caches here.
   *   3. retro_deinit, still with a live context: a core frees GL handles
   *      here, and they are only valid while a context is current.
   *   4. only now the GPU context itself. It used to go first, so a core's
   *      last GL calls hit a dead context (Mupen64Plus-Next crashed writing
   *      its shader cache). */
  ezcore_session *prev = g_active;
  g_active = s;
  /* context_destroy pairs with context_reset: a core whose load failed
   * before it was ever given its context must not be told to tear one down
   * (Dolphin then shut down a GL backend it never set up, calling NULL). */
  if (s->gpu && s->gpu_negotiated && s->hw_render_cb &&
      s->hw_render_cb->context_destroy) {
    s->hw_render_cb->context_destroy();
  }
  if (s->game_loaded && s->retro_unload_game) s->retro_unload_game();
  s->game_loaded = false;
  if (s->inited) {
    s->retro_deinit();
    s->inited = false;
  }
  if (s->gpu) {
    ezcore_gpu_destroy(s->gpu);
    s->gpu = NULL;
  }
  s->hw_render_cb = NULL;
  s->gpu_negotiated = false;
  g_active = prev == s ? NULL : prev;

  ezcore_free_core_options(s);
  ezcore_free_input_descs(s);
  ezcore_free_controller_ports(s);
  ezcore_free_mem_descs(s);
  ez_dyn_close(s->handle);
  free(s->frame);
  free(s->audio);
  free(s);
}

bool ezcore_init(ezcore_session *s) {
  if (!s) return false;
  g_active = s;
  if (!s->inited) {
    s->retro_init();
    s->inited = true;
  }
  return true;
}

/* Load content into the session. Also releases every held button on all four
 * ports when the new game takes over (same stuck-input class as
 * ezcore_reset, see the note at the top of this file): frontends sample the
 * pad asynchronously, so a button still down when the user loads a game into
 * a live session stays latched in input_buttons and the freshly loaded core
 * reads 1 for that bit on its very first frames — phantom input held across
 * the game boundary. ezcore_unload needs no clear because it frees the
 * session outright.
 *
 * Placement is deliberate: after retro_load_game() and only on success. A
 * failed load leaves the session still running the previous game, so its
 * input state is live player input and must survive the attempt — clearing
 * unconditionally at the top would silently drop held buttons for a game that
 * never went away. Only the game boundary itself resets the pad. */
bool ezcore_load_game(ezcore_session *s, const char *rom_path, const void *data,
                   size_t size) {
  if (!s) return false;
  struct retro_game_info info = {rom_path, data, size, NULL};
  bool ok = s->retro_load_game(&info);
  if (ok) clear_input(s);
  /* A GPU core renders into our framebuffer; size it to the largest frame
   * the core can produce, now that it can say (SET_HW_RENDER came during
   * load, before the geometry was known). */
  if (ok && s->gpu) {
    struct retro_system_av_info av;
    memset(&av, 0, sizeof(av));
    s->retro_get_system_av_info(&av);
    unsigned mw = av.geometry.max_width ? av.geometry.max_width : av.geometry.base_width;
    unsigned mh = av.geometry.max_height ? av.geometry.max_height : av.geometry.base_height;
    if (mw && mh) ezcore_gpu_resize(s->gpu, (int)mw, (int)mh);
    /* libretro: the FRONTEND calls context_reset once the context is usable
     * -- that is where a core creates its GL resources and resolves its GL
     * functions. Never calling it left every real GL core running with no
     * resources and NULL function pointers (Mupen64Plus-Next crashed in
     * glsm_ctl). Our shim runs first, then the core's own. */
    if (s->hw_render_cb && s->hw_render_cb->context_reset) {
      ezcore_session *prev = g_active;
      g_active = s;
      s->hw_render_cb->context_reset();
      g_active = prev;
    }
  }
  s->game_loaded = ok;
  return ok;
}

void ezcore_run_frame(ezcore_session *s) {
  if (!s) return;
  g_active = s;
  /* One mouse snapshot per frame: every read inside retro_run sees the same
   * delta, and motion reported meanwhile waits for the next frame. */
  s->mouse_frame_dx = (int16_t)(s->mouse_pending_dx > 32767 ? 32767
                       : s->mouse_pending_dx < -32768 ? -32768 : s->mouse_pending_dx);
  s->mouse_frame_dy = (int16_t)(s->mouse_pending_dy > 32767 ? 32767
                       : s->mouse_pending_dy < -32768 ? -32768 : s->mouse_pending_dy);
  s->mouse_pending_dx = s->mouse_pending_dy = 0;
  s->retro_run();
  s->mouse_frame_dx = s->mouse_frame_dy = 0;
}

/* Reset the currently loaded game. Safe to call only after load_game.
 * Also releases every held button on all four ports (see the note at the top
 * of this file): clearing happens after the guard, so the early-out stays a
 * true no-op, but before retro_reset() so the core sees a clean input state
 * as it resets. A session that is valid and has a game loaded but no
 * retro_reset is left untouched — such a core cannot be reset at all, so
 * silently dropping the player's current input there would change behaviour
 * without delivering a reset. */
void ezcore_reset(ezcore_session *s) {
  if (!s || !s->game_loaded || !s->retro_reset) return;
  clear_input(s);
  s->retro_reset();
}

const char *ezcore_core_name(ezcore_session *s) { return s ? s->name : "?"; }
const char *ezcore_core_version(ezcore_session *s) { return s ? s->version : "?"; }

/* Requires a loaded game: several cores (e.g. mGBA) dereference active
 * content here and segfault when called pre-load. Frontends must only
 * query geometry after ezcore_load_game succeeds. */
void ezcore_system_geometry(ezcore_session *s, unsigned *w, unsigned *h,
                         double *fps) {
  if (!s) return;
  if (!s->game_loaded) {
    if (w) *w = 0;
    if (h) *h = 0;
    if (fps) *fps = 0;
    return;
  }
  struct retro_system_av_info av;
  memset(&av, 0, sizeof(av));
  s->retro_get_system_av_info(&av);
  if (w) *w = av.geometry.base_width;
  if (h) *h = av.geometry.base_height;
  if (fps) *fps = av.timing.fps;
}

/* Sample rate from AV timing (valid after load_game). Returns 0 if unavailable. */
double ezcore_sample_rate(ezcore_session *s) {
  if (!s || !s->game_loaded) return 0.0;
  struct retro_system_av_info av;
  memset(&av, 0, sizeof(av));
  s->retro_get_system_av_info(&av);
  return av.timing.sample_rate;
}

void ezcore_cheat_reset(ezcore_session *s) {
  if (s && s->retro_cheat_reset) s->retro_cheat_reset();
}

bool ezcore_cheat_set(ezcore_session *s, unsigned index, bool enabled,
                   const char *code) {
  if (!s || !code || !s->retro_cheat_set) return false;
  /* The libretro hook is void; true means dispatch was attempted, not that
   * the core validated the code. */
  s->retro_cheat_set(index, enabled, code);
  return true;
}

void ezcore_set_button(ezcore_session *s, unsigned port, unsigned button_id,
                    bool pressed) {
  if (!s || port >= 4 || button_id >= 16) return;
  if (pressed)
    s->input_buttons[port] |= (1u << button_id);
  else
    s->input_buttons[port] &= ~(1u << button_id);
}

/* Clear all buttons for a port. */
void ezcore_clear_buttons(ezcore_session *s, unsigned port) {
  if (!s || port >= 4) return;
  s->input_buttons[port] = 0;
}

void ezcore_set_analog(ezcore_session *s, unsigned port, unsigned stick,
                       unsigned axis, int16_t value) {
  if (!s || port >= 4 || stick > 1 || axis > 1) return;
  s->analog[port][stick][axis] = value;
}

void ezcore_mouse_move(ezcore_session *s, int dx, int dy) {
  if (!s) return;
  /* Saturate rather than overflow if a host floods motion between frames. */
  int64_t x = (int64_t)s->mouse_pending_dx + dx;
  int64_t y = (int64_t)s->mouse_pending_dy + dy;
  s->mouse_pending_dx = (int32_t)(x > 1000000 ? 1000000 : x < -1000000 ? -1000000 : x);
  s->mouse_pending_dy = (int32_t)(y > 1000000 ? 1000000 : y < -1000000 ? -1000000 : y);
}

void ezcore_set_mouse_button(ezcore_session *s, unsigned id, bool pressed) {
  if (!s || id >= 32) return;
  if (pressed) s->mouse_buttons |= (1u << id);
  else s->mouse_buttons &= ~(1u << id);
}

void ezcore_set_key(ezcore_session *s, unsigned keycode, bool pressed,
                    uint32_t character, uint16_t modifiers) {
  if (!s || keycode >= RETROK_LAST) return;
  if (pressed) s->keys[keycode / 8] |= (uint8_t)(1u << (keycode % 8));
  else s->keys[keycode / 8] &= (uint8_t)~(1u << (keycode % 8));
  if (s->keyboard_cb) {
    ezcore_session *prev = g_active;
    g_active = s; /* the callback may query input state */
    s->keyboard_cb(pressed, keycode, character, modifiers);
    g_active = prev;
  }
}

void ezcore_set_pointer(ezcore_session *s, int16_t x, int16_t y, bool pressed) {
  if (!s) return;
  s->pointer_x = x;
  s->pointer_y = y;
  s->pointer_pressed = pressed;
}

/* --- Safe frame/audio access (copies) --- */

/* Copies the latest frame's pixels into `out` as RGBA bytes.
 * `out` must be at least width*height*4 bytes.
 * Returns the number of bytes copied (width*height*4), or 0 if no frame yet. */
size_t ezcore_frame_pixels_copy(ezcore_session *s, uint8_t *out,
                             size_t out_size) {
  if (!s || !out) return 0;
  size_t need = (size_t)s->frame_w * s->frame_h * 4;
  if (need == 0 || need > out_size) return 0;
  for (size_t i = 0; i < need / 4; ++i) {
    uint32_t pixel = s->frame[i];
    out[i * 4] = (uint8_t)(pixel >> 16);
    out[i * 4 + 1] = (uint8_t)(pixel >> 8);
    out[i * 4 + 2] = (uint8_t)pixel;
    out[i * 4 + 3] = 255;
  }
  return need;
}

/* Returns width/height of latest frame. 0 when no frame yet. */
void ezcore_frame_size(ezcore_session *s, unsigned *w, unsigned *h) {
  if (!s) { if (w) *w = 0; if (h) *h = 0; return; }
  if (w) *w = s->frame_w;
  if (h) *h = s->frame_h;
}

/* Returns a const pointer to the latest frame (XRGB8888). Use for fast access
 * when the frame is only read. Do NOT free. */
const uint32_t *ezcore_frame_pixels(ezcore_session *s, unsigned *w, unsigned *h) {
  if (!s) return NULL;
  if (w) *w = s->frame_w;
  if (h) *h = s->frame_h;
  return s->frame;
}

/* Audio: frames appended by the audio batch callback; drained by player. */
size_t ezcore_audio_drain(ezcore_session *s, int16_t *out, size_t frames) {
  if (!s || !out) return 0;
  size_t n = s->audio_len < frames ? s->audio_len : frames;
  memcpy(out, s->audio, n * 2 * sizeof(int16_t));
  memmove(s->audio, s->audio + n * 2,
          (s->audio_len - n) * 2 * sizeof(int16_t));
  s->audio_len -= n;
  return n;
}

/* Drains up to `max_frames` stereo s16 samples into `out`.
 * `out` must be at least max_frames * 2 * sizeof(int16_t) bytes.
 * Returns number of frames actually drained. */
size_t ezcore_audio_drain_copy(ezcore_session *s, int16_t *out,
                            size_t max_frames) {
  return ezcore_audio_drain(s, out, max_frames);
}

/* Current number of audio frames queued in the ring buffer. */
size_t ezcore_audio_pending(ezcore_session *s) {
  return s ? s->audio_len : 0;
}

/* Save states live in the runtime (local vault today, sync providers
 * tomorrow). All three require a loaded game and degrade to 0/false
 * when the core omits the entry points. */
size_t ezcore_serialize_size(ezcore_session *s) {
  if (!s || !s->game_loaded || !s->retro_serialize_size) return 0;
  return s->retro_serialize_size();
}

bool ezcore_serialize(ezcore_session *s, void *out, size_t size) {
  if (!s || !s->game_loaded || !s->retro_serialize || !out) return false;
  return s->retro_serialize(out, size);
}

bool ezcore_unserialize(ezcore_session *s, const void *data, size_t size) {
  if (!s || !s->game_loaded || !s->retro_unserialize || !data) return false;
  return s->retro_unserialize(data, size);
}

/* ---- Core Options & Capability Surface ---- */

/* Returns the version that the host reported to the core via
 * RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION.  Stored by the core in its
 * library_version string at load time; callers verify it there. */

unsigned ezcore_get_core_option_count(ezcore_session *s) {
  return s ? s->num_core_options : 0;
}

bool ezcore_get_core_option(ezcore_session *s, unsigned index,
                            const char **key, const char **default_value,
                            const char **value) {
  if (!s || index >= s->num_core_options) return false;
  const struct ezcore_core_option *co = &s->core_options[index];
  if (key) *key = co->key;
  if (default_value) *default_value = co->default_value;
  if (value) *value = co->value;
  return true;
}

bool ezcore_set_core_option(ezcore_session *s, const char *key,
                            const char *value) {
  if (!s || !key) return false;
  for (unsigned i = 0; i < s->num_core_options; i++) {
    struct ezcore_core_option *co = &s->core_options[i];
    if (co->key && strcmp(co->key, key) == 0) {
      /* Re-setting the current value is not a change: raising the update
       * flag would make the core reconfigure for nothing. */
      bool same = co->value && value && strcmp(co->value, value) == 0;
      if (!same) {
        free(co->value);
        co->value = ezcore_strdup(value);
        s->core_options_dirty = true;
      }
      return true;
    }
  }
  return false;
}

unsigned ezcore_get_input_descriptor_count(ezcore_session *s) {
  return s ? s->num_input_descs : 0;
}

bool ezcore_get_input_descriptor(ezcore_session *s, unsigned index,
                                 unsigned *port, unsigned *device,
                                 unsigned *desc_index, unsigned *id,
                                 const char **description) {
  if (!s || index >= s->num_input_descs) return false;
  const struct ezcore_input_desc *d = &s->input_descs[index];
  if (port) *port = d->port;
  if (device) *device = d->device;
  if (desc_index) *desc_index = d->index;
  if (id) *id = d->id;
  if (description) *description = d->description;
  return true;
}

unsigned ezcore_get_controller_port_count(ezcore_session *s) {
  return s ? s->num_controller_ports : 0;
}

unsigned ezcore_get_controller_port_type_count(ezcore_session *s, unsigned port) {
  if (!s || port >= s->num_controller_ports) return 0;
  return s->controller_ports[port].num_types;
}

bool ezcore_get_controller_port_type(ezcore_session *s, unsigned port,
                                     unsigned type_index, unsigned *id,
                                     const char **description) {
  if (!s || port >= s->num_controller_ports) return false;
  const struct ezcore_controller_port *p = &s->controller_ports[port];
  if (type_index >= p->num_types) return false;
  const struct ezcore_controller_desc *d = &p->types[type_index];
  if (id) *id = d->id;
  if (description) *description = d->desc;
  return true;
}

unsigned ezcore_get_memory_descriptor_count(ezcore_session *s) {
  return s ? s->num_mem_descs : 0;
}

bool ezcore_get_memory_descriptor(ezcore_session *s, unsigned index,
                                  uint64_t *flags, void **ptr,
                                  size_t *offset, size_t *start,
                                  size_t *select, size_t *disconnect,
                                  size_t *len, const char **addrspace) {
  if (!s || index >= s->num_mem_descs) return false;
  const struct ezcore_mem_desc *md = &s->mem_descs[index];
  if (flags) *flags = md->flags;
  if (ptr) *ptr = md->ptr;
  if (offset) *offset = md->offset;
  if (start) *start = md->start;
  if (select) *select = md->select;
  if (disconnect) *disconnect = md->disconnect;
  if (len) *len = md->len;
  if (addrspace) *addrspace = md->addrspace;
  return true;
}
