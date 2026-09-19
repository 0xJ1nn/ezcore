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

add_library(ezcore_runtime SHARED
  src/runtime.c
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

# --- Tests ---
add_executable(test_abi test/test_abi.c)
target_link_libraries(test_abi PRIVATE ezcore_runtime)
target_include_directories(test_abi PRIVATE include)

# Native core input/reset/audio/frame test using the synthetic core
add_executable(test_core_player test/test_core_player.c)
target_link_libraries(test_core_player PRIVATE ezcore_runtime)
target_include_directories(test_core_player PRIVATE include)

enable_testing()
add_test(NAME abi_version COMMAND test_abi)

# Native core lifecycle test (synthetic — deterministic, no copyrighted content)
add_test(NAME core_player
  COMMAND test_core_player
  ${CMAKE_BINARY_DIR}/libsynth_libretro${CMAKE_SHARED_LIBRARY_SUFFIX})

# Crash-isolated per-core boot test (forks a child so one crash doesn't kill the runner)
add_executable(test_core_boot test/test_core_boot.c)
target_link_libraries(test_core_boot PRIVATE ezcore_runtime)
target_include_directories(test_core_boot PRIVATE include)

# Boot tests for cores that have test ROMs available.
# Fixture-gated: skipped when native/test-roms/ is absent (fresh clones, CI
# without fixtures). Suffix follows the host platform (.so/.dylib/.dll).
if(EXISTS "${CMAKE_SOURCE_DIR}/../native/test-roms/cpu_instrs.gb")
  add_test(NAME boot_sameboy COMMAND test_core_boot
    "${CMAKE_SOURCE_DIR}/../native/cores/sameboy/sameboy_libretro${CMAKE_SHARED_LIBRARY_SUFFIX}"
    "${CMAKE_SOURCE_DIR}/../native/test-roms/cpu_instrs.gb")
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/../native/test-roms/test.gba")
  add_test(NAME boot_mgba COMMAND test_core_boot
    "${CMAKE_SOURCE_DIR}/../native/cores/mgba/mgba_libretro${CMAKE_SHARED_LIBRARY_SUFFIX}"
    "${CMAKE_SOURCE_DIR}/../native/test-roms/test.gba")
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/../native/test-roms/ezcore_nes_minimal.nes")
  add_test(NAME boot_mesen COMMAND test_core_boot
    "${CMAKE_SOURCE_DIR}/../native/cores/mesen/mesen_libretro${CMAKE_SHARED_LIBRARY_SUFFIX}"
    "${CMAKE_SOURCE_DIR}/../native/test-roms/ezcore_nes_minimal.nes")
endif()
