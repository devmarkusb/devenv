#!/usr/bin/env bash
# Install system libraries required by Qt6GuiConfig.cmake in CI.
# Tries emerge (Gentoo with synced Portage), then vcpkg (/opt/vcpkg), then apt-get.
# Last resort: create cmake stubs in /tmp/qt-redirects/ for use with
# CMAKE_FIND_PACKAGE_REDIRECTS_DIR — the one cmake mechanism that is checked
# before NO_DEFAULT_PATH restricts the search (which Qt's internal find_dependency
# uses for its Wrap* packages).
set -euo pipefail

append_cmake_prefix_path() {
    local path="$1"
    if [[ -z "${GITHUB_ENV:-}" ]]; then return; fi
    local existing="${CMAKE_PREFIX_PATH:-}"
    local merged="${path}${existing:+:${existing}}"
    export CMAKE_PREFIX_PATH="${merged}"
    echo "CMAKE_PREFIX_PATH=${merged}" >> "${GITHUB_ENV}"
    echo "Added ${path} to CMAKE_PREFIX_PATH"
}

# Always add Qt6's cmake dir to CMAKE_PREFIX_PATH for direct find_package callers
# that use the standard search path (not Qt's NO_DEFAULT_PATH mechanism).
if [[ -n "${QT_ROOT_DIR:-}" && -d "${QT_ROOT_DIR}/lib/cmake/Qt6" ]]; then
    append_cmake_prefix_path "${QT_ROOT_DIR}/lib/cmake/Qt6"
fi

# Diagnostic: print the find_dependency calls made by Qt6GuiDependencies.cmake.
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

# --- vcpkg ---
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

# --- CMAKE_FIND_PACKAGE_REDIRECTS_DIR stubs ---
#
# cmake checks CMAKE_FIND_PACKAGE_REDIRECTS_DIR before all other locations,
# including before NO_DEFAULT_PATH restricts the search — unlike CMAKE_PREFIX_PATH
# entries, which Qt's internal find_dependency(WrapXxx ... NO_DEFAULT_PATH) ignores.
#
# Files here are named <PackageName>Config.cmake (no subdirectory). They create
# empty INTERFACE IMPORTED targets, satisfying cmake configuration and
# compile_commands.json generation for clang-tidy without the system libs.
#
# The caller must pass -DCMAKE_FIND_PACKAGE_REDIRECTS_DIR=/tmp/qt-redirects
# to the cmake invocation (done via extra_cmake_args in clang-tidy.yml).
REDIRECTS_DIR="/tmp/qt-redirects"
mkdir -p "${REDIRECTS_DIR}"

make_stub() {
    local pkg="$1"
    cat > "${REDIRECTS_DIR}/${pkg}Config.cmake" << EOF
# CI stub: ${pkg} — empty INTERFACE target for clang-tidy analysis only.
if(NOT TARGET ${pkg}::${pkg})
    add_library(${pkg}::${pkg} INTERFACE IMPORTED)
endif()
set(${pkg}_FOUND TRUE)
EOF
}

echo "Writing cmake stubs in ${REDIRECTS_DIR}/ (CMAKE_FIND_PACKAGE_REDIRECTS_DIR):"
make_stub WrapOpenGL
make_stub WrapEGL
make_stub WrapVulkanHeaders
make_stub WrapXCB
make_stub WrapXkbCommon
make_stub WrapFreetype
make_stub WrapHarfbuzz
make_stub WrapZLIB
echo "  Done. Pass -DCMAKE_FIND_PACKAGE_REDIRECTS_DIR=${REDIRECTS_DIR} to cmake."
