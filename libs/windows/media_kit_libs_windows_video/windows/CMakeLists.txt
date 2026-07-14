# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

cmake_policy(SET CMP0175 NEW)

option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ==============================================================================
function(download_and_verify url md5 locationForArchive)
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)
    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed.")
    endif()
  endif()
endfunction()

# ==============================================================================
# 查找 7-Zip
# ==============================================================================
find_program(SEVENZ_EXECUTABLE NAMES 7z 7za
  PATHS
    "C:/Program Files/7-Zip"
    "C:/Program Files (x86)/7-Zip"
    "$ENV{ProgramFiles}/7-Zip"
    "$ENV{ProgramFiles\(x86\)}/7-Zip"
)
if(NOT SEVENZ_EXECUTABLE)
  message(FATAL_ERROR "7-Zip not found. Install: winget install 7zip.7zip")
endif()
message(STATUS "7-Zip: ${SEVENZ_EXECUTABLE}")

# ==============================================================================
# libmpv — 官方 media-kit/libmpv-win32-video-cmake
#
# 不知道官方包是 include/client.h（扁平）还是 include/mpv/client.h（嵌套），
# 所以解压后自动检测并适配。
# ==============================================================================

if(${FLUTTER_TARGET_PLATFORM} STREQUAL "windows-x64")
  set(LIBMPV "mpv-dev-x86_64-20241021-git-0f78584.7z")
  set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-cmake/releases/download/20241021/${LIBMPV}")
  set(LIBMPV_MD5 "6ecf18e85b093c3f7edb16f3ee6603f3")
else()
  set(LIBMPV "mpv-dev-aarch64-20241021-git-0f78584.7z")
  set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-cmake/releases/download/20241021/${LIBMPV}")
  set(LIBMPV_MD5 "5b507a35db13eee6cb7eb21e8be7c83d")
endif()
string(REGEX REPLACE "\\.7z$" "" LIBMPV_TOP "${LIBMPV}")
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

download_and_verify(${LIBMPV_URL} ${LIBMPV_MD5} ${LIBMPV_ARCHIVE})

if(NOT EXISTS "${LIBMPV_SRC}/include/client.h")
  message(STATUS "Extracting libmpv...")

  # 清理
  file(REMOVE_RECURSE "${LIBMPV_SRC}")
  file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/${LIBMPV_TOP}")

  # 步骤1：7z 解压
  execute_process(
    COMMAND "${SEVENZ_EXECUTABLE}" x "${LIBMPV_ARCHIVE}" "-o${CMAKE_BINARY_DIR}" -y
    RESULT_VARIABLE _r
  )
  if(NOT _r EQUAL 0)
    message(FATAL_ERROR "7z extract libmpv failed: exit ${_r}")
  endif()

  # 步骤2：检测结构并适配
  #  情况A: include/client.h 已存在 → 直接改名即可
  #  情况B: include/mpv/client.h 存在 → 先把 mpv/* 提到 include/，再改名
  if(EXISTS "${CMAKE_BINARY_DIR}/${LIBMPV_TOP}/include/mpv/client.h")
    message(STATUS "  Detected nested structure (include/mpv/), flattening...")
    file(COPY
      "${CMAKE_BINARY_DIR}/${LIBMPV_TOP}/include/mpv/"
      DESTINATION "${CMAKE_BINARY_DIR}/${LIBMPV_TOP}/include/"
    )
    file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/${LIBMPV_TOP}/include/mpv")
  elseif(EXISTS "${CMAKE_BINARY_DIR}/${LIBMPV_TOP}/include/client.h")
    message(STATUS "  Detected flat structure, no flattening needed.")
  else()
    message(FATAL_ERROR "Unexpected libmpv archive structure. Cannot find client.h")
  endif()

  # 步骤3：重命名 → libmpv
  file(RENAME "${CMAKE_BINARY_DIR}/${LIBMPV_TOP}" "${LIBMPV_SRC}")
  message(STATUS "libmpv ready: ${LIBMPV_SRC}")
endif()

# ==============================================================================
# ANGLE — mmozeiko/build-angle
# ==============================================================================

if(${FLUTTER_TARGET_PLATFORM} STREQUAL "windows-x64")
  set(ANGLE "angle-x64-2026-06-27.zip")
  set(ANGLE_URL "https://github.com/mmozeiko/build-angle/releases/download/2026-06-27/${ANGLE}")
  set(ANGLE_TOP "angle-x64")
else()
  set(ANGLE "angle-arm64-2026-06-27.zip")
  set(ANGLE_URL "https://github.com/mmozeiko/build-angle/releases/download/2026-06-27/${ANGLE}")
  set(ANGLE_TOP "angle-arm64")
endif()
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

if(NOT EXISTS "${ANGLE_ARCHIVE}")
  message(STATUS "Downloading ANGLE from ${ANGLE_URL}...")
  file(DOWNLOAD "${ANGLE_URL}" "${ANGLE_ARCHIVE}" SHOW_PROGRESS)
endif()

if(NOT EXISTS "${ANGLE_SRC}/include/EGL/egl.h")
  message(STATUS "Extracting ANGLE...")

  file(REMOVE_RECURSE "${ANGLE_SRC}")
  file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/${ANGLE_TOP}")

  execute_process(
    COMMAND "${SEVENZ_EXECUTABLE}" x "${ANGLE_ARCHIVE}" "-o${CMAKE_BINARY_DIR}" -y
    RESULT_VARIABLE _r
  )
  if(NOT _r EQUAL 0)
    message(FATAL_ERROR "7z extract ANGLE failed: exit ${_r}")
  endif()

  file(RENAME "${CMAKE_BINARY_DIR}/${ANGLE_TOP}" "${ANGLE_SRC}")
  message(STATUS "ANGLE ready: ${ANGLE_SRC}")
endif()

# ==============================================================================
# 构建 Flutter 插件
# ==============================================================================
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/bin/d3dcompiler_47.dll"
  "${ANGLE_SRC}/bin/libEGL.dll"
  "${ANGLE_SRC}/bin/libGLESv2.dll"
  PARENT_SCOPE
)
