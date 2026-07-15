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
# libmpv — shinchiro/mpv-winbuild-cmake
#
# 7z 包结构（有顶层目录）：
#   mpv-dev-aarch64-.../
#     include/
#       mpv/
#         client.h, render.h, render_gl.h, stream_cb.h
#     libmpv-2.dll, libmpv.dll.a
#
# media_kit 需要: libmpv/include/client.h
# ==============================================================================
if(${FLUTTER_TARGET_PLATFORM} STREQUAL "windows-x64")
  set(LIBMPV "mpv-dev-x86_64-v3-20260610-git-304426c.7z")
  set(LIBMPV_URL "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/${LIBMPV}")
  set(LIBMPV_MD5 "497cceffc0f498c0c8745c8ec9bf32ba")
else()
  set(LIBMPV "mpv-dev-aarch64-20260610-git-304426c.7z")
  set(LIBMPV_URL "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/${LIBMPV}")
  set(LIBMPV_MD5 "fd3099a41b51c643dd64e93958ada7e6")
endif()
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

download_and_verify(${LIBMPV_URL} ${LIBMPV_MD5} ${LIBMPV_ARCHIVE})

if(NOT EXISTS "${LIBMPV_SRC}/include/client.h")
  message(STATUS "Extracting libmpv...")

  # 清理残留
  file(REMOVE_RECURSE "${LIBMPV_SRC}")

  # 步骤1：解压到 libmpv/（包有顶层目录，解压后 libmpv/ 下面多一层）
  execute_process(
    COMMAND "${SEVENZ_EXECUTABLE}" x "${LIBMPV_ARCHIVE}" "-o${LIBMPV_SRC}" -y
    RESULT_VARIABLE _r
  )
  if(NOT _r EQUAL 0)
    message(FATAL_ERROR "7z extract libmpv failed: exit ${_r}")
  endif()

  # 步骤2：GLOB 找到唯一的顶层子目录
  file(GLOB _subdirs LIST_DIRECTORIES true "${LIBMPV_SRC}/*")
  list(LENGTH _subdirs _count)
  if(_count EQUAL 0)
    message(FATAL_ERROR "Unexpected libmpv archive structure: no subdirectory found")
  endif()
  list(GET _subdirs 0 _topdir)

  # 步骤3：把顶层目录内容提到 libmpv/ 根目录
  #        先删掉刚创建的空 libmpv/，再把 _topdir 重命名为 libmpv
  file(RENAME "${_topdir}" "${CMAKE_BINARY_DIR}/_libmpv_rename_tmp")
  file(REMOVE_RECURSE "${LIBMPV_SRC}")
  file(RENAME "${CMAKE_BINARY_DIR}/_libmpv_rename_tmp" "${LIBMPV_SRC}")

  # 步骤4：扁平化 include/mpv/* → include/
  if(EXISTS "${LIBMPV_SRC}/include/mpv/client.h")
    message(STATUS "  Flattening include/mpv/ → include/")
    file(COPY "${LIBMPV_SRC}/include/mpv/" DESTINATION "${LIBMPV_SRC}/include/")
    file(REMOVE_RECURSE "${LIBMPV_SRC}/include/mpv")
  endif()

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
