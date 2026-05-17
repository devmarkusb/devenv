cmake_minimum_required(VERSION 3.24)

# Embedded consumers: fetch cmake_include lockfile deps (e.g. mb-pre-commit) without
# CMAKE_PROJECT_TOP_LEVEL_INCLUDES. Lockfile: ../fetchcontent-lockfile.json or consumer root.
include("${CMAKE_CURRENT_LIST_DIR}/cmake/mb-devenv-ensure-lockfile-eager.cmake")

project(devenv LANGUAGES NONE)

# From fetched https://github.com/devmarkusb/pre-commit (see fetchcontent-lockfile.json).
mb_pre_commit_setup_project()
