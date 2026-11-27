// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* Windows side of the atomic-replace seam. The C runtime's rename() fails
 * when the target exists, so a battery save would never be refreshed after
 * the first write; MoveFileEx with REPLACE_EXISTING is the Win32 equivalent. */
#include "ezcore_file_replace.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

bool ezcore_file_replace(const char *from, const char *to) {
  if (!from || !to) return false;
  return MoveFileExA(from, to, MOVEFILE_REPLACE_EXISTING) != 0;
}
