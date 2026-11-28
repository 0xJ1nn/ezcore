// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* One small atomic-replace seam. POSIX rename(2) replaces an existing target;
 * Windows rename() refuses to, so the two platforms cannot share a call.
 * Exactly one implementation is compiled per platform, like the dynamic-loader
 * and video-lock seams.

 * Used by the battery-save writer: a save is written to a temporary file and
 * then moved over the real one, so a crash mid-write can never leave the next
 * session loading half of one cart generation and half of another. */
#ifndef EZCORE_FILE_REPLACE_H
#define EZCORE_FILE_REPLACE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Moves `from` onto `to`, replacing `to` if it exists. Both paths are UTF-8
 * on POSIX and ANSI on Windows, matching what stdio already accepts there.
 * Returns false on failure; the caller decides whether to remove `from`. */
bool ezcore_file_replace(const char *from, const char *to);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* EZCORE_FILE_REPLACE_H */
