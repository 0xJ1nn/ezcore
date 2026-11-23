# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception
cmake_minimum_required(VERSION 3.22.1)
project(ezcore_surface C)

add_library(ezcore_surface SHARED ezcore_surface_jni.c)
find_library(ANDROID_LIBRARY android)
target_link_libraries(ezcore_surface ${ANDROID_LIBRARY})
