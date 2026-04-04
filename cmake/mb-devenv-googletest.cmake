# Shared GoogleTest setup for this repository's test executables.
# Add `devenv/cmake` to `CMAKE_MODULE_PATH` once, then
# `include(mb-devenv-googletest)` from test-focused `CMakeLists.txt` files.

include_guard(GLOBAL)

# Show stdout/stderr when a test fails, which helps both local debugging and CI.
list(APPEND CMAKE_CTEST_ARGUMENTS "--output-on-failure")

find_package(GTest REQUIRED)
include(GoogleTest)

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    foreach(_mb_devenv_gtest_tg IN ITEMS gtest gtest_main gmock gmock_main)
        if(TARGET ${_mb_devenv_gtest_tg})
            target_compile_options(
                ${_mb_devenv_gtest_tg}
                PRIVATE -Wno-character-conversion
            )
        endif()
    endforeach()
endif()

# Sanitized binaries are slow to start; default gtest discovery timeout (5s) is often too low.
set(_mb_devenv_gtest_discovery_timeout_sanitizer 60)

# Globs `*.test.cpp` under `CMAKE_CURRENT_SOURCE_DIR`, links `GTest::gtest_main`, applies essentials, registers tests.
# Pass extra `target_link_libraries` arguments after the target name (typically `PRIVATE your::lib`).
function(mb_devenv_add_test target)
    file(GLOB_RECURSE _mb_devenv_gtest_sources CONFIGURE_DEPENDS "*.test.cpp")
    add_executable(${target})
    target_sources(${target} PRIVATE ${_mb_devenv_gtest_sources})
    target_link_libraries(${target} PRIVATE GTest::gtest_main ${ARGN})
    mb_devenv_set_target_essentials(${target})
    if(MB_DEVENV_SANITIZER)
        gtest_discover_tests(
            ${target}
            DISCOVERY_TIMEOUT ${_mb_devenv_gtest_discovery_timeout_sanitizer}
        )
    else()
        gtest_discover_tests(${target})
    endif()
endfunction()
