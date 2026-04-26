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

#### mb-devenv-install-library-config.cmake

Defines **`mb_devenv_install_library(name)`** for libraries. Call it with a target name of the form
`namespace.library-name` (e.g. `mb.cpp-lib-template`). It:

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

| Input           | Required | Description                             |
|-----------------|----------|-----------------------------------------|
| `matrix_config` | yes      | Compiler-keyed JSON matrix (see below). |

Expands a nested JSON structure into a flat compiler × version × C++ standard × stdlib × test-type matrix. Linux
gcc/clang jobs run in `ghcr.io/bemanproject/infra-containers-<compiler>:<version>` Docker images; Apple Clang uses
`macos-latest`; MSVC uses `windows-latest`. Supported test-type suffixes: `Default`, `TSan`, `MSan`, `MaxSan`,
`MaxWarn`, `MaxWarnMsvc`, `Dynamic`, `Coverage`. Coverage rows run `gcovr` and upload to Coveralls.

**Consumer assumptions:** `devenv/cmake/toolchains/*.cmake` and
`devenv/cmake/fetch-content-from-lockfile.cmake` present; Ninja Multi-Config generator.

### preset-test.yml

**Trigger:** `workflow_call`

| Input           | Required | Description                                                                                               |
|-----------------|----------|-----------------------------------------------------------------------------------------------------------|
| `matrix_config` | yes      | JSON **array** of `{"preset":"ci","runner":"ubuntu-latest"}` or `{"preset":"ci","image":"..."}` objects.  |

Runs `cmake --workflow --preset <name>` for each matrix entry. For Windows/MSVC set `"runner":"windows-latest"` — MSVC
setup is gated on the runner name.

### install-test.yml

**Trigger:** `workflow_call`

| Input            | Required | Description                                            |
|------------------|----------|--------------------------------------------------------|
| `image`          | yes      | Container image for building the library.              |
| `cxx_standard`   | yes      | `CMAKE_CXX_STANDARD` value (e.g. `20`).                |
| `namespace`      | yes      | CMake namespace / package prefix (e.g. `mycompany`).   |
| `include_header` | no       | Full include path for the consumer smoke test.         |
| `main_header`    | no       | Header file name; defaults to `<library>.hpp`.         |

Configures the project with the FetchContent lockfile helper, resolves the library name from the CMake file API
codemodel reply, installs to `dist/`, then builds a minimal `find_package` consumer to verify the installation.

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

### .gitignore

Just as a sidenote, our .gitignore is overkill for this current repo but by the way provides a
reasonable template default for C++ projects. So you might copy and paste.
