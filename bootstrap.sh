#!/usr/bin/env bash
set -e

# Prefer running from repo root (parent of devenv) so .venv and hooks live in the project
if [ -n "${BASH_SOURCE[0]}" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="$(cd "${script_dir}/.." && pwd)"
    if [ -d "${repo_root}/.git" ] && [ "$(pwd)" != "${repo_root}" ]; then
        echo "Running from repo root for consistent .venv and pre-commit setup."
        cd "${repo_root}"
    fi
fi

if [ ! -d .venv ]; then
    python3 -m venv .venv
fi
# shellcheck source=/dev/null
source .venv/bin/activate
pip install -q --upgrade pip
pip install -q pre-commit
pre-commit install
