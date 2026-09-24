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

enable_testing()
add_test(NAME abi_version COMMAND test_abi)

# Native core lifecycle test (synthetic — deterministic, no copyrighted content)
add_test(NAME core_player
  COMMAND test_core_player
  ${CMAKE_BINARY_DIR}/libsynth_libretro${CMAKE_SHARED_LIBRARY_SUFFIX})

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
