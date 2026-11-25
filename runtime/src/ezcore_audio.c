// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* ezcore_audio.c — one native audio implementation for all five targets.
 *
 * miniaudio supplies the device clock and the platform backend; everything
 * between the core and the device is ours: a single-producer/single-consumer
 * ring of stereo s16 frames, a resampler owned by the device thread, and
 * dynamic rate control that keeps the ring near half full. The producer is the
 * libretro audio callback, the consumer is the miniaudio data callback, so no
 * mutex sits on the audio path. Only this translation unit includes
 * miniaudio's implementation.
 */
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#include "miniaudio.h"

#include "ezcore_audio_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ezcore_audio {
  ma_device device;
  ma_resampler resampler;
  int16_t *ring;
  int16_t *scratch;
  ma_uint64 ring_cap;     /* power-of-two frames */
  ma_uint64 scratch_frames;
  volatile ma_uint64 write_pos; /* producer: core thread */
  volatile ma_uint64 read_pos;  /* consumer: device thread */
  double base_ratio;            /* input rate / output rate */
  volatile ma_uint32 volume_milli;
  volatile ma_uint32 muted;
  volatile ma_uint32 running;
  volatile ma_uint32 ratio_micro;
  volatile ma_uint64 frames_written;
  volatile ma_uint64 frames_played;
  volatile ma_uint64 underruns;
  volatile ma_uint64 overruns;
  ma_bool32 resampler_ready;
  ma_bool32 device_ready;
};

/* One device per process: a session owns the libretro callbacks, so only the
 * audio device attached to that session may receive frames. */
static ezcore_audio *g_active;

ezcore_audio *ezcore_audio_active(void) { return g_active; }

static ma_uint64 load64(volatile ma_uint64 *v) {
  return ma_atomic_load_explicit_64(v, ma_atomic_memory_order_relaxed);
}

static void store64(volatile ma_uint64 *v, ma_uint64 value) {
  ma_atomic_exchange_explicit_64(v, value, ma_atomic_memory_order_relaxed);
}

static ma_uint32 load32(volatile ma_uint32 *v) {
  return ma_atomic_load_explicit_32(v, ma_atomic_memory_order_relaxed);
}

static ma_uint64 ring_used(const ezcore_audio *a) {
  ma_uint64 w = ma_atomic_load_explicit_64(&a->write_pos, ma_atomic_memory_order_acquire);
  ma_uint64 r = ma_atomic_load_explicit_64(&a->read_pos, ma_atomic_memory_order_acquire);
  return w - r;
}

static void ring_push(ezcore_audio *a, const int16_t *data, ma_uint64 frames) {
  ma_uint64 w = load64(&a->write_pos);
  size_t offset = (size_t)(w & (a->ring_cap - 1));
  size_t first = (size_t)(frames < a->ring_cap - offset ? frames : a->ring_cap - offset);

  memcpy(a->ring + offset * 2, data, first * 2 * sizeof(int16_t));
  if (first < frames)
    memcpy(a->ring, data + first * 2, (size_t)(frames - first) * 2 * sizeof(int16_t));

  ma_atomic_exchange_explicit_64(&a->write_pos, w + frames, ma_atomic_memory_order_release);
  store64(&a->frames_written, load64(&a->frames_written) + frames);
}

/* Copy without advancing the read index: the resampler decides how much of
 * the input it actually consumed. */
static void ring_peek(const ezcore_audio *a, int16_t *dst, ma_uint64 frames) {
  ma_uint64 r = ma_atomic_load_explicit_64(&a->read_pos, ma_atomic_memory_order_relaxed);
  size_t offset = (size_t)(r & (a->ring_cap - 1));
  size_t first = (size_t)(frames < a->ring_cap - offset ? frames : a->ring_cap - offset);

  memcpy(dst, a->ring + offset * 2, first * 2 * sizeof(int16_t));
  if (first < frames)
    memcpy(dst + first * 2, a->ring, (size_t)(frames - first) * 2 * sizeof(int16_t));
}

size_t ezcore_audio_feed(const int16_t *data, size_t frames) {
  ezcore_audio *a = g_active;
  if (!a || !data || frames == 0) return 0;

  ma_uint64 r = ma_atomic_load_explicit_64(&a->read_pos, ma_atomic_memory_order_acquire);
  ma_uint64 w = ma_atomic_load_explicit_64(&a->write_pos, ma_atomic_memory_order_relaxed);
  ma_uint64 free_frames = a->ring_cap - (w - r);
  size_t accepted = frames < free_frames ? frames : (size_t)free_frames;

  if (accepted < frames)
    store64(&a->overruns, load64(&a->overruns) + (ma_uint64)(frames - accepted));
  if (accepted > 0)
    ring_push(a, data, accepted);
  return accepted;
}

static void data_callback(ma_device *device, void *output, const void *input,
                          ma_uint32 frame_count) {
  (void)input;
  ezcore_audio *a = (ezcore_audio *)device->pUserData;
  if (!a || frame_count == 0) return;

  float *out = (float *)output;
  const ma_uint32 channels = 2;

  /* Dynamic rate control: a filling ring is drained faster, an emptying ring
   * more slowly. The correction is clamped to the standard +/-0.5% window so
   * pitch stays imperceptible. */
  double fill = (double)ring_used(a) / (double)a->ring_cap;
  double correction = 1.0 + (fill - 0.5) * 0.01;
  if (correction < 0.995) correction = 0.995;
  if (correction > 1.005) correction = 1.005;
  float ratio = (float)(a->base_ratio * correction);
  ma_resampler_set_rate_ratio(&a->resampler, ratio);
  ma_atomic_exchange_explicit_32(&a->ratio_micro, (ma_uint32)(ratio * 1000000.0f),
                                 ma_atomic_memory_order_relaxed);

  ma_uint64 done = 0;
  while (done < frame_count) {
    ma_uint64 want_out = frame_count - done;
    ma_uint64 want_in = 0;
    ma_resampler_get_required_input_frame_count(&a->resampler, want_out, &want_in);
    if (want_in == 0) want_in = 1;
    if (want_in > a->scratch_frames) want_in = a->scratch_frames;

    ma_uint64 available = ring_used(a);
    ma_uint64 real = want_in < available ? want_in : available;
    if (real > 0) ring_peek(a, a->scratch, real);
    if (real < want_in)
      memset(a->scratch + real * 2, 0, (size_t)(want_in - real) * 2 * sizeof(int16_t));
    if (real == 0)
      store64(&a->underruns, load64(&a->underruns) + 1);

    ma_uint64 in_done = want_in;
    ma_uint64 out_made = want_out;
    ma_result result = ma_resampler_process_pcm_frames(
        &a->resampler, a->scratch, &in_done, out + done * channels, &out_made);
    if (result != MA_SUCCESS) {
      out_made = 0;
      in_done = 0;
    }

    ma_uint64 consumed = in_done < real ? in_done : real;
    if (consumed > 0) {
      ma_uint64 r = ma_atomic_load_explicit_64(&a->read_pos, ma_atomic_memory_order_relaxed);
      ma_atomic_exchange_explicit_64(&a->read_pos, r + consumed, ma_atomic_memory_order_release);
    }

    if (out_made < want_out) {
      memset(out + (done + out_made) * channels, 0,
             (size_t)(want_out - out_made) * channels * sizeof(float));
    }
    if (out_made == 0) break; /* never spin on a resampler that made no progress */
    done += out_made;
  }

  float volume = (float)load32(&a->volume_milli) / 1000.0f;
  if (load32(&a->muted)) volume = 0.0f;
  if (volume != 1.0f) {
    for (ma_uint32 i = 0; i < frame_count * channels; ++i) out[i] *= volume;
  }
  store64(&a->frames_played, load64(&a->frames_played) + frame_count);
}

ezcore_audio *ezcore_audio_open(const ezcore_audio_config *config, char *err,
                                size_t err_len) {
  if (err && err_len) err[0] = '\0';
  if (!config || config->input_sample_rate == 0 || config->output_sample_rate == 0 ||
      config->channels != 2) {
    if (err && err_len)
      snprintf(err, err_len, "audio config needs two channels and non-zero rates");
    return NULL;
  }

  ezcore_audio *a = (ezcore_audio *)calloc(1, sizeof(*a));
  if (!a) {
    if (err && err_len) snprintf(err, err_len, "audio allocation failed");
    return NULL;
  }

  ma_uint64 cap = config->ring_frames ? config->ring_frames : 8192;
  if (cap < 256) cap = 256;
  ma_uint64 rounded = 1;
  while (rounded < cap) rounded <<= 1;
  a->ring_cap = rounded;
  a->scratch_frames = rounded > 8192 ? rounded : 8192;
  a->ring = (int16_t *)malloc(a->ring_cap * 2 * sizeof(int16_t));
  a->scratch = (int16_t *)malloc(a->scratch_frames * 2 * sizeof(int16_t));
  if (a->ring) memset(a->ring, 0, a->ring_cap * 2 * sizeof(int16_t));
  if (!a->ring || !a->scratch) {
    if (err && err_len) snprintf(err, err_len, "audio ring allocation failed");
    ezcore_audio_close(a);
    return NULL;
  }

  a->base_ratio = (double)config->input_sample_rate / (double)config->output_sample_rate;
  float volume = config->volume < 0.0f ? 0.0f : config->volume;
  if (volume > 1.0f) volume = 1.0f;
  ma_atomic_exchange_explicit_32(&a->volume_milli, (ma_uint32)(volume * 1000.0f),
                                 ma_atomic_memory_order_relaxed);
  ma_atomic_exchange_explicit_32(&a->muted, config->muted ? 1 : 0,
                                 ma_atomic_memory_order_relaxed);
  ma_atomic_exchange_explicit_32(&a->ratio_micro, (ma_uint32)(a->base_ratio * 1000000.0),
                                 ma_atomic_memory_order_relaxed);

  /* Start with a half-full ring of silence. The device clock then has a
   * buffer before the first core frame arrives, so opening the device is not
   * itself an underrun. These frames are not counted as core audio. */
  ma_atomic_exchange_explicit_64(&a->write_pos, a->ring_cap / 2,
                                 ma_atomic_memory_order_release);

  ma_resampler_config resampler_config = ma_resampler_config_init(
      ma_format_s16, config->channels, config->input_sample_rate,
      config->output_sample_rate, ma_resample_algorithm_linear);
  if (ma_resampler_init(&resampler_config, NULL, &a->resampler) != MA_SUCCESS) {
    if (err && err_len) snprintf(err, err_len, "resampler initialisation failed");
    ezcore_audio_close(a);
    return NULL;
  }
  a->resampler_ready = MA_TRUE;

  ma_device_config device_config = ma_device_config_init(ma_device_type_playback);
  device_config.playback.format = ma_format_f32;
  device_config.playback.channels = config->channels;
  device_config.sampleRate = config->output_sample_rate;
  device_config.periodSizeInMilliseconds = 10;
  device_config.dataCallback = data_callback;
  device_config.pUserData = a;

  ma_result result;
  if (config->backend == EZCORE_AUDIO_BACKEND_NULL) {
    ma_backend backends[] = {ma_backend_null};
    result = ma_device_init_ex(backends, 1, NULL, &device_config, &a->device);
  } else {
    result = ma_device_init(NULL, &device_config, &a->device);
  }
  if (result != MA_SUCCESS) {
    if (err && err_len)
      snprintf(err, err_len, "audio device initialisation failed (%d)", (int)result);
    ezcore_audio_close(a);
    return NULL;
  }
  a->device_ready = MA_TRUE;

  result = ma_device_start(&a->device);
  if (result != MA_SUCCESS) {
    if (err && err_len) snprintf(err, err_len, "audio device start failed (%d)", (int)result);
    ezcore_audio_close(a);
    return NULL;
  }
  ma_atomic_exchange_explicit_32(&a->running, 1, ma_atomic_memory_order_release);
  g_active = a;
  return a;
}

void ezcore_audio_close(ezcore_audio *audio) {
  if (!audio) return;
  if (g_active == audio) g_active = NULL;
  if (audio->device_ready) {
    if (load32(&audio->running)) {
      ma_atomic_exchange_explicit_32(&audio->running, 0, ma_atomic_memory_order_release);
      ma_device_stop(&audio->device);
    }
    ma_device_uninit(&audio->device);
  }
  if (audio->resampler_ready) ma_resampler_uninit(&audio->resampler, NULL);
  free(audio->ring);
  free(audio->scratch);
  free(audio);
}

void ezcore_audio_set_volume(ezcore_audio *audio, float volume) {
  if (!audio) return;
  if (volume < 0.0f) volume = 0.0f;
  if (volume > 1.0f) volume = 1.0f;
  ma_atomic_exchange_explicit_32(&audio->volume_milli, (ma_uint32)(volume * 1000.0f),
                                 ma_atomic_memory_order_release);
}

void ezcore_audio_set_muted(ezcore_audio *audio, bool muted) {
  if (!audio) return;
  ma_atomic_exchange_explicit_32(&audio->muted, muted ? 1 : 0,
                                 ma_atomic_memory_order_release);
}

bool ezcore_audio_stats(ezcore_audio *audio, ezcore_audio_statistics *out) {
  if (!audio || !out) return false;
  out->frames_written = load64(&audio->frames_written);
  out->frames_played = load64(&audio->frames_played);
  out->underruns = load64(&audio->underruns);
  out->overruns = load64(&audio->overruns);
  ma_uint64 buffered = ring_used(audio);
  out->buffered_frames = (size_t)buffered;
  out->fill_fraction = (double)buffered / (double)audio->ring_cap;
  out->rate_ratio = (double)load32(&audio->ratio_micro) / 1000000.0;
  out->volume = (float)load32(&audio->volume_milli) / 1000.0f;
  out->muted = load32(&audio->muted) != 0;
  out->device_running = load32(&audio->running) != 0;
  out->output_sample_rate = audio->device.sampleRate;
  return true;
}
