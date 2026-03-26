# Shared GoogleTest setup for this repository's test executables.
# Add `devenv/cmake` to `CMAKE_MODULE_PATH` once, then
# `include(mb-devenv-googletest)` from test-focused `CMakeLists.txt` files.

include_guard(GLOBAL)

# Show stdout/stderr when a test fails, which helps both local debugging and CI.
list(APPEND CMAKE_CTEST_ARGUMENTS "--output-on-failure")

find_package(GTest REQUIRED)
include(GoogleTest)

function(mb_devenv_add_test target)
    gtest_discover_tests(${target})
endfunction()
