// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* ezcore_loop.c — the runtime-owned run thread, one per session.
 *
 * The thread calls retro_run through the session API, paced by the audio device
 * clock from ezcore_audio.c. When no device is open it falls back to a
 * monotonic clock. Each completed frame goes into a three-slot buffer: a
 * reader pins the newest complete frame and the producer never overwrites a
 * pinned slot, so a slow Flutter texture presents a recent frame rather than
 * blocking emulation (latest-frame-wins). Input and controls are written from
 * another thread through atomics and a bounded queue; both are applied by the
 * loop thread, which is the only thread that ever calls into the core.
 *
 * The same source is compiled for all five release targets. Thread creation,
 * sleeping and the monotonic clock use small platform wrappers here so no
 * third-party thread library enters the runtime; the audio device comes from
 * the shared miniaudio implementation.
 */
#include "ezcore_runtime.h"
#include "ezcore_audio_internal.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <pthread.h>
#include <time.h>
#endif

#define EZCORE_CTRL_CAP 64u
#define EZCORE_HIST_MIN 8u
#define EZCORE_HIST_MAX 256u
#define EZCORE_HIST_DEFAULT 64u
#define EZCORE_HIST_MAX_MS 40.0
#define EZCORE_MAX_LOOPS 8u

/* ---- Platform wrappers (POSIX and Win32 only; no third-party threading) ---- */

typedef void (*ez_thread_proc)(void *);

typedef struct {
  ez_thread_proc proc;
  void *arg;
} ez_thread_args;

#if defined(_WIN32)
typedef HANDLE ez_thread_handle;

static DWORD WINAPI ez_thread_trampoline(LPVOID p) {
  ez_thread_args *a = (ez_thread_args *)p;
  a->proc(a->arg);
  free(a);
  return 0;
}

static bool ez_thread_start(ez_thread_handle *out, ez_thread_proc proc, void *arg) {
  ez_thread_args *a = (ez_thread_args *)malloc(sizeof(*a));
  if (!a) return false;
  a->proc = proc;
  a->arg = arg;
  *out = CreateThread(NULL, 0, ez_thread_trampoline, a, 0, NULL);
  if (!*out) {
    free(a);
    return false;
  }
  return true;
}

static void ez_thread_join(ez_thread_handle thread) {
  WaitForSingleObject(thread, INFINITE);
  CloseHandle(thread);
}

static double ez_now_seconds(void) {
  LARGE_INTEGER freq, counter;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&counter);
  if (freq.QuadPart == 0) return 0.0;
  return (double)counter.QuadPart / (double)freq.QuadPart;
}

static void ez_nap_ms(unsigned ms) { Sleep(ms); }
#else
typedef pthread_t ez_thread_handle;

static void *ez_thread_trampoline(void *p) {
  ez_thread_args *a = (ez_thread_args *)p;
  a->proc(a->arg);
  free(a);
  return NULL;
}

static bool ez_thread_start(ez_thread_handle *out, ez_thread_proc proc, void *arg) {
  ez_thread_args *a = (ez_thread_args *)malloc(sizeof(*a));
  if (!a) return false;
  a->proc = proc;
  a->arg = arg;
  if (pthread_create(out, NULL, ez_thread_trampoline, a) != 0) {
    free(a);
    return false;
  }
  return true;
}

static void ez_thread_join(ez_thread_handle thread) { pthread_join(thread, NULL); }

static double ez_now_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void ez_nap_ms(unsigned ms) {
  struct timespec ts;
  ts.tv_sec = (time_t)(ms / 1000u);
  ts.tv_nsec = (long)(ms % 1000u) * 1000000L;
  nanosleep(&ts, NULL);
}
#endif

/* ---- Process-wide guards ----
 * Core callbacks route through one active-session pointer in runtime.c, and
 * the audio device is process-wide. The run lock is held across retro_run and
 * across control calls that enter the core, so a second loop (a session
 * preview, for example) cannot steal the callback target mid-frame. With the
 * one-game-at-a-time player it is uncontended. */
static atomic_flag g_run_lock = ATOMIC_FLAG_INIT;
static atomic_flag g_registry_lock = ATOMIC_FLAG_INIT;
static ezcore_session *g_registry[EZCORE_MAX_LOOPS];

static void lock_spin(atomic_flag *flag) {
  while (atomic_flag_test_and_set_explicit(flag, memory_order_acquire)) {
  }
}

static void unlock_spin(atomic_flag *flag) {
  atomic_flag_clear_explicit(flag, memory_order_release);
}

static bool registry_add(ezcore_session *s) {
  bool ok = false;
  lock_spin(&g_registry_lock);
  for (unsigned i = 0; i < EZCORE_MAX_LOOPS; i++) {
    if (!g_registry[i]) {
      g_registry[i] = s;
      ok = true;
      break;
    }
  }
  unlock_spin(&g_registry_lock);
  return ok;
}

static void registry_remove(ezcore_session *s) {
  lock_spin(&g_registry_lock);
  for (unsigned i = 0; i < EZCORE_MAX_LOOPS; i++) {
    if (g_registry[i] == s) g_registry[i] = NULL;
  }
  unlock_spin(&g_registry_lock);
}

/* ---- Queued controls ---- */

typedef enum {
  CTRL_NONE = 0,
  CTRL_PAUSE,
  CTRL_FAST_FORWARD,
  CTRL_SAVE,
  CTRL_LOAD,
  CTRL_RESET,
  CTRL_CHEAT_RESET,
  CTRL_CHEAT_SET,
  CTRL_OPTION
} ctrl_type;

typedef struct {
  _Atomic unsigned state; /* 0 free, 1 queued, 2 applying, 3 done */
  uint64_t token;
  ctrl_type type;
  bool result;
  bool boolean;
  uint32_t number;
  void *ptr;       /* SAVE: caller buffer. LOAD: runtime-owned copy. */
  size_t size;
  bool owns_ptr;   /* only LOAD owns the buffer */
  char *text;      /* CHEAT_SET code, or OPTION key */
  char *text2;     /* OPTION value */
} ctrl_slot;

/* ---- Triple-buffered frames ---- */

typedef struct {
  /* 0 free, 1 ready, 2 pinned by a reader, 3 claimed by the producer */
  _Atomic int state;
  _Atomic uint64_t generation;
  uint32_t *pixels;
  unsigned w, h;
  size_t capacity;
} frame_slot;

struct ezcore_loop {
  ezcore_session *session;
  ez_thread_handle thread;
  bool thread_live;

  _Atomic int stop;
  _Atomic int paused;
  _Atomic uint32_t fast_forward;
  _Atomic int user_muted;

  /* Input written through FFI; copied into the session before retro_run. */
  _Atomic uint32_t buttons[4];
  _Atomic int16_t analog[4][2][2];

  ctrl_slot controls[EZCORE_CTRL_CAP];
  atomic_flag ctrl_lock;
  uint64_t next_token;
  _Atomic uint64_t controls_applied;

  frame_slot slots[3];
  _Atomic int pinned; /* -1 when no frame is pinned */

  double fps;
  uint32_t buckets;
  double hist_max_ms;
  uint32_t *histogram;

  _Atomic uint64_t frames_run;
  _Atomic uint64_t dropped_frames;
  _Atomic uint64_t frame_clock;
  double sum_frame_ms;
  uint64_t frame_samples;
  double frame_last_ms;
  double frame_max_ms;

  /* Seqlock: odd sequence means the writer is mid-update. */
  _Atomic unsigned stats_seq;
  ezcore_loop_statistics stats[2];
};

/* ---- Helpers ---- */

/* Reserves a slot and fills it under one lock. `fill` receives the slot. */
typedef void (*ctrl_fill_fn)(ctrl_slot *, void *);

static uint64_t queue_control(ezcore_loop *loop, ctrl_type type,
                              ctrl_fill_fn fill, void *ctx) {
  if (!loop) return 0;
  uint64_t token = 0;
  lock_spin(&loop->ctrl_lock);
  for (unsigned i = 0; i < EZCORE_CTRL_CAP; i++) {
    ctrl_slot *slot = &loop->controls[i];
    if (atomic_load_explicit(&slot->state, memory_order_relaxed) != 0) continue;
    memset(slot, 0, sizeof(*slot));
    slot->type = type;
    slot->state = 1;
    token = ++loop->next_token;
    slot->token = token;
    if (fill) fill(slot, ctx);
    atomic_store_explicit(&slot->state, 1, memory_order_release);
    break;
  }
  unlock_spin(&loop->ctrl_lock);
  return token;
}

static void fill_pause(ctrl_slot *s, void *ctx) { s->boolean = *(bool *)ctx; }
static void fill_ff(ctrl_slot *s, void *ctx) { s->number = *(uint32_t *)ctx; }
static void fill_reset(ctrl_slot *s, void *ctx) { (void)s; (void)ctx; }
static void fill_save(ctrl_slot *s, void *ctx) {
  ctrl_slot *src = (ctrl_slot *)ctx;
  s->ptr = src->ptr;
  s->size = src->size;
}
static void fill_load(ctrl_slot *s, void *ctx) {
  ctrl_slot *src = (ctrl_slot *)ctx;
  /* Copy the bytes: the caller may free them as soon as the call returns. */
  s->ptr = malloc(src->size ? src->size : 1);
  if (s->ptr) {
    memcpy(s->ptr, src->ptr, src->size);
    s->size = src->size;
    s->owns_ptr = true;
  }
}
static void fill_cheat_set(ctrl_slot *s, void *ctx) {
  ctrl_slot *src = (ctrl_slot *)ctx;
  s->number = src->number;
  s->boolean = src->boolean;
  if (src->text) s->text = strdup(src->text);
}
static void fill_option(ctrl_slot *s, void *ctx) {
  ctrl_slot *src = (ctrl_slot *)ctx;
  if (src->text) s->text = strdup(src->text);
  if (src->text2) s->text2 = strdup(src->text2);
}

static void apply_inputs(ezcore_loop *loop) {
  ezcore_session *s = loop->session;
  for (unsigned port = 0; port < 4; port++) {
    uint32_t mask = atomic_load_explicit(&loop->buttons[port], memory_order_relaxed);
    for (unsigned button = 0; button < 16; button++) {
      ezcore_set_button(s, port, button, (mask & (1u << button)) != 0);
    }
    for (unsigned stick = 0; stick < 2; stick++) {
      for (unsigned axis = 0; axis < 2; axis++) {
        ezcore_set_analog(s, port, stick, axis,
                          atomic_load_explicit(&loop->analog[port][stick][axis],
                                               memory_order_relaxed));
      }
    }
  }
}

static void sync_loop_audio(ezcore_loop *loop) {
  ezcore_audio *audio = ezcore_audio_active();
  if (!audio) return;
  /* Fast-forward drops device audio: the core still produces frames, but the
   * player hears silence rather than a sped-up tape. Restore the user's mute
   * preference when normal speed resumes. */
  ezcore_audio_set_muted(audio,
                         atomic_load(&loop->user_muted) != 0 ||
                             atomic_load(&loop->fast_forward) > 1);
}

static void process_controls(ezcore_loop *loop) {
  for (;;) {
    ctrl_slot *slot = NULL;
    lock_spin(&loop->ctrl_lock);
    for (unsigned i = 0; i < EZCORE_CTRL_CAP; i++) {
      ctrl_slot *candidate = &loop->controls[i];
      if (atomic_load_explicit(&candidate->state, memory_order_relaxed) == 1) {
        atomic_store_explicit(&candidate->state, 2, memory_order_relaxed);
        slot = candidate;
        break;
      }
    }
    unlock_spin(&loop->ctrl_lock);
    if (!slot) return;

    bool ok = false;
    switch (slot->type) {
      case CTRL_PAUSE:
        atomic_store(&loop->paused, slot->boolean ? 1 : 0);
        ok = true;
        break;
      case CTRL_FAST_FORWARD: {
        uint32_t factor = slot->number;
        if (factor < 1) factor = 1;
        if (factor > 8) factor = 8;
        atomic_store(&loop->fast_forward, factor);
        sync_loop_audio(loop);
        ok = true;
        break;
      }
      case CTRL_SAVE:
        lock_spin(&g_run_lock);
        ok = ezcore_serialize(loop->session, slot->ptr, slot->size);
        unlock_spin(&g_run_lock);
        break;
      case CTRL_LOAD:
        lock_spin(&g_run_lock);
        ok = ezcore_unserialize(loop->session, slot->ptr, slot->size);
        unlock_spin(&g_run_lock);
        break;
      case CTRL_RESET:
        lock_spin(&g_run_lock);
        ezcore_reset(loop->session);
        unlock_spin(&g_run_lock);
        ok = true;
        break;
      case CTRL_CHEAT_RESET:
        lock_spin(&g_run_lock);
        ezcore_cheat_reset(loop->session);
        unlock_spin(&g_run_lock);
        ok = true;
        break;
      case CTRL_CHEAT_SET:
        lock_spin(&g_run_lock);
        ok = ezcore_cheat_set(loop->session, slot->number, slot->boolean, slot->text);
        unlock_spin(&g_run_lock);
        break;
      case CTRL_OPTION:
        lock_spin(&g_run_lock);
        ok = ezcore_set_core_option(loop->session, slot->text, slot->text2);
        unlock_spin(&g_run_lock);
        break;
      case CTRL_NONE:
        break;
    }

    slot->result = ok;
    if (slot->owns_ptr) free(slot->ptr);
    free(slot->text);
    free(slot->text2);
    atomic_fetch_add_explicit(&loop->controls_applied, 1, memory_order_relaxed);
    atomic_store_explicit(&slot->state, 3, memory_order_release);
  }
}

static void publish_frame(ezcore_loop *loop, const ezcore_session *session) {
  unsigned w = 0, h = 0;
  ezcore_frame_size((ezcore_session *)session, &w, &h);
  if (!w || !h) return;
  size_t need = (size_t)w * h * 4;

  frame_slot *target = NULL;
  bool replaced = false;
  int pinned = atomic_load_explicit(&loop->pinned, memory_order_acquire);
  /* Claim a slot with a compare-and-swap so a reader that pins it at the same
   * instant cannot read while the new frame is being copied into it. Three
   * attempts cover a reader racing each candidate. */
  for (unsigned attempt = 0; attempt < 3 && !target; attempt++) {
    frame_slot *free_slot = NULL;
    frame_slot *oldest_ready = NULL;
    uint64_t oldest = UINT64_MAX;
    for (unsigned i = 0; i < 3; i++) {
      frame_slot *slot = &loop->slots[i];
      if ((int)i == pinned) continue;
      int state = atomic_load_explicit(&slot->state, memory_order_acquire);
      if (state == 0) {
        free_slot = slot;
        break;
      }
      if (state == 1) {
        uint64_t generation = atomic_load_explicit(&slot->generation, memory_order_relaxed);
        if (generation < oldest) {
          oldest = generation;
          oldest_ready = slot;
        }
      }
    }
    if (free_slot) {
      int expected = 0;
      if (atomic_compare_exchange_strong_explicit(&free_slot->state, &expected, 3,
                                                  memory_order_acq_rel,
                                                  memory_order_relaxed))
        target = free_slot;
      continue;
    }
    if (oldest_ready) {
      int expected = 1;
      if (atomic_compare_exchange_strong_explicit(&oldest_ready->state, &expected, 3,
                                                  memory_order_acq_rel,
                                                  memory_order_relaxed)) {
        target = oldest_ready;
        replaced = true;
      }
    }
  }
  if (!target) return;
  if (replaced)
    atomic_fetch_add_explicit(&loop->dropped_frames, 1, memory_order_relaxed);

  if (target->capacity < need) {
    uint32_t *bigger = (uint32_t *)realloc(target->pixels, need);
    if (!bigger) return;
    target->pixels = bigger;
    target->capacity = need;
  }
  unsigned tw = 0, th = 0;
  const uint32_t *src = ezcore_frame_pixels((ezcore_session *)session, &tw, &th);
  if (!src || tw != w || th != h) return;
  memcpy(target->pixels, src, need);
  target->w = w;
  target->h = h;
  atomic_store_explicit(&target->generation,
                        atomic_fetch_add_explicit(&loop->frame_clock, 1,
                                                  memory_order_relaxed) + 1,
                        memory_order_relaxed);
  atomic_store_explicit(&target->state, 1, memory_order_release);
}

static void record_frame_time(ezcore_loop *loop, double ms) {
  if (ms < 0.0) ms = 0.0;
  uint32_t bucket = (uint32_t)(ms / loop->hist_max_ms * (double)loop->buckets);
  if (bucket >= loop->buckets) bucket = loop->buckets - 1;
  loop->histogram[bucket]++;
  loop->sum_frame_ms += ms;
  loop->frame_samples++;
  loop->frame_last_ms = ms;
  if (ms > loop->frame_max_ms) loop->frame_max_ms = ms;
}

static double percentile_ms(const ezcore_loop *loop, double fraction) {
  if (!loop->frame_samples) return 0.0;
  double target = (double)loop->frame_samples * fraction;
  uint64_t seen = 0;
  for (uint32_t i = 0; i < loop->buckets; i++) {
    seen += loop->histogram[i];
    if (seen >= target) {
      return (double)(i + 1) * loop->hist_max_ms / (double)loop->buckets;
    }
  }
  return loop->hist_max_ms;
}

static void publish_stats(ezcore_loop *loop) {
  unsigned seq = atomic_load_explicit(&loop->stats_seq, memory_order_relaxed);
  unsigned buffer = (seq / 2u) & 1u; /* the slot not read for this sequence */
  atomic_store_explicit(&loop->stats_seq, seq + 1, memory_order_release);

  unsigned pending = 0;
  for (unsigned i = 0; i < EZCORE_CTRL_CAP; i++) {
    if (atomic_load_explicit(&loop->controls[i].state, memory_order_relaxed) == 1)
      pending++;
  }
  ezcore_audio_statistics ast;
  uint64_t underruns = 0;
  ezcore_audio *audio = ezcore_audio_active();
  if (audio && ezcore_audio_stats(audio, &ast)) underruns = ast.underruns;

  ezcore_loop_statistics st;
  st.frames_run = atomic_load_explicit(&loop->frames_run, memory_order_relaxed);
  st.dropped_frames = atomic_load_explicit(&loop->dropped_frames, memory_order_relaxed);
  st.control_applied = atomic_load_explicit(&loop->controls_applied, memory_order_relaxed);
  st.control_pending = pending;
  st.audio_underruns = underruns;
  st.frame_last_ms = loop->frame_last_ms;
  st.frame_mean_ms = loop->frame_samples ? loop->sum_frame_ms / (double)loop->frame_samples : 0.0;
  st.frame_p50_ms = percentile_ms(loop, 0.50);
  st.frame_p95_ms = percentile_ms(loop, 0.95);
  st.frame_p99_ms = percentile_ms(loop, 0.99);
  st.frame_max_ms = loop->frame_max_ms;
  st.histogram_len = loop->buckets;
  st.histogram = loop->histogram;
  loop->stats[buffer] = st;

  atomic_store_explicit(&loop->stats_seq, seq + 2, memory_order_release);
}

static void run_loop(void *arg) {
  ezcore_loop *loop = (ezcore_loop *)arg;
  ezcore_audio *paced_audio = NULL;
  uint64_t audio_cursor = 0;
  uint64_t mono_deadline = 0;
  const double period = 1.0 / loop->fps;

  while (!atomic_load_explicit(&loop->stop, memory_order_acquire)) {
    /* Controls run even while paused: save/load/reset must work with the game
     * held still, and are only ever applied between frames. */
    process_controls(loop);
    publish_stats(loop);

    if (atomic_load_explicit(&loop->paused, memory_order_acquire)) {
      ez_nap_ms(1);
      continue;
    }

    ezcore_audio *active = ezcore_audio_active();
    if (active != paced_audio) {
      paced_audio = active;
      audio_cursor = 0;
      mono_deadline = 0;
    }

    if (paced_audio) {
      ezcore_audio_statistics ast;
      if (ezcore_audio_stats(paced_audio, &ast) && ast.output_sample_rate > 0) {
        if (!audio_cursor) audio_cursor = ast.frames_played;
        audio_cursor += (uint64_t)((double)ast.output_sample_rate * period + 0.5);
        while (!atomic_load_explicit(&loop->stop, memory_order_acquire) &&
               !atomic_load_explicit(&loop->paused, memory_order_acquire)) {
          if (!ezcore_audio_stats(paced_audio, &ast) ||
              ast.frames_played >= audio_cursor)
            break;
          ez_nap_ms(1);
        }
      }
    } else {
      uint64_t now = (uint64_t)(ez_now_seconds() * 1e9);
      if (!mono_deadline) mono_deadline = now;
      mono_deadline += (uint64_t)(period * 1e9);
      if (mono_deadline < now) mono_deadline = now; /* recover from a long stall */
      while (!atomic_load_explicit(&loop->stop, memory_order_acquire) &&
             !atomic_load_explicit(&loop->paused, memory_order_acquire) &&
             (uint64_t)(ez_now_seconds() * 1e9) < mono_deadline) {
        ez_nap_ms(1);
      }
    }

    if (atomic_load_explicit(&loop->stop, memory_order_acquire)) break;
    if (atomic_load_explicit(&loop->paused, memory_order_acquire)) continue;

    uint32_t count = atomic_load_explicit(&loop->fast_forward, memory_order_relaxed);
    if (count < 1) count = 1;
    double started = ez_now_seconds();
    for (uint32_t i = 0; i < count; i++) {
      apply_inputs(loop);
      lock_spin(&g_run_lock);
      ezcore_run_frame(loop->session);
      unlock_spin(&g_run_lock);
      atomic_fetch_add_explicit(&loop->frames_run, 1, memory_order_relaxed);
      publish_frame(loop, loop->session);
      if (atomic_load_explicit(&loop->stop, memory_order_acquire)) break;
    }
    double elapsed_ms = (ez_now_seconds() - started) * 1000.0;
    if (elapsed_ms < 0.0) elapsed_ms = 0.0;
    record_frame_time(loop, elapsed_ms / (double)count);
  }
  publish_stats(loop);
}

/* ---- Public API ---- */

ezcore_loop *ezcore_loop_start(ezcore_session *s, const ezcore_loop_config *config,
                               char *err, size_t err_len) {
  if (err && err_len) err[0] = '\0';
  if (!s) {
    if (err && err_len) snprintf(err, err_len, "no session to run");
    return NULL;
  }
  if (!registry_add(s)) {
    if (err && err_len)
      snprintf(err, err_len, "session already has a run loop");
    return NULL;
  }

  ezcore_loop *loop = (ezcore_loop *)calloc(1, sizeof(*loop));
  if (!loop) {
    registry_remove(s);
    if (err && err_len) snprintf(err, err_len, "run loop allocation failed");
    return NULL;
  }
  loop->session = s;
  atomic_init(&loop->pinned, -1);
  atomic_flag_clear(&loop->ctrl_lock);

  unsigned fps = config && config->target_fps ? config->target_fps : 0;
  if (!fps) {
    unsigned w = 0, h = 0;
    double core_fps = 0.0;
    ezcore_system_geometry(s, &w, &h, &core_fps);
    fps = core_fps > 0.0 ? (unsigned)(core_fps + 0.5) : 60u;
  }
  if (fps < 1) fps = 60u;
  loop->fps = (double)fps;

  loop->buckets = config && config->histogram_buckets ? config->histogram_buckets
                                                       : EZCORE_HIST_DEFAULT;
  if (loop->buckets < EZCORE_HIST_MIN) loop->buckets = EZCORE_HIST_MIN;
  if (loop->buckets > EZCORE_HIST_MAX) loop->buckets = EZCORE_HIST_MAX;
  loop->hist_max_ms = config && config->histogram_max_ms > 0.0
                          ? config->histogram_max_ms
                          : EZCORE_HIST_MAX_MS;
  loop->histogram = (uint32_t *)calloc(loop->buckets, sizeof(uint32_t));
  if (!loop->histogram) {
    free(loop);
    registry_remove(s);
    if (err && err_len) snprintf(err, err_len, "histogram allocation failed");
    return NULL;
  }

  if (!ez_thread_start(&loop->thread, run_loop, loop)) {
    free(loop->histogram);
    free(loop);
    registry_remove(s);
    if (err && err_len) snprintf(err, err_len, "run thread creation failed");
    return NULL;
  }
  loop->thread_live = true;
  publish_stats(loop);
  return loop;
}

void ezcore_loop_stop(ezcore_loop *loop) {
  if (!loop) return;
  atomic_store_explicit(&loop->stop, 1, memory_order_release);
  if (loop->thread_live) {
    ez_thread_join(loop->thread);
    loop->thread_live = false;
  }
  registry_remove(loop->session);
  for (unsigned i = 0; i < 3; i++) free(loop->slots[i].pixels);
  for (unsigned i = 0; i < EZCORE_CTRL_CAP; i++) {
    ctrl_slot *slot = &loop->controls[i];
    if (atomic_load_explicit(&slot->state, memory_order_relaxed) == 1) {
      if (slot->owns_ptr) free(slot->ptr);
      free(slot->text);
      free(slot->text2);
      atomic_store_explicit(&slot->state, 3, memory_order_release);
    }
  }
  free(loop->histogram);
  free(loop);
}

const uint32_t *ezcore_loop_frame(ezcore_loop *loop, unsigned *w, unsigned *h) {
  if (w) *w = 0;
  if (h) *h = 0;
  if (!loop) return NULL;
  if (atomic_load_explicit(&loop->pinned, memory_order_acquire) >= 0) return NULL;
  for (;;) {
    frame_slot *best = NULL;
    uint64_t newest = 0;
    for (unsigned i = 0; i < 3; i++) {
      frame_slot *slot = &loop->slots[i];
      if (atomic_load_explicit(&slot->state, memory_order_acquire) != 1) continue;
      uint64_t generation = atomic_load_explicit(&slot->generation, memory_order_acquire);
      if (!best || generation > newest) {
        best = slot;
        newest = generation;
      }
    }
    if (!best || !best->pixels) return NULL;
    int expected = 1;
    if (!atomic_compare_exchange_strong_explicit(&best->state, &expected, 2,
                                                  memory_order_acquire,
                                                  memory_order_relaxed)) {
      continue; /* the producer reclaimed it between the scan and the pin */
    }
    for (unsigned i = 0; i < 3; i++) {
      if (&loop->slots[i] == best) atomic_store(&loop->pinned, (int)i);
    }
    if (w) *w = best->w;
    if (h) *h = best->h;
    return best->pixels;
  }
}

void ezcore_loop_frame_release(ezcore_loop *loop) {
  if (!loop) return;
  int index = atomic_exchange_explicit(&loop->pinned, -1, memory_order_acq_rel);
  if (index >= 0 && index < 3)
    atomic_store_explicit(&loop->slots[index].state, 0, memory_order_release);
}

void ezcore_loop_set_button(ezcore_loop *loop, unsigned port, unsigned button,
                            bool pressed) {
  if (!loop || port >= 4 || button >= 16) return;
  uint32_t mask = atomic_load_explicit(&loop->buttons[port], memory_order_relaxed);
  if (pressed) mask |= (1u << button);
  else mask &= ~(1u << button);
  atomic_store_explicit(&loop->buttons[port], mask, memory_order_relaxed);
}

void ezcore_loop_clear_buttons(ezcore_loop *loop, unsigned port) {
  if (!loop || port >= 4) return;
  atomic_store_explicit(&loop->buttons[port], 0, memory_order_relaxed);
}

void ezcore_loop_set_analog(ezcore_loop *loop, unsigned port, unsigned stick,
                            unsigned axis, int16_t value) {
  if (!loop || port >= 4 || stick > 1 || axis > 1) return;
  atomic_store_explicit(&loop->analog[port][stick][axis], value, memory_order_relaxed);
}

uint64_t ezcore_loop_control_pause(ezcore_loop *loop, bool paused) {
  bool value = paused;
  return queue_control(loop, CTRL_PAUSE, fill_pause, &value);
}

uint64_t ezcore_loop_control_fast_forward(ezcore_loop *loop, uint32_t factor) {
  return queue_control(loop, CTRL_FAST_FORWARD, fill_ff, &factor);
}

uint64_t ezcore_loop_control_save(ezcore_loop *loop, void *out, size_t size) {
  if (!out) return 0;
  ctrl_slot ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.ptr = out;
  ctx.size = size;
  return queue_control(loop, CTRL_SAVE, fill_save, &ctx);
}

uint64_t ezcore_loop_control_load(ezcore_loop *loop, const void *data, size_t size) {
  if (!data || !size) return 0;
  ctrl_slot ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.ptr = (void *)data;
  ctx.size = size;
  return queue_control(loop, CTRL_LOAD, fill_load, &ctx);
}

uint64_t ezcore_loop_control_reset(ezcore_loop *loop) {
  return queue_control(loop, CTRL_RESET, fill_reset, NULL);
}

uint64_t ezcore_loop_control_cheat_reset(ezcore_loop *loop) {
  return queue_control(loop, CTRL_CHEAT_RESET, fill_reset, NULL);
}

uint64_t ezcore_loop_control_cheat_set(ezcore_loop *loop, unsigned index,
                                        bool enabled, const char *code) {
  if (!code) return 0;
  ctrl_slot ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.number = index;
  ctx.boolean = enabled;
  ctx.text = (char *)code;
  return queue_control(loop, CTRL_CHEAT_SET, fill_cheat_set, &ctx);
}

uint64_t ezcore_loop_control_option(ezcore_loop *loop, const char *key,
                                     const char *value) {
  if (!key || !value) return 0;
  ctrl_slot ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.text = (char *)key;
  ctx.text2 = (char *)value;
  return queue_control(loop, CTRL_OPTION, fill_option, &ctx);
}

bool ezcore_loop_control_wait(ezcore_loop *loop, uint64_t token,
                              uint32_t timeout_ms, bool *result) {
  if (!loop || !token) return false;
  const double deadline = ez_now_seconds() + (double)timeout_ms / 1000.0;
  for (;;) {
    lock_spin(&loop->ctrl_lock);
    bool found = false, done = false, ok = false;
    for (unsigned i = 0; i < EZCORE_CTRL_CAP; i++) {
      ctrl_slot *slot = &loop->controls[i];
      if (slot->token != token) continue;
      found = true;
      done = atomic_load_explicit(&slot->state, memory_order_acquire) == 3;
      ok = slot->result;
      break;
    }
    unlock_spin(&loop->ctrl_lock);
    if (!found) return false;
    if (done) {
      if (result) *result = ok;
      return true;
    }
    if (ez_now_seconds() >= deadline) return false;
    ez_nap_ms(1);
  }
}

bool ezcore_loop_stats(ezcore_loop *loop, ezcore_loop_statistics *out) {
  if (!loop || !out) return false;
  /* The run thread publishes statistics between every frame and every control.
   * A reader that races those updates must yield, not give up after a handful
   * of back-to-back loads: under load the writer can change the sequence on
   * every attempt. Bound the wait so a wedged loop cannot block a caller. */
  const double deadline = ez_now_seconds() + 0.100;
  for (;;) {
    unsigned before = atomic_load_explicit(&loop->stats_seq, memory_order_acquire);
    if (!(before & 1u)) {
      /* The writer publishes into buffer (seq/2)&1 and then advances seq to
       * seq+2, so an even sequence N describes the buffer written for N-2. */
      unsigned buffer = before == 0 ? 0u : ((before / 2u) - 1u) & 1u;
      ezcore_loop_statistics snapshot = loop->stats[buffer];
      unsigned after = atomic_load_explicit(&loop->stats_seq, memory_order_acquire);
      if (before == after) {
        *out = snapshot;
        return true;
      }
    }
    if (ez_now_seconds() >= deadline) return false;
    ez_nap_ms(1);
  }
}
