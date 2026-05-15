cmake_minimum_required(VERSION 3.24)

project(devenv LANGUAGES NONE)

# From fetched https://github.com/devmarkusb/pre-commit (see fetchcontent-lockfile.json).
# Subdirectory consumers: skip dev hook setup (they must not depend on mb_pre_commit, and
# mb_pre_commit_setup defaults use CMAKE_SOURCE_DIR = top-level tree, not mb.util alone).
if(PROJECT_IS_TOP_LEVEL)
    mb_pre_commit_setup()
endif()
