cmake_minimum_required(VERSION 3.21)
project(ezcore_runtime C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# libretro-common headers are vendored at build time by scripts/build_core.sh
# into runtime/external/libretro-common/include. CI fails loudly if absent
# so nobody silently builds against a stale copy.
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/libretro-common/include/libretro.h")
  message(FATAL_ERROR
    "libretro.h not vendored. Run scripts/build_core.sh --fetch-headers first.")
endif()

# Platform seam: exactly one dynload implementation per target OS.
if(WIN32)
  set(EZCORE_DYNLOAD_SRC src/dynload_win32.c)
else()
  set(EZCORE_DYNLOAD_SRC src/dynload_posix.c)
endif()

# GPU render context (ADR-018, Option B). ezcore_gpu.c is the only file that
# knows which backend is in play; exactly one *_platform backend is compiled in
# per platform, and the Vulkan backend is portable because it goes through the
# loader rather than linking libvulkan. No EGL/GLES/Vulkan library is linked
# here on purpose -- see the comment at the top of ezcore_gpu_egl.c.
if(WIN32)
  set(EZCORE_GPU_BACKEND src/ezcore_gpu_wgl.c)
elseif(APPLE)
  set(EZCORE_GPU_BACKEND src/ezcore_gpu_cgl.c)
else()
  set(EZCORE_GPU_BACKEND src/ezcore_gpu_egl.c)
endif()

add_library(ezcore_runtime SHARED
  src/runtime.c
  src/ezcore_gpu.c
  src/ezcore_gpu_vulkan.c
  ${EZCORE_GPU_BACKEND}
  ${EZCORE_DYNLOAD_SRC}
)
target_include_directories(ezcore_runtime PUBLIC
  include
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(ezcore_runtime PROPERTIES SUFFIX ".dylib")
endif()

# --- Synthetic test core (deterministic, no ROMs needed) ---
add_library(synth_libretro SHARED
  test/synth_core/synth_test_core.c
)
target_include_directories(synth_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_libretro PROPERTIES SUFFIX ".dylib")
endif()

# Variants used to verify that optional libretro entry points may be absent.
add_library(synth_no_cheat_libretro SHARED
  test/synth_core/synth_test_core.c
)
target_compile_definitions(synth_no_cheat_libretro PRIVATE
  EZCORE_SYNTH_NO_CHEAT
)
target_include_directories(synth_no_cheat_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_no_cheat_libretro PROPERTIES SUFFIX ".dylib")
endif()

add_library(synth_no_reset_cheat_libretro SHARED
  test/synth_core/synth_test_core.c
)
target_compile_definitions(synth_no_reset_cheat_libretro PRIVATE
  EZCORE_SYNTH_NO_CHEAT_RESET
)
target_include_directories(synth_no_reset_cheat_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_no_reset_cheat_libretro PROPERTIES SUFFIX ".dylib")
endif()

add_library(synth_no_set_cheat_libretro SHARED
  test/synth_core/synth_test_core.c
)
target_compile_definitions(synth_no_set_cheat_libretro PRIVATE
  EZCORE_SYNTH_NO_CHEAT_SET
)
target_include_directories(synth_no_set_cheat_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_no_set_cheat_libretro PROPERTIES SUFFIX ".dylib")
endif()

# --- Synthetic core that exercises core-options & capability env calls ---
add_library(synth_options_libretro SHARED
  test/synth_core/synth_options_core.c
)
target_include_directories(synth_options_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_options_libretro PROPERTIES SUFFIX ".dylib")
endif()

# --- Synthetic core that reads every input device (P3) ---
add_library(synth_input_libretro SHARED
  test/synth_core/synth_input_core.c
)
target_include_directories(synth_input_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_input_libretro PROPERTIES SUFFIX ".dylib")
endif()

# --- Synthetic core that READS its options (GET_VARIABLE / _UPDATE) ---
add_library(synth_variables_libretro SHARED
  test/synth_core/synth_variables_core.c
)
target_include_directories(synth_variables_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_variables_libretro PROPERTIES SUFFIX ".dylib")
endif()

# --- P6 spike: core that crashes on demand, so crash containment can be
# exercised against a real signal instead of a simulated one. Same binary runs
# clean or faults, selected by EZCORE_CRASH_AFTER at retro_run time. ---
add_library(crash_libretro SHARED
  test/crash_core.c
)
target_include_directories(crash_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(crash_libretro PROPERTIES SUFFIX ".dylib")
endif()

# --- Synthetic core that echoes every port's button 0 into the audio sample.
# Used by the stuck-input regression test (test_input_reset) so a reset's
# effect on input can be observed through the real input_state path.
add_library(synth_all_ports_libretro SHARED
  test/synth_core/synth_test_core.c
)
target_compile_definitions(synth_all_ports_libretro PRIVATE
  EZCORE_SYNTH_ALL_PORTS
)
target_include_directories(synth_all_ports_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_all_ports_libretro PROPERTIES SUFFIX ".dylib")
endif()

# --- Synthetic core that echoes every port AND rejects a content-less load.
# Used by the load-game stuck-input regression test (test_loadgame_input):
# the all-ports build proves a successful load clears held buttons, and this
# build's EZCORE_SYNTH_FAIL_LOAD guard lets the same test prove that a FAILED
# load leaves the still-running session's input untouched.
add_library(synth_all_ports_fail_load_libretro SHARED
  test/synth_core/synth_test_core.c
)
target_compile_definitions(synth_all_ports_fail_load_libretro PRIVATE
  EZCORE_SYNTH_ALL_PORTS
  EZCORE_SYNTH_FAIL_LOAD
)
target_include_directories(synth_all_ports_fail_load_libretro PRIVATE
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(synth_all_ports_fail_load_libretro PROPERTIES SUFFIX ".dylib")
endif()

# --- Tests ---
add_executable(test_abi test/test_abi.c)
target_link_libraries(test_abi PRIVATE ezcore_runtime)
target_include_directories(test_abi PRIVATE include)

# Native core input/reset/audio/frame test using the synthetic core
add_executable(test_core_player test/test_core_player.c)
target_link_libraries(test_core_player PRIVATE ezcore_runtime)
target_include_directories(test_core_player PRIVATE include)

# Optional libretro entry points must not make a core unloadable.
add_executable(test_optional_cheats test/test_optional_cheats.c)
target_link_libraries(test_optional_cheats PRIVATE ezcore_runtime)
target_include_directories(test_optional_cheats PRIVATE include)
add_dependencies(test_optional_cheats
  synth_libretro
  synth_no_cheat_libretro
  synth_no_reset_cheat_libretro
  synth_no_set_cheat_libretro
)

# Stuck-input regression: ezcore_reset must release held buttons.
add_executable(test_input_reset test/test_input_reset.c)
target_link_libraries(test_input_reset PRIVATE ezcore_runtime)
target_include_directories(test_input_reset PRIVATE include)
add_dependencies(test_input_reset synth_all_ports_libretro)

# Stuck-input regression: ezcore_load_game must release held buttons on a
# successful load, and must NOT touch them when the load fails.
add_executable(test_loadgame_input test/test_loadgame_input.c)
target_link_libraries(test_loadgame_input PRIVATE ezcore_runtime)
target_include_directories(test_loadgame_input PRIVATE include)
add_dependencies(test_loadgame_input
  synth_all_ports_libretro
  synth_all_ports_fail_load_libretro
)

enable_testing()
add_test(NAME abi_version COMMAND test_abi)

# docs/API.md must describe the ABI the header exports (docs/PLATFORM.md §8).
# stdlib-only python; skipped silently on hosts without python3.
find_program(PYTHON3_EXECUTABLE python3)
if(PYTHON3_EXECUTABLE)
  add_test(NAME api_docs
           COMMAND ${PYTHON3_EXECUTABLE}
                   ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/check_api_docs.py)
  # The kernel capability count ("13 of 93 environment commands") lived in
  # prose and sat wrong in six files simultaneously, because api_docs only
  # checks the ezCORE-owned ABI and could never see a libretro figure. This
  # gate recomputes both numbers from the vendored header and the runtime
  # source on every run and compares them against what the docs claim.
  add_test(NAME env_coverage_docs
           COMMAND ${PYTHON3_EXECUTABLE}
                   ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/check_env_coverage_docs.py)
endif()


# A synthetic core that REQUIRES hardware rendering, in the shape of the six
# cores P8 exists for. Synthetic and CC0: no copyrighted core, no ROM, no
# gameplay. It is the only test that can prove env_cb is actually wired --
# the seam test proves a context can be made, not that a core can get one.
add_library(synth_hw_core SHARED test/synth_core/synth_hw_core.c)
target_include_directories(synth_hw_core PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/external/libretro-common/include)
set_target_properties(synth_hw_core PROPERTIES PREFIX "")

add_executable(test_hw_render_core test/test_hw_render_core.c)
target_include_directories(test_hw_render_core PRIVATE include)
target_link_libraries(test_hw_render_core PRIVATE ezcore_runtime ${CMAKE_DL_LIBS})
add_test(NAME hw_render_core COMMAND test_hw_render_core
         $<TARGET_FILE:synth_hw_core>)

# How a core picks its context type: GET_PREFERRED_HW_RENDER is answered by
# the host, and Vulkan is refused until frames can be handed over.
add_executable(test_hw_negotiation test/test_hw_negotiation.c)
target_include_directories(test_hw_negotiation PRIVATE include
  ${CMAKE_CURRENT_SOURCE_DIR}/external/libretro-common/include)
target_link_libraries(test_hw_negotiation PRIVATE ezcore_runtime ${CMAKE_DL_LIBS})
add_dependencies(test_hw_negotiation synth_hw_core)
add_test(NAME hw_negotiation COMMAND test_hw_negotiation
         $<TARGET_FILE:synth_hw_core>)

# Drawing variant of the same core: renders a known picture and submits it
# with RETRO_HW_FRAME_BUFFER_VALID, so GPU readback can be checked.
add_library(synth_hw_draw SHARED test/synth_core/synth_hw_core.c)
target_compile_definitions(synth_hw_draw PRIVATE EZCORE_SYNTH_HW_DRAW)
target_include_directories(synth_hw_draw PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/external/libretro-common/include)
set_target_properties(synth_hw_draw PROPERTIES PREFIX "")

add_executable(test_hw_readback test/test_hw_readback.c)
target_include_directories(test_hw_readback PRIVATE include)
target_link_libraries(test_hw_readback PRIVATE ezcore_runtime)
add_dependencies(test_hw_readback synth_hw_draw)
add_test(NAME hw_readback COMMAND test_hw_readback
         $<TARGET_FILE:synth_hw_draw>)

# libretro teardown order: unload_game, context_destroy, deinit, then the
# context goes away.
add_executable(test_unload_order test/test_unload_order.c)
target_include_directories(test_unload_order PRIVATE include)
target_link_libraries(test_unload_order PRIVATE ezcore_runtime)
add_dependencies(test_unload_order synth_hw_core)
add_test(NAME unload_order COMMAND test_unload_order
         $<TARGET_FILE:synth_hw_core> ${CMAKE_BINARY_DIR}/unload_order.txt)

# GPU context seam test (ADR-018, Option B). Exercises a real GLES3 context
# and a real Vulkan device where the host has them, and SKIPS with a printed
# reason where it does not -- a GPU test that fails without a GPU would only
# ever be runnable on one machine, and would get deleted.
add_executable(test_gpu_context test/test_gpu_context.c)
target_include_directories(test_gpu_context PRIVATE src)
target_link_libraries(test_gpu_context PRIVATE ezcore_runtime)
add_test(NAME gpu_context COMMAND test_gpu_context)

# Native core lifecycle test (synthetic — deterministic, no copyrighted content)
add_test(NAME core_player
  COMMAND test_core_player
  ${CMAKE_BINARY_DIR}/libsynth_libretro${CMAKE_SHARED_LIBRARY_SUFFIX})

# Core-options & capability surface test (uses synth_options_libretro)
add_executable(test_core_options test/test_core_options.c)
target_link_libraries(test_core_options PRIVATE ezcore_runtime)
target_include_directories(test_core_options PRIVATE include)
add_dependencies(test_core_options synth_options_libretro)

add_test(NAME core_options
  COMMAND test_core_options
  ${CMAKE_BINARY_DIR}/libsynth_options_libretro${CMAKE_SHARED_LIBRARY_SUFFIX})

# P3: analog, mouse, keyboard (state + callback) and pointer reach a core.
add_executable(test_input_devices test/test_input_devices.c)
target_link_libraries(test_input_devices PRIVATE ezcore_runtime)
target_include_directories(test_input_devices PRIVATE include
  external/libretro-common/include)
add_dependencies(test_input_devices synth_input_libretro)
add_test(NAME input_devices
  COMMAND test_input_devices $<TARGET_FILE:synth_input_libretro>)

# Regression: an option value the host sets must reach the core through
# GET_VARIABLE, with GET_VARIABLE_UPDATE raised exactly once per change.
add_executable(test_core_variables test/test_core_variables.c)
target_link_libraries(test_core_variables PRIVATE ezcore_runtime)
target_include_directories(test_core_variables PRIVATE include)
add_dependencies(test_core_variables synth_variables_libretro)

add_test(NAME core_variables
  COMMAND test_core_variables
  $<TARGET_FILE:synth_variables_libretro>)

# Regression: a button held at reset time must not stay latched afterwards.
add_test(NAME input_reset_clears_buttons
  COMMAND test_input_reset
  $<TARGET_FILE:synth_all_ports_libretro>)

# Regression: a button held when a second game is loaded must not stay latched
# across the game boundary, and a failed load must leave input alone.
add_test(NAME loadgame_clears_buttons
  COMMAND test_loadgame_input
  $<TARGET_FILE:synth_all_ports_libretro>
  $<TARGET_FILE:synth_all_ports_fail_load_libretro>)

# Regression coverage for cores that omit each optional cheat symbol.
add_test(NAME optional_cheat_symbols_none
  COMMAND test_optional_cheats
  $<TARGET_FILE:synth_no_cheat_libretro> 0x00 0)
add_test(NAME optional_cheat_symbols_without_reset
  COMMAND test_optional_cheats
  $<TARGET_FILE:synth_no_reset_cheat_libretro> 0x80 1)
add_test(NAME optional_cheat_symbols_without_set
  COMMAND test_optional_cheats
  $<TARGET_FILE:synth_no_set_cheat_libretro> 0x40 0)
add_test(NAME optional_cheat_symbols_supported
  COMMAND test_optional_cheats
  $<TARGET_FILE:synth_libretro> 0xC0 1)

# Crash-isolated per-core boot test (forks a child so one crash doesn't kill the runner)
add_executable(test_core_boot test/test_core_boot.c)
target_link_libraries(test_core_boot PRIVATE ezcore_runtime)
target_include_directories(test_core_boot PRIVATE include)

# P6 exit-code contract: proves crash_libretro still faults on demand and that
# a real signal death is classified as exit 9 (kCrashExitCode), the mapping
# test_core_boot.c already uses. Until this existed the fixture was built and
# never run, so `ctest` could not have told a maintainer it had rotted.
# POSIX-only: needs fork()/WIFSIGNALED to isolate the faulting grandchild.
add_executable(test_crash_signal test/test_crash_signal.c)
target_link_libraries(test_crash_signal PRIVATE ezcore_runtime)
target_include_directories(test_crash_signal PRIVATE include)
add_dependencies(test_crash_signal crash_libretro)

# P6 (ADR-015): the helper process that hosts one core session, so a core
# crash ends that process instead of the app. Links the unchanged runtime.
add_executable(ezcore_core_host host/ezcore_core_host.c)
target_link_libraries(ezcore_core_host PRIVATE ezcore_runtime)
target_include_directories(ezcore_core_host PRIVATE include)
# Finds libezcore_runtime beside itself, in the build tree and in a release
# bundle alike (release.sh ships the two side by side).
if(APPLE)
  set_target_properties(ezcore_core_host PROPERTIES
    BUILD_RPATH "@loader_path" INSTALL_RPATH "@loader_path")
elseif(UNIX)
  set_target_properties(ezcore_core_host PROPERTIES
    BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN")
endif()

# Drives the host over its pipe protocol: a good core end to end, a core that
# segfaults mid-frame (only the host dies), and the host exiting when its
# input closes. POSIX-only (fork/exec/waitpid).
add_executable(test_core_host test/test_core_host.c)
add_dependencies(test_core_host ezcore_core_host synth_libretro crash_libretro)

if(NOT WIN32)
  add_test(NAME crash_signal_exit_code
    COMMAND test_crash_signal
    $<TARGET_FILE:crash_libretro>)
  add_test(NAME core_host_contains_crash
    COMMAND test_core_host
    $<TARGET_FILE:ezcore_core_host>
    $<TARGET_FILE:synth_libretro>
    $<TARGET_FILE:crash_libretro>)
endif()

# Boot tests for cores that have test ROMs available.
# Fixture-gated: skipped when native/test-roms/ is absent (fresh clones, CI
# without fixtures). Core tree follows the host platform:
# macos-arm64 -> native/cores, everything else -> native/cores-<plat>-<arch>
# (matches core_platform.sh OUT_DIR). Suffix follows the host platform
# (.so/.dylib/.dll).
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
  set(EZCORE_CORES_ROOT "${CMAKE_SOURCE_DIR}/../native/cores")
else()
  execute_process(COMMAND uname -m OUTPUT_VARIABLE EZCORE_HOST_ARCH
                  OUTPUT_STRIP_TRAILING_WHITESPACE)
  # Match core_platform.sh naming: linux x64 -> cores-linux-x64
  set(EZCORE_HOST_PLAT "${CMAKE_HOST_SYSTEM_NAME}")
  if(EZCORE_HOST_ARCH STREQUAL "x86_64")
    set(EZCORE_HOST_ARCH "x64")
  elseif(EZCORE_HOST_ARCH STREQUAL "aarch64")
    set(EZCORE_HOST_ARCH "arm64")
  endif()
  string(TOLOWER "${EZCORE_HOST_PLAT}" EZCORE_HOST_PLAT)
  set(EZCORE_CORES_ROOT
      "${CMAKE_SOURCE_DIR}/../native/cores-${EZCORE_HOST_PLAT}-${EZCORE_HOST_ARCH}")
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/../native/test-roms/cpu_instrs.gb")
  add_test(NAME boot_pocketbit COMMAND test_core_boot
    "${EZCORE_CORES_ROOT}/pocketbit/pocketbit_libretro${CMAKE_SHARED_LIBRARY_SUFFIX}"
    "${CMAKE_SOURCE_DIR}/../native/test-roms/cpu_instrs.gb")
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/../native/test-roms/test.gba")
  add_test(NAME boot_advancebit COMMAND test_core_boot
    "${EZCORE_CORES_ROOT}/advancebit/advancebit_libretro${CMAKE_SHARED_LIBRARY_SUFFIX}"
    "${CMAKE_SOURCE_DIR}/../native/test-roms/test.gba")
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/../native/test-roms/ezcore_nes_minimal.nes")
  add_test(NAME boot_nesbyte COMMAND test_core_boot
    "${EZCORE_CORES_ROOT}/nesbyte/nesbyte_libretro${CMAKE_SHARED_LIBRARY_SUFFIX}"
    "${CMAKE_SOURCE_DIR}/../native/test-roms/ezcore_nes_minimal.nes")
endif()
