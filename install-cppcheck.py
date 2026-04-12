#!/usr/bin/env python3

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
    return subprocess.run(
        command,
        check=check,
        capture_output=capture_output,
        text=True,
    )


def cppcheck_candidates() -> list[Path]:
    candidates: list[Path] = []
    seen: set[Path] = set()

    def add(path_text: str | Path | None) -> None:
        if not path_text:
            return
        path = Path(path_text).expanduser()
        if not path.exists():
            return
        resolved = path.resolve()
        if resolved in seen:
            return
        seen.add(resolved)
        candidates.append(resolved)

    add(shutil.which("cppcheck"))

    if sys.platform == "darwin":
        add("/opt/homebrew/bin/cppcheck")
        add("/usr/local/bin/cppcheck")
        if command_exists("brew"):
            for formula in ("cppcheck",):
                try:
                    prefix = run(
                        ["brew", "--prefix", formula],
                        check=True,
                        capture_output=True,
                    ).stdout.strip()
                except subprocess.CalledProcessError:
                    continue
                add(Path(prefix) / "bin" / "cppcheck")
    elif os.name == "nt":
        for env_var in ("ProgramFiles", "ProgramFiles(x86)"):
            base = os.environ.get(env_var, "")
            if base:
                add(Path(base) / "Cppcheck" / "cppcheck.exe")
                add(Path(base) / "Cppcheck" / "bin" / "cppcheck.exe")
        local_app_data = os.environ.get("LOCALAPPDATA", "")
        if local_app_data:
            add(Path(local_app_data) / "Programs" / "Cppcheck" / "cppcheck.exe")
            add(Path(local_app_data) / "Programs" / "Cppcheck" / "bin" / "cppcheck.exe")
            add(Path(local_app_data) / "Microsoft" / "WinGet" / "Links" / "cppcheck.exe")
        program_data = os.environ.get("ProgramData", "")
        if program_data:
            add(Path(program_data) / "chocolatey" / "bin" / "cppcheck.exe")
    else:
        add("/usr/bin/cppcheck")
        add("/usr/local/bin/cppcheck")

    return candidates


def detect_cppcheck() -> Path | None:
    candidates = cppcheck_candidates()
    return candidates[0] if candidates else None


def cppcheck_version(executable: Path) -> str:
    try:
        result = run([str(executable), "--version"], capture_output=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return ""
    return (result.stdout or result.stderr).strip()


def unix_privilege_prefix() -> list[str]:
    if os.name == "nt":
        return []
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        return []
    if command_exists("sudo"):
        return ["sudo", "-n"]
    return []


def install_with_apt(prefix: list[str]) -> None:
    run(prefix + ["apt-get", "update"])
    run(prefix + ["apt-get", "install", "-y", "cppcheck"])


def install_with_dnf(prefix: list[str]) -> None:
    run(prefix + ["dnf", "install", "-y", "cppcheck"])


def install_with_pacman(prefix: list[str]) -> None:
    run(prefix + ["pacman", "-Sy", "--noconfirm", "cppcheck"])


def install_with_zypper(prefix: list[str]) -> None:
    run(prefix + ["zypper", "--non-interactive", "install", "cppcheck"])


def install_with_brew() -> None:
    run(["brew", "install", "cppcheck"])


def install_on_linux() -> None:
    prefix = unix_privilege_prefix()
    if command_exists("apt-get"):
        install_with_apt(prefix)
        return
    if command_exists("dnf"):
        install_with_dnf(prefix)
        return
    if command_exists("pacman"):
        install_with_pacman(prefix)
        return
    if command_exists("zypper"):
        install_with_zypper(prefix)
        return
    if command_exists("brew"):
        install_with_brew()
        return
    raise SystemExit(
        "Unable to install cppcheck automatically on Linux: no supported package manager found."
    )


def install_on_macos() -> None:
    if not command_exists("brew"):
        raise SystemExit("Homebrew not found. Install cppcheck manually or install Homebrew first.")
    install_with_brew()


def install_with_winget() -> None:
    common = [
        "winget",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity",
        "--silent",
        "-e",
        "--id",
        "Cppcheck.Cppcheck",
    ]
    listed = run(common[:1] + ["list"] + common[1:], check=False, capture_output=True)
    if listed.returncode == 0 and "Cppcheck.Cppcheck" in listed.stdout:
        run(common[:1] + ["upgrade"] + common[1:], check=False)
        return
    run(common[:1] + ["install"] + common[1:])


def install_with_choco() -> None:
    listed = run(["choco", "list", "--local-only", "cppcheck"], check=False, capture_output=True)
    if listed.returncode == 0 and "cppcheck" in listed.stdout.lower():
        run(["choco", "upgrade", "cppcheck", "-y"])
        return
    run(["choco", "install", "cppcheck", "-y"])


def install_on_windows() -> None:
    if command_exists("winget"):
        install_with_winget()
        return
    if command_exists("choco"):
        install_with_choco()
        return
    raise SystemExit(
        "Unable to install cppcheck automatically on Windows: neither winget nor choco is available."
    )


def ensure_cppcheck() -> Path:
    executable = detect_cppcheck()
    if executable is not None:
        return executable

    eprint("cppcheck not found. Attempting installation.")
    try:
        if os.name == "nt":
            install_on_windows()
        elif sys.platform == "darwin":
            install_on_macos()
        elif sys.platform.startswith("linux"):
            install_on_linux()
        else:
            raise SystemExit(
                f"Unable to install cppcheck automatically on unsupported platform '{sys.platform}'."
            )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip() if exc.stderr else ""
        stdout = exc.stdout.strip() if exc.stdout else ""
        details = "\n".join(part for part in (stdout, stderr) if part)
        if details:
            raise SystemExit(f"cppcheck installation failed.\n{details}") from exc
        raise SystemExit("cppcheck installation failed.") from exc

    executable = detect_cppcheck()
    if executable is None:
        raise SystemExit(
            "cppcheck installation command completed, but the executable still could not be found."
        )
    return executable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Locate or install cppcheck using a supported platform package manager."
    )
    parser.add_argument(
        "--ensure",
        action="store_true",
        help="Install cppcheck if it is not already available.",
    )
    parser.add_argument(
        "--print-path",
        action="store_true",
        help="Print only the resolved cppcheck executable path to stdout.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    executable = ensure_cppcheck() if args.ensure else detect_cppcheck()
    if executable is None:
        eprint("cppcheck executable not found.")
        return 1

    if args.print_path:
        print(executable)
        return 0

    version = cppcheck_version(executable)
    if version:
        eprint(version)
    eprint(f"cppcheck executable: {executable}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
