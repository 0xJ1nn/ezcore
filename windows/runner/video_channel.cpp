// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* Windows desktop video bridge. Frames are read from the same three-slot
 * snapshot bridge as Linux; this file only registers the pixel-buffer texture
 * with Flutter and services the channel the player uses to publish frames. */
#include "video_channel.h"

#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include "ezcore_runtime.h"
#include "ezcore_video_texture.h"

namespace {

constexpr char kChannel[] = "ezcore/video";

struct VideoApi {
  HMODULE module = nullptr;
  ezcore_video_texture* (*create)(void) = nullptr;
  void (*destroy)(ezcore_video_texture*) = nullptr;
  bool (*publish_session)(ezcore_video_texture*, ezcore_session*) = nullptr;
  const uint8_t* (*pixels)(ezcore_video_texture*, uint32_t*, uint32_t*) =
      nullptr;
  void (*stats)(ezcore_video_texture*, ezcore_video_texture_stats*) = nullptr;
};

VideoApi g_api;
ezcore_video_texture* g_bridge = nullptr;
FlutterDesktopPixelBuffer g_pixel_buffer{};

bool LoadApi() {
  if (g_api.create) return true;
  g_api.module = LoadLibraryA("ezcore_runtime.dll");
  if (!g_api.module) return false;
  g_api.create = reinterpret_cast<decltype(g_api.create)>(
      GetProcAddress(g_api.module, "ezcore_video_texture_create"));
  g_api.destroy = reinterpret_cast<decltype(g_api.destroy)>(
      GetProcAddress(g_api.module, "ezcore_video_texture_destroy"));
  g_api.publish_session = reinterpret_cast<decltype(g_api.publish_session)>(
      GetProcAddress(g_api.module, "ezcore_video_texture_publish_session"));
  g_api.pixels = reinterpret_cast<decltype(g_api.pixels)>(
      GetProcAddress(g_api.module, "ezcore_video_texture_pixels"));
  g_api.stats = reinterpret_cast<decltype(g_api.stats)>(
      GetProcAddress(g_api.module, "ezcore_video_texture_stats_get"));
  if (!g_api.create || !g_api.destroy || !g_api.publish_session ||
      !g_api.pixels || !g_api.stats) {
    g_api.create = nullptr;
    return false;
  }
  return true;
}

}  // namespace

class VideoChannel::Impl {
 public:
  explicit Impl(flutter::PluginRegistrar* registrar)
      : registrar_(registrar->texture_registrar()) {
    flutter::PixelBufferTexture texture(
        [](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
          uint32_t width = 0, height = 0;
          const uint8_t* pixels = g_api.pixels(g_bridge, &width, &height);
          if (!pixels) return nullptr;
          g_pixel_buffer.buffer = pixels;
          g_pixel_buffer.width = width;
          g_pixel_buffer.height = height;
          g_pixel_buffer.release_callback = nullptr;
          g_pixel_buffer.release_context = nullptr;
          return &g_pixel_buffer;
        });
    texture_ = std::make_unique<flutter::TextureVariant>(std::move(texture));
    texture_id_ = registrar_->RegisterTexture(texture_.get());
    if (texture_id_ < 0) return;

    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), kChannel,
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
          Handle(call, std::move(result));
        });
  }

  ~Impl() {
    if (channel_) channel_->SetMethodCallHandler(nullptr);
    if (texture_id_ >= 0) registrar_->UnregisterTexture(texture_id_, nullptr);
  }

  bool valid() const { return texture_id_ >= 0 && channel_ != nullptr; }

  void SetSession(int64_t address) {
    session_ = reinterpret_cast<ezcore_session*>(static_cast<intptr_t>(address));
  }

  bool Publish() {
    if (!session_) return false;
    bool ok = g_api.publish_session(g_bridge, session_);
    if (ok) {
      registrar_->MarkTextureFrameAvailable(texture_id_);
      LogStats();
    }
    return ok;
  }

  flutter::EncodableValue Stats() const {
    ezcore_video_texture_stats stats;
    g_api.stats(g_bridge, &stats);
    return flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("framesPublished"),
         flutter::EncodableValue(static_cast<int64_t>(stats.frames_published))},
        {flutter::EncodableValue("framesDropped"),
         flutter::EncodableValue(static_cast<int64_t>(stats.frames_dropped))},
        {flutter::EncodableValue("width"),
         flutter::EncodableValue(static_cast<int64_t>(stats.width))},
        {flutter::EncodableValue("height"),
         flutter::EncodableValue(static_cast<int64_t>(stats.height))},
    });
  }

  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string& name = call.method_name();
    if (name == "attach") {
      const auto* arguments = call.arguments();
      if (arguments) {
        if (const auto* address = std::get_if<int64_t>(arguments)) {
          SetSession(*address);
        }
      }
      result->Success(flutter::EncodableValue(session_ != nullptr));
    } else if (name == "create") {
      result->Success(flutter::EncodableValue(texture_id_));
    } else if (name == "frameReady") {
      result->Success(flutter::EncodableValue(Publish()));
    } else if (name == "stats") {
      result->Success(Stats());
    } else {
      result->NotImplemented();
    }
  }

 private:
  void LogStats() {
    if (++notifications_ % 60 != 0) return;
    ezcore_video_texture_stats stats;
    g_api.stats(g_bridge, &stats);
    char message[160];
    snprintf(message, sizeof(message),
             "ezCORE video: %llu frames, %llu dropped, %ux%u\n",
             static_cast<unsigned long long>(stats.frames_published),
             static_cast<unsigned long long>(stats.frames_dropped), stats.width,
             stats.height);
    OutputDebugStringA(message);
  }

  flutter::TextureRegistrar* registrar_ = nullptr;
  std::unique_ptr<flutter::TextureVariant> texture_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  int64_t texture_id_ = -1;
  ezcore_session* session_ = nullptr;
  uint64_t notifications_ = 0;
};

std::unique_ptr<VideoChannel> VideoChannel::Create(
    flutter::PluginRegistrar* registrar) {
  if (!LoadApi()) return nullptr;
  auto* bridge = g_api.create();
  if (!bridge) return nullptr;
  g_bridge = bridge;
  auto channel = std::unique_ptr<VideoChannel>(new VideoChannel(registrar));
  if (!channel->impl_ || !channel->impl_->valid()) {
    g_bridge = nullptr;
    g_api.destroy(bridge);
    return nullptr;
  }
  return channel;
}

VideoChannel::VideoChannel(flutter::PluginRegistrar* registrar)
    : impl_(std::make_unique<Impl>(registrar)) {}

VideoChannel::~VideoChannel() {
  if (g_bridge) {
    g_api.destroy(g_bridge);
    g_bridge = nullptr;
  }
}
