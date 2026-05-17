#!/usr/bin/env python3
"""Generate and manage local Nix/direnv/Conan dev-env boilerplate.

This script is intentionally self-contained so it can be moved to a separate
repository later with minimal changes.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


SCRIPT_NAME = Path(__file__).name
SCRIPT_HINT = "python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py"
CONFIG_FILE = "cppenv-nix-conan.json"
ENVRC_FILE = ".envrc"
FLAKE_FILE = "flake.nix"
CONAN_PROFILES_DIR = Path("conan/profiles")
CONANFILE_TXT = "conanfile.txt"


DEFAULT_CONFIG: dict[str, Any] = {
    "version": 1,
    "description": "Project-local dev env kit config",
    "default_shell": "gcc15",
    "platform_default_shells": {
        "darwin": "appleclang",
        "linux": "gcc15",
    },
    "systems": [
        "x86_64-linux",
        "aarch64-linux",
        "x86_64-darwin",
        "aarch64-darwin",
    ],
    "conanfile": {
        "format": "txt",
        "generators": ["CMakeDeps", "CMakeToolchain"],
        "requires": [],
    },
    "bootstrap": {
        "nix_installer": "determinate",
        "install_nix": True,
        "install_direnv": True,
        "install_xcode_clt_on_macos": True,
        "configure_direnv_hook": True,
        "shell_rc_files": ["~/.zshrc", "~/.bashrc"],
    },
    "cmake_presets": {
        "path": "CMakePresets.json",
        "base_preset_name": "nix-conan",
        "source_presets": [
            "gcc-debug",
            "gcc-release",
            "clang-debug",
            "clang-release",
            "clang-libc++-debug",
            "clang-libc++-release",
            "appleclang-debug",
            "appleclang-release",
            "appleclang-maxsan-release",
        ],
        "auto_sync_on_render": False,
    },
    "shells": {
        "gcc15": {
            "packages": ["cmake", "ninja", "pkg-config", "conan", "gcc15"],
        },
        "clang21": {
            "packages": ["cmake", "ninja", "pkg-config", "conan", "clang_21"],
        },
        "clang21-libcxx": {
            "packages": [
                "cmake",
                "ninja",
                "pkg-config",
                "conan",
                "llvmPackages_21.clangWithLibcAndBasicRtAndLibcxx",
            ],
        },
        "appleclang": {
            "packages": ["cmake", "ninja", "pkg-config", "conan"],
            "env": {
                "CC": "/usr/bin/cc",
                "CXX": "/usr/bin/c++",
            },
        },
    },
    "conan_profiles": {
        "linux-gcc-debug": {
            "include": "default",
            "settings": {
                "build_type": "Debug",
                "compiler": "gcc",
                "compiler.version": "15",
                "compiler.cppstd": "26",
                "compiler.libcxx": "libstdc++11",
            },
            "user_toolchain": "{{profile_dir}}/../../devenv/cmake/toolchains/gcc-toolchain.cmake",
        },
        "linux-gcc-release": {
            "include": "default",
            "settings": {
                "build_type": "RelWithDebInfo",
                "compiler": "gcc",
                "compiler.version": "15",
                "compiler.cppstd": "26",
                "compiler.libcxx": "libstdc++11",
            },
            "user_toolchain": "{{profile_dir}}/../../devenv/cmake/toolchains/gcc-toolchain.cmake",
        },
        "linux-clang-debug": {
            "include": "default",
            "settings": {
                "build_type": "Debug",
                "compiler": "clang",
                "compiler.version": "21",
                "compiler.cppstd": "26",
                "compiler.libcxx": "libstdc++11",
            },
            "user_toolchain": "{{profile_dir}}/../../devenv/cmake/toolchains/clang-toolchain.cmake",
        },
        "linux-clang-release": {
            "include": "default",
            "settings": {
                "build_type": "RelWithDebInfo",
                "compiler": "clang",
                "compiler.version": "21",
                "compiler.cppstd": "26",
                "compiler.libcxx": "libstdc++11",
            },
            "user_toolchain": "{{profile_dir}}/../../devenv/cmake/toolchains/clang-toolchain.cmake",
        },
        "linux-clang-libcxx-debug": {
            "include": "default",
            "settings": {
                "build_type": "Debug",
                "compiler": "clang",
                "compiler.version": "21",
                "compiler.cppstd": "26",
                "compiler.libcxx": "libc++",
            },
            "user_toolchain": "{{profile_dir}}/../../devenv/cmake/toolchains/clang-libc++-toolchain.cmake",
        },
        "linux-clang-libcxx-release": {
            "include": "default",
            "settings": {
                "build_type": "RelWithDebInfo",
                "compiler": "clang",
                "compiler.version": "21",
                "compiler.cppstd": "26",
                "compiler.libcxx": "libc++",
            },
            "user_toolchain": "{{profile_dir}}/../../devenv/cmake/toolchains/clang-libc++-toolchain.cmake",
        },
        "macos-appleclang-debug": {
            "include": "default",
            "settings": {
                "build_type": "Debug",
                "compiler.cppstd": "23",
                "compiler.libcxx": "libc++",
            },
            "user_toolchain": "{{profile_dir}}/../../devenv/cmake/toolchains/appleclang-toolchain.cmake",
        },
        "macos-appleclang-release": {
            "include": "default",
            "settings": {
                "build_type": "RelWithDebInfo",
                "compiler.cppstd": "23",
                "compiler.libcxx": "libc++",
            },
            "user_toolchain": "{{profile_dir}}/../../devenv/cmake/toolchains/appleclang-toolchain.cmake",
        },
    },
}


TOOLCHAIN_CONFIGURE_PRESETS = {
    "gcc",
    "clang",
    "clang-libc++",
    "appleclang",
    "msvc",
}


def die(message: str, code: int = 1) -> None:
    print(f"{SCRIPT_NAME}: {message}", file=sys.stderr)
    raise SystemExit(code)


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def load_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        die(f"missing {path}. run `{SCRIPT_HINT} init` first.")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        die(f"invalid JSON in {path}: {exc}")
    if not isinstance(data, dict):
        die(f"{path} must be a JSON object.")
    for key in ("default_shell", "shells", "conan_profiles"):
        if key not in data:
            die(f"{path} is missing required key: {key!r}")
    shells = data["shells"]
    if not isinstance(shells, dict) or not shells:
        die(f"{path}: 'shells' must be a non-empty object.")
    default_shell = data["default_shell"]
    if default_shell not in shells:
        die(f"{path}: default_shell {default_shell!r} is not in shells.")
    return data


def resolve_config_path(root: Path) -> Path:
    return root / CONFIG_FILE


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def print_command(command: list[str]) -> None:
    quoted = shlex.join(command)
    print(f"+ {quoted}")


def run_checked(command: list[str]) -> None:
    print_command(command)
    subprocess.run(command, check=True)


def run_shell_checked(command: str) -> None:
    print(f"+ {command}")
    subprocess.run(["bash", "-lc", command], check=True)


def xcode_clt_installed() -> bool:
    if platform.system() != "Darwin":
        return True
    result = subprocess.run(
        ["xcode-select", "-p"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def detect_linux_package_manager() -> str | None:
    for candidate in ("apt-get", "dnf", "yum", "pacman", "zypper", "apk"):
        if command_exists(candidate):
            return candidate
    return None


def sudo_prefix() -> list[str]:
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        return []
    if command_exists("sudo"):
        return ["sudo"]
    die("root privileges are required but `sudo` is not available.")


def install_linux_packages(packages: list[str], *, assume_yes: bool) -> None:
    manager = detect_linux_package_manager()
    if manager is None:
        die(
            "unsupported Linux package manager. install prerequisites manually: "
            + ", ".join(packages)
        )
    if not packages:
        return

    prefix = sudo_prefix()
    if manager == "apt-get":
        run_checked(prefix + ["apt-get", "update"])
        cmd = prefix + ["apt-get", "install"]
        if assume_yes:
            cmd.append("-y")
        run_checked(cmd + packages)
        return
    if manager in {"dnf", "yum"}:
        cmd = prefix + [manager, "install"]
        if assume_yes:
            cmd.append("-y")
        run_checked(cmd + packages)
        return
    if manager == "pacman":
        cmd = prefix + ["pacman", "-Sy", "--needed"]
        if assume_yes:
            cmd.append("--noconfirm")
        run_checked(cmd + packages)
        return
    if manager == "zypper":
        cmd = prefix + ["zypper"]
        if assume_yes:
            cmd.append("--non-interactive")
        run_checked(cmd + ["install"] + packages)
        return
    if manager == "apk":
        run_checked(prefix + ["apk", "add"] + packages)
        return
    die(f"unsupported package manager: {manager}")


def infer_shell_for_rc_file(rc_path: Path) -> str | None:
    file_name = rc_path.name.lower()
    if "bash" in file_name:
        return "bash"
    if "zsh" in file_name:
        return "zsh"
    return None


def resolve_direnv_hook_targets(bootstrap: dict[str, Any]) -> list[tuple[Path, str]]:
    raw_targets = bootstrap.get("shell_rc_files")
    target_entries: list[str] = []

    if isinstance(raw_targets, str):
        if raw_targets.strip():
            target_entries.append(raw_targets.strip())
    elif isinstance(raw_targets, list):
        for item in raw_targets:
            if isinstance(item, str) and item.strip():
                target_entries.append(item.strip())

    legacy_target = bootstrap.get("shell_rc_file")
    if isinstance(legacy_target, str) and legacy_target.strip():
        target_entries.append(legacy_target.strip())

    # Always include both common interactive shells unless already configured.
    for default_entry in ("~/.zshrc", "~/.bashrc"):
        if default_entry not in target_entries:
            target_entries.append(default_entry)

    seen: set[str] = set()
    targets: list[tuple[Path, str]] = []
    for entry in target_entries:
        rc_path = Path(entry).expanduser()
        key = str(rc_path)
        if key in seen:
            continue
        seen.add(key)

        shell_name = infer_shell_for_rc_file(rc_path)
        if shell_name is None:
            print(f"Skipping unsupported rc file for direnv hook: {rc_path}")
            continue
        targets.append((rc_path, shell_name))
    return targets


def ensure_direnv_hook(rc_path: Path, shell_name: str) -> None:
    hook_snippet = f"direnv hook {shell_name}"
    hook_line = f'eval "$(direnv hook {shell_name})"'
    if rc_path.exists():
        current = rc_path.read_text(encoding="utf-8")
    else:
        current = ""
    if hook_snippet in current:
        print(f"direnv hook ({shell_name}) already present in {rc_path}")
        return
    text = current
    if text and not text.endswith("\n"):
        text += "\n"
    text += f"{hook_line}\n"
    rc_path.parent.mkdir(parents=True, exist_ok=True)
    rc_path.write_text(text, encoding="utf-8")
    print(f"Added direnv hook ({shell_name}) to {rc_path}")


def normalize_inherits(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [item for item in value if isinstance(item, str)]
    return []


def find_named_preset(presets: list[Any], name: str) -> dict[str, Any] | None:
    for preset in presets:
        if isinstance(preset, dict) and preset.get("name") == name:
            return preset
    return None


def upsert_named_preset(presets: list[Any], preset: dict[str, Any]) -> str:
    name = preset.get("name")
    for index, existing in enumerate(presets):
        if isinstance(existing, dict) and existing.get("name") == name:
            presets[index] = preset
            return "updated"
    presets.append(preset)
    return "added"


def render_nix_conan_configure_preset(
    source_name: str,
    source_preset: dict[str, Any],
    base_preset_name: str,
) -> dict[str, Any]:
    source_inherits = normalize_inherits(source_preset.get("inherits"))
    filtered_inherits = [
        item
        for item in source_inherits
        if item not in TOOLCHAIN_CONFIGURE_PRESETS and item != base_preset_name
    ]

    preset: dict[str, Any] = {
        "name": f"{base_preset_name}-{source_name}",
        "displayName": f"Nix+Conan {source_preset.get('displayName', source_name)}",
        "description": f"Nix+Conan variant of `{source_name}`.",
        "inherits": [base_preset_name, *filtered_inherits],
    }
    if "cacheVariables" in source_preset:
        preset["cacheVariables"] = source_preset["cacheVariables"]
    return preset


def render_envrc(config: dict[str, Any]) -> str:
    default_shell = config["default_shell"]
    platform_defaults = config.get("platform_default_shells", {})
    darwin_default = platform_defaults.get("darwin", default_shell)
    linux_default = platform_defaults.get("linux", default_shell)
    return "\n".join(
        [
            f"# Generated by {SCRIPT_HINT}",
            f': "${{NIX_DEVSHELL:={default_shell}}}"',
            'if [[ -z "${NIX_DEVSHELL_SET_BY_PLATFORM:-}" ]]; then',
            '  case "$(uname -s)" in',
            f'    Darwin) export NIX_DEVSHELL="{darwin_default}" ;;',
            f'    Linux) export NIX_DEVSHELL="{linux_default}" ;;',
            "  esac",
            "fi",
            'use flake ".#${NIX_DEVSHELL}"',
            "",
        ]
    )


def format_nix_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def render_flake(config: dict[str, Any]) -> str:
    systems = config.get("systems", DEFAULT_CONFIG["systems"])
    if not isinstance(systems, list) or not systems:
        die("config 'systems' must be a non-empty list.")
    shells = config["shells"]
    default_shell = config["default_shell"]
    description = config.get("description", "dev env shells")

    lines: list[str] = [
        "{",
        f'  description = "{format_nix_string(str(description))}";',
        "",
        '  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";',
        "",
        "  outputs = { self, nixpkgs }:",
        "    let",
        "      systems = [",
    ]
    for system in systems:
        lines.append(f'        "{system}"')
    lines += [
        "      ];",
        "      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);",
        "    in",
        "    {",
        "      devShells = forAllSystems (system:",
        "        let",
        "          pkgs = import nixpkgs { inherit system; };",
        "        in",
        "        {",
    ]

    for shell_name, shell_data in shells.items():
        packages = shell_data.get("packages", [])
        if not isinstance(packages, list):
            die(f"shell {shell_name!r}: packages must be a list.")
        pkg_list = " ".join(packages)
        lines += [
            f"          {shell_name} = pkgs.mkShell {{",
            f"            packages = with pkgs; [ {pkg_list} ];",
        ]
        env_vars = shell_data.get("env", {})
        if env_vars:
            lines.append("            shellHook = ''")
            for key, value in env_vars.items():
                lines.append(f'              export {key}="{format_nix_string(value)}"')
            lines.append("            '';")
        lines += [
            "          };",
            "",
        ]

    default_packages = " ".join(shells[default_shell]["packages"])
    lines += [
        "          default = pkgs.mkShell {",
        f"            packages = with pkgs; [ {default_packages} ];",
        "          };",
        "        });",
        "    };",
        "}",
        "",
    ]
    return "\n".join(lines)


def render_conan_profile(profile_data: dict[str, Any]) -> str:
    include_profile = profile_data.get("include", "default")
    settings = profile_data.get("settings", {})
    toolchain = profile_data.get("user_toolchain")
    if not isinstance(settings, dict) or not settings:
        die("conan profile settings must be a non-empty object.")
    if not toolchain:
        die("conan profile is missing user_toolchain.")
    if not isinstance(toolchain, str):
        die("conan profile user_toolchain must be a string.")

    normalized_toolchain = toolchain.strip()
    if not normalized_toolchain:
        die("conan profile user_toolchain must not be empty.")
    if "{{profile_dir}}" not in normalized_toolchain:
        # Keep absolute paths as-is; make relative ones stable from profile location.
        is_posix_abs = normalized_toolchain.startswith("/")
        is_windows_abs = (
            len(normalized_toolchain) >= 3
            and normalized_toolchain[1] == ":"
            and normalized_toolchain[2] in {"\\", "/"}
        )
        if not (is_posix_abs or is_windows_abs):
            normalized_toolchain = (
                "{{profile_dir}}/../../" + normalized_toolchain.lstrip("./")
            )

    lines = [
        f"include({include_profile})",
        "",
        "[settings]",
    ]
    for key, value in settings.items():
        lines.append(f"{key}={value}")
    lines += [
        "",
        "[conf]",
        "tools.cmake.cmaketoolchain:generator=Ninja",
        f'tools.cmake.cmaketoolchain:user_toolchain=["{normalized_toolchain}"]',
        "",
    ]
    return "\n".join(lines)


def render_conanfile(config: dict[str, Any]) -> str:
    conanfile = config.get(
        "conanfile",
        {
            "format": "txt",
            "generators": ["CMakeDeps", "CMakeToolchain"],
            "requires": [],
        },
    )
    if not isinstance(conanfile, dict):
        die("config key 'conanfile' must be an object.")

    format_name = conanfile.get("format", "txt")
    if format_name != "txt":
        die("only conanfile format 'txt' is supported right now.")

    generators = conanfile.get("generators", ["CMakeDeps", "CMakeToolchain"])
    requires = conanfile.get("requires", [])
    if not isinstance(generators, list) or not generators:
        die("conanfile.generators must be a non-empty list.")
    if not isinstance(requires, list):
        die("conanfile.requires must be a list.")

    lines: list[str] = []
    if requires:
        lines += ["[requires]"]
        for requirement in requires:
            lines.append(str(requirement))
        lines.append("")

    lines += ["[generators]"]
    for generator in generators:
        lines.append(str(generator))
    lines.append("")
    return "\n".join(lines)


def sync_cmake_presets(root: Path, config: dict[str, Any]) -> None:
    cmake_config = config.get("cmake_presets", {})
    if not isinstance(cmake_config, dict):
        die("config key 'cmake_presets' must be an object.")

    presets_path = root / str(cmake_config.get("path", "CMakePresets.json"))
    if not presets_path.exists():
        die(f"CMake presets file not found: {presets_path}")

    base_preset_name = str(cmake_config.get("base_preset_name", "nix-conan"))
    source_presets = cmake_config.get("source_presets", [])
    if not isinstance(source_presets, list) or not source_presets:
        die("cmake_presets.source_presets must be a non-empty list.")

    try:
        cmake_data = json.loads(presets_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        die(f"invalid JSON in {presets_path}: {exc}")

    for key in ("configurePresets", "buildPresets", "testPresets", "workflowPresets"):
        if key not in cmake_data or not isinstance(cmake_data[key], list):
            die(f"{presets_path} is missing list key: {key}")

    configure_presets = cmake_data["configurePresets"]
    build_presets = cmake_data["buildPresets"]
    test_presets = cmake_data["testPresets"]
    workflow_presets = cmake_data["workflowPresets"]

    base_configure_preset = {
        "name": base_preset_name,
        "hidden": True,
        "toolchainFile": "${sourceDir}/build/conan/conan_toolchain.cmake",
    }
    upsert_named_preset(configure_presets, base_configure_preset)

    generated_preset_names: list[str] = []
    for source_name_raw in source_presets:
        source_name = str(source_name_raw)
        source = find_named_preset(configure_presets, source_name)
        if source is None:
            die(f"source configure preset {source_name!r} not found in {presets_path}")
        generated_configure = render_nix_conan_configure_preset(
            source_name=source_name,
            source_preset=source,
            base_preset_name=base_preset_name,
        )
        upsert_named_preset(configure_presets, generated_configure)
        generated_name = str(generated_configure["name"])
        generated_preset_names.append(generated_name)

        upsert_named_preset(
            build_presets,
            {
                "name": generated_name,
                "configurePreset": generated_name,
                "inherits": ["base"],
            },
        )
        upsert_named_preset(
            test_presets,
            {
                "name": generated_name,
                "inherits": "base",
                "configurePreset": generated_name,
            },
        )
        upsert_named_preset(
            workflow_presets,
            {
                "name": generated_name,
                "displayName": (
                    f"Nix+Conan {source.get('displayName', source_name)}: "
                    "configure, build, test"
                ),
                "description": f"Nix+Conan local/CI loop for {source_name}.",
                "steps": [
                    {"type": "configure", "name": generated_name},
                    {"type": "build", "name": generated_name},
                    {"type": "test", "name": generated_name},
                ],
            },
        )

    presets_path.write_text(json.dumps(cmake_data, indent=2) + "\n", encoding="utf-8")
    print(
        f"Synchronized {len(generated_preset_names)} Nix+Conan presets in {presets_path}"
    )


def cmd_init(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    config_path = root / CONFIG_FILE
    if config_path.exists() and not args.force:
        die(f"{config_path} already exists. use --force to overwrite.")
    write_file(config_path, json.dumps(DEFAULT_CONFIG, indent=2) + "\n")
    print(f"Wrote {config_path}")


def cmd_render(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    config = load_config(resolve_config_path(root))

    write_file(root / FLAKE_FILE, render_flake(config))
    write_file(root / ENVRC_FILE, render_envrc(config))
    write_file(root / CONANFILE_TXT, render_conanfile(config))

    conan_profiles = config["conan_profiles"]
    if not isinstance(conan_profiles, dict):
        die("config key 'conan_profiles' must be an object.")
    for profile_name, profile_data in conan_profiles.items():
        if not isinstance(profile_data, dict):
            die(f"conan profile {profile_name!r} must be an object.")
        profile_path = root / CONAN_PROFILES_DIR / profile_name
        write_file(profile_path, render_conan_profile(profile_data))

    print(f"Wrote {root / FLAKE_FILE}")
    print(f"Wrote {root / ENVRC_FILE}")
    print(f"Wrote {root / CONANFILE_TXT}")
    print(
        f"Wrote {len(conan_profiles)} Conan profiles under {root / CONAN_PROFILES_DIR}"
    )

    cmake_config = config.get("cmake_presets", {})
    if isinstance(cmake_config, dict) and bool(cmake_config.get("auto_sync_on_render")):
        sync_cmake_presets(root, config)


def cmd_switch_shell(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    config_path = resolve_config_path(root)
    config = load_config(config_path)
    shell_name = args.shell
    if shell_name not in config["shells"]:
        available = ", ".join(sorted(config["shells"].keys()))
        die(f"unknown shell {shell_name!r}. available: {available}")

    config["default_shell"] = shell_name
    write_file(config_path, json.dumps(config, indent=2) + "\n")
    write_file(root / ENVRC_FILE, render_envrc(config))
    print(f"Set default_shell={shell_name} in {config_path}")
    print(f"Wrote {root / ENVRC_FILE}")

    if args.reload_direnv:
        result = subprocess.run(["direnv", "allow"], cwd=root, check=False)
        if result.returncode != 0:
            die("`direnv allow` failed after switching shell.")
        print("Ran `direnv allow`.")


def cmd_bootstrap_prereqs(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    config = load_config(resolve_config_path(root))
    bootstrap = config.get("bootstrap", {})
    if not isinstance(bootstrap, dict):
        die("config key 'bootstrap' must be an object.")

    os_name = platform.system()
    install_mode = args.install
    assume_yes = args.yes

    nix_installer = args.nix_installer or bootstrap.get("nix_installer", "determinate")
    if nix_installer not in {"determinate", "official"}:
        die("nix installer must be one of: determinate, official")

    install_nix = bool(bootstrap.get("install_nix", True))
    install_direnv = bool(bootstrap.get("install_direnv", True))
    install_xcode = bool(bootstrap.get("install_xcode_clt_on_macos", True))
    configure_hook = bool(bootstrap.get("configure_direnv_hook", True))
    hook_targets = resolve_direnv_hook_targets(bootstrap)

    needs_xcode = os_name == "Darwin" and install_xcode and not xcode_clt_installed()
    needs_nix = install_nix and not command_exists("nix")
    needs_direnv = install_direnv and not command_exists("direnv")
    needs_curl = (needs_nix or needs_direnv) and not command_exists("curl")

    print(f"OS: {os_name}")
    print(f"install mode: {'ON' if install_mode else 'OFF'}")
    print(f"- xcode clt: {'missing' if needs_xcode else 'ok/skipped'}")
    print(f"- nix: {'missing' if needs_nix else 'ok/skipped'}")
    print(f"- direnv: {'missing' if needs_direnv else 'ok/skipped'}")
    print(f"- curl: {'missing' if needs_curl else 'ok/skipped'}")

    if not any((needs_xcode, needs_nix, needs_direnv, needs_curl)):
        print("All configured prerequisites are already installed.")
        if configure_hook and command_exists("direnv"):
            for rc_path, shell_name in hook_targets:
                ensure_direnv_hook(rc_path, shell_name)
        return

    if not install_mode:
        print(
            "Some prerequisites are missing. Re-run with `--install` to install them."
        )
        return

    if os_name == "Darwin":
        if needs_xcode:
            print("Requesting Xcode Command Line Tools installation dialog...")
            run_checked(["xcode-select", "--install"])
        if needs_curl:
            die("curl is missing on macOS; install it manually first.")

        if needs_direnv:
            if command_exists("brew"):
                cmd = ["brew", "install", "direnv"]
                run_checked(cmd)
            else:
                die("Homebrew is required to auto-install direnv on macOS.")
    elif os_name == "Linux":
        linux_packages: list[str] = []
        if needs_curl:
            linux_packages.append("curl")
        if needs_direnv:
            linux_packages.append("direnv")
        if linux_packages:
            install_linux_packages(linux_packages, assume_yes=assume_yes)
    else:
        die(f"unsupported OS for bootstrap: {os_name}")

    if needs_nix:
        if nix_installer == "determinate":
            run_shell_checked(
                "curl --proto '=https' --tlsv1.2 -sSf -L "
                "https://install.determinate.systems/nix | "
                "sh -s -- install --no-confirm"
            )
        else:
            run_shell_checked(
                "curl -L https://nixos.org/nix/install | sh -s -- --daemon"
            )

    if configure_hook:
        if command_exists("direnv"):
            for rc_path, shell_name in hook_targets:
                ensure_direnv_hook(rc_path, shell_name)
        else:
            print("Skipping direnv hook setup because `direnv` is still unavailable.")


def cmd_sync_cmake_presets(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    config = load_config(resolve_config_path(root))
    sync_cmake_presets(root, config)


def cmd_setup(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    config_path = resolve_config_path(root)

    if config_path.exists():
        print(f"Using existing {config_path}")
    else:
        write_file(config_path, json.dumps(DEFAULT_CONFIG, indent=2) + "\n")
        print(f"Wrote {config_path}")

    config = load_config(config_path)

    write_file(root / FLAKE_FILE, render_flake(config))
    write_file(root / ENVRC_FILE, render_envrc(config))
    write_file(root / CONANFILE_TXT, render_conanfile(config))

    conan_profiles = config["conan_profiles"]
    if not isinstance(conan_profiles, dict):
        die("config key 'conan_profiles' must be an object.")
    for profile_name, profile_data in conan_profiles.items():
        if not isinstance(profile_data, dict):
            die(f"conan profile {profile_name!r} must be an object.")
        profile_path = root / CONAN_PROFILES_DIR / profile_name
        write_file(profile_path, render_conan_profile(profile_data))

    print(f"Wrote {root / FLAKE_FILE}")
    print(f"Wrote {root / ENVRC_FILE}")
    print(f"Wrote {root / CONANFILE_TXT}")
    print(
        f"Wrote {len(conan_profiles)} Conan profiles under {root / CONAN_PROFILES_DIR}"
    )

    if args.sync_cmake_presets:
        sync_cmake_presets(root, config)

    bootstrap_args = argparse.Namespace(
        root=str(root),
        install=args.install_prereqs,
        yes=args.yes,
        nix_installer=args.nix_installer,
    )
    cmd_bootstrap_prereqs(bootstrap_args)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=".",
        help="Project root directory (default: current directory).",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser("init", help=f"Create default {CONFIG_FILE}")
    init_parser.add_argument(
        "--force",
        action="store_true",
        help=f"Overwrite an existing {CONFIG_FILE}",
    )
    init_parser.set_defaults(func=cmd_init)

    render_parser = subparsers.add_parser(
        "render",
        help=(
            f"Render flake.nix, .envrc, conanfile.txt and Conan profiles from "
            f"{CONFIG_FILE}"
        ),
    )
    render_parser.set_defaults(func=cmd_render)

    switch_parser = subparsers.add_parser(
        "switch-shell",
        help=f"Set default_shell in {CONFIG_FILE} and regenerate .envrc",
    )
    switch_parser.add_argument("shell", help=f"Shell name from {CONFIG_FILE}")
    switch_parser.add_argument(
        "--reload-direnv",
        action="store_true",
        help="Run `direnv allow` after updating .envrc",
    )
    switch_parser.set_defaults(func=cmd_switch_shell)

    bootstrap_parser = subparsers.add_parser(
        "bootstrap-prereqs",
        help="Check or install local prerequisites (nix, direnv, Xcode CLT).",
    )
    bootstrap_parser.add_argument(
        "--install",
        action="store_true",
        help="Install missing prerequisites.",
    )
    bootstrap_parser.add_argument(
        "--yes",
        action="store_true",
        help="Assume yes for Linux package manager prompts where supported.",
    )
    bootstrap_parser.add_argument(
        "--nix-installer",
        choices=["determinate", "official"],
        help=f"Override bootstrap.nix_installer from {CONFIG_FILE}.",
    )
    bootstrap_parser.set_defaults(func=cmd_bootstrap_prereqs)

    sync_cmake_parser = subparsers.add_parser(
        "sync-cmake-presets",
        help="Sync Nix+Conan configure/build/test/workflow presets into CMakePresets.json.",
    )
    sync_cmake_parser.set_defaults(func=cmd_sync_cmake_presets)

    setup_parser = subparsers.add_parser(
        "setup",
        help=(
            "One-shot setup: create config if needed, render generated files, "
            "sync CMake presets, and check/install prerequisites."
        ),
    )
    setup_parser.add_argument(
        "--no-sync-cmake-presets",
        dest="sync_cmake_presets",
        action="store_false",
        help="Skip syncing CMakePresets.json.",
    )
    setup_parser.add_argument(
        "--install-prereqs",
        action="store_true",
        help="Install missing prerequisites during setup.",
    )
    setup_parser.add_argument(
        "--yes",
        action="store_true",
        help="Assume yes for Linux package manager prompts where supported.",
    )
    setup_parser.add_argument(
        "--nix-installer",
        choices=["determinate", "official"],
        help=f"Override bootstrap.nix_installer from {CONFIG_FILE}.",
    )
    setup_parser.set_defaults(func=cmd_setup, sync_cmake_presets=True)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
