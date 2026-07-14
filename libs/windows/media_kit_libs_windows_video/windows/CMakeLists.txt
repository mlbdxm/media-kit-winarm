# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

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
  # 检查归档文件是否已存在
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # MD5 不匹配则删除，重新下载
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 不匹配，已删除旧文件。")
    endif()
  endif()

  # 文件不存在则下载
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "正在从 ${url} 下载归档文件...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "已下载归档文件到 ${locationForArchive}。")

    # 校验新下载文件的 MD5
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} 校验通过。")
    else()
      message(FATAL_ERROR "${locationForArchive} 完整性校验失败，请尝试重新构建项目。")
    endif()
  endif()
endfunction()

# ==============================================================================
# 工具函数：检查目录是否存在且非空
# ==============================================================================
function(check_directory_exists_and_not_empty dir result_var)
  if(EXISTS "${dir}")
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "目录 ${dir} 存在但为空!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "目录 ${dir} 不存在!")
  endif()
endfunction()

# ==============================================================================
# 7-Zip 解压工具（优先使用系统已安装的，否则自动下载）
# ==============================================================================

# 第1步：查找系统已安装的 7z
find_program(SEVENZ_EXECUTABLE 7z
  PATHS
    "C:/Program Files/7-Zip"
    "C:/Program Files (x86)/7-Zip"
    "$ENV{ProgramFiles}/7-Zip"
    "$ENV{ProgramFiles\(x86\)}/7-Zip"
)

# 第2步：找不到则自动下载 7-Zip Extra
if(NOT SEVENZ_EXECUTABLE)
  set(SEVENZ_URL "https://www.7-zip.org/a/7z2409-extra.7z")
  set(SEVENZ_ARCHIVE "${CMAKE_BINARY_DIR}/7z-extra.7z")
  set(SEVENZ_DIR "${CMAKE_BINARY_DIR}/7z-extra")

  if(NOT EXISTS "${SEVENZ_DIR}")
    if(NOT EXISTS "${SEVENZ_ARCHIVE}")
      message(STATUS "正在从 ${SEVENZ_URL} 下载 7-Zip Extra...")
      file(DOWNLOAD "${SEVENZ_URL}" "${SEVENZ_ARCHIVE}" SHOW_PROGRESS)
    endif()
    message(STATUS "正在解压 7-Zip Extra...")
    file(ARCHIVE_EXTRACT INPUT "${SEVENZ_ARCHIVE}" DESTINATION "${SEVENZ_DIR}")
  endif()

  if(EXISTS "${SEVENZ_DIR}/x64/7za.exe")
    set(SEVENZ_EXECUTABLE "${SEVENZ_DIR}/x64/7za.exe")
  elseif(EXISTS "${SEVENZ_DIR}/7za.exe")
    set(SEVENZ_EXECUTABLE "${SEVENZ_DIR}/7za.exe")
  elseif(EXISTS "${SEVENZ_DIR}/x86/7za.exe")
    set(SEVENZ_EXECUTABLE "${SEVENZ_DIR}/x86/7za.exe")
  endif()
endif()

if(NOT SEVENZ_EXECUTABLE)
  message(FATAL_ERROR "未找到 7-Zip 且自动下载失败。请手动安装: winget install 7zip.7zip")
endif()

message(STATUS "使用 7-Zip: ${SEVENZ_EXECUTABLE}")

# ==============================================================================
# libmpv（mpv 播放器核心库）
# ------------------------------------------------------------------------------
# media_kit_video 插件期望的目录结构：
#   libmpv/
#     include/
#       client.h          ← 头文件直接在 include/ 下
#       render.h
#       render_gl.h
#       stream_cb.h
#     libmpv-2.dll
#     libmpv.dll.a
#
# 所以需要：解压 → 把 include/mpv/*.h 提一层到 include/ → 删除 include/mpv/ → 重命名为 libmpv
# ==============================================================================

if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
  # ---- Windows ARM64 ----
  set(LIBMPV "mpv-dev-aarch64-20260610-git-304426c.7z")
  set(LIBMPV_URL "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/${LIBMPV}")
  set(LIBMPV_MD5 "fd3099a41b51c643dd64e93958ada7e6")
  set(LIBMPV_DIR "mpv-dev-aarch64-20260610-git-304426c")
else()
  # ---- Windows x64 ----
  set(LIBMPV "mpv-dev-x86_64-v3-20260610-git-304426c.7z")
  set(LIBMPV_URL "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/${LIBMPV}")
  set(LIBMPV_MD5 "497cceffc0f498c0c8745c8ec9bf32ba")
  set(LIBMPV_DIR "mpv-dev-x86_64-v3-20260610-git-304426c")
endif()
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")
download_and_verify(${LIBMPV_URL} ${LIBMPV_MD5} ${LIBMPV_ARCHIVE})
check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)
if(NOT LIBMPV_SRC_VALID)
  message(STATUS "正在解压 ${LIBMPV}...")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT" POST_BUILD

    # --------------------------------------------------------------------------
    # 第1步：解压 7z 到 CMAKE_BINARY_DIR
    #         解压后产生 ${LIBMPV_DIR}/ 目录（如 mpv-dev-aarch64-20260610-git-304426c/）
    # --------------------------------------------------------------------------
    COMMAND "${SEVENZ_EXECUTABLE}" x "${LIBMPV_ARCHIVE}" -o"${CMAKE_BINARY_DIR}" -y

    # --------------------------------------------------------------------------
    # 第2步：把 include/mpv/*.h 逐个拷贝到 include/（消除 mpv/ 这一层）
    #         用 copy_if_different 而不是 copy_directory，因为 Windows 上
    #         copy_directory 在目标已存在时会失败
    # --------------------------------------------------------------------------
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/mpv/client.h"
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/client.h"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/mpv/render.h"
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/render.h"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/mpv/render_gl.h"
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/render_gl.h"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/mpv/stream_cb.h"
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/stream_cb.h"

    # --------------------------------------------------------------------------
    # 第3步：删除原来的 include/mpv/ 子目录（头文件已提到上层）
    # --------------------------------------------------------------------------
    COMMAND ${CMAKE_COMMAND} -E remove_directory
      "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/mpv"

    # --------------------------------------------------------------------------
    # 第4步：重命名 ${LIBMPV_DIR} → libmpv（media_kit_video 期望的名字）
    # --------------------------------------------------------------------------
    COMMAND ${CMAKE_COMMAND} -E rename "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}" "${LIBMPV_SRC}"

    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
  )
endif()


# ==============================================================================
# ANGLE（OpenGL ES → Direct3D 翻译层，用于视频渲染）
# ------------------------------------------------------------------------------
# mmozeiko/build-angle 发布的 zip 包解压后目录结构（以 ARM64 为例）：
#   angle-arm64/
#     include/
#       EGL/
#         egl.h
#       GLES2/
#       GLES3/
#       KHR/
#     bin/
#       libEGL.dll
#       libGLESv2.dll
#       d3dcompiler_47.dll
#     lib/
#       libEGL.dll.lib
#       libGLESv2.dll.lib
#
# media_kit_video 插件期望的目录结构：
#   ANGLE/
#     include/
#       EGL/
#         egl.h
#     bin/
#       libEGL.dll
#       ...
#     lib/
#       ...
#
# 所以需要：解压 → 重命名 angle-arm64 → ANGLE（消除 angle-arm64 这一层）
# ==============================================================================

if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
  # ---- Windows ARM64 ----
  set(ANGLE "angle-arm64-2026-06-27.zip")
  set(ANGLE_URL "https://github.com/mmozeiko/build-angle/releases/download/2026-06-27/${ANGLE}")
  set(ANGLE_DIR "angle-arm64")
else()
  # ---- Windows x64 ----
  set(ANGLE "angle-x64-2026-06-27.zip")
  set(ANGLE_URL "https://github.com/mmozeiko/build-angle/releases/download/2026-06-27/${ANGLE}")
  set(ANGLE_DIR "angle-x64")
endif()
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")
if(NOT EXISTS "${ANGLE_ARCHIVE}")
  message(STATUS "正在从 ${ANGLE_URL} 下载 ANGLE...")
  file(DOWNLOAD "${ANGLE_URL}" "${ANGLE_ARCHIVE}" SHOW_PROGRESS)
endif()
check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)
if(NOT ANGLE_SRC_VALID)
  message(STATUS "正在解压 ${ANGLE}...")
  add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_ANGLE_EXTRACT" POST_BUILD

    # --------------------------------------------------------------------------
    # 第1步：解压到 CMAKE_BINARY_DIR
    #         解压后产生 ${ANGLE_DIR}/ 目录（如 angle-arm64/）
    # --------------------------------------------------------------------------
    COMMAND "${SEVENZ_EXECUTABLE}" x "${ANGLE_ARCHIVE}" -o"${CMAKE_BINARY_DIR}" -y

    # --------------------------------------------------------------------------
    # 第2步：重命名 ${ANGLE_DIR} → ANGLE（消除 angle-arm64/ 这一层）
    #         ANGLE 内部已有 include/、bin/、lib/ 子目录，无需额外处理
    # --------------------------------------------------------------------------
    COMMAND ${CMAKE_COMMAND} -E rename "${CMAKE_BINARY_DIR}/${ANGLE_DIR}" "${ANGLE_SRC}"

    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
  )
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

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
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
# 导出捆绑 DLL 列表（供 media_kit_video 等上级插件使用）
# ==============================================================================
set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/bin/d3dcompiler_47.dll"
  "${ANGLE_SRC}/bin/libEGL.dll"
  "${ANGLE_SRC}/bin/libGLESv2.dll"
  PARENT_SCOPE
)
