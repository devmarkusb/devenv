# devenv — agent instructions

Portable instructions for AI agents working in this repository. Tool-specific files (`.cursor/rules/`, `CLAUDE.md`) are thin adapters only.

## Project overview

**devenv** is a **git submodule** of shared C++ developer infrastructure: CMake modules and toolchains, FetchContent lockfile provider, pre-commit integration (via [mb-pre-commit](https://github.com/devmarkusb/pre-commit)), Python helper scripts, and **reusable GitHub Actions workflows** for consumer repos.

This repo is **not** a C++ application: there is no product source tree and **no CTest targets** here. CI validates CMake configure/build, lint, and workflow syntax. Consumer projects add `devenv/` as a submodule and call its CMake modules and workflows.

## Build commands

Requires **CMake 3.31+** for presets (see `CMakePresets.json`); `cmake_minimum_required` in `CMakeLists.txt` is **3.24** for consumers including individual `.cmake` files only.

| Task | Command |
|------|---------|
| Local dev loop (configure + build) | `cmake --workflow --preset dev` |
| CI-equivalent configure + build | `cmake --workflow --preset ci` |
| Configure only (Debug, Ninja) | `cmake --preset default` |
| Build after configure | `cmake --build --preset default` |
| Trace FetchContent provider | `cmake --workflow --preset trace-fetch` |
| Unix Makefiles (no Ninja) | `cmake --preset unix-makefiles` then `cmake --build --preset unix-makefiles` |
| Clang toolchain + ci preset | `cmake --preset ci -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/clang-toolchain.cmake` then `cmake --build --preset ci` |
| Refresh pre-commit after CMake | `cmake --build build/default --target mb-pre-commit-sweep` (build dir name follows preset; default → `build/default`) |

Build output lives under `build/<presetName>/` (gitignored). FetchContent deps land in `build/*/_deps/` — do not edit.

## Test commands

**This repository has no unit/integration tests.** Do not invent `ctest` runs for devenv itself.

Consumer repos using `mb-devenv-defaults.cmake` / `mb-devenv-googletest.cmake` run tests via their own CI (e.g. `ctest --test-dir build` in `build-and-test.yml`). When changing those modules, reason about consumer impact; devenv CI will not catch test regressions in parent projects.

## Formatting and linting

Run from repo root after `cmake --workflow --preset dev` (creates `.venv` and installs the git `pre-commit` hook):

```bash
pre-commit run --all-files
# or, after configure:
cmake --build build/default --target mb-pre-commit-sweep
```

Hooks (`.pre-commit-config.yaml`): pre-commit-hooks, markdownlint (`.markdownlint.yaml`), codespell, **ruff** + ruff-format + pyupgrade (`--py310-plus`), **gersemi** (CMake, `.gersemirc`), **clang-format** (C++ only — no C++ sources in this repo, so hook often skips).

| Check | When / how |
|-------|----------------|
| GitHub Actions syntax | `actionlint -color` (CI installs v1.7.12; **unverified** locally if `actionlint` not on PATH) |
| Workflow security | `zizmor` in CI only (`.github/zizmor.yml`) |
| clang-tidy (consumer pattern) | `python3 scripts/clang-tidy-review.py changed` or `full` (needs configured build + `compile_commands.json`) |
| cppcheck (consumer pattern) | `./scripts/run-cppcheck.sh [preset] [build-dir]` |

Python scripts: `clang-tidy-review.py`, `install-boost.py`, `install-cppcheck.py`, `run-cppcheck.sh` — keep compatible with **Python 3.10+** (pyupgrade target).

## Architecture and important directories

| Path | Role |
|------|------|
| `cmake/` | Modules: defaults, warnings, GoogleTest helper, install config, cppcheck, FetchContent lockfile provider, toolchains |
| `cmake/toolchains/` | `gcc`, `clang`, `clang-libc++`, `appleclang`, `msvc`; optional `MB_DEVENV_SANITIZER` |
| `cmake/detail/` | Internal helpers (warnings, defs, ctest filter script) |
| `.github/workflows/` | **Reusable** `workflow_call` workflows for consumers + this repo's `ci.yml`, `pre-commit-check.yml` |
| `fetchcontent-lockfile.json` | Pins FetchContent deps (e.g. mb-pre-commit **v3.0.0**) |
| `CMakePresets.json` | Presets: `default`, `ci`, `dev`, `trace-fetch`, `unix-makefiles`, `vs2022` |
| `clang-tidy-review.py`, `run-cppcheck.sh`, `install-*.py` | Standalone tooling documented in `README.md` |
| `git-sub.sh` | Submodule + Git LFS convenience for consumers |

**Consumer contract:** workflows and docs assume the submodule path `devenv/`. Changing paths or public CMake function signatures is a **breaking change** for downstream repos.

## Coding conventions

- **CMake:** Format/lint with gersemi; `warn_about_unknown_commands: false` in `.gersemirc` for lockfile helper quirks. Prefer `include_guard`, clear `option()` names prefixed `MB_DEVENV_` for public cache variables.
- **Python:** Ruff format/lint via pre-commit; no `pyproject.toml` in-tree — hook defaults apply.
- **Markdown:** `README.md` is long-form consumer docs; markdownlint rules in `.markdownlint.yaml` (e.g. line length 119, tables exempt from wrapping).
- **Workflows:** Pin third-party actions with full commit SHAs where already done; match existing `permissions:` and `concurrency:` patterns. `pre-commit-check.yml` uses `pull_request_target` intentionally (reviewdog) — do not switch to `pull_request` without understanding token scope.
- **Version pins:** Bump `fetchcontent-lockfile.json` tags deliberately; re-run `cmake --workflow --preset dev` and pre-commit after lockfile or mb-pre-commit changes.

## Testing expectations

Before finishing a change:

1. **`pre-commit run --all-files`** for any touched tracked files (or sweep target after CMake edits).
2. **`cmake --workflow --preset ci`** (or at least `dev`) when changing `CMakeLists.txt`, `cmake/**`, `CMakePresets.json`, or `fetchcontent-lockfile.json`.
3. **`actionlint -color`** when editing `.github/workflows/**` (matches CI `workflow-lint` job).
4. For **reusable workflow** changes (`build-and-test.yml`, `preset-test.yml`, `.github/actions/*`, etc.): verify inputs documented in `README.md` still match; consumers pin `@tag` or SHA.

No coverage or ctest requirement in this repo.

## Files and directories agents must not edit without explicit approval

- **Secrets / env:** `.env`, credentials, `PRIVATE_KEY`, tokens
- **Lock / pins:** `fetchcontent-lockfile.json` (unless task is explicitly to bump a dependency)
- **Generated / vendored:** `build/`, `.venv/`, `build/**/_deps/`, `.ruff_cache/`
- **Git internals:** `.git/hooks/` (CMake installs hooks; do not hand-edit)
- **IDE:** `.idea/` (local editor state)
- **Consumer-local:** `CMakeUserPresets.json` (gitignored template)
- **CI release/deploy:** none today; treat any future release workflow as restricted
- **Local tooling:** `/actionlint` (gitignored; CI downloads its own copy — install via `brew install actionlint` or the download script locally)

Avoid drive-by edits to unrelated workflows or README sections.

## Security and privacy constraints

- Never commit secrets or real tokens; reusable workflows use `secrets` only via documented `workflow_call` inputs.
- **`pull_request_target`** runs in base-repo context — be cautious suggesting workflow changes that execute untrusted PR code with elevated permissions.
- Do not add broad MCP servers, default browser/fileshell tools, or repo-level credentials in config.
- Submodule and FetchContent URLs point to public GitHub repos; verify tags when bumping.

## Review checklist before final response

- [ ] Change scope matches the task; no unrelated refactors
- [ ] `pre-commit run --all-files` passes (or failures explained)
- [ ] CMake workflow `dev` or `ci` succeeds if build files changed
- [ ] `actionlint` clean if workflows changed
- [ ] README updated when changing public CMake API or reusable workflow inputs
- [ ] Consumer path `devenv/` and backward compatibility considered
- [ ] No secrets, lockfile drive-bys, or edits under `build/` / `.venv/`
