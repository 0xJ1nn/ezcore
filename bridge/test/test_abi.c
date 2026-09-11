#include <assert.h>
#include <stdio.h>

#include "libretro_bridge.h"

int main(void) {
  assert(huh_abi_version() == HUH_ABI_VERSION);
  printf("bridge ABI v%d OK\n", huh_abi_version());
  return 0;
}
