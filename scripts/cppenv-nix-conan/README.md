# cppenv-nix-conan

Small, movable boilerplate generator for project-local Nix/direnv/Conan setup.

## Why

- Keep repeated shell/profile boilerplate in one config file (`cppenv-nix-conan.json`).
- Regenerate `flake.nix`, `.envrc`, `conanfile.txt`, and Conan profiles consistently.
- Easy to lift this directory into a dedicated repo later.

## Commands

From repo root:

```bash
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py setup
```

One-shot setup with prereq installation:

```bash
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py setup --install-prereqs --yes
```

Manual step-by-step:

```bash
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py init
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py render
```

Sync Nix+Conan presets in `CMakePresets.json`:

```bash
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py sync-cmake-presets
```

Check prerequisites:

```bash
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py bootstrap-prereqs
```

Install missing prerequisites (Linux/macOS):

```bash
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py bootstrap-prereqs --install --yes
```

Switch default shell:

```bash
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py switch-shell clang21
# optionally:
python3 devenv/scripts/cppenv-nix-conan/cppenv-nix-conan.py switch-shell gcc15 --reload-direnv
```

## Generated files

- `cppenv-nix-conan.json` (source config)
- `flake.nix`
- `.envrc`
- `conanfile.txt`
- `conan/profiles/*` (declared profiles from config)

## Notes

- `switch-shell` edits `default_shell` in `cppenv-nix-conan.json` and regenerates `.envrc`.
- Per-platform default shells are controlled via `platform_default_shells`.
- Adjust package/profile names in `cppenv-nix-conan.json` if your nixpkgs snapshot changes.
- `bootstrap-prereqs` behavior is controlled in `cppenv-nix-conan.json` under `bootstrap`.
- `bootstrap-prereqs` ensures direnv hooks exist in both `~/.zshrc` and `~/.bashrc`
  by default and skips files that already contain the matching hook.
- Customize hook targets via `bootstrap.shell_rc_files` (list of rc files).
- Conan profile `user_toolchain` paths are rendered relative to profile location
  using `{{profile_dir}}`, so CI and local builds do not depend on build folder layout.
- CMake presets sync behavior is controlled under `cmake_presets` (`path`, `source_presets`, `auto_sync_on_render`).
- `conanfile.txt` is generated from `cppenv-nix-conan.json` (`conanfile` section) and will be overwritten on `render/setup`.
