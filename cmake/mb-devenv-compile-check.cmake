# Small executable that includes a given header, forcing a full compile of that surface.
# Add `devenv/cmake` to `CMAKE_MODULE_PATH` once, then
# `include(mb-devenv-compile-check)` and call `mb_devenv_add_compile_check(...)`.

include_guard(GLOBAL)

# Creates an executable ${target} from a generated TU that #includes HEADER, links libraries, and applies defaults.
#
# Usage:
#   mb_devenv_add_compile_check(
#       my.lib.compile-check
#       PRIVATE my::lib
#       HEADER "my/lib/umbrella.hpp"
#   )
#
# Optional keyword SYSTEM_INCLUDE (before HEADER): use #include <HEADER> instead of #include "HEADER".
function(mb_devenv_add_compile_check target)
    cmake_parse_arguments(
        PARSE_ARGV 1
        ARG
        "SYSTEM_INCLUDE"
        "HEADER"
        ""
    )

    if(NOT ARG_HEADER)
        message(
            FATAL_ERROR
            "mb_devenv_add_compile_check(${target}): HEADER is required"
        )
    endif()

    if(ARG_SYSTEM_INCLUDE)
        set(MB_DEVENV_COMPILE_CHECK_INCLUDE_LINE "#include <${ARG_HEADER}>")
    else()
        set(MB_DEVENV_COMPILE_CHECK_INCLUDE_LINE "#include \"${ARG_HEADER}\"")
    endif()

    string(REGEX REPLACE "[^A-Za-z0-9_]" "_" _mb_devenv_cc_slug "${target}")
    set(
        _mb_devenv_cc_gen
        "${CMAKE_CURRENT_BINARY_DIR}/mb_devenv_compile_check_${_mb_devenv_cc_slug}.cpp"
    )
    configure_file(
        "${CMAKE_CURRENT_LIST_DIR}/mb-devenv-compile-check.cpp.in"
        "${_mb_devenv_cc_gen}"
        @ONLY
    )

    add_executable(${target})
    target_sources(${target} PRIVATE "${_mb_devenv_cc_gen}")
    target_link_libraries(${target} ${ARG_UNPARSED_ARGUMENTS})
    mb_devenv_set_target_defaults(${target})
endfunction()
