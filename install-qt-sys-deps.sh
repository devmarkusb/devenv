#!/usr/bin/env bash
# Install system libraries required by Qt6GuiConfig.cmake (xcb, xkbcommon) in CI.
# Tries emerge (Gentoo with synced Portage), then vcpkg (/opt/vcpkg), then apt-get.
set -euo pipefail

append_cmake_prefix_path() {
    local path="$1"
    if [[ -z "${GITHUB_ENV:-}" ]]; then return; fi
    local existing="${CMAKE_PREFIX_PATH:-}"
    local merged="${path}${existing:+:${existing}}"
    echo "CMAKE_PREFIX_PATH=${merged}" >> "${GITHUB_ENV}"
    echo "Added ${path} to CMAKE_PREFIX_PATH"
}

# --- Gentoo (Portage) ---
if command -v emerge &>/dev/null && [[ -d /var/db/repos/gentoo ]]; then
    privilege=()
    if [[ "$(id -u)" != "0" ]] && command -v sudo &>/dev/null; then
        privilege=(sudo -n)
    fi
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

# --- vcpkg (Beman infra-containers when Portage is unavailable) ---
VCPKG="${VCPKG_INSTALLATION_ROOT:-/opt/vcpkg}/vcpkg"
if [[ -x "${VCPKG}" ]]; then
    TRIPLET="x64-linux"
    "${VCPKG}" install \
        "libxcb:${TRIPLET}" \
        "libxkbcommon:${TRIPLET}"
    INSTALLED="$(dirname "${VCPKG}")/installed/${TRIPLET}"
    if [[ -d "${INSTALLED}" ]]; then
        append_cmake_prefix_path "${INSTALLED}"
    fi
    exit 0
fi

# --- apt-get (Ubuntu hosts) ---
if command -v apt-get &>/dev/null; then
    privilege=()
    if [[ "$(id -u)" != "0" ]] && command -v sudo &>/dev/null; then
        privilege=(sudo)
    fi
    "${privilege[@]+"${privilege[@]}"}" apt-get update -y
    "${privilege[@]+"${privilege[@]}"}" apt-get install -y \
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
