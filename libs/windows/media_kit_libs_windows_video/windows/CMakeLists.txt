# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.18)  # 需要 3.18 才支持 file(ARCHIVE_EXTRACT) 解压 7z

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
      message(STATUS "MD5 不匹配，已删除旧文件。")
    endif()
  endif()
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "正在从 ${url} 下载...")
    file(DOWNLOAD "${url}" "${locationForArchive}" SHOW_PROGRESS)
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      message(FATAL_ERROR "${locationForArchive} 完整性校验失败，请重新构建。")
    endif()
    message(STATUS "${locationForArchive} 下载并校验通过。")
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
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
  endif()
endfunction()

# ==============================================================================
# libmpv（mpv 播放器核心库）
# ------------------------------------------------------------------------------
# shinchiro 的 ARM64 7z 包解压后结构：
#   mpv-dev-aarch64-20260610-git-304426c/
#     include/
#       mpv/              ← 多了一层！media_kit_video 期望 include/client.h
#         client.h
#         render.h
#         render_gl.h
#         stream_cb.h
#     libmpv-2.dll
#     libmpv.dll.a
#
# 我们在 CMake 配置阶段用 file(ARCHIVE_EXTRACT) 解压，
# 然后把 include/mpv/*.h 拷贝到 include/，删除 mpv/ 子目录，再重命名为 libmpv。
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

# 下载（如果还没下载或 MD5 不匹配）
download_and_verify(${LIBMPV_URL} ${LIBMPV_MD5} ${LIBMPV_ARCHIVE})

# 如果目标目录中缺少关键文件 client.h，则（重新）解压
if(NOT EXISTS "${LIBMPV_SRC}/include/client.h")
  message(STATUS "正在解压 ${LIBMPV}（CMake 配置阶段）...")

  # 先清理可能存在的残留目录
  file(REMOVE_RECURSE "${LIBMPV_SRC}")
  file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}")

  # 步骤1：用 CMake 内置的解压功能解压 7z 到构建目录
  #         file(ARCHIVE_EXTRACT) 是 CMake 3.18+ 的内置功能，不依赖外部 7z
  file(ARCHIVE_EXTRACT INPUT "${LIBMPV_ARCHIVE}" DESTINATION "${CMAKE_BINARY_DIR}")

  # 步骤2：把 include/mpv/*.h 拷贝到 include/（消除 mpv/ 这一层）
  file(COPY "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/mpv/"
       DESTINATION "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/")

  # 步骤3：删除多余的 include/mpv/ 空目录
  file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}/include/mpv")

  # 步骤4：重命名为 libmpv
  file(RENAME "${CMAKE_BINARY_DIR}/${LIBMPV_DIR}" "${LIBMPV_SRC}")

  message(STATUS "libmpv 解压完成 → ${LIBMPV_SRC}")
endif()


# ==============================================================================
# ANGLE（OpenGL ES → Direct3D 翻译层）
# ------------------------------------------------------------------------------
# mmozeiko 的 ARM64 zip 包解压后结构：
#   angle-arm64/
#     include/
#       EGL/egl.h
#       GLES2/ GLES3/ KHR/
#     bin/
#       libEGL.dll, libGLESv2.dll, d3dcompiler_47.dll
#     lib/
#       libEGL.dll.lib, libGLESv2.dll.lib
#
# media_kit_video 期望 ANGLE/include/EGL/egl.h，所以只需把 angle-arm64 重命名为 ANGLE。
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

# 下载 ANGLE
if(NOT EXISTS "${ANGLE_ARCHIVE}")
  message(STATUS "正在从 ${ANGLE_URL} 下载 ANGLE...")
  file(DOWNLOAD "${ANGLE_URL}" "${ANGLE_ARCHIVE}" SHOW_PROGRESS)
endif()

# 如果目标目录中缺少关键文件 egl.h，则（重新）解压
if(NOT EXISTS "${ANGLE_SRC}/include/EGL/egl.h")
  message(STATUS "正在解压 ${ANGLE}（CMake 配置阶段）...")

  # 先清理可能存在的残留
  file(REMOVE_RECURSE "${ANGLE_SRC}")
  file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/${ANGLE_DIR}")

  # 步骤1：解压 zip 到构建目录（CMake 内置功能）
  file(ARCHIVE_EXTRACT INPUT "${ANGLE_ARCHIVE}" DESTINATION "${CMAKE_BINARY_DIR}")

  # 步骤2：重命名 angle-arm64 → ANGLE
  file(RENAME "${CMAKE_BINARY_DIR}/${ANGLE_DIR}" "${ANGLE_SRC}")

  message(STATUS "ANGLE 解压完成 → ${ANGLE_SRC}")
endif()

# ==============================================================================
# 构建 Flutter 插件（纯占位 DLL，真正的逻辑在 media_kit_video 中）
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
