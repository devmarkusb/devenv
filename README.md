# devenv

Basic must-haves for a convenient general infrastructure setup of C++ apps/libs. Intended to be added as a **git
submodule** to your project repo.

## Quick start

From your project repo root, add devenv as a submodule (SSH or HTTPS):

```bash
git submodule add git@github.com:devmarkusb/devenv.git devenv
# or
git submodule add https://github.com/devmarkusb/devenv.git devenv
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

- **Bootstrap:** `devenv/bootstrap.sh` sets up a venv and installs pre-commit in your project; hooks are defined by the
  project’s root `.pre-commit-config.yaml`.
- **Run on all files:**
  `pre-commit run --all-files`
- **Devenv’s own config:** `devenv/.pre-commit-config.yaml` is a minimal config used when working inside the devenv
  repo (e.g. gersemi, codespell, YAML checks). Consumer projects use their own config at the repo root.

#### Syncing .clang-format from devmarkusb/clangformat

To use a shared clang-format config (optionally versioned per clang-format major), run the script **from inside the
`devenv` directory** (so path resolution works):

```bash
cd devenv && ./sync-clang-format.sh [VERSION]
```

- **VERSION** (optional): clang-format major (e.g. `14`, `22`). Default: from `.pre-commit-config.yaml` (mirrors-clang-format
  `rev`) or `22`.
- Overwrites the project repo root `.clang-format`. Fetches `configs/v<VERSION>/.clang-format` from the clangformat repo,
  or the repo root `.clang-format` if that path doesn’t exist.
- Env overrides: `CLANGFORMAT_REPO`, `CLANGFORMAT_BRANCH`, `CLANGFORMAT_VERSION`.

The folder **`devenv/clangformat-configs/`** holds versioned configs (`configs/v14/`, `configs/v22/`) to copy into
[devmarkusb/clangformat](https://github.com/devmarkusb/clangformat) so that repo can serve them. See
`devenv/clangformat-configs/README.md`.

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

Optional **sanitizers** via cache variable `MB_SANITIZER`:

- **MaxSan** — Address, leak, pointer-compare/subtract, undefined (and on MSVC, address only).
- **TSan** — Thread sanitizer.
- **MSan** — Memory sanitizer (Clang/AppleClang only; uses `msan.supp` if present).

Release-type configs use `-O3` (or MSVC `/O2`) and can still add sanitizer flags. Toolchains append the project root to
`CMAKE_PREFIX_PATH` so `find_package(...)` can resolve config packages from the build tree.

#### fetch-content-from-lockfile.cmake

CMake **dependency provider** (CMake 3.24+). Include it as a top-level include (e.g. via
`CMAKE_PROJECT_TOP_LEVEL_INCLUDES` in presets). It:

- Reads a JSON lockfile from the **consumer project** (default: `fetchcontent-lockfile.json` in the project root;
  override with `MB_FETCHCONTENT_LOCKFILE`).
- Implements `FIND_PACKAGE`: when the project calls `find_package(PkgName)`, the provider can satisfy it by FetchContent
  using `git_repository` and `git_tag` from the lockfile.
- Adds the lockfile to `CMAKE_CONFIGURE_DEPENDS` so CMake reconfigures when the lockfile changes.

Lockfile format: a JSON object with a `dependencies` array; each entry has `name`, `package_name`, `git_repository`,
`git_tag`. This gives reproducible builds without relying on system packages (e.g. GTest).

#### install-library-config.cmake

Defines **`mb_install_library(name)`** for header-only/INTERFACE libraries. Call it with a target name of the form
`namespace.library-name` (e.g. `mb.cpp-lib-template`). It:

- Installs the target and its `FILE_SET HEADERS`.
- Optionally installs a CMake config-file package (so consumers can `find_package(...)`) using a template
  `cmake/<name>-config.cmake.in`.
- Config is controlled by `MB_INSTALL_CONFIG_FILE_PACKAGES` (list) or `<UPPERCASE_NAME>_INSTALL_CONFIG_FILE_PACKAGE` (
  per-library ON/OFF).

### .github/workflows

#### pre-commit.yml

Reusable workflow for **lint check (pre-commit)**. Main repo typically calls it from a workflow like
`pre-commit-check.yml` with `uses: .../devenv/.github/workflows/pre-commit.yml`.

- **On push to `main`:** Full checkout (with submodules), runs pre-commit on **all files** so formatting/lint issues are
  fixed over the whole tree.
- **On pull_request_target:** Checkouts the PR branch, runs pre-commit only on **changed files**, then uses **reviewdog
  ** (action-suggester) to post suggested fixes as PR comments.

Requires Python (e.g. 3.13) and, for PRs, `gh` and a token that can write checks and comments.
