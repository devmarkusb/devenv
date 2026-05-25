cmake_minimum_required(VERSION 3.10)

# Optional build-time cppcheck integration via CMAKE_CXX_CPPCHECK.
# Include this file once from your project root CMakeLists.txt:
#
#   include(devenv/cmake/mb-devenv-cppcheck.cmake)
#
# Then configure with -DMB_DEVENV_CPPCHECK=ON to activate.
#
# This is independent of devenv/scripts/run-cppcheck.sh, which runs cppcheck as a
# dedicated post-configure analysis step using --project=compile_commands.json.
# Use one or both; they complement each other.
#
# Flags differ intentionally:
#   build-time (this file)  — lighter: no --check-level=exhaustive so each
#                             build stays fast; --force because cmake may not
#                             pass every include path in all configurations.
#   run-cppcheck.sh         — thorough: --check-level=exhaustive,
#                             --enable=warning,style,performance,portability,
#                             --library=googletest; run separately in CI.

option(
    MB_DEVENV_CPPCHECK
    "Run cppcheck on each translation unit during the build."
    OFF
)
option(
    MB_DEVENV_CPPCHECK_AUTO_INSTALL
    "Attempt to install cppcheck with devenv/scripts/install-cppcheck.py when it is missing."
    OFF
)

function(_mb_devenv_cppcheck_find_executable out_var)
    find_program(
        _mb_devenv_cppcheck_executable
        NAMES cppcheck cppcheck.exe
        HINTS
            "$ENV{ProgramFiles}/Cppcheck"
            "$ENV{ProgramFiles\(x86\)}/Cppcheck"
            "$ENV{LOCALAPPDATA}/Programs/Cppcheck"
        PATH_SUFFIXES "" "bin"
    )
    set(${out_var} "${_mb_devenv_cppcheck_executable}" PARENT_SCOPE)
endfunction()

function(_mb_devenv_cppcheck_try_install out_var)
    set(_mb_devenv_cppcheck_installer
        "${PROJECT_SOURCE_DIR}/devenv/scripts/install-cppcheck.py"
    )
    if(NOT EXISTS "${_mb_devenv_cppcheck_installer}")
        message(
            WARNING
            "MB_DEVENV_CPPCHECK_AUTO_INSTALL is ON, but installer script was not found at "
            "'${_mb_devenv_cppcheck_installer}'."
        )
        set(${out_var} "" PARENT_SCOPE)
        return()
    endif()

    find_package(Python3 COMPONENTS Interpreter QUIET)
    set(_mb_devenv_cppcheck_python "${Python3_EXECUTABLE}")
    if(NOT _mb_devenv_cppcheck_python)
        find_program(_mb_devenv_cppcheck_python NAMES python3 python py)
    endif()
    if(NOT _mb_devenv_cppcheck_python)
        message(
            WARNING
            "MB_DEVENV_CPPCHECK_AUTO_INSTALL is ON, but no Python interpreter was found "
            "to run '${_mb_devenv_cppcheck_installer}'."
        )
        set(${out_var} "" PARENT_SCOPE)
        return()
    endif()

    message(
        STATUS
        "Attempting to install cppcheck via ${_mb_devenv_cppcheck_installer}."
    )
    execute_process(
        COMMAND
            "${_mb_devenv_cppcheck_python}" "${_mb_devenv_cppcheck_installer}"
            --ensure --print-path
        RESULT_VARIABLE _mb_devenv_cppcheck_result
        OUTPUT_VARIABLE _mb_devenv_cppcheck_stdout
        ERROR_VARIABLE _mb_devenv_cppcheck_stderr
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
    )
    if(NOT _mb_devenv_cppcheck_result EQUAL 0)
        message(
            WARNING
            "cppcheck install command failed (${_mb_devenv_cppcheck_result}).\n"
            "stdout:\n${_mb_devenv_cppcheck_stdout}\n"
            "stderr:\n${_mb_devenv_cppcheck_stderr}"
        )
        set(${out_var} "" PARENT_SCOPE)
        return()
    endif()

    if(_mb_devenv_cppcheck_stdout)
        file(
            TO_CMAKE_PATH
            "${_mb_devenv_cppcheck_stdout}"
            _mb_devenv_cppcheck_detected
        )
        if(EXISTS "${_mb_devenv_cppcheck_detected}")
            set(${out_var} "${_mb_devenv_cppcheck_detected}" PARENT_SCOPE)
            return()
        endif()
    endif()

    _mb_devenv_cppcheck_find_executable(_mb_devenv_cppcheck_detected)
    set(${out_var} "${_mb_devenv_cppcheck_detected}" PARENT_SCOPE)
endfunction()

if(MB_DEVENV_CPPCHECK)
    _mb_devenv_cppcheck_find_executable(_mb_devenv_cppcheck_executable)
    if(NOT _mb_devenv_cppcheck_executable AND MB_DEVENV_CPPCHECK_AUTO_INSTALL)
        _mb_devenv_cppcheck_try_install(_mb_devenv_cppcheck_executable)
    endif()

    if(_mb_devenv_cppcheck_executable)
        set(MB_DEVENV_CPPCHECK_EXECUTABLE
            "${_mb_devenv_cppcheck_executable}"
            CACHE FILEPATH
            "Detected cppcheck executable"
            FORCE
        )
        set(CMAKE_CXX_CPPCHECK "${_mb_devenv_cppcheck_executable}")
        list(
            APPEND CMAKE_CXX_CPPCHECK
            "--enable=warning,style,performance,portability"
            "--inconclusive"
            "--force"
            "--inline-suppr"
            "--suppress=missingIncludeSystem"
        )
        if(EXISTS "${PROJECT_SOURCE_DIR}/CppCheckSuppressions.txt")
            list(
                APPEND CMAKE_CXX_CPPCHECK
                "--suppressions-list=${PROJECT_SOURCE_DIR}/CppCheckSuppressions.txt"
            )
        endif()
        message(STATUS "CMAKE_CXX_CPPCHECK: ${CMAKE_CXX_CPPCHECK}")
    else()
        message(
            WARNING
            "MB_DEVENV_CPPCHECK is ON, but cppcheck was not found. "
            "Set MB_DEVENV_CPPCHECK_AUTO_INSTALL=ON for a best-effort install via "
            "devenv/scripts/install-cppcheck.py, or install cppcheck manually."
        )
    endif()
endif()
