#!/usr/bin/env bash
# Sync .clang-format from devmarkusb/clangformat (versioned configs).
# Usage: cd devenv && ./sync-clang-format.sh [VERSION]
#   VERSION = clang-format major (e.g. 22, 14). Default: from .pre-commit-config.yaml rev or 22.
# Writes to repo root .clang-format. Run from inside the devenv directory.

set -e

CLANGFORMAT_REPO="${CLANGFORMAT_REPO:-https://github.com/devmarkusb/clangformat}"
CLANGFORMAT_BRANCH="${CLANGFORMAT_BRANCH:-main}"

# Repo root = parent of directory containing this script
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
output_file="${repo_root}/.clang-format"

# Resolve version: arg > env > from .pre-commit-config.yaml > default 22
resolve_version() {
    if [ -n "$1" ]; then
        echo "$1"
        return
    fi
    if [ -n "${CLANGFORMAT_VERSION}" ]; then
        echo "${CLANGFORMAT_VERSION}"
        return
    fi
    local precommit="${repo_root}/.pre-commit-config.yaml"
    if [ -f "${precommit}" ]; then
        # mirrors-clang-format rev: v22.1.0 → 22
        if grep -q "mirrors-clang-format" "${precommit}" 2>/dev/null; then
            local rev
            rev=$(grep -A 5 "mirrors-clang-format" "${precommit}" | grep "rev:" | head -1 | sed -n 's/.*rev: *v\([0-9]*\).*/\1/p')
            if [ -n "${rev}" ]; then
                echo "${rev}"
                return
            fi
        fi
    fi
    echo "22"
}

version="$(resolve_version "$1")"
# Versioned URL (configs/v22/.clang-format); fallback to root .clang-format
base_url="https://raw.githubusercontent.com/devmarkusb/clangformat/${CLANGFORMAT_BRANCH}"
url_versioned="${base_url}/configs/v${version}/.clang-format"
url_default="${base_url}/.clang-format"

tmp_file="$(mktemp)"
cleanup() { rm -f "${tmp_file}"; }
trap cleanup EXIT

fetch_to() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -sSL --fail -o "${out}" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "${out}" "$url"
    else
        echo "Need curl or wget to fetch .clang-format." >&2
        exit 1
    fi
}

echo "Using clang-format config version: ${version}"
if fetch_to "${url_versioned}" "${tmp_file}" 2>/dev/null && [ -s "${tmp_file}" ] && ! head -1 "${tmp_file}" | grep -q "<!DOCTYPE"; then
    mv "${tmp_file}" "${output_file}"
    echo "Updated ${output_file} from configs/v${version}/.clang-format"
else
    fetch_to "${url_default}" "${tmp_file}"
    mv "${tmp_file}" "${output_file}"
    echo "Updated ${output_file} from root .clang-format"
fi
