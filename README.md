# devenv

[![CI](https://github.com/devmarkusb/devenv/actions/workflows/ci.yml/badge.svg)](https://github.com/devmarkusb/devenv/actions/workflows/ci.yml)
[![Lint](https://github.com/devmarkusb/devenv/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/devmarkusb/devenv/actions/workflows/pre-commit.yml)

Basic must-haves for a convenient general infrastructure setup of C++ apps/libs. Intended to be added as a **git
submodule** to your project repo.

## Quick start

From your project repo root, add devenv as a submodule (SSH or HTTPS):

```bash
git submodule add https://github.com/devmarkusb/devenv.git devenv
# or (less preferable, permission issues for ci)
git submodule add git@github.com:devmarkusb/devenv.git devenv
```

Then run the bootstrap script **from the project repo root** (so `.venv` is created there and pre-commit hooks apply to
your project):

```bash
./devenv/bootstrap.sh
```

This creates a Python venv in `.venv`, installs [pre-commit](https://pre-commit.com), and runs `pre-commit install` so
hooks run on commit. Your project should have its own `.pre-commit-config.yaml` at the repo root; pre-commit will use
that.

## Maintaining / updating the submodule

After cloning or pulling your main repo, update submodules from the main repo root:

```bash
git submodule update --init --recursive --recommend-shallow
```

Or use the convenience script (same directory):

```bash
./devenv/git-sub.sh
```

`git-sub.sh` also initializes and runs **Git LFS** (`git lfs pull`) if your repo uses LFS (detected via `filter=lfs` in
`.gitattributes`), and can install `git-lfs` on Linux (apt) or macOS (Homebrew) if missing.

---

## Features

### pre-commit

- **Bootstrap:** `./devenv/bootstrap.sh` sets up a venv and installs pre-commit in your project; hooks are defined by the
  project’s root `.pre-commit-config.yaml`.
- **Run on all files:**
  `pre-commit run --all-files`
- **Devenv’s own config:** `devenv/.pre-commit-config.yaml` is a minimal config used when working inside the devenv
  repo (e.g. gersemi, codespell, YAML checks). Consumer projects use their own config at the repo root.

For a shared, versioned `.clang-format`, use [devmarkusb/dot-clangformat](https://github.com/devmarkusb/dot-clangformat)
and follow its README (CMake **FetchContent**, Python one-shot install, preset choice vs. clang-format major).

### cmake

#### Toolchains (`cmake/toolchains/`)

CMake toolchain files for use with presets or `-DCMAKE_TOOLCHAIN_FILE=...`:

| File                           | Compiler              | Notes                                           |
|--------------------------------|-----------------------|-------------------------------------------------|
| `gcc-toolchain.cmake`          | GCC (gcc/g++)         | Linux / MinGW                                   |
| `clang-toolchain.cmake`        | Clang (clang/clang++) | libstdc++ by default                            |
| `clang-libc++-toolchain.cmake` | Clang with libc++     | Includes clang-toolchain, adds `-stdlib=libc++` |
| `appleclang-toolchain.cmake`   | Apple Clang (cc/c++)  | macOS                                           |
| `msvc-toolchain.cmake`         | MSVC (cl)             | Windows                                         |

Optional **sanitizers** via cache variable `MB_DEVENV_SANITIZER`:

- **MaxSan** — Address, leak, pointer-compare/subtract, undefined (and on MSVC, address only).
- **TSan** — Thread sanitizer.
- **MSan** — Memory sanitizer (Clang/AppleClang only; uses `msan.supp` if present).

Release-type configs use `-O3` (or MSVC `/O2`) and can still add sanitizer flags. Toolchains append the project root to
`CMAKE_PREFIX_PATH` so `find_package(...)` can resolve config packages from the build tree.

#### fetch-content-from-lockfile.cmake

CMake **dependency provider** (CMake 3.24+). Include it as a top-level include (e.g. via
`CMAKE_PROJECT_TOP_LEVEL_INCLUDES` in presets). It:

- Reads a JSON lockfile from the **consumer project** (default: `fetchcontent-lockfile.json` in the project root;
  override with `MB_DEVENV_FETCHCONTENT_LOCKFILE`).
- Implements `FIND_PACKAGE`: when the project calls `find_package(PkgName)`, the provider can satisfy it by FetchContent
  using `git_repository` and `git_tag` from the lockfile.
- Adds the lockfile to `CMAKE_CONFIGURE_DEPENDS` so CMake reconfigures when the lockfile changes.

Lockfile format: a JSON object with a `dependencies` array. Each entry requires **`name`**, **`git_repository`**, and
**`git_tag`**. Optional fields:

- **`package_name`** — If set (non-empty), that dependency is resolved when the project calls
  `find_package(<package_name>)` (FetchContent + `set(<Package>_FOUND)`).
- **`cmake_include`** — For dependencies *without* `package_name`, used with FetchContent during the top-level include:
  path under the fetched repo to a `.cmake` file to `include()` after populate (avoids nested `project()` when the dep has
  its own `CMakeLists.txt`).
- **`cmake_variables`** — JSON object: keys are CMake variable names, values are strings or numbers (applied as
  `set()` before `include()` or `FetchContent_MakeAvailable`). On the `find_package` path, variables are applied after
  defaults such as `INSTALL_GTEST` for GoogleTest, so the lockfile can override them.

This gives reproducible builds without relying on system packages (e.g. GTest).

#### mb-devenv-install-library-config.cmake

Defines **`mb_devenv_install_library(name)`** for header-only/INTERFACE libraries. Call it with a target name of the form
`namespace.library-name` (e.g. `mb.cpp-lib-template-header-only`). It:

- Installs the target and its `FILE_SET HEADERS`.
- Optionally installs a CMake config-file package (so consumers can `find_package(...)`) using a template
  `cmake/<name>-config.cmake.in`.
- Config is controlled by
  `MB_DEVENV_INSTALL_CONFIG_FILE_PACKAGES` (list) or `<UPPERCASE_NAME>_INSTALL_CONFIG_FILE_PACKAGE` (
  per-library ON/OFF).

### .github/workflows

#### ci.yml

Runs on pushes to `main`, pull requests, and manual dispatch. Uses **CMake 3.31+** (matches `cmakeMinimumRequired` in
`CMakePresets.json`; `cmake_minimum_required` in `CMakeLists.txt` is 3.24 for consumers including only individual
`.cmake` modules). Jobs mirror `CMakePresets.json`:

- **workflow preset `ci`** on Ubuntu and macOS (`cmake --workflow --preset ci`) — Ninja, Release, lockfile FetchContent.
- **workflow preset `dev`** on Ubuntu — Ninja, Debug, same dependency path as local dev.
- **presets `unix-makefiles`** on Ubuntu — `Unix Makefiles` generator without Ninja.
- **`ci` + `cmake/toolchains/clang-toolchain.cmake`** on Ubuntu — exercises the Clang toolchain file with the `ci` preset.
- **presets `vs2022` / `vs2022-debug`** on Windows — Visual Studio 2022, MSVC x64.

#### pre-commit.yml

Reusable workflow for **lint check (pre-commit)**. Main repo typically calls it from a workflow like
`pre-commit-check.yml` with `uses: .../devenv/.github/workflows/pre-commit.yml`.

- **On push to `main`:** Full checkout (with submodules), runs pre-commit on **all files** so formatting/lint issues are
  fixed over the whole tree.
- **On pull_request_target:** Checkouts the PR branch, runs pre-commit only on **changed files**, then uses
  **reviewdog** (action-suggester) to post suggested fixes as PR comments.

Requires Python (e.g. 3.13) and, for PRs, `gh` and a token that can write checks and comments.

### .gitignore

Just as a sidenote, our .gitignore is overkill for this current repo but by the way provides a
reasonable template default for C++ projects. So you might copy and paste.
