#!/usr/bin/env bash
# Consumer CI/local helper: install Qt 6 when needed and expose it to CMake.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${script_dir}/install-qt.py" --ensure --export-github-env "$@"
