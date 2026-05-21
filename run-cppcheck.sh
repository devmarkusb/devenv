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

# Cppcheck does not apply the real compiler's builtin macros (__clang__, __APPLE__, …).
# Query them from the compile_commands.json toolchain so platform headers preprocess correctly.
mapfile -t define_args < <(
    python3 - "${compile_commands}" <<'PY'
import json
import shlex
import subprocess
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    db = json.load(f)

entry = next(
    e
    for e in db
    if "_deps" not in e.get("file", "").replace("\\", "/")
)
cmd = entry.get("command")
if not cmd:
    cmd = " ".join(shlex.quote(a) for a in entry["arguments"])

args = shlex.split(cmd)
compiler = args[0]
probe_flags: list[str] = []
for index, arg in enumerate(args):
    if arg.startswith("-std="):
        probe_flags.append(arg)
    elif arg in ("-arch", "--target") and index + 1 < len(args):
        probe_flags.extend((arg, args[index + 1]))
    elif arg.startswith("-arch=") or arg.startswith("--target="):
        probe_flags.append(arg)

result = subprocess.run(
    [compiler, *probe_flags, "-dM", "-E", "-x", "c++", "-"],
    input=b"",
    capture_output=True,
    check=True,
)
for line in result.stdout.decode().splitlines():
    if not line.startswith("#define "):
        continue
    name, _, value = line[8:].strip().partition(" ")
    if value == "":
        print(f"-D{name}")
    else:
        print(f"-D{name}={value}")
PY
)

"${cppcheck_bin}" \
    --project="${compile_commands}" \
    --cppcheck-build-dir="${cppcheck_build_dir}" \
    "${define_args[@]}" \
    --quiet \
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
