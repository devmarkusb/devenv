#!/usr/bin/env python3
"""Locate or install Boost for CMake CONFIG mode (e.g. find_package(Boost CONFIG))."""

from __future__ import annotations

import argparse
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
    command: list[str], *, check: bool = True, capture_output: bool = False
) -> subprocess.CompletedProcess[str]:
    stdout = subprocess.PIPE if capture_output else sys.stderr
    stderr = subprocess.PIPE if capture_output else sys.stderr
    return subprocess.run(
        command,
        check=check,
        stdout=stdout,
        stderr=stderr,
        text=True,
    )


def unix_privilege_prefix() -> list[str]:
    if os.name == "nt":
        return []
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        return []
    if command_exists("sudo"):
        return ["sudo", "-n"]
    return []


def boost_config_dirs(prefix: Path) -> list[Path]:
    roots = [prefix / "lib" / "cmake"]
    lib_dir = prefix / "lib"
    if lib_dir.is_dir():
        roots.extend(path / "cmake" for path in lib_dir.iterdir() if path.is_dir())
    found: list[Path] = []
    for cmake_root in roots:
        if not cmake_root.is_dir():
            continue
        found.extend(path for path in cmake_root.glob("Boost-*") if path.is_dir())
    return sorted(found)


def prefix_from_boost_config(config_dir: Path) -> Path:
    cmake_dir = config_dir.parent
    lib_entry = cmake_dir.parent
    if lib_entry.name == "lib":
        return lib_entry.parent
    if lib_entry.parent.name == "lib":
        return lib_entry.parent.parent
    return lib_entry.parent


def detect_cmake_prefix_paths() -> list[Path]:
    prefixes: list[Path] = []
    seen: set[Path] = set()

    def add(prefix: Path | None) -> None:
        if prefix is None:
            return
        resolved = prefix.expanduser().resolve()
        configs = boost_config_dirs(resolved)
        if not configs:
            return
        install_prefix = prefix_from_boost_config(configs[0])
        if install_prefix in seen:
            return
        seen.add(install_prefix)
        prefixes.append(install_prefix)

    for env_name in ("CMAKE_PREFIX_PATH", "BOOST_ROOT"):
        raw = os.environ.get(env_name, "")
        if not raw:
            continue
        for part in raw.split(os.pathsep):
            part = part.strip()
            if part:
                add(Path(part))

    if sys.platform == "darwin" and command_exists("brew"):
        try:
            brew_prefix = run(
                ["brew", "--prefix", "boost"],
                check=True,
                capture_output=True,
            ).stdout.strip()
            add(Path(brew_prefix))
        except subprocess.CalledProcessError:
            pass

    vcpkg_root = Path("/opt/vcpkg")
    if vcpkg_root.is_dir():
        for triplet_dir in (vcpkg_root / "installed").glob("*"):
            add(triplet_dir)

    vcpkg_installation_root = os.environ.get("VCPKG_INSTALLATION_ROOT", "")
    if vcpkg_installation_root:
        installed = Path(vcpkg_installation_root) / "installed"
        if installed.is_dir():
            for triplet_dir in installed.glob("*"):
                add(triplet_dir)

    for system_prefix in (Path("/usr/local"), Path("/usr")):
        add(system_prefix)

    return prefixes


def vcpkg_executable() -> Path | None:
    candidates = [
        Path("/opt/vcpkg/vcpkg"),
        Path(os.environ.get("VCPKG_INSTALLATION_ROOT", "")) / "vcpkg.exe",
        Path(os.environ.get("VCPKG_INSTALLATION_ROOT", "")) / "vcpkg",
    ]
    for candidate in candidates:
        if not candidate.is_file():
            continue
        if candidate.suffix.lower() == ".exe" or os.access(candidate, os.X_OK):
            return candidate
    return None


def default_vcpkg_triplet() -> str:
    if os.name == "nt":
        return "x64-windows"
    if sys.platform == "darwin":
        return "x64-osx"
    return "x64-linux"


def vcpkg_boost_packages(components: list[str]) -> list[str]:
    packages: list[str] = []
    for component in components:
        slug = component.replace("_", "-")
        packages.append(f"boost-{slug}")
    return packages


def install_with_vcpkg(components: list[str], triplet: str | None) -> Path:
    vcpkg = vcpkg_executable()
    if vcpkg is None:
        raise SystemExit("vcpkg executable not found.")

    triplet = triplet or default_vcpkg_triplet()
    env = os.environ.copy()
    env.setdefault("VCPKG_DEFAULT_TRIPLET", triplet)

    packages = vcpkg_boost_packages(components)
    run([str(vcpkg), "install", *packages, "--triplet", triplet], env=env)

    vcpkg_root = vcpkg.parent
    prefix = (vcpkg_root / "installed" / triplet).resolve()
    if not boost_config_dirs(prefix):
        raise SystemExit(
            f"vcpkg install finished but Boost CMake config was not found under {prefix}."
        )
    return prefix


def install_with_brew() -> Path:
    if not command_exists("brew"):
        raise SystemExit("Homebrew not found. Install Boost manually or install Homebrew first.")
    run(["brew", "install", "boost"])
    prefix_text = run(["brew", "--prefix", "boost"], check=True, capture_output=True).stdout.strip()
    prefix = Path(prefix_text).resolve()
    if not boost_config_dirs(prefix):
        raise SystemExit(f"brew install boost completed but CMake config not found under {prefix}.")
    return prefix


def install_with_apt() -> Path:
    prefix_cmds = unix_privilege_prefix()
    run(prefix_cmds + ["apt-get", "update"])
    run(prefix_cmds + ["apt-get", "install", "-y", "libboost-all-dev"])
    prefixes = detect_cmake_prefix_paths()
    if prefixes:
        return prefixes[0]
    raise SystemExit("apt install libboost-all-dev completed but Boost CMake config was not found.")


def install_boost(components: list[str], triplet: str | None) -> Path:
    if vcpkg_executable() is not None:
        return install_with_vcpkg(components, triplet)
    if sys.platform == "darwin":
        return install_with_brew()
    if sys.platform.startswith("linux") and command_exists("apt-get"):
        return install_with_apt()
    raise SystemExit(
        "Unable to install Boost automatically: need vcpkg, Homebrew (macOS), or apt-get (Linux)."
    )


def append_github_env_cmake_prefix_path(prefix: Path) -> None:
    github_env = os.environ.get("GITHUB_ENV")
    if not github_env:
        return
    prefix_text = str(prefix)
    existing = os.environ.get("CMAKE_PREFIX_PATH", "")
    merged = (
        f"{prefix_text}{os.pathsep}{existing}"
        if existing
        else prefix_text
    )
    with open(github_env, "a", encoding="utf-8") as env_file:
        env_file.write(f"CMAKE_PREFIX_PATH={merged}\n")
    os.environ["CMAKE_PREFIX_PATH"] = merged


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Locate or install Boost for CMake find_package(Boost CONFIG)."
    )
    parser.add_argument(
        "--ensure",
        action="store_true",
        help="Install Boost when no suitable CMake package config is found.",
    )
    parser.add_argument(
        "--components",
        default="property-tree",
        help="Boost components for vcpkg (comma-separated, default: property-tree).",
    )
    parser.add_argument(
        "--vcpkg-triplet",
        default="",
        help="vcpkg triplet (default: x64-linux, x64-osx, or x64-windows).",
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
    components = [part.strip() for part in args.components.split(",") if part.strip()]
    triplet = args.vcpkg_triplet.strip() or None

    prefixes = detect_cmake_prefix_paths()
    if not prefixes and args.ensure:
        eprint("Boost CMake package not found. Attempting installation.")
        try:
            prefix = install_boost(components, triplet)
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr.strip() if exc.stderr else ""
            stdout = exc.stdout.strip() if exc.stdout else ""
            details = "\n".join(part for part in (stdout, stderr) if part)
            if details:
                raise SystemExit(f"Boost installation failed.\n{details}") from exc
            raise SystemExit("Boost installation failed.") from exc
        prefixes = [prefix]

    if prefixes and args.export_github_env:
        append_github_env_cmake_prefix_path(prefixes[0])

    if not prefixes:
        eprint("Boost CMake package config not found.")
        return 1

    primary = prefixes[0]
    if args.print_prefix_path:
        print(primary)
        return 0

    eprint(f"Boost CMake prefix: {primary}")
    for extra in prefixes[1:]:
        eprint(f"  also: {extra}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
