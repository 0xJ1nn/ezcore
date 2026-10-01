/* A synthetic core that REQUIRES hardware rendering, in the shape of the six
 * cores P8 is for: it calls SET_HW_RENDER in retro_load_game and refuses to run
 * if the host says no.
 *
 * This is the test that proves env_cb is actually wired. The seam test proves a
 * context can be created; only this proves a CORE can ask for one and be
 * driven through it. Everything about it is synthetic and CC0 -- no
 * copyrighted core, no ROM, no gameplay.
 *
 * Each step is recorded in globals that the test asserts on, so a failure says
 * WHICH negotiation step broke rather than just "the core did not run".
 */
#include <stdio.h>
#include <string.h>

#include <libretro.h>

#define W 64
#define H 64

/* The callback struct is SESSION-LONG state, not a load-time temporary. The
 * first version of this fixture declared it as a local of retro_load_game and
 * stored &local in g_cb, so every use after that function returned -- including
 * retro_reset -- dereferenced dead stack. A real core keeps this struct alive
 * for the whole session, which is what the host relies on when it overwrites
 * the function pointers. */
static struct retro_hw_render_callback g_hw;
static struct retro_hw_render_callback *g_cb = NULL;

/* --- what the host told us, for the test to check --- */
int g_set_hw_render_result = -1;   /* what env_cb returned */
int g_have_context = 0;             /* context_reset was called */
int g_negotiated = 0;              /* GET_HW_RENDER_INTERFACE succeeded */
unsigned g_framebuffer = 0xFFFFFFFFu; /* what get_current_framebuffer gave */
int g_proc_address_ok = 0;         /* our resolver returned a real symbol */
unsigned g_iface_version = 0xFFFFFFFFu; /* interface_version the host reported */
int g_frames_drawn = 0;
static unsigned g_fb = 0;
static int g_fired = 0;

/* context_reset: the core creates its GL resources here. It is the FIRST thing
 * a real core does, and libretro.h:4151 says the context is only valid after
 * it, so the test asserts our shim ran. */
static void on_context_reset(void) {
  g_have_context = 1;
  g_fb = g_cb ? g_cb->get_current_framebuffer() : 0;
  g_framebuffer = g_fb;
}

static void on_context_destroy(void) { g_have_context = 0; }

/* The core asks OUR resolver (SET_PROC_ADDRESS_CALLBACK hands this back) and
 * expects a real, callable symbol. On a working GLES3 context glClear must
 * resolve; if it does not, the core cannot render and must not claim to. */
/* The real typedef: libretro.h:5790 is a function POINTER returning a
 * retro_proc_address_t. The first draft used `void *(const char *)`, which
 * happens to be layout-compatible here and would have been a silently
 * wrong type on any ABI where it is not. */
/* This is the core's INITIAL resolver. The host captures it, then installs its
 * own, and hands that one back through SET_PROC_ADDRESS_CALLBACK. A real core
 * then uses the resolver it was GIVEN -- not the one it shipped with.
 *
 * The first version of this fixture called g_cb->get_proc_address from here,
 * which after the host installed its shim is the host's resolver, which
 * eventually reaches the core's original again: infinite mutual recursion, or
 * at best a flag that only sets on some paths. The point of the test is to
 * exercise the resolver the core was given, so that is what it calls. */
static retro_proc_address_t on_get_proc_initial(const char *sym) {
  (void)sym;
  return NULL;   /* the core's own fallback: no driver extensions */
}

void retro_init(void) {
  g_cb = NULL; g_fb = 0; g_fired = 0; g_have_context = 0;
  g_negotiated = 0; g_framebuffer = 0xFFFFFFFFu; g_proc_address_ok = 0;
  g_iface_version = 0xFFFFFFFFu;
  g_frames_drawn = 0; g_set_hw_render_result = -1;
}

void retro_deinit(void) {}

unsigned retro_api_version(void) { return RETRO_API_VERSION; }

void retro_get_system_info(struct retro_system_info *info) {
  memset(info, 0, sizeof(*info));
  info->library_name = "ezTest HW Render Probe";
  info->library_version = "1.0.0";
  info->valid_extensions = "probe";
  info->need_fullpath = false;
  info->block_extract = false;
}

void retro_get_system_av_info(struct retro_system_av_info *av) {
  memset(av, 0, sizeof(*av));
  av->geometry.base_width = W;
  av->geometry.base_height = H;
  av->geometry.max_width = W;
  av->geometry.max_height = H;
  av->geometry.aspect_ratio = (float)W / (float)H;
}

/* The environment callback the host installs. A real core stores exactly
 * this and calls it for SET_HW_RENDER; getting this wrong is why cores that
 * "require" hardware often fall back to software -- they never actually ask. */
static retro_environment_t env_cb = NULL;
void retro_set_environment(retro_environment_t cb) { env_cb = cb; }
#ifdef EZCORE_SYNTH_HW_DRAW
/* Drawing variant (synth_hw_draw target): it renders a known picture and
 * submits it the way real GPU cores do, so readback can be checked. */
static retro_video_refresh_t g_video = NULL;
typedef void (*gl_bindfb_t)(unsigned, unsigned);
typedef void (*gl_clearcolor_t)(float, float, float, float);
typedef void (*gl_clear_t)(unsigned);
typedef void (*gl_scissor_t)(int, int, int, int);
typedef void (*gl_cap_t)(unsigned);
typedef void (*gl_viewport_t)(int, int, int, int);
static gl_bindfb_t p_bind;
static gl_clearcolor_t p_clearcolor;
static gl_clear_t p_clear;
static gl_scissor_t p_scissor;
static gl_cap_t p_enable, p_disable;
static gl_viewport_t p_viewport;
void retro_set_video_refresh(retro_video_refresh_t cb) { g_video = cb; }
#else
void retro_set_video_refresh(retro_video_refresh_t cb) { (void)cb; }
#endif
void retro_set_audio_sample(retro_audio_sample_t cb) { (void)cb; }
void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { (void)cb; }
void retro_set_input_poll(retro_input_poll_t cb) { (void)cb; }
void retro_set_input_state(retro_input_state_t cb) { (void)cb; }
void retro_set_controller_port_device(unsigned p, unsigned d) {
  (void)p; (void)d;
}
void retro_set_log_callback(retro_log_printf_t cb) { (void)cb; }
void retro_deinit_log(void) {}



bool retro_load_game(const struct retro_game_info *game) {
  (void)game;
  /* No environment callback means no way to ask for a context. A core must
   * refuse rather than pretend, which is why the test can tell "host declined"
   * apart from "host never answered". */
  if (!env_cb) return false;
  memset(&g_hw, 0, sizeof(g_hw));
  struct retro_hw_render_callback *hw = &g_hw;
  hw->context_type = RETRO_HW_CONTEXT_OPENGLES3;
  hw->version_major = 3;
  hw->version_minor = 0;
  hw->get_proc_address = on_get_proc_initial;
  hw->context_reset = on_context_reset;
  hw->context_destroy = on_context_destroy;
  hw->get_current_framebuffer = NULL;   /* the HOST fills this in */
  hw->depth = true;
  hw->stencil = true;
  hw->bottom_left_origin = true;
  hw->cache_context = false;
  hw->debug_context = false;

  /* Ask for GLES3, the way a mobile-first core would. */
  g_set_hw_render_result =
      env_cb(RETRO_ENVIRONMENT_SET_HW_RENDER, hw) ? 1 : 0;
  if (!g_set_hw_render_result) return false;

  /* The host must have installed its own shims over ours; if it did not, it
   * never created a context and this core must not pretend otherwise. */
  if (hw->context_reset == on_context_reset) return false;
  g_cb = hw;

  /* Now the interface, which libretro.h:1638 requires AFTER context_reset.
   * `data` is `const struct retro_hw_render_interface **` -- the host stores a
   * pointer to ITS OWN interface struct there. The first version of this
   * fixture passed an `int *`, so the host wrote a pointer into a 4-byte int
   * and the core read back a truncated, nonsense pointer. */
  g_cb->context_reset();   /* the host marks itself negotiated inside this */

  const struct retro_hw_render_interface *iface = NULL;
  if (env_cb(RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE, &iface) && iface) {
    g_negotiated = 1;
    g_iface_version = iface->interface_version;
  } else {
    g_negotiated = 0;
  }

  /* Only now ask which resolver to use. The host hands back the one that
   * will work; the core uses it for the rest of the session. */
  retro_hw_get_proc_address_t resolver = NULL;
  /* A core without a working resolver cannot render, so it refuses here rather
   * than drawing nothing: a NULL glClear is a black screen, not a fallback. */
  if (!env_cb(RETRO_ENVIRONMENT_SET_PROC_ADDRESS_CALLBACK, &resolver) ||
      !resolver)
    return false;
  /* A core resolves what it needs and REFUSES to run if it cannot: rendering
   * with a NULL glClear is a black screen, not a fallback. */
  {
    void *p = (void *)resolver("glClear");
    if (p) g_proc_address_ok |= 1;
    p = (void *)resolver("glGenFramebuffers");
    if (p) g_proc_address_ok |= 2;
    p = (void *)resolver("glBindFramebuffer");
    if (p) g_proc_address_ok |= 4;
  }
#ifdef EZCORE_SYNTH_HW_DRAW
  p_bind = (gl_bindfb_t)resolver("glBindFramebuffer");
  p_clearcolor = (gl_clearcolor_t)resolver("glClearColor");
  p_clear = (gl_clear_t)resolver("glClear");
  p_scissor = (gl_scissor_t)resolver("glScissor");
  p_enable = (gl_cap_t)resolver("glEnable");
  p_disable = (gl_cap_t)resolver("glDisable");
  p_viewport = (gl_viewport_t)resolver("glViewport");
  if (!p_bind || !p_clearcolor || !p_clear || !p_scissor || !p_enable ||
      !p_disable || !p_viewport)
    return false;
#endif

  return true;
}

void retro_unload_game(void) { if (g_cb) { g_cb->context_destroy(); g_cb = NULL; } }
void retro_reset(void) { if (g_cb) g_cb->context_reset(); }

/* Draw only when we were actually given a context and a framebuffer, which is
 * the whole point: a core handed no context must not pretend to render. */
void retro_run(void) {
  if (!g_cb || !g_have_context) return;
  if (g_framebuffer == 0xFFFFFFFFu) return;
  g_frames_drawn++;
#ifdef EZCORE_SYNTH_HW_DRAW
  /* Red everywhere, green in the top half in GL terms (bottom-left origin,
   * so y = H/2 .. H is the top of the picture), then submit. */
  p_bind(0x8D40 /* GL_FRAMEBUFFER */, (unsigned)g_cb->get_current_framebuffer());
  p_viewport(0, 0, W, H);
  p_clearcolor(1.0f, 0.0f, 0.0f, 1.0f);
  p_clear(0x4000 /* GL_COLOR_BUFFER_BIT */);
  p_enable(0x0C11 /* GL_SCISSOR_TEST */);
  p_scissor(0, H / 2, W, H / 2);
  p_clearcolor(0.0f, 1.0f, 0.0f, 1.0f);
  p_clear(0x4000);
  p_disable(0x0C11);
  if (g_video) g_video(RETRO_HW_FRAME_BUFFER_VALID, W, H, 0);
#endif
}

size_t retro_serialize_size(void) { return 0; }
bool retro_serialize(void *d, size_t s) { (void)d; (void)s; return true; }
bool retro_unserialize(const void *d, size_t s) { (void)d; (void)s; return true; }
bool retro_load_game_special(unsigned t, const struct retro_game_info *i,
                             size_t n) {
  (void)t; (void)i; (void)n; return false;
}
void retro_cheat_reset(void) {}
void retro_cheat_set(unsigned i, bool e, const char *c) {
  (void)i; (void)e; (void)c;
}

/* --- accessors for the test, since the core is dlopen'd --- */
int probe_set_hw_render_result(void) { return g_set_hw_render_result; }
int probe_have_context(void) { return g_have_context; }
int probe_negotiated(void) { return g_negotiated; }
unsigned probe_framebuffer(void) { return g_framebuffer; }
int probe_proc_address_ok(void) { return g_proc_address_ok; }
unsigned probe_iface_version(void) { return g_iface_version; }
int probe_frames_drawn(void) { return g_frames_drawn; }
