// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

#ifndef EZCORE_VIDEO_CHANNEL_H_
#define EZCORE_VIDEO_CHANNEL_H_

#include <flutter/plugin_registrar.h>

#include <memory>

/* Mirrors the Linux desktop texture channel: one pixel-buffer texture on the
 * engine's texture registrar, driven by the same native frame snapshots. */
class VideoChannel {
 public:
  static std::unique_ptr<VideoChannel> Create(
      flutter::PluginRegistrar* registrar);
  ~VideoChannel();

  VideoChannel(const VideoChannel&) = delete;
  VideoChannel& operator=(const VideoChannel&) = delete;

 private:
  explicit VideoChannel(flutter::PluginRegistrar* registrar);

  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // EZCORE_VIDEO_CHANNEL_H_
