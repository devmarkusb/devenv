cmake_minimum_required(VERSION 3.24)

project(devenv LANGUAGES NONE)

# After project(): tier A (TOP_LEVEL_INCLUDES) may have populated eager lockfile deps; tier B
# (embedded add_subdirectory) still needs cmake_include deps fetched here.
include("${CMAKE_CURRENT_LIST_DIR}/cmake/mb-devenv-ensure-lockfile-eager.cmake")

# From fetched https://github.com/devmarkusb/pre-commit (see fetchcontent-lockfile.json).
mb_pre_commit_setup_project()
