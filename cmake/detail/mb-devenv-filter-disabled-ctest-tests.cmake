if(NOT DEFINED TESTS_FILE)
    message(FATAL_ERROR "TESTS_FILE must be set")
endif()

if(NOT EXISTS "${TESTS_FILE}")
    message(FATAL_ERROR "CTest tests file not found: ${TESTS_FILE}")
endif()

file(STRINGS "${TESTS_FILE}" _mb_devenv_ctest_lines)

set(_mb_devenv_filtered_lines "")
list(LENGTH _mb_devenv_ctest_lines _mb_devenv_line_count)
math(EXPR _mb_devenv_last_index "${_mb_devenv_line_count} - 1")
set(_mb_devenv_skip_next OFF)

foreach(_mb_devenv_line_index RANGE ${_mb_devenv_last_index})
    if(_mb_devenv_skip_next)
        set(_mb_devenv_skip_next OFF)
        continue()
    endif()

    list(GET _mb_devenv_ctest_lines ${_mb_devenv_line_index} _mb_devenv_line)

    if(_mb_devenv_line MATCHES "^add_test\\(" AND _mb_devenv_line_index LESS _mb_devenv_last_index)
        math(EXPR _mb_devenv_next_index "${_mb_devenv_line_index} + 1")
        list(GET _mb_devenv_ctest_lines ${_mb_devenv_next_index} _mb_devenv_next_line)
        if(_mb_devenv_next_line MATCHES " PROPERTIES DISABLED YES ")
            set(_mb_devenv_skip_next ON)
            continue()
        endif()
    endif()

    string(REPLACE " --gtest_also_run_disabled_tests" "" _mb_devenv_line "${_mb_devenv_line}")
    list(APPEND _mb_devenv_filtered_lines "${_mb_devenv_line}")
endforeach()

string(JOIN "\n" _mb_devenv_filtered_content ${_mb_devenv_filtered_lines})
string(APPEND _mb_devenv_filtered_content "\n")
file(WRITE "${TESTS_FILE}" "${_mb_devenv_filtered_content}")
