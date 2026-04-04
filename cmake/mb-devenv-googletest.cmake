# Shared GoogleTest setup for this repository's test executables.
# Add `devenv/cmake` to `CMAKE_MODULE_PATH` once, then
# `include(mb-devenv-googletest)` from test-focused `CMakeLists.txt` files.

include_guard(GLOBAL)

enable_testing()

# Show stdout/stderr when a test fails, which helps both local debugging and CI.
list(APPEND CMAKE_CTEST_ARGUMENTS "--output-on-failure")

find_package(GTest REQUIRED)
include(GoogleTest)

# Sanitized binaries are slow to start; default gtest discovery timeout (5s) is often too low.
set(_mb_devenv_gtest_discovery_timeout_sanitizer 120)

function(mb_devenv_add_test target)
    if(MB_DEVENV_SANITIZER)
        gtest_discover_tests(${target} DISCOVERY_TIMEOUT ${_mb_devenv_gtest_discovery_timeout_sanitizer})
    else()
        gtest_discover_tests(${target})
    endif()
endfunction()
