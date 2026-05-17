#!/usr/bin/env bash
# Install system libraries required by Qt6GuiConfig.cmake (xcb, xkbcommon) in CI.
# Tries emerge (Gentoo with synced Portage), then vcpkg (/opt/vcpkg), then apt-get.
# If none succeed, injects cmake stubs directly into Qt's lib/cmake tree so that
# Qt's internal find_dependency(WrapXxx NO_DEFAULT_PATH) mechanism finds them.
set -euo pipefail

append_cmake_prefix_path() {
    local path="$1"
    if [[ -z "${GITHUB_ENV:-}" ]]; then return; fi
    local existing="${CMAKE_PREFIX_PATH:-}"
    local merged="${path}${existing:+:${existing}}"
    # Export so subsequent calls in this script see the accumulated value.
    export CMAKE_PREFIX_PATH="${merged}"
    echo "CMAKE_PREFIX_PATH=${merged}" >> "${GITHUB_ENV}"
    echo "Added ${path} to CMAKE_PREFIX_PATH"
}

# Qt's Wrap* cmake config files live inside lib/cmake/WrapXxx/ subdirectories.
# Qt6Config.cmake sets _qt_additional_packages_prefix_paths = lib/cmake and then
# searches for each dependency with NO_DEFAULT_PATH (ignoring CMAKE_PREFIX_PATH
# and $ENV{CMAKE_PREFIX_PATH} entirely). Adding Qt6's cmake dir to the env prefix
# path is still useful for direct find_package callers that use the normal search.
if [[ -n "${QT_ROOT_DIR:-}" && -d "${QT_ROOT_DIR}/lib/cmake/Qt6" ]]; then
    append_cmake_prefix_path "${QT_ROOT_DIR}/lib/cmake/Qt6"
    echo "Added Qt6 cmake dir to CMAKE_PREFIX_PATH for Wrap* module discovery"
fi

# Diagnostic: show what find_dependency calls Qt6GuiDependencies.cmake actually makes.
QT_GUI_DEPS="${QT_ROOT_DIR:-}/lib/cmake/Qt6Gui/Qt6GuiDependencies.cmake"
if [[ -f "${QT_GUI_DEPS}" ]]; then
    echo "=== Qt6GuiDependencies.cmake find_dependency calls ==="
    grep -E 'find_dependency|find_package' "${QT_GUI_DEPS}" || echo "(none found)"
    echo "======================================================"
fi

privilege=()
if [[ "$(id -u)" != "0" ]] && command -v sudo &>/dev/null; then
    privilege=(sudo)
fi

# --- Gentoo (Portage) ---
if command -v emerge &>/dev/null && [[ -d /var/db/repos/gentoo ]]; then
    "${privilege[@]+"${privilege[@]}"}" emerge --noreplace --getbinpkg \
        x11-libs/libxcb \
        x11-libs/libxkbcommon \
        x11-libs/xcb-util-wm \
        x11-libs/xcb-util-image \
        x11-libs/xcb-util-keysyms \
        x11-libs/xcb-util-renderutil \
        media-libs/mesa
    exit 0
fi

# --- vcpkg (fallback when Portage is unavailable) ---
VCPKG="${VCPKG_INSTALLATION_ROOT:-/opt/vcpkg}/vcpkg"
if [[ -x "${VCPKG}" ]]; then
    TRIPLET="x64-linux"
    if "${VCPKG}" install "libxcb:${TRIPLET}" "libxkbcommon:${TRIPLET}" 2>&1; then
        INSTALLED="$(dirname "${VCPKG}")/installed/${TRIPLET}"
        [[ -d "${INSTALLED}" ]] && append_cmake_prefix_path "${INSTALLED}"
        exit 0
    fi
    echo "::warning::vcpkg could not install libxcb/libxkbcommon; falling through to apt-get."
fi

# --- apt-get (Debian/Ubuntu) ---
if command -v apt-get &>/dev/null; then
    "${privilege[@]+"${privilege[@]}"}" apt-get update -y
    "${privilege[@]+"${privilege[@]}"}" apt-get install -y \
        cmake \
        ninja-build \
        libgl1-mesa-dev \
        libxcb1-dev \
        libxcb-render0-dev \
        libxcb-shape0-dev \
        libxcb-xfixes0-dev \
        libxcb-icccm4-dev \
        libxcb-image0-dev \
        libxcb-keysyms1-dev \
        libxcb-renderutil0-dev \
        libxkbcommon-dev \
        libxkbcommon-x11-dev
    exit 0
fi

echo "::warning::Could not install Qt6Gui system dependencies (no emerge, vcpkg, or apt-get found)."

# --- cmake stubs injected into Qt's cmake tree (last resort for Beman Gentoo CI) ---
#
# Qt's internal find_dependency for Wrap* packages uses NO_DEFAULT_PATH with
# PATHS = _qt_additional_packages_prefix_paths (= ${QT_ROOT_DIR}/lib/cmake).
# Regular CMAKE_PREFIX_PATH entries are ignored by this mechanism.
#
# By writing stub WrapXxxConfig.cmake files directly into Qt's lib/cmake/WrapXxx/
# subdirectories, we place them exactly where Qt's cmake search will look —
# without modifying any cmake command-line arguments.
#
# The stubs declare FOUND=TRUE and create empty INTERFACE IMPORTED targets.
# This is sufficient for cmake to configure successfully and emit
# compile_commands.json for clang-tidy. It is NOT suitable for real linking.
if [[ -n "${QT_ROOT_DIR:-}" && -d "${QT_ROOT_DIR}/lib/cmake" ]]; then
    QT_LIB_CMAKE="${QT_ROOT_DIR}/lib/cmake"

    make_wrap_stub() {
        local pkg="$1"
        local dir="${QT_LIB_CMAKE}/${pkg}"
        mkdir -p "${dir}"
        cat > "${dir}/${pkg}Config.cmake" << EOF
# CI stub: ${pkg} -- empty INTERFACE target for clang-tidy analysis only.
if(NOT TARGET ${pkg}::${pkg})
    add_library(${pkg}::${pkg} INTERFACE IMPORTED)
endif()
set(${pkg}_FOUND TRUE)
EOF
        echo "  Wrote stub: ${dir}/${pkg}Config.cmake"
    }

    echo "Writing cmake stubs into ${QT_LIB_CMAKE} for clang-tidy CI analysis:"
    # Cover all Wrap* packages that Qt6GuiDependencies.cmake may require.
    # The stubs replace Qt's own configs (which would fail on missing system libs).
    make_wrap_stub WrapOpenGL
    make_wrap_stub WrapEGL
    make_wrap_stub WrapVulkanHeaders
    make_wrap_stub WrapXCB
    make_wrap_stub WrapXkbCommon
    make_wrap_stub WrapFreetype
    make_wrap_stub WrapHarfbuzz
    make_wrap_stub WrapZLIB
fi
