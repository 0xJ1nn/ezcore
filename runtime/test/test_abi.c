#include <assert.h>
#include <stdio.h>

#include "ezcore_runtime.h"

int main(void) {
  assert(ezcore_abi_version() == EZCORE_ABI_VERSION);
  printf("ezCore runtime ABI v%d OK\n", ezcore_abi_version());
  return 0;
}
