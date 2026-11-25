// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

#ifndef EZCORE_VIDEO_CHANNEL_H_
#define EZCORE_VIDEO_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

/* Registers the pixel-buffer texture and the frame channel on the Flutter
 * engine owned by [view]. The runtime library is resolved when the channel is
 * created, so no build-time link dependency is added to the runner. */
void ezcore_video_channel_setup(FlView* view);

#endif  // EZCORE_VIDEO_CHANNEL_H_
