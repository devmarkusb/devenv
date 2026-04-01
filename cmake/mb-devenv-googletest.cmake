# Shared GoogleTest setup for this repository's test executables.
# Add `devenv/cmake` to `CMAKE_MODULE_PATH` once, then
# `include(mb-devenv-googletest)` from test-focused `CMakeLists.txt` files.

include_guard(GLOBAL)

# Show stdout/stderr when a test fails, which helps both local debugging and CI.
list(APPEND CMAKE_CTEST_ARGUMENTS "--output-on-failure")

find_package(GTest REQUIRED)

# When FindGTest provides IMPORTED targets with non-system includes only, move them to
# INTERFACE_SYSTEM_INCLUDE_DIRECTORIES so consumers get -isystem. FetchContent
# googletest uses SYSTEM INTERFACE; CMake still mirrors paths onto INTERFACE_INCLUDE_DIRECTORIES,
# so we must not clear that unless INTERFACE_SYSTEM_INCLUDE_DIRECTORIES is unset — otherwise
# include propagation breaks. Skip below when INTERFACE_SYSTEM_INCLUDE_DIRECTORIES is already set.
# Resolve ALIAS targets (FetchContent uses GTest::* aliases to gtest, etc.).
foreach(_mb_gtest_imported IN ITEMS GTest::gtest GTest::gtest_main GTest::gmock GTest::gmock_main)
    if(TARGET "${_mb_gtest_imported}")
        get_target_property(_mb_gtest_aliased "${_mb_gtest_imported}" ALIASED_TARGET)
        if(_mb_gtest_aliased AND NOT _mb_gtest_aliased STREQUAL "ALIASED_TARGET-NOTFOUND")
            set(_mb_gtest_t "${_mb_gtest_aliased}")
        else()
            set(_mb_gtest_t "${_mb_gtest_imported}")
        endif()
        get_target_property(_mb_gtest_sys "${_mb_gtest_t}" INTERFACE_SYSTEM_INCLUDE_DIRECTORIES)
        if(_mb_gtest_sys AND NOT _mb_gtest_sys STREQUAL "INTERFACE_SYSTEM_INCLUDE_DIRECTORIES-NOTFOUND")
            continue()
        endif()
        get_target_property(_mb_gtest_inc "${_mb_gtest_t}" INTERFACE_INCLUDE_DIRECTORIES)
        if(_mb_gtest_inc AND NOT _mb_gtest_inc STREQUAL "INTERFACE_INCLUDE_DIRECTORIES-NOTFOUND")
            set_target_properties(
                "${_mb_gtest_t}"
                PROPERTIES INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${_mb_gtest_inc}"
                             INTERFACE_INCLUDE_DIRECTORIES ""
            )
        endif()
    endif()
endforeach()

include(GoogleTest)

function(mb_devenv_add_test target)
    gtest_discover_tests(${target})
endfunction()
