// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* Linux desktop video bridge. The runtime produces RGBA snapshots; Flutter
 * reads them through FlPixelBufferTexture. Both sides use the same three-slot
 * bridge as the Windows runner, so the two desktop targets behave alike. */
#include "video_channel.h"

#include <dlfcn.h>

#include <cstdint>
#include <cstring>
#include <memory>

#include "ezcore_runtime.h"
#include "ezcore_video_texture.h"

namespace {

constexpr char kChannel[] = "ezcore/video";

struct VideoApi {
  void* handle = nullptr;
  ezcore_video_texture* (*create)(void) = nullptr;
  void (*destroy)(ezcore_video_texture*) = nullptr;
  bool (*publish_session)(ezcore_video_texture*, ezcore_session*) = nullptr;
  const uint8_t* (*pixels)(ezcore_video_texture*, uint32_t*, uint32_t*) =
      nullptr;
  void (*stats)(ezcore_video_texture*, ezcore_video_texture_stats*) = nullptr;
};

VideoApi g_api;

bool LoadApi() {
  if (g_api.create) return true;
  g_api.handle = dlopen("libezcore_runtime.so", RTLD_NOW | RTLD_LOCAL);
  if (!g_api.handle) {
    g_warning("ezCORE video bridge: %s", dlerror());
    return false;
  }
  g_api.create = reinterpret_cast<decltype(g_api.create)>(
      dlsym(g_api.handle, "ezcore_video_texture_create"));
  g_api.destroy = reinterpret_cast<decltype(g_api.destroy)>(
      dlsym(g_api.handle, "ezcore_video_texture_destroy"));
  g_api.publish_session = reinterpret_cast<decltype(g_api.publish_session)>(
      dlsym(g_api.handle, "ezcore_video_texture_publish_session"));
  g_api.pixels = reinterpret_cast<decltype(g_api.pixels)>(
      dlsym(g_api.handle, "ezcore_video_texture_pixels"));
  g_api.stats = reinterpret_cast<decltype(g_api.stats)>(
      dlsym(g_api.handle, "ezcore_video_texture_stats_get"));
  if (!g_api.create || !g_api.destroy || !g_api.publish_session ||
      !g_api.pixels || !g_api.stats) {
    g_warning("ezCORE video bridge: runtime symbols are missing");
    g_api.create = nullptr;
    return false;
  }
  return true;
}

struct _EzcoreDesktopTexture {
  FlPixelBufferTexture parent_instance;
  ezcore_video_texture* bridge;
};

G_DECLARE_FINAL_TYPE(EzcoreDesktopTexture, ezcore_desktop_texture, EZCORE,
                     DESKTOP_TEXTURE, FlPixelBufferTexture)
G_DEFINE_TYPE(EzcoreDesktopTexture, ezcore_desktop_texture,
              fl_pixel_buffer_texture_get_type())

gboolean ezcore_desktop_texture_copy_pixels(FlPixelBufferTexture* texture, const uint8_t** buffer,
                    uint32_t* width, uint32_t* height, GError** error) {
  auto* self = EZCORE_DESKTOP_TEXTURE(texture);
  const uint8_t* pixels = g_api.pixels(self->bridge, width, height);
  if (!pixels) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                        "No video frame is available");
    return FALSE;
  }
  *buffer = pixels;
  return TRUE;
}

void ezcore_desktop_texture_class_init(EzcoreDesktopTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      ezcore_desktop_texture_copy_pixels;
}

void ezcore_desktop_texture_init(EzcoreDesktopTexture* self) {
  self->bridge = g_api.create();
}

class VideoChannel {
 public:
  static std::unique_ptr<VideoChannel> Create(FlView* view) {
    if (!LoadApi()) return nullptr;
    auto channel = std::unique_ptr<VideoChannel>(new VideoChannel(view));
    if (!channel->texture_) return nullptr;
    return channel;
  }

  ~VideoChannel() {
    if (channel_) fl_method_channel_set_method_call_handler(channel_, nullptr,
                                                            nullptr, nullptr);
    if (texture_ && registrar_) {
      fl_texture_registrar_unregister_texture(registrar_, FL_TEXTURE(texture_));
    }
    if (texture_) g_object_unref(texture_);
    if (bridge_) g_api.destroy(bridge_);
  }

  void Handle(FlMethodCall* call) {
    const gchar* name = fl_method_call_get_name(call);
    g_autoptr(FlValue) args = fl_value_ref(fl_method_call_get_args(call));
    g_autoptr(FlValue) value = nullptr;

    if (g_strcmp0(name, "attach") == 0) {
      session_ = reinterpret_cast<ezcore_session*>(
          static_cast<intptr_t>(fl_value_get_int(args)));
      value = fl_value_new_bool(session_ != nullptr);
    } else if (g_strcmp0(name, "create") == 0) {
      value = fl_value_new_int(fl_texture_get_id(FL_TEXTURE(texture_)));
      g_info("ezCORE video texture registered (id %" G_GINT64_FORMAT ")",
             fl_value_get_int(value));
    } else if (g_strcmp0(name, "frameReady") == 0) {
      bool ok = session_ && g_api.publish_session(bridge_, session_);
      if (ok) {
        fl_texture_registrar_mark_texture_frame_available(
            registrar_, FL_TEXTURE(texture_));
        LogStats();
      }
      value = fl_value_new_bool(ok);
    } else if (g_strcmp0(name, "stats") == 0) {
      ezcore_video_texture_stats stats;
      g_api.stats(bridge_, &stats);
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string(map, "framesPublished",
                          fl_value_new_int(static_cast<int64_t>(stats.frames_published)));
      fl_value_set_string(map, "framesDropped",
                          fl_value_new_int(static_cast<int64_t>(stats.frames_dropped)));
      fl_value_set_string(map, "width", fl_value_new_int(stats.width));
      fl_value_set_string(map, "height", fl_value_new_int(stats.height));
      value = fl_value_ref(map);
    } else {
      fl_method_call_respond_not_implemented(call, nullptr);
      return;
    }
    fl_method_call_respond_success(call, value, nullptr);
  }

 private:
  explicit VideoChannel(FlView* view) {
    FlEngine* engine = fl_view_get_engine(view);
    registrar_ = fl_engine_get_texture_registrar(engine);
    texture_ = EZCORE_DESKTOP_TEXTURE(
        g_object_new(ezcore_desktop_texture_get_type(), nullptr));
    bridge_ = EZCORE_DESKTOP_TEXTURE(texture_)->bridge;
    if (!bridge_ ||
        !fl_texture_registrar_register_texture(registrar_, FL_TEXTURE(texture_))) {
      g_warning("ezCORE video texture could not be registered");
      g_object_unref(texture_);
      texture_ = nullptr;
      bridge_ = nullptr;
      return;
    }
    auto* codec = fl_standard_method_codec_new();
    channel_ = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                     kChannel, FL_METHOD_CODEC(codec));
    g_object_unref(codec);
    fl_method_channel_set_method_call_handler(
        channel_,
        [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
          static_cast<VideoChannel*>(data)->Handle(call);
        },
        this, nullptr);
  }

  void LogStats() {
    if (++notifications_ % 60 != 0) return;
    ezcore_video_texture_stats stats;
    g_api.stats(bridge_, &stats);
    g_info("ezCORE video: %" G_GUINT64_FORMAT " frames, %" G_GUINT64_FORMAT
           " dropped, %ux%u",
           stats.frames_published, stats.frames_dropped, stats.width,
           stats.height);
  }

  FlTextureRegistrar* registrar_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  EzcoreDesktopTexture* texture_ = nullptr;
  ezcore_video_texture* bridge_ = nullptr;
  ezcore_session* session_ = nullptr;
  uint64_t notifications_ = 0;
};

std::unique_ptr<VideoChannel> g_channel;

}  // namespace

void ezcore_video_channel_setup(FlView* view) {
  g_channel = VideoChannel::Create(view);
}
