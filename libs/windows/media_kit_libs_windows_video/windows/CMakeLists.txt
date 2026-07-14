# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
function(download_and_verify url md5 locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify MD5 of the newly downloaded file.
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
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

# ============ 7-Zip ============

# 1. 先找系统已安装的 7z
find_program(SEVENZ_EXECUTABLE 7z
  PATHS
    "C:/Program Files/7-Zip"
    "C:/Program Files (x86)/7-Zip"
    "$ENV{ProgramFiles}/7-Zip"
    "$ENV{ProgramFiles\(x86\)}/7-Zip"
)

# 2. 找不到则下载最新 7-Zip Extra
if(NOT SEVENZ_EXECUTABLE)
  set(SEVENZ_URL "https://www.7-zip.org/a/7z2409-extra.7z")
  set(SEVENZ_ARCHIVE "${CMAKE_BINARY_DIR}/7z-extra.7z")
  set(SEVENZ_DIR "${CMAKE_BINARY_DIR}/7z-extra")

  if(NOT EXISTS "${SEVENZ_DIR}")
    if(NOT EXISTS "${SEVENZ_ARCHIVE}")
      message(STATUS "Downloading 7-Zip Extra from ${SEVENZ_URL}...")
      file(DOWNLOAD "${SEVENZ_URL}" "${SEVENZ_ARCHIVE}" SHOW_PROGRESS)
    endif()
    message(STATUS "Extracting 7-Zip Extra...")
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
  message(FATAL_ERROR "7-Zip not found and auto-download failed. Install: winget install 7zip.7zip")
endif()

message(STATUS "Using 7-Zip: ${SEVENZ_EXECUTABLE}")

# ============ libmpv ============

if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
  set(LIBMPV "mpv-dev-aarch64-20260610-git-304426c.7z")
  set(LIBMPV_URL "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/${LIBMPV}")
  set(LIBMPV_MD5 "fd3099a41b51c643dd64e93958ada7e6")
else()
  set(LIBMPV "mpv-dev-x86_64-v3-20260610-git-304426c.7z")
  set(LIBMPV_URL "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/${LIBMPV}")
  set(LIBMPV_MD5 "497cceffc0f498c0c8745c8ec9bf32ba")
endif()

set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

download_and_verify(
  ${LIBMPV_URL}
  ${LIBMPV_MD5}
  ${LIBMPV_ARCHIVE}
)

check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  make_directory("${LIBMPV_SRC}")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT" POST_BUILD
    COMMAND "${SEVENZ_EXECUTABLE}" x "${LIBMPV_ARCHIVE}" -o"${LIBMPV_SRC}" -y
    WORKING_DIRECTORY "${LIBMPV_SRC}"
  )
endif()

# ============ ANGLE (ARM64 & x64 from mmozeiko/build-angle) ============

if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
  set(ANGLE "angle-arm64-2026-06-27.zip")
  set(ANGLE_URL "https://github.com/mmozeiko/build-angle/releases/download/2026-06-27/${ANGLE}")
  set(ANGLE_DIR "angle-arm64")
else()
  set(ANGLE "angle-x64-2026-06-27.zip")
  set(ANGLE_URL "https://github.com/mmozeiko/build-angle/releases/download/2026-06-27/${ANGLE}")
  set(ANGLE_DIR "angle-x64")
endif()

set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE/${ANGLE_DIR}")

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
    TARGET "${PROJECT_NAME}_ANGLE_EXTRACT" POST_BUILD
    COMMAND "${SEVENZ_EXECUTABLE}" x "${ANGLE_ARCHIVE}" -o"${CMAKE_BINARY_DIR}/ANGLE" -y
    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/ANGLE"
  )
endif()

# ------------------------------------------------------------------------------
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

# DLL 在新 ANGLE 包的 bin/ 目录下
set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/bin/d3dcompiler_47.dll"
  "${ANGLE_SRC}/bin/libEGL.dll"
  "${ANGLE_SRC}/bin/libGLESv2.dll"
  PARENT_SCOPE
)
