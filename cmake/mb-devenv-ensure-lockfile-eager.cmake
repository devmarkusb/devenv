# Fetch lockfile entries that use cmake_include (no package_name) when the top-level
# CMAKE_PROJECT_TOP_LEVEL_INCLUDES pass did not run (embedded add_subdirectory(devenv)).
# Does not register the find_package dependency provider (that still needs TOP_LEVEL_INCLUDES).

cmake_minimum_required(VERSION 3.24)

include(FetchContent)

function(_mb_devenv_ensure_apply_cmake_variables dep_json error_prefix)
    string(
        JSON kind
        ERROR_VARIABLE kind_err
        TYPE "${dep_json}"
        "cmake_variables"
    )
    if(kind_err OR NOT kind STREQUAL "OBJECT")
        return()
    endif()
    string(JSON n ERROR_VARIABLE err LENGTH "${dep_json}" "cmake_variables")
    if(err OR n EQUAL 0)
        return()
    endif()
    math(EXPR n_max "${n} - 1")
    foreach(i RANGE "${n_max}")
        string(
            JSON key
            ERROR_VARIABLE err
            MEMBER "${dep_json}"
            "cmake_variables"
            "${i}"
        )
        if(err)
            message(FATAL_ERROR "${error_prefix}: ${err}")
        endif()
        string(
            JSON val
            ERROR_VARIABLE err
            GET "${dep_json}"
            "cmake_variables"
            "${key}"
        )
        if(err)
            message(FATAL_ERROR "${error_prefix}: ${err}")
        endif()
        set("${key}" "${val}")
    endforeach()
endfunction()

set(_mb_devenv_ensure_lockfile "")
if(MB_DEVENV_ROOT AND MB_DEVENV_FETCHCONTENT_LOCKFILE)
    set(_mb_devenv_ensure_lockfile
        "${MB_DEVENV_ROOT}/${MB_DEVENV_FETCHCONTENT_LOCKFILE}"
    )
elseif(EXISTS "${CMAKE_CURRENT_LIST_DIR}/../fetchcontent-lockfile.json")
    set(_mb_devenv_ensure_lockfile
        "${CMAKE_CURRENT_LIST_DIR}/../fetchcontent-lockfile.json"
    )
elseif(EXISTS "${CMAKE_SOURCE_DIR}/fetchcontent-lockfile.json")
    set(_mb_devenv_ensure_lockfile
        "${CMAKE_SOURCE_DIR}/fetchcontent-lockfile.json"
    )
endif()

if(
    "${_mb_devenv_ensure_lockfile}" STREQUAL ""
    OR NOT EXISTS "${_mb_devenv_ensure_lockfile}"
)
    return()
endif()

file(READ "${_mb_devenv_ensure_lockfile}" _mb_devenv_ensure_root)
string(
    JSON _mb_devenv_ensure_deps
    ERROR_VARIABLE _mb_devenv_ensure_deps_err
    GET "${_mb_devenv_ensure_root}"
    "dependencies"
)
if(_mb_devenv_ensure_deps_err)
    message(
        FATAL_ERROR
        "${_mb_devenv_ensure_lockfile}: ${_mb_devenv_ensure_deps_err}"
    )
endif()

string(
    JSON _mb_devenv_ensure_n
    ERROR_VARIABLE _mb_devenv_ensure_n_err
    LENGTH "${_mb_devenv_ensure_deps}"
)
if(_mb_devenv_ensure_n_err OR _mb_devenv_ensure_n LESS_EQUAL 0)
    return()
endif()

math(EXPR _mb_devenv_ensure_max "${_mb_devenv_ensure_n} - 1")
foreach(_mb_devenv_ensure_i RANGE "${_mb_devenv_ensure_max}")
    set(_mb_devenv_ensure_ep
        "${_mb_devenv_ensure_lockfile}, dependency ${_mb_devenv_ensure_i}"
    )
    string(
        JSON _mb_devenv_ensure_dep
        ERROR_VARIABLE _mb_devenv_ensure_dep_err
        GET "${_mb_devenv_ensure_deps}"
        "${_mb_devenv_ensure_i}"
    )
    if(_mb_devenv_ensure_dep_err)
        message(
            FATAL_ERROR
            "${_mb_devenv_ensure_ep}: ${_mb_devenv_ensure_dep_err}"
        )
    endif()

    string(
        JSON _mb_devenv_ensure_pkg
        ERROR_VARIABLE _mb_devenv_ensure_pkg_err
        GET "${_mb_devenv_ensure_dep}"
        "package_name"
    )
    if(
        NOT _mb_devenv_ensure_pkg_err
        AND NOT "${_mb_devenv_ensure_pkg}" STREQUAL ""
    )
        continue()
    endif()

    string(
        JSON _mb_devenv_ensure_name
        ERROR_VARIABLE _mb_devenv_ensure_name_err
        GET "${_mb_devenv_ensure_dep}"
        "name"
    )
    string(
        JSON _mb_devenv_ensure_repo
        ERROR_VARIABLE _mb_devenv_ensure_repo_err
        GET "${_mb_devenv_ensure_dep}"
        "git_repository"
    )
    string(
        JSON _mb_devenv_ensure_tag
        ERROR_VARIABLE _mb_devenv_ensure_tag_err
        GET "${_mb_devenv_ensure_dep}"
        "git_tag"
    )
    string(
        JSON _mb_devenv_ensure_cmake_include
        ERROR_VARIABLE _mb_devenv_ensure_inc_err
        GET "${_mb_devenv_ensure_dep}"
        "cmake_include"
    )
    if(
        _mb_devenv_ensure_name_err
        OR _mb_devenv_ensure_repo_err
        OR _mb_devenv_ensure_tag_err
        OR _mb_devenv_ensure_inc_err
        OR "${_mb_devenv_ensure_cmake_include}" STREQUAL ""
    )
        continue()
    endif()

    if(
        _mb_devenv_ensure_name STREQUAL "mb_pre_commit"
        AND COMMAND mb_pre_commit_setup_project
    )
        continue()
    endif()

    FetchContent_GetProperties(
        "${_mb_devenv_ensure_name}"
        POPULATED _mb_devenv_ensure_populated
    )
    if(_mb_devenv_ensure_populated)
        continue()
    endif()

    FetchContent_Declare(
        "${_mb_devenv_ensure_name}"
        GIT_REPOSITORY "${_mb_devenv_ensure_repo}"
        GIT_TAG "${_mb_devenv_ensure_tag}"
        GIT_SHALLOW ON
        EXCLUDE_FROM_ALL
        SYSTEM
    )
    if(POLICY CMP0169)
        cmake_policy(PUSH)
        cmake_policy(SET CMP0169 OLD)
    endif()
    FetchContent_Populate("${_mb_devenv_ensure_name}")
    if(POLICY CMP0169)
        cmake_policy(POP)
    endif()

    _mb_devenv_ensure_apply_cmake_variables(
        "${_mb_devenv_ensure_dep}"
        "${_mb_devenv_ensure_ep}"
    )

    string(TOLOWER "${_mb_devenv_ensure_name}" _mb_devenv_ensure_lc)
    set(_mb_devenv_ensure_src "${${_mb_devenv_ensure_lc}_SOURCE_DIR}")
    include("${_mb_devenv_ensure_src}/${_mb_devenv_ensure_cmake_include}")
endforeach()
