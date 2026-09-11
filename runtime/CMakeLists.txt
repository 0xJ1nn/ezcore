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

add_library(ezcore_runtime SHARED
  src/runtime.c
)
target_include_directories(ezcore_runtime PUBLIC
  include
  external/libretro-common/include
)
if(APPLE)
  set_target_properties(ezcore_runtime PROPERTIES SUFFIX ".dylib")
endif()

add_executable(test_abi test/test_abi.c)
target_link_libraries(test_abi PRIVATE ezcore_runtime)
target_include_directories(test_abi PRIVATE include)

enable_testing()
add_test(NAME abi_version COMMAND test_abi)
