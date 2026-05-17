#!/usr/bin/env bash
# Install system libraries required by Qt6GuiConfig.cmake (xcb, xkbcommon) in CI.
# Tries emerge (Gentoo with synced Portage), then vcpkg (/opt/vcpkg), then apt-get.
# If none succeed, creates cmake stubs for the missing Qt wrapper packages so that
# cmake can configure and produce compile_commands.json for clang-tidy analysis.
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

# Qt's Wrap* cmake config files (WrapOpenGL, WrapEGL, WrapXkbCommon, WrapXCB, …)
# live in lib/cmake/Qt6/, not in the standard lib/cmake/WrapXxx/ directories.
# They are normally found via _qt_additional_packages_prefix_paths set inside
# Qt6Config.cmake. When that variable is empty (observed in Beman CI), cmake
# cannot find them. Adding the Qt6 cmake subdirectory to CMAKE_PREFIX_PATH fixes
# discovery unconditionally.
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

# --- cmake stubs (last resort for Beman Gentoo CI without installable system libs) ---
# The stubs provide empty INTERFACE IMPORTED targets so cmake can configure
# successfully and produce compile_commands.json for clang-tidy. They are NOT
# suitable for compilation or linking — only for static analysis.
# Prepend the stubs directory BEFORE the Qt cmake dir so cmake finds our stubs
# first (Qt's real Wrap* configs would fail-fast when the system lib is absent).
if [[ -n "${QT_ROOT_DIR:-}" ]]; then
    STUBS_DIR="/tmp/qt-sys-stubs"
    mkdir -p "${STUBS_DIR}/lib/cmake"

    make_wrap_stub() {
        local pkg="$1"
        local dir="${STUBS_DIR}/lib/cmake/${pkg}"
        mkdir -p "${dir}"
        cat > "${dir}/${pkg}Config.cmake" << EOF
# CI stub: ${pkg} — empty INTERFACE target for clang-tidy analysis only.
if(NOT TARGET ${pkg}::${pkg})
    add_library(${pkg}::${pkg} INTERFACE IMPORTED)
endif()
set(${pkg}_FOUND TRUE)
EOF
    }

    # Known Qt6Gui PUBLIC find_dependency targets that require unavailable system libs.
    # Extend this list if a subsequent CI run shows more failing Wrap* packages.
    make_wrap_stub WrapOpenGL
    make_wrap_stub WrapEGL
    make_wrap_stub WrapXCB
    make_wrap_stub WrapXkbCommon
    make_wrap_stub WrapVulkanHeaders

    # Prepend stubs dir so it takes precedence over Qt's own Wrap* cmake configs.
    append_cmake_prefix_path "${STUBS_DIR}"
    echo "Created cmake stubs in ${STUBS_DIR} for clang-tidy CI analysis."
fi
