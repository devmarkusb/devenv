cmake_minimum_required(VERSION 3.24)

project(devenv LANGUAGES NONE)

# From fetched https://github.com/devmarkusb/pre-commit (see fetchcontent-lockfile.json).
mb_pre_commit_setup(
    PRE_COMMIT_INSTALL_EXAMPLE_CONFIG OFF
)
