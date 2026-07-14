# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

# 修复 MSBuild 的 CMP0175 警告（官方最新版有这行）
cmake_policy(SET CMP0175 NEW)

# 这个选项会被 media_kit 家族的其他包读取
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# 解决 MSVC 兼容性问题
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ==============================================================================
# 工具函数：下载并校验 MD5
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
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  if(EXISTS "${dir}")
    file(GLOB dir_contents "${dir}/*")
    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# ==============================================================================
# 查找 7-Zip（解压 .7z 文件需要）
# ==============================================================================
find_program(SEVENZ_EXECUTABLE NAMES 7z 7za
  PATHS
    "C:/Program Files/7-Zip"
    "C:/Program Files (x86)/7-Zip"
    "$ENV{ProgramFiles}/7-Zip"
    "$ENV{ProgramFiles\(x86\)}/7-Zip"
)
if(SEVENZ_EXECUTABLE)
  message(STATUS "Using 7zip for extraction: ${SEVENZ_EXECUTABLE}")
else()
  message(FATAL_ERROR "7-Zip not found. Please install: winget install 7zip.7zip")
endif()

# ==============================================================================
# libmpv（mpv 播放器核心库）
# ------------------------------------------------------------------------------
# 使用 media-kit 官方维护的 libmpv-win32-video-cmake 构建（已包含 ARM64）
#
# 官方 7z 包解压后目录结构：
#   libmpv/
#     include/
#       mpv/                 ← 官方包的头文件在 include/mpv/ 子目录下
#         client.h
#         render.h
#         render_gl.h
#         stream_cb.h
#     libmpv-2.dll
#     libmpv.dll.a
#
# media_kit_video 期望: libmpv/include/client.h（无 mpv/ 子目录）
#
# 官方做法：解压到 libmpv/ → xcopy include/mpv → mpv/ → rmdir include/ → ren mpv include
# 完全用 Windows 原生命令，不依赖 cmake -E rename
# ==============================================================================

# 按 FLUTTER_TARGET_PLATFORM 判断架构（官方推荐方式）
if(${FLUTTER_TARGET_PLATFORM} STREQUAL "windows-x64")
  set(LIBMPV_ARCH "x86_64")
  set(LIBMPV "mpv-dev-x86_64-20241021-git-0f78584.7z")
  set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-cmake/releases/download/20241021/${LIBMPV}")
  set(LIBMPV_MD5 "6ecf18e85b093c3f7edb16f3ee6603f3")
else()
  set(LIBMPV_ARCH "aarch64")
  set(LIBMPV "mpv-dev-aarch64-20241021-git-0f78584.7z")
  set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-cmake/releases/download/20241021/${LIBMPV}")
  set(LIBMPV_MD5 "5b507a35db13eee6cb7eb21e8be7c83d")
endif()
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")
download_and_verify(${LIBMPV_URL} ${LIBMPV_MD5} ${LIBMPV_ARCHIVE})
check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  make_directory("${LIBMPV_SRC}")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
    POST_BUILD
    # 第1步：解压 7z 到 libmpv/（此时结构: libmpv/include/mpv/client.h）
    COMMAND "${SEVENZ_EXECUTABLE}" x -y "${LIBMPV_ARCHIVE}"
    # 第2步：把 include/mpv/ 拷贝到 mpv/（因为 include/ 需要被删除后重建）
    COMMAND xcopy "${LIBMPV_SRC}\\include\\mpv" "${LIBMPV_SRC}\\mpv" /E /H /C /I
    # 第3步：删除原来的 include/（包含 mpv/ 子目录）
    COMMAND rmdir "${LIBMPV_SRC}\\include" /S /Q
    # 第4步：重命名 mpv/ → include/（最终: libmpv/include/client.h ✓）
    COMMAND ren "${LIBMPV_SRC}\\mpv" "include"
    WORKING_DIRECTORY "${LIBMPV_SRC}"
  )
endif()

# ==============================================================================
# ANGLE（OpenGL ES → Direct3D 翻译层）
# ------------------------------------------------------------------------------
# 使用 mmozeiko/build-angle 的 ARM64 构建（官方 ANGLE 源不支持 ARM64）
#
# zip 包解压后目录结构：
#   ANGLE/
#     angle-arm64/                     ← 多了一层！
#       include/EGL/egl.h
#       bin/libEGL.dll, libGLESv2.dll
#       lib/libEGL.dll.lib
#
# media_kit_video 期望: ANGLE/include/EGL/egl.h
# 所以需要解压 → xcopy angle-arm64/* → ANGLE/ → rmdir angle-arm64
# ==============================================================================

if(${FLUTTER_TARGET_PLATFORM} STREQUAL "windows-x64")
  set(ANGLE "angle-x64-2026-06-27.zip")
  set(ANGLE_URL "https://github.com/mmozeiko/build-angle/releases/download/2026-06-27/${ANGLE}")
  set(ANGLE_DIR "angle-x64")
else()
  set(ANGLE "angle-arm64-2026-06-27.zip")
  set(ANGLE_URL "https://github.com/mmozeiko/build-angle/releases/download/2026-06-27/${ANGLE}")
  set(ANGLE_DIR "angle-arm64")
endif()
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

# 下载 ANGLE
if(NOT EXISTS "${ANGLE_ARCHIVE}")
  message(STATUS "Downloading ANGLE from ${ANGLE_URL}...")
  file(DOWNLOAD "${ANGLE_URL}" "${ANGLE_ARCHIVE}" SHOW_PROGRESS)
endif()

check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)
if(NOT ANGLE_SRC_VALID)
  message(STATUS "Extracting ${ANGLE}...")
  make_directory("${ANGLE_SRC}")
  add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
    POST_BUILD
    # 第1步：解压到 ANGLE/（此时结构: ANGLE/angle-arm64/include/EGL/egl.h）
    COMMAND "${SEVENZ_EXECUTABLE}" x -y "${ANGLE_ARCHIVE}"
    # 第2步：把 angle-arm64/* 的内容拷贝到 ANGLE/ 根目录
    COMMAND xcopy "${ANGLE_SRC}\\${ANGLE_DIR}" "${ANGLE_SRC}\\" /E /H /C /I /Y
    # 第3步：删除 angle-arm64/ 子目录
    COMMAND rmdir "${ANGLE_SRC}\\${ANGLE_DIR}" /S /Q
    WORKING_DIRECTORY "${ANGLE_SRC}"
  )
endif()

# ==============================================================================
# 构建 Flutter 插件（纯占位 DLL）
# ==============================================================================
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)
target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

# ==============================================================================
# 导出捆绑 DLL 列表
# ==============================================================================
set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  PARENT_SCOPE
)
