cmake_minimum_required(VERSION 3.24)

project(devenv LANGUAGES NONE)

# From fetched https://github.com/devmarkusb/pre-commit (see fetchcontent-lockfile.json).
# Top-level: hooks/venv at this repo root. add_subdirectory(devenv): same for *this* tree
# (submodule commits use devenv/.git/hooks, not the parent). Parent must still fetch
# mb_pre_commit via its lockfile so mb_pre_commit_setup_subdirectory is defined.
if(PROJECT_IS_TOP_LEVEL)
    mb_pre_commit_setup(PRE_COMMIT_INSTALL_EXAMPLE_CONFIG OFF)
else()
    mb_pre_commit_setup_subdirectory(PRE_COMMIT_INSTALL_EXAMPLE_CONFIG OFF)
endif()
