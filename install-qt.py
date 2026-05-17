#!/usr/bin/env python3
"""Locate or install Qt 6 for CMake find_package(Qt6) (uiwrap qt backend)."""

from __future__ import annotations

import argparse
import glob
import os
from pathlib import Path
import shutil
import subprocess
import sys


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def run(
    command: list[str],
    *,
    check: bool = True,
    capture_output: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    stdout = subprocess.PIPE if capture_output else sys.stderr
    stderr = subprocess.PIPE if capture_output else sys.stderr
    return subprocess.run(
        command,
        check=check,
        stdout=stdout,
        stderr=stderr,
        text=True,
        env=env,
    )


def unix_privilege_prefix() -> list[str]:
    if os.name == "nt":
        return []
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        return []
    if command_exists("sudo"):
        return ["sudo", "-n"]
    return []


def qt6_config_directories() -> list[Path]:
    candidates: list[Path] = []
    for env_name in ("Qt6_DIR", "CMAKE_PREFIX_PATH"):
        raw = os.environ.get(env_name, "")
        if not raw:
            continue
        for part in raw.split(os.pathsep):
            part = part.strip()
            if not part:
                continue
            path = Path(part)
            if path.name == "Qt6":
                candidates.append(path)
            elif (path / "lib" / "cmake" / "Qt6").is_dir():
                candidates.append(path / "lib" / "cmake" / "Qt6")
            else:
                candidates.append(path)

    if sys.platform == "darwin" and command_exists("brew"):
        try:
            brew_prefix = run(
                ["brew", "--prefix", "qt"],
                check=True,
                capture_output=True,
            ).stdout.strip()
            candidates.append(Path(brew_prefix) / "lib" / "cmake" / "Qt6")
        except subprocess.CalledProcessError:
            pass

    if sys.platform.startswith("linux"):
        candidates.extend(Path(path) for path in glob.glob("/usr/lib/*/cmake/Qt6"))
        system_cmake = Path("/usr/lib/cmake/Qt6")
        if system_cmake.is_dir():
            candidates.append(system_cmake)

    return candidates


def prefix_from_qt6_config_dir(config_dir: Path) -> Path:
    resolved = config_dir.expanduser().resolve()
    if resolved.name == "Qt6" and resolved.parent.name == "cmake":
        lib_dir = resolved.parent.parent
        if lib_dir.name == "lib":
            return lib_dir.parent
        return lib_dir
    return resolved


def qt6_cmake_prefix() -> Path | None:
    for config_dir in qt6_config_directories():
        if (config_dir / "Qt6Config.cmake").is_file():
            return prefix_from_qt6_config_dir(config_dir)
    return None


def append_github_env_cmake_prefix_path(prefix: Path) -> None:
    github_env = os.environ.get("GITHUB_ENV")
    if not github_env:
        return
    prefix_text = str(prefix)
    existing = os.environ.get("CMAKE_PREFIX_PATH", "")
    merged = f"{prefix_text}{os.pathsep}{existing}" if existing else prefix_text
    with open(github_env, "a", encoding="utf-8") as env_file:
        env_file.write(f"CMAKE_PREFIX_PATH={merged}\n")
    os.environ["CMAKE_PREFIX_PATH"] = merged


def install_with_apt() -> Path:
    prefix_cmds = unix_privilege_prefix()
    run(prefix_cmds + ["apt-get", "update"])
    run(
        prefix_cmds
        + [
            "apt-get",
            "install",
            "-y",
            "qt6-base-dev",
            "qt6-declarative-dev",
        ]
    )
    prefix = qt6_cmake_prefix()
    if prefix is None:
        raise SystemExit(
            "apt install qt6-base-dev qt6-declarative-dev completed but Qt6 CMake config was not found."
        )
    return prefix


def install_with_brew() -> Path:
    if not command_exists("brew"):
        raise SystemExit(
            "Homebrew not found. Install Qt 6 manually or install Homebrew first."
        )
    run(["brew", "install", "qt"])
    prefix = qt6_cmake_prefix()
    if prefix is None:
        raise SystemExit(
            "brew install qt completed but Qt6 CMake config was not found."
        )
    return prefix


def install_qt6() -> Path:
    if sys.platform == "darwin":
        return install_with_brew()
    if sys.platform.startswith("linux") and command_exists("apt-get"):
        return install_with_apt()
    raise SystemExit(
        "Unable to install Qt 6 automatically: need apt-get (Linux) or Homebrew (macOS)."
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Locate or install Qt 6 for CMake find_package(Qt6)."
    )
    parser.add_argument(
        "--ensure",
        action="store_true",
        help="Install Qt 6 when no suitable CMake package config is found.",
    )
    parser.add_argument(
        "--export-github-env",
        action="store_true",
        help="Append CMAKE_PREFIX_PATH to GITHUB_ENV when set (CI).",
    )
    parser.add_argument(
        "--print-prefix-path",
        action="store_true",
        help="Print the detected or installed CMAKE_PREFIX_PATH entry to stdout.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    prefix = qt6_cmake_prefix()
    if prefix is None and args.ensure:
        eprint("Qt6 CMake package not found. Attempting installation.")
        try:
            prefix = install_qt6()
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr.strip() if exc.stderr else ""
            stdout = exc.stdout.strip() if exc.stdout else ""
            details = "\n".join(part for part in (stdout, stderr) if part)
            if details:
                raise SystemExit(f"Qt 6 installation failed.\n{details}") from exc
            raise SystemExit("Qt 6 installation failed.") from exc

    if prefix is not None and args.export_github_env:
        append_github_env_cmake_prefix_path(prefix)

    if prefix is None:
        eprint("Qt6 CMake package config not found.")
        return 1

    if args.print_prefix_path:
        print(prefix)
        return 0

    eprint(f"Qt6 CMake prefix: {prefix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
