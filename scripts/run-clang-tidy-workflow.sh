#!/usr/bin/env bash

set -euo pipefail

MODE="${1:-}"
case "${MODE}" in
  changed|full) ;;
  *)
    echo "::error::First argument must be 'changed' or 'full'."
    exit 1
    ;;
esac

PRESET="${PRESET:-clang-release}"
EXTRA_CMAKE_ARGS="${EXTRA_CMAKE_ARGS:-}"
USE_NIX_CONAN="${USE_NIX_CONAN:-false}"
NIX_PACKAGES="${NIX_PACKAGES:-cmake ninja pkg-config conan python3 clang clang-tools}"
CONAN_INSTALL_ENABLED="${CONAN_INSTALL_ENABLED:-true}"
CONANFILE_INPUT="${CONANFILE_INPUT:-}"
CONAN_PROFILE="${CONAN_PROFILE:-default}"
CONAN_INSTALL_ARGS="${CONAN_INSTALL_ARGS:---build=missing}"
CONAN_OUTPUT_FOLDER="${CONAN_OUTPUT_FOLDER:-build/conan}"
BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-}"
REPORT_FILE="${REPORT_FILE:-}"

cmake_extra_args=()
if [[ -n "${EXTRA_CMAKE_ARGS}" ]]; then
  cmake_extra_args+=("--cmake-extra=${EXTRA_CMAKE_ARGS}")
fi

tool_runner() {
  "$@"
}

if [[ "${USE_NIX_CONAN}" == "true" ]]; then
  read -r -a package_names <<< "${NIX_PACKAGES}"
  if [[ ${#package_names[@]} -eq 0 ]]; then
    echo "::error::nix_packages is empty."
    exit 1
  fi

  installables=()
  for package_name in "${package_names[@]}"; do
    installables+=("nixpkgs#${package_name}")
  done

  run_in_nix() {
    nix shell "${installables[@]}" --command "$@"
  }

  tool_runner() {
    run_in_nix "$@"
  }

  echo "Tool versions:"
  tool_runner cmake --version
  tool_runner ninja --version
  tool_runner conan --version
  tool_runner clang-tidy --version

  if [[ "${CONAN_INSTALL_ENABLED}" == "true" ]]; then
    conanfile_path="${CONANFILE_INPUT}"
    if [[ -z "${conanfile_path}" ]]; then
      if [[ -f "conanfile.py" ]]; then
        conanfile_path="conanfile.py"
      elif [[ -f "conanfile.txt" ]]; then
        conanfile_path="conanfile.txt"
      fi
    fi

    if [[ -n "${conanfile_path}" ]]; then
      read -r -a conan_extra_args <<< "${CONAN_INSTALL_ARGS}"
      tool_runner conan profile detect --force
      tool_runner conan install \
        "${conanfile_path}" \
        --profile "${CONAN_PROFILE}" \
        --output-folder "${CONAN_OUTPUT_FOLDER}" \
        "${conan_extra_args[@]}"
    else
      echo "No conanfile.py/conanfile.txt found; skipping conan install."
    fi
  fi
fi

if [[ "${MODE}" == "changed" ]]; then
  if [[ -z "${BASE_SHA}" ]]; then
    echo "::error::BASE_SHA is required for changed mode."
    exit 1
  fi
  if [[ -z "${HEAD_SHA}" ]]; then
    echo "::error::HEAD_SHA is required for changed mode."
    exit 1
  fi
  tool_runner python3 ./devenv/scripts/clang-tidy-review.py changed \
    --base "${BASE_SHA}" \
    --head "${HEAD_SHA}" \
    --preset "${PRESET}" \
    "${cmake_extra_args[@]}"
  exit 0
fi

report_args=()
if [[ -n "${REPORT_FILE}" ]]; then
  report_args+=(--report-file "${REPORT_FILE}")
fi
tool_runner python3 ./devenv/scripts/clang-tidy-review.py full \
  "${report_args[@]}" \
  --preset "${PRESET}" \
  "${cmake_extra_args[@]}"
