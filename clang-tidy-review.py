#!/usr/bin/env python3

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request


SOURCE_SUFFIXES = (".c", ".cc", ".cpp", ".cxx")
HEADER_SUFFIXES = (".h", ".hh", ".hpp", ".hxx")
EXCLUDED_TEST_SUFFIXES = (".test.c", ".test.cc", ".test.cpp", ".test.cxx")
HEADER_FILTER = r"^(.*\/)?(include|src|examples)\/"
ZERO_SHA = "0000000000000000000000000000000000000000"
FULL_SCAN_TRIGGER_PATHS = {
    ".clang-tidy",
    "CMakeLists.txt",
    "CMakePresets.json",
    "devenv/clang-tidy-review.py",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the same clang-tidy selection logic used by CI."
    )
    parser.add_argument(
        "mode",
        choices=("changed", "full"),
        help="Whether to scan only affected translation units or the full project.",
    )
    parser.add_argument(
        "--base",
        dest="base_ref",
        default="",
        help="Diff base for changed mode. Defaults to merge-base with upstream, origin/main, or main.",
    )
    parser.add_argument(
        "--head",
        dest="head_ref",
        default="HEAD",
        help="Diff head for changed mode. Defaults to HEAD.",
    )
    parser.add_argument(
        "--preset",
        default="clang-release",
        help="CMake configure preset to use. Defaults to clang-release.",
    )
    parser.add_argument(
        "--report-file",
        default="",
        help="Save and tee clang-tidy output to this file.",
    )
    parser.add_argument(
        "--show-summary",
        action="store_true",
        help="Show clang-tidy warning statistics instead of suppressing them with --quiet.",
    )
    parser.add_argument(
        "--install",
        action="store_true",
        help="Install or upgrade the latest available LLVM/clang-tidy from a package manager.",
    )
    return parser.parse_args()


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    check: bool = True,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=str(cwd or repo_root()),
        check=check,
        capture_output=capture_output,
        text=True,
    )


def git_output(*args: str, check: bool = True) -> str:
    result = run(["git", *args], capture_output=True, check=check)
    return result.stdout.strip()


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def sudo_prefix() -> list[str]:
    if os.name == "nt":
        return []
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        return []
    if command_exists("sudo"):
        return ["sudo"]
    return []


def parse_version(output: str) -> tuple[int, ...] | None:
    match = re.search(r"version\s+(\d+)(?:\.(\d+))?(?:\.(\d+))?", output)
    if not match:
        return None
    return tuple(int(part) for part in match.groups(default="0"))


def detect_clang_tidy_version(executable: Path) -> tuple[int, ...] | None:
    try:
        result = subprocess.run(
            [str(executable), "--version"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    return parse_version(result.stdout + result.stderr)


def discover_clang_tidy_candidates() -> list[tuple[tuple[int, ...], int, Path, str]]:
    candidates: list[tuple[tuple[int, ...], int, Path, str]] = []
    seen: set[Path] = set()

    def add_candidate(path_text: str | None, priority: int, source: str) -> None:
        if not path_text:
            return
        path = Path(path_text).expanduser()
        if not path.exists():
            return
        resolved = path.resolve()
        if resolved in seen:
            return
        version = detect_clang_tidy_version(resolved)
        if version is None:
            return
        seen.add(resolved)
        candidates.append((version, priority, resolved, source))

    add_candidate(shutil.which("clang-tidy"), 10, "PATH")

    for pattern in (
        "/usr/bin/clang-tidy-*",
        "/usr/local/bin/clang-tidy-*",
        "/opt/local/bin/clang-tidy-*",
    ):
        for path in sorted(Path("/").glob(pattern.lstrip("/"))):
            add_candidate(str(path), 20, "versioned-system")

    if sys.platform == "darwin" and command_exists("brew"):
        try:
            brew_prefix = run(
                ["brew", "--prefix", "llvm"], capture_output=True, check=True
            ).stdout.strip()
        except subprocess.CalledProcessError:
            brew_prefix = ""
        add_candidate(
            str(Path(brew_prefix) / "bin" / "clang-tidy") if brew_prefix else "",
            30,
            "homebrew-llvm",
        )

    if os.name == "nt":
        for env_var in ("ProgramFiles", "ProgramFiles(x86)"):
            base = os.environ.get(env_var, "")
            if base:
                add_candidate(
                    str(Path(base) / "LLVM" / "bin" / "clang-tidy.exe"),
                    30,
                    f"{env_var}-LLVM",
                )

    return candidates


def install_or_upgrade_latest_clang_tidy() -> None:
    if sys.platform == "darwin":
        if not command_exists("brew"):
            raise SystemExit("Homebrew not found. Please install Homebrew first.")
        run(["brew", "update"])
        installed = (
            run(
                ["brew", "list", "--versions", "llvm"],
                capture_output=True,
                check=False,
            ).returncode
            == 0
        )
        if installed:
            run(["brew", "upgrade", "llvm"], check=False)
        else:
            run(["brew", "install", "llvm"])
        return

    if os.name == "nt":
        if not command_exists("winget"):
            raise SystemExit("winget not found. Please install LLVM manually.")
        common = [
            "winget",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--silent",
            "-e",
            "--id",
            "LLVM.LLVM",
        ]
        upgrade = run(common[:1] + ["upgrade"] + common[1:], check=False)
        if upgrade.returncode != 0:
            run(common[:1] + ["install"] + common[1:])
        return

    if sys.platform.startswith("linux"):
        if not command_exists("apt-get"):
            raise SystemExit(
                "Automatic installation is only implemented for apt-based Linux systems."
            )

        with tempfile.TemporaryDirectory() as temp_dir:
            llvm_sh = Path(temp_dir) / "llvm.sh"
            urllib.request.urlretrieve("https://apt.llvm.org/llvm.sh", llvm_sh)
            run(sudo_prefix() + ["bash", str(llvm_sh)])

        run(sudo_prefix() + ["apt-get", "update", "-qq"])
        search = run(
            ["apt-cache", "search", r"^clang-tidy-[0-9]+$"],
            capture_output=True,
            check=False,
        ).stdout.splitlines()
        versioned_packages = sorted(
            (
                (int(match.group(2)), match.group(1))
                for line in search
                if (match := re.match(r"^(clang-tidy-(\d+))\s", line))
            ),
            reverse=True,
        )
        package = versioned_packages[0][1] if versioned_packages else "clang-tidy"
        run(sudo_prefix() + ["apt-get", "install", "-y", package])
        return

    raise SystemExit("Unsupported OS for automatic clang-tidy installation.")


def select_clang_tidy(install: bool) -> Path:
    if install:
        install_or_upgrade_latest_clang_tidy()

    candidates = discover_clang_tidy_candidates()
    if not candidates:
        raise SystemExit(
            "clang-tidy not found.\n\n"
            "Rerun with --install to install the latest available LLVM/clang-tidy.\n"
            "macOS:  brew install llvm\n"
            "Linux:  use --install on apt-based systems\n"
            "Windows: use --install if winget is available"
        )

    version, _, path, source = max(candidates, key=lambda item: (item[0], item[1]))
    version_text = ".".join(str(part) for part in version)
    print(f"Using clang-tidy {version_text} from {path} ({source}).")
    return path


def configure(preset: str) -> None:
    run(["cmake", "--preset", preset])


def discover_extra_args_before() -> list[str]:
    if sys.platform != "darwin" or not command_exists("xcrun"):
        return []
    try:
        sdk_path = run(
            ["xcrun", "--show-sdk-path"], capture_output=True, check=True
        ).stdout.strip()
    except subprocess.CalledProcessError:
        return []
    if not sdk_path:
        return []
    return ["--extra-arg-before=-isysroot", f"--extra-arg-before={sdk_path}"]


def list_git_files() -> list[str]:
    output = git_output("ls-files")
    return [line for line in output.splitlines() if line]


def is_translation_unit(path: str) -> bool:
    return (
        (path.startswith("src/") or path.startswith("examples/"))
        and path.endswith(SOURCE_SUFFIXES)
        and not path.endswith(EXCLUDED_TEST_SUFFIXES)
    )


def translation_units_from_compile_db(build_dir: Path) -> list[str] | None:
    """Return repo-relative TUs from compile_commands.json, or None if unavailable."""
    compile_db = build_dir / "compile_commands.json"
    if not compile_db.is_file():
        return None

    root = repo_root()
    units: list[str] = []
    for entry in json.loads(compile_db.read_text()):
        file_path = Path(entry["file"])
        try:
            rel = file_path.relative_to(root).as_posix()
        except ValueError:
            continue
        if is_translation_unit(rel):
            units.append(rel)
    return sorted(set(units))


def list_git_translation_units() -> list[str]:
    return [path for path in list_git_files() if is_translation_unit(path)]


def is_header(path: str) -> bool:
    return (
        path.startswith("include/")
        or path.startswith("src/")
        or path.startswith("examples/")
    ) and path.endswith(HEADER_SUFFIXES)


def should_trigger_full_scan(path: str) -> bool:
    return (
        is_header(path)
        or path in FULL_SCAN_TRIGGER_PATHS
        or path.endswith("/CMakeLists.txt")
        or path.startswith("cmake/")
        or path.startswith("devenv/cmake/")
    )


def normalize_line_ranges(ranges: list[list[int]]) -> list[list[int]]:
    if not ranges:
        return []

    normalized: list[list[int]] = []
    for start, end in sorted(ranges):
        if not normalized or start > normalized[-1][1] + 1:
            normalized.append([start, end])
            continue
        normalized[-1][1] = max(normalized[-1][1], end)
    return normalized


def build_changed_line_filter(base_sha: str, head_sha: str) -> str:
    diff_output = git_output(
        "diff",
        "--unified=0",
        "--no-color",
        "--diff-filter=ACMR",
        base_sha,
        head_sha,
    )

    current_path = ""
    changed_ranges_by_path: dict[str, list[list[int]]] = {}
    hunk_pattern = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")

    for line in diff_output.splitlines():
        if line.startswith("+++ "):
            path_text = line[4:]
            if path_text == "/dev/null":
                current_path = ""
            elif path_text.startswith("b/"):
                current_path = path_text[2:]
            else:
                current_path = path_text
            continue

        if not current_path or not (
            is_translation_unit(current_path) or is_header(current_path)
        ):
            continue

        match = hunk_pattern.match(line)
        if not match:
            continue

        start = int(match.group(1))
        count = int(match.group(2) or "1")
        if count == 0:
            continue

        end = start + count - 1
        changed_ranges_by_path.setdefault(current_path, []).append([start, end])

    line_filter = [
        {"name": path, "lines": normalize_line_ranges(ranges)}
        for path, ranges in sorted(changed_ranges_by_path.items())
        if ranges
    ]
    return json.dumps(line_filter, separators=(",", ":"))


def resolve_default_base_ref() -> str:
    for ref in ("@{upstream}", "origin/main", "main", "HEAD^"):
        if (
            run(
                ["git", "rev-parse", "--verify", "--quiet", ref], check=False
            ).returncode
            == 0
        ):
            if ref == "HEAD^":
                return git_output("rev-parse", ref)
            return git_output("merge-base", "HEAD", ref)
    return ""


def filter_translation_units_to_compile_db(
    units: list[str], build_dir: Path
) -> list[str]:
    """Keep only TUs that appear in compile_commands.json for this configure preset."""
    compile_units = translation_units_from_compile_db(build_dir)
    if compile_units is None:
        return units

    compile_set = set(compile_units)
    selected = [unit for unit in units if unit in compile_set]
    skipped = [unit for unit in units if unit not in compile_set]
    if skipped:
        print(
            "Skipping translation units not built by the active CMake preset "
            f"({len(skipped)} file(s); e.g. Qt impl sources when MB_UIWRAP_USE_IMPLEMENTATION=own):"
        )
        for unit in skipped[:8]:
            print(f"  - {unit}")
        if len(skipped) > 8:
            print(f"  ... and {len(skipped) - 8} more")
    return selected


def select_changed_translation_units(
    base_ref: str, head_ref: str, build_dir: Path
) -> tuple[list[str], str]:
    head_sha = git_output("rev-parse", head_ref)
    base_sha = base_ref or resolve_default_base_ref()
    if base_sha == ZERO_SHA:
        base_sha = git_output("rev-list", "--max-count=1", f"{head_sha}^", check=False)

    if not base_sha:
        print("No diff base available; skipping changed-lines clang-tidy run.")
        return [], ""

    changed_output = git_output(
        "diff", "--name-only", "--diff-filter=ACMR", base_sha, head_sha
    )
    changed_paths = [line for line in changed_output.splitlines() if line]
    if not changed_paths:
        print("No changed files to analyze.")
        return [], ""

    compile_units = translation_units_from_compile_db(build_dir)
    all_translation_units = (
        compile_units if compile_units is not None else list_git_translation_units()
    )
    if not all_translation_units:
        print("No translation units found; skipping changed-files clang-tidy run.")
        return [], ""

    line_filter = build_changed_line_filter(base_sha, head_sha)
    if not line_filter or line_filter == "[]":
        print("No changed source or header lines to analyze.")
        return [], ""

    if any(should_trigger_full_scan(path) for path in changed_paths):
        print(
            "Header or build configuration changes detected; running clang-tidy on "
            "translation units from compile_commands.json."
        )
        return all_translation_units, line_filter

    selected = [path for path in changed_paths if is_translation_unit(path)]
    selected = filter_translation_units_to_compile_db(selected, build_dir)
    if not selected:
        print("No changed translation units to analyze for the active CMake preset.")
        return [], ""
    return selected, line_filter


def select_full_translation_units(build_dir: Path) -> list[str]:
    compile_units = translation_units_from_compile_db(build_dir)
    if compile_units is not None:
        if compile_units:
            return compile_units
        print("No translation units found in compile_commands.json.")
        return []

    translation_units = list_git_translation_units()
    if not translation_units:
        print("No translation units found; skipping full clang-tidy run.")
        return []
    return translation_units


def run_single_clang_tidy(
    clang_tidy: Path,
    build_dir: Path,
    translation_unit: str,
    line_filter: str,
    extra_args_before: list[str],
    *,
    quiet: bool,
) -> tuple[int, str, str]:
    command = [
        str(clang_tidy),
        "-p",
        str(build_dir),
        f"-header-filter={HEADER_FILTER}",
    ]
    if quiet:
        command.append("--quiet")
    command.extend(extra_args_before)
    if line_filter:
        command.append(f"-line-filter={line_filter}")
    command.append(translation_unit)

    result = subprocess.run(
        command,
        cwd=str(repo_root()),
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout, result.stderr


def run_clang_tidy(
    clang_tidy: Path,
    build_dir: Path,
    translation_units: list[str],
    report_file: str,
    *,
    line_filter: str = "",
    quiet: bool = True,
) -> int:
    if not translation_units:
        return 0

    report_handle = None
    if report_file:
        report_path = Path(report_file)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_handle = report_path.open("w", encoding="utf-8")

    status = 0
    workers = os.cpu_count() or 1

    try:
        extra_args_before = discover_extra_args_before()
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(
                    run_single_clang_tidy,
                    clang_tidy,
                    build_dir,
                    unit,
                    line_filter,
                    extra_args_before,
                    quiet=quiet,
                ): unit
                for unit in translation_units
            }
            for future in concurrent.futures.as_completed(futures):
                returncode, stdout_text, stderr_text = future.result()
                if stdout_text:
                    sys.stdout.write(stdout_text)
                    sys.stdout.flush()
                if stderr_text:
                    sys.stderr.write(stderr_text)
                    sys.stderr.flush()
                if report_handle:
                    if stdout_text:
                        report_handle.write(stdout_text)
                    if stderr_text:
                        report_handle.write(stderr_text)
                status = max(status, returncode)
    finally:
        if report_handle:
            report_handle.close()

    return status


def main() -> int:
    args = parse_args()
    os.chdir(repo_root())

    clang_tidy = select_clang_tidy(args.install)
    configure(args.preset)
    build_dir = repo_root() / "build" / args.preset

    if args.mode == "full":
        translation_units = select_full_translation_units(build_dir)
        line_filter = ""
    else:
        translation_units, line_filter = select_changed_translation_units(
            args.base_ref, args.head_ref, build_dir
        )

    return run_clang_tidy(
        clang_tidy,
        build_dir,
        translation_units,
        args.report_file,
        line_filter=line_filter,
        quiet=not args.show_summary,
    )


if __name__ == "__main__":
    raise SystemExit(main())
