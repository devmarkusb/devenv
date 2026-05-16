# devenv

[![CI](https://github.com/devmarkusb/devenv/actions/workflows/ci.yml/badge.svg)](https://github.com/devmarkusb/devenv/actions/workflows/ci.yml)
[![Lint](https://github.com/devmarkusb/devenv/actions/workflows/pre-commit-check.yml/badge.svg)](https://github.com/devmarkusb/devenv/actions/workflows/pre-commit-check.yml)

Basic must-haves for a convenient general infrastructure setup of C++ apps/libs. Intended to be added as a **git
submodule** to your project repo.

## Quick start

From your project repo root, add devenv as a submodule (SSH or HTTPS):

```bash
git submodule add https://github.com/devmarkusb/devenv.git devenv
# or (less preferable, permission issues for ci)
git submodule add git@github.com:devmarkusb/devenv.git devenv
```

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
`CMAKE_PREFIX_PATH`.

#### fetch-content-from-lockfile.cmake

CMake **dependency provider** (CMake 3.24+). Include it as a top-level include (e.g., via
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
  path under the fetched repo to a `.cmake` file to `include()` after populate (avoids nested `project()` when the dep
  has its own `CMakeLists.txt`).
- **`cmake_variables`** — JSON object: keys are CMake variable names, values are strings or numbers (applied as
  `set()` before `include()` or `FetchContent_MakeAvailable`). On the `find_package` path, variables are applied after
  defaults such as `INSTALL_GTEST` for GoogleTest, so the lockfile can override them.

This gives reproducible builds without relying on system packages (e.g., GTest).

#### pre-commit (mb-pre-commit)

When you `add_subdirectory(devenv)` from a parent repo, `devenv/CMakeLists.txt` calls
`mb_pre_commit_setup_subdirectory()` (mb-pre-commit **v2.5.0+**, via `fetchcontent-lockfile.json`) so commits made
**inside `devenv/`** get hooks and a `.venv` there. Your parent should still call `mb_pre_commit_setup()` for its own
tree. The parent hook does **not** run on submodule commits.

After updating the `devenv` submodule, re-run CMake in the parent so hooks/venv refresh. Sweep target in the submodule:
`mb-pre-commit-sweep-devenv` (default name from `CMAKE_PROJECT_NAME`).

#### mb-devenv-install-library-config.cmake

Defines **`mb_devenv_install_library(name)`** for libraries. Call it with a target name of the form
`namespace.library-name` (e.g. `mb.cpp-lib-template`). It:

- Installs the target and its `FILE_SET HEADERS`.
- Optionally installs a CMake config-file package (so consumers can `find_package(...)`) using a template
  `cmake/<name>-config.cmake.in`.
- Config is controlled by
  `MB_DEVENV_INSTALL_CONFIG_FILE_PACKAGES` (list) or `<UPPERCASE_NAME>_INSTALL_CONFIG_FILE_PACKAGE` (
  per-library ON/OFF).

#### mb-devenv-cppcheck.cmake

Optional **build-time cppcheck integration** via CMake's `CMAKE_CXX_CPPCHECK`. Include it once from your
project root `CMakeLists.txt`:

```cmake
include(devenv/cmake/mb-devenv-cppcheck.cmake)
```

Then configure with `-DMB_DEVENV_CPPCHECK=ON` to activate, and optionally
`-DMB_DEVENV_CPPCHECK_AUTO_INSTALL=ON` to install cppcheck automatically if missing.

**This is independent of `run-cppcheck.sh`.** Use one, the other, or both — they complement each other:

|             | `mb-devenv-cppcheck.cmake`              | `run-cppcheck.sh`                  |
|-------------|-----------------------------------------|------------------------------------|
| When        | Every `cmake --build`                   | Explicitly (locally or in CI)      |
| How         | `CMAKE_CXX_CPPCHECK` per TU             | `--project=compile_commands.json`  |
| Speed       | Fast (no exhaustive check)              | Thorough                           |
| Checks      | `warning,style,performance,portability` | Same + `--check-level=exhaustive`  |
| Extra flags | `--force`                               | `--library=googletest`             |

`--check-level=exhaustive` is intentionally absent from the build-time integration — it would make every
incremental build too slow. `--force` is present because cmake may not expose every include path across all
`#ifdef` configurations; the script uses `--project=compile_commands.json` which embeds the exact compile
flags, so `--force` is unnecessary there. The `--enable` flag set is the same in both.

`MB_DEVENV_CPPCHECK_EXECUTABLE` is set as a CMake cache variable pointing to the found/installed binary.

### clang-tidy-review.py

Script for running clang-tidy locally or in CI with the same selection logic. Requires clang-tidy to be installed
(use `--install` on supported platforms) and a configured build directory (`--preset` must name a valid CMake configure
preset that produces a `compile_commands.json`).

**Local usage:**

```bash
# Lint only lines changed since the upstream / origin/main / main branch
python3 devenv/clang-tidy-review.py changed

# Lint the full project
python3 devenv/clang-tidy-review.py full

# Show warning statistics instead of suppressing noise with --quiet
python3 devenv/clang-tidy-review.py changed --show-summary

# Install or upgrade to the latest available clang-tidy first
python3 devenv/clang-tidy-review.py changed --install

# Override the CMake preset (default: clang-release)
python3 devenv/clang-tidy-review.py full --preset clang-debug

# Save output to a file while also printing it
python3 devenv/clang-tidy-review.py full --report-file /tmp/tidy.txt
```

In `changed` mode, if any changed file is a header, a CMake file, or anything under `cmake/` /
`devenv/cmake/`, the script automatically widens the scan to the **full project** (a header change can affect
any translation unit). The diff base defaults to the merge-base with the upstream branch; override with
`--base <sha>`.

Also ships `clang-tidy-problem-matcher.json` which GitHub Actions workflows can load with
`::add-matcher::devenv/clang-tidy-problem-matcher.json` to turn clang-tidy diagnostics into inline PR annotations.

### install-boost.py / install-boost.sh

Locates or installs **Boost** for CMake **`find_package(Boost CONFIG)`** (used by consumers such as
**uiwrap** with the `own` backend). **Linux:** `apt` `libboost-all-dev` when available (including
Beman CI containers, even if `/opt/vcpkg` exists). **macOS:** Homebrew. **Windows:** vcpkg via
`VCPKG_INSTALLATION_ROOT`. Falls back to vcpkg on Linux only when `apt-get` is unavailable.

**Local usage:**

```bash
# Install if missing, print the CMake prefix
python3 devenv/install-boost.py --ensure --print-prefix-path

# CI helper (also appends CMAKE_PREFIX_PATH to GITHUB_ENV when set)
./devenv/install-boost.sh
```

Optional flags: `--components property-tree` (vcpkg package names `boost-<component>`),
`--vcpkg-triplet x64-linux`.

**CI usage:** pass `default_setup_script: devenv/install-boost.sh` to
`preset-test.yml` or `build-and-test.yml` (no forked “with-boost” workflows required).

### install-cppcheck.py

Locates or installs cppcheck using the platform's package manager (apt, dnf, pacman, zypper, emerge,
Homebrew, winget, choco). Used internally by `run-cppcheck.sh` but can also be called directly:

```bash
# Print the path to the detected cppcheck executable
python3 devenv/install-cppcheck.py --print-path

# Install if not present, then print the path
python3 devenv/install-cppcheck.py --ensure --print-path
```

### run-cppcheck.sh

Convenience script that wires together cmake configure, cppcheck installation, and the cppcheck run. It is
designed to be called from the consumer's project root (either locally or from CI):

```bash
# Run with the default preset (clang-release) — cmake configure + cppcheck
./devenv/run-cppcheck.sh

# Override preset and/or build directory
./devenv/run-cppcheck.sh clang-debug
./devenv/run-cppcheck.sh clang-release /tmp/custom-build
```

The script:

- Calls `install-cppcheck.py --ensure --print-path` to locate or install cppcheck automatically.
- Configures cmake (`cmake -S . --preset <preset> -B <build-dir>`) to produce `compile_commands.json`.
- Runs cppcheck with `--enable=warning,style,performance,portability`, `--check-level=exhaustive`,
  `--inline-suppr`, `--inconclusive`, `--library=googletest`, and `--template=gcc`.
- If `CppCheckSuppressions.txt` exists in the project root, passes it via `--suppressions-list`.
- Excludes `_deps/` (FetchContent dependencies) from analysis.

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

#### pre-commit-check.yml

Devenv's own trigger workflow — calls `pre-commit.yml` on push to `main` and `pull_request_target`. Use it as a
template for consumer repos that want the same pattern without referencing devenv's internal workflow directly.

---

## Reusable GitHub Actions workflows

The following workflows are designed to be called from consumer C++ CMake project repositories. Reference them with a
**full ref** (tag, SHA, or branch) so upstream changes don't break your CI unexpectedly:

```yaml
jobs:
  build:
    uses: devmarkusb/devenv/.github/workflows/build-and-test.yml@main
    with:
      matrix_config: ${{ vars.MATRIX_JSON }}
```

Pin the callee ref (e.g. `@v1.0.0` or a commit SHA) for stability.

Consumer repos are expected to include devenv as a git submodule at `devenv/` so the toolchain files and CMake modules
referenced inside these workflows resolve correctly.

### build-and-test.yml

**Trigger:** `workflow_call`

| Input                    | Required | Description                                                  |
|--------------------------|----------|--------------------------------------------------------------|
| `matrix_config`          | yes      | Compiler-keyed JSON matrix (see below).                      |
| `default_setup_script`   | no       | Repo-relative bash script for rows that omit `setup_script`. |

Expands a nested JSON structure into a flat compiler × version × C++ standard × stdlib × test-type matrix. Linux
gcc/clang jobs run in `ghcr.io/bemanproject/infra-containers-<compiler>:<version>` Docker images; Apple Clang uses
`macos-latest`; MSVC uses `windows-latest`. Supported test-type suffixes: `Default`, `TSan`, `MSan`, `MaxSan`,
`MaxWarn`, `MaxWarnMsvc`, `Dynamic`, `Coverage`. Coverage rows run `gcovr` and upload to [Coveralls](https://coveralls.io)
(activate the repo at coveralls.io and results appear at `https://coveralls.io/github/<org>/<repo>`).

Optional setup fields (`setup_script`, `setup`, `setup_shell`) may appear at the **top level** of `matrix_config` (applied
to every row), on a compiler-branch array element (the object with `"versions"`), or on nested objects in the `tests`
tree — inner levels override outer (not on individual test name strings such as `"Debug.Default"`). Consumer setup runs
after checkout and before MSVC/macOS/CMake setup.
Inline `setup` defaults to `pwsh` on `msvc` jobs and `bash` otherwise unless `setup_shell` is set.

**Consumer assumptions:** `devenv/cmake/toolchains/*.cmake` and
`devenv/cmake/fetch-content-from-lockfile.cmake` present; Ninja Multi-Config generator.

### preset-test.yml

**Trigger:** `workflow_call`

| Input                    | Required | Description                                                                                               |
|--------------------------|----------|-----------------------------------------------------------------------------------------------------------|
| `matrix_config`          | yes      | JSON **array** of preset matrix objects (see below).                                                      |
| `default_setup_script`   | no       | Repo-relative bash script for entries that omit `setup_script` (e.g. `.github/ci/preset-setup.sh`).       |

Each matrix object supports:

| Field            | Required | Description                                                                               |
|------------------|----------|-------------------------------------------------------------------------------------------|
| `preset`         | yes      | CMake workflow preset name passed to `cmake --workflow --preset`.                         |
| `runner`         | no       | GitHub-hosted runner (default `ubuntu-latest`). Required for Windows/MSVC.                |
| `image`          | no       | Job `container:` image (steps run inside the container).                                  |
| `setup_script`   | no       | Repo-relative bash script run after checkout (install system packages, etc.).             |
| `setup`          | no       | Inline shell commands for the same purpose (use `setup_shell` on Windows if needed).      |
| `setup_shell`    | no       | Shell for `setup` only (default `bash`, or `pwsh` when `runner` starts with `windows`).   |

Runs `cmake --workflow --preset <name>` for each matrix entry. Consumer setup runs after checkout and before
CMake/MSVC setup. For Windows/MSVC set `"runner":"windows-latest"` — MSVC setup is gated on the runner name.

Example with Boost (shared devenv helper):

```yaml
jobs:
  presets:
    uses: devmarkusb/devenv/.github/workflows/preset-test.yml@main
    with:
      default_setup_script: devenv/install-boost.sh
      matrix_config: |
        [
          {"preset": "ci", "runner": "ubuntu-latest"},
          {"preset": "ci", "image": "ghcr.io/bemanproject/infra-containers-gcc:latest"}
        ]
```

For one-off packages, use per-matrix `setup` / `setup_script` instead of forking the reusable workflow.

### install-test.yml

**Trigger:** `workflow_call`

| Input            | Required | Description                                                    |
|------------------|----------|----------------------------------------------------------------|
| `image`          | yes      | Container image for building the library.                      |
| `cxx_standard`   | yes      | `CMAKE_CXX_STANDARD` value (e.g. `20`).                        |
| `namespace`      | yes      | CMake namespace / package prefix (e.g. `mycompany`).           |
| `include_header` | no       | Full include path for the consumer smoke test.                 |
| `main_header`    | no       | Header file name; defaults to `<library>.hpp`.                 |
| `setup_script`   | no       | Repo-relative bash script run after checkout in the container. |
| `setup`          | no       | Inline shell commands before CMake configure.                  |
| `setup_shell`    | no       | Shell for `setup` (default `bash`).                            |

Configures the project with the FetchContent lockfile helper, resolves the library name from the CMake file API
codemodel reply, installs to `dist/`, then builds a minimal `find_package` consumer to verify the installation.
Consumer setup runs after checkout and before the library configure step.

### update-pre-commit.yml

**Trigger:** `workflow_call`

| Secret        | Required | Description                              |
|---------------|----------|------------------------------------------|
| `APP_ID`      | yes      | GitHub App ID for creating the PR.       |
| `PRIVATE_KEY` | yes      | GitHub App private key.                  |

Runs `pre-commit autoupdate`, applies hooks to all files (non-blocking so the PR is still created even if hooks fail),
opens or updates a PR via `peter-evans/create-pull-request`, adds a warning to the PR body and job summary when
`--all-files` fails, then **fails the job** so the run stays red until follow-up fixes land.

### pre-commit.yml

**Trigger:** `workflow_call` (invoked with the caller's `on` events, e.g. `push` / `pull_request_target`).

Consumer repos call it from their own trigger workflow, e.g.:

```yaml
on:
  pull_request_target:
  push:
    branches: [main]
jobs:
  pre-commit:
    uses: devmarkusb/devenv/.github/workflows/pre-commit.yml@main
```

- **On push:** Full checkout (with submodules), installs pre-commit via pip (with cache), runs `--all-files`.
- **On `pull_request_target`:** Checks out the PR branch with `gh pr checkout`, runs pre-commit, then uses
  **reviewdog** (`action-suggester`) to post suggested fixes as PR comments on failure.

Requires `gh` token with `checks:write`, `issues:write`, `pull-requests:write` for the PR job.

### clang-tidy-review.yml

**Trigger:** `workflow_call`

| Input                    | Required | Description                                        |
|--------------------------|----------|----------------------------------------------------|
| `clang_image`            | yes      | Docker image providing clang-tidy.                 |
| `preset`                 | no       | CMake configure preset (default: `clang-release`). |
| `report_artifact_name`   | no       | Artifact name for the full-scan report.            |
| `default_setup_script`   | no       | Repo-relative bash script before configure (e.g. Boost). |

Two jobs, gated by event:

- **`changed-lines`** — on `pull_request` and `push`: runs `clang-tidy-review.py changed`, scoping analysis to
  modified lines (or widening to the full project when headers / CMake files change).
- **`full-project`** — on `schedule`, `workflow_dispatch`, and pushes to `main`: runs the full scan and uploads
  the report as a workflow artifact.

Consumer repos only need to define their `on:` trigger section and a single `uses:` job:

```yaml
name: clang-tidy

on:
  pull_request:
    paths: ["**/*.cpp", "**/*.hpp", "**/*.h", ".clang-tidy", "cmake/**", "devenv/cmake/**"]
  push:
    branches: [main]
    paths: ["**/*.cpp", "**/*.hpp", "**/*.h", ".clang-tidy", "cmake/**", "devenv/cmake/**"]
  schedule:
    - cron: "17 4 * * 0"
  workflow_dispatch:

concurrency:
  group: clang-tidy-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  clang-tidy:
    uses: devmarkusb/devenv/.github/workflows/clang-tidy-review.yml@main
    with:
      clang_image: ghcr.io/bemanproject/infra-containers-clang:latest
      default_setup_script: devenv/install-boost.sh
```

Projects that require Boost (or other deps) for `cmake --preset` must pass `default_setup_script`, same as
`cppcheck.yml` / `preset-test.yml`.

The problem matcher (`devenv/clang-tidy-problem-matcher.json`) is loaded automatically inside the reusable
workflow — no separate file needed in the consumer repo.

### cppcheck.yml

**Trigger:** `workflow_call`

| Input                    | Required | Description                                              |
|--------------------------|----------|----------------------------------------------------------|
| `preset`                 | no       | CMake configure preset (default: `clang-release`).       |
| `default_setup_script`   | no       | Repo-relative bash script before configure (e.g. Boost). |

Runs a full-project cppcheck scan on `ubuntu-latest` by calling `devenv/run-cppcheck.sh`. Consumer repos
need only an `on:` section and a `uses:` job with optional setup — no cppcheck installation step, no inline shell:

```yaml
name: cppcheck

on:
  pull_request:
    paths: ["**/*.cpp", "**/*.hpp", "**/*.h", "cmake/**", "devenv/cmake/**",
            "CppCheckSuppressions.txt", "devenv/run-cppcheck.sh"]
  push:
    branches: [main]
    paths: ["**/*.cpp", "**/*.hpp", "**/*.h", "cmake/**", "devenv/cmake/**",
            "CppCheckSuppressions.txt", "devenv/run-cppcheck.sh"]
  schedule:
    - cron: "31 4 * * 0"
  workflow_dispatch:

concurrency:
  group: cppcheck-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  cppcheck:
    uses: devmarkusb/devenv/.github/workflows/cppcheck.yml@main
    with:
      default_setup_script: devenv/install-boost.sh
```

Projects that require Boost (or other deps) for `cmake --preset` must pass `default_setup_script`, same as
`preset-test.yml` / `build-and-test.yml`.

Place a `CppCheckSuppressions.txt` in the project root to suppress specific findings; the script picks it
up automatically.

### .gitignore

Just as a sidenote, our .gitignore is overkill for this current repo but by the way provides a
reasonable template default for C++ projects. So you might copy and paste.
