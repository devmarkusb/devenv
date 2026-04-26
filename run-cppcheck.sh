#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

preset="${1:-clang-release}"
build_dir="${2:-${repo_root}/build/${preset}}"
compile_commands="${build_dir}/compile_commands.json"
cppcheck_build_dir="${build_dir}/cppcheck"
suppression_file="${repo_root}/CppCheckSuppressions.txt"

cppcheck_bin="$(python3 "${script_dir}/install-cppcheck.py" --ensure --print-path)"

cmake -S "${repo_root}" --preset "${preset}" -B "${build_dir}"

if [[ ! -f "${compile_commands}" ]]; then
    echo "Expected compile database at '${compile_commands}' but it was not generated." >&2
    exit 1
fi

mkdir -p "${cppcheck_build_dir}"

suppression_args=()
if [[ -f "${suppression_file}" ]]; then
    suppression_args+=("--suppressions-list=${suppression_file}")
fi

"${cppcheck_bin}" \
    --project="${compile_commands}" \
    --cppcheck-build-dir="${cppcheck_build_dir}" \
    --enable=warning,style,performance,portability \
    --check-level=exhaustive \
    --error-exitcode=1 \
    --inline-suppr \
    --inconclusive \
    --library=googletest \
    --suppress=missingIncludeSystem \
    "${suppression_args[@]}" \
    --template=gcc \
    -i"${build_dir}/_deps"
