// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* POSIX side of the atomic-replace seam: rename(2) already replaces the
 * target atomically within one filesystem. */
#include "ezcore_file_replace.h"

#include <stdio.h>

bool ezcore_file_replace(const char *from, const char *to) {
  return from && to && rename(from, to) == 0;
}
