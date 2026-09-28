/* test_core_options.c — exercises the runtime's P1b core-options &
 * capability-surface env handlers and the ezcore_* host query API.
 *
 * Uses the synthetic options core (synth_options_core.c) which, during
 * retro_set_environment, calls:
 *   - RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION
 *   - RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL   (v1 intl)
 *   - RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2     (v2 — overwrites INTL)
 *   - RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS
 *   - RETRO_ENVIRONMENT_SET_CONTROLLER_INFO
 *   - RETRO_ENVIRONMENT_SET_MEMORY_MAPS
 *
 * The synth core additionally zeros all its static data inside
 * retro_load_game, so any pointer the runtime merely stashed (rather
 * than deep-copying) would be gone — proving ownership transfer.
 *
 * Exit: 0 = pass, 1-9 = step that failed.
 */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ezcore_runtime.h"

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    } else {                                                                   \
      printf("ok: %s\n", msg);                                                 \
    }                                                                          \
  } while (0)

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_core_options <synth_options_core>\n");
    return 9;
  }
  const char *core_path = argv[1];

  /* --- ABI --- */
  CHECK(ezcore_abi_version() == 1, "ABI version is 1");

  /* --- Load (triggers retro_set_environment → env_cb) --- */
  char err[1024] = {0};
  ezcore_session *s = ezcore_load(core_path, err, sizeof(err));
  CHECK(s != NULL, "options core loaded");
  CHECK(ezcore_init(s), "init ok");

  /* === Version round-trip ===
   * The synth core calls GET_CORE_OPTIONS_VERSION and only sends V2
   * options if the host reported >= 0x20000.  Finding 2 V2 options
   * stored proves the host answered the version query correctly. */
  unsigned opt_count = ezcore_get_core_option_count(s);
  CHECK(opt_count == 2, "version round-trip: host reported v2, 2 V2 options stored");

  /* Option 0: test_region, default "auto" */
  const char *key, *def, *val;
  CHECK(ezcore_get_core_option(s, 0, &key, &def, &val), "get option[0] ok");
  CHECK(key != NULL && strcmp(key, "test_region") == 0, "option[0] key");
  CHECK(def != NULL && strcmp(def, "auto") == 0, "option[0] default");
  CHECK(val != NULL && strcmp(val, "auto") == 0, "option[0] initial value == default");

  /* Option 1: test_frameskip, default "disabled" */
  CHECK(ezcore_get_core_option(s, 1, &key, &def, &val), "get option[1] ok");
  CHECK(key != NULL && strcmp(key, "test_frameskip") == 0, "option[1] key");
  CHECK(def != NULL && strcmp(def, "disabled") == 0, "option[1] default");

  /* Out-of-range index → false */
  CHECK(!ezcore_get_core_option(s, opt_count, &key, &def, &val),
        "get option out-of-range returns false");

  /* === ezcore_set_core_option (set a value) === */
  CHECK(ezcore_set_core_option(s, "test_region", "pal"), "set existing option");
  CHECK(ezcore_get_core_option(s, 0, &key, &def, &val), "re-get option[0]");
  CHECK(strcmp(val, "pal") == 0, "option[0] value updated to pal");

  /* Setting to a different valid value */
  CHECK(ezcore_set_core_option(s, "test_region", "ntsc-u"), "set option to ntsc-u");
  CHECK(ezcore_get_core_option(s, 0, &key, &def, &val), "re-get option[0] after ntsc-u");
  CHECK(strcmp(val, "ntsc-u") == 0, "option[0] value updated to ntsc-u");

  /* === Unknown key tolerated === */
  CHECK(!ezcore_set_core_option(s, "nonexistent_key", "x"),
        "set unknown key returns false");
  /* Stored option unchanged */
  CHECK(ezcore_get_core_option(s, 0, &key, &def, &val), "get option[0] still valid");
  CHECK(strcmp(val, "ntsc-u") == 0, "option[0] unchanged after failed set");

  /* === SET_INPUT_DESCRIPTORS stored === */
  unsigned id_count = ezcore_get_input_descriptor_count(s);
  CHECK(id_count == 2, "two input descriptors stored");
  unsigned port, dev, idx, id; const char *desc;
  CHECK(ezcore_get_input_descriptor(s, 0, &port, &dev, &idx, &id, &desc),
        "get input desc[0] ok");
  CHECK(desc != NULL && strcmp(desc, "B Button") == 0, "input desc[0] text");
  CHECK(port == 0, "input desc[0] port");
  CHECK(ezcore_get_input_descriptor(s, 1, &port, &dev, &idx, &id, &desc) &&
        desc != NULL && strcmp(desc, "Start") == 0,
        "input desc[1] text");

  /* === SET_CONTROLLER_INFO stored === */
  unsigned port_count = ezcore_get_controller_port_count(s);
  CHECK(port_count == 1, "one controller port stored");

  /* === SET_MEMORY_MAPS stored === */
  unsigned mm_count = ezcore_get_memory_descriptor_count(s);
  CHECK(mm_count == 2, "two memory descriptors stored");
  uint64_t flags; void *ptr; size_t off, start, sel, disc, len;
  const char *addrspace;
  CHECK(ezcore_get_memory_descriptor(s, 0, &flags, &ptr, &off, &start,
                                     &sel, &disc, &len, &addrspace),
        "get mem desc[0] ok");
  CHECK(addrspace != NULL && strcmp(addrspace, "RAM") == 0, "mem desc[0] addrspace");
  CHECK(start == 0x0000, "mem desc[0] start");
  CHECK(len == 0x2000, "mem desc[0] length");
  CHECK(ezcore_get_memory_descriptor(s, 1, &flags, &ptr, &off, &start,
                                     &sel, &disc, &len, &addrspace) &&
        addrspace != NULL && strcmp(addrspace, "ROM") == 0,
        "mem desc[1] addrspace");

  /* === Deep-copy proof: load_game zeros the core's static data ===
   * After load_game the runtime's copies must still be valid. */
  CHECK(ezcore_load_game(s, "/dev/null", NULL, 0), "load_game ok");

  /* Options still stored and correct (runtime deep-copied, not pointer-stashed) */
  CHECK(ezcore_get_core_option_count(s) == 2, "option count persists after source zeroed");
  CHECK(ezcore_get_core_option(s, 0, &key, &def, &val) &&
        key && strcmp(key, "test_region") == 0,
        "option[0] key survives source zeroing");
  CHECK(ezcore_get_core_option(s, 0, &key, &def, &val) &&
        val && strcmp(val, "ntsc-u") == 0,
        "option[0] value survives source zeroing");

  /* Input descriptors survive zeroing */
  CHECK(ezcore_get_input_descriptor_count(s) == 2, "input descs survive source zeroing");
  CHECK(ezcore_get_input_descriptor(s, 0, &port, &dev, &idx, &id, &desc) &&
        desc && strcmp(desc, "B Button") == 0,
        "input desc[0] survives source zeroing");

  /* Controller info survives */
  CHECK(ezcore_get_controller_port_count(s) == 1, "controller info survives zeroing");

  /* Memory descriptors survive */
  CHECK(ezcore_get_memory_descriptor_count(s) == 2, "memory descs survive source zeroing");
  CHECK(ezcore_get_memory_descriptor(s, 0, &flags, &ptr, &off, &start,
                                     &sel, &disc, &len, &addrspace) &&
        addrspace && strcmp(addrspace, "RAM") == 0,
        "mem desc[0] addrspace survives source zeroing");

  /* === Lifecycle: unload (must free all deep copies without crashing) === */
  ezcore_unload(s);
  s = NULL;

  /* Re-load to verify no stale global state */
  s = ezcore_load(core_path, err, sizeof(err));
  CHECK(s != NULL, "re-load options core ok");
  CHECK(ezcore_get_core_option_count(s) == 2, "fresh load has 2 options (no stale state)");
  CHECK(ezcore_get_controller_port_count(s) == 1, "fresh load has controller info");
  CHECK(ezcore_get_memory_descriptor_count(s) == 2, "fresh load has memory maps");
  ezcore_unload(s);

  printf("\n✅ ALL CORE OPTIONS TESTS PASSED\n");
  return 0;
}
