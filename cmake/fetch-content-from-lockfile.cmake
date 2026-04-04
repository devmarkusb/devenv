# Recommended usage via
# "CMAKE_PROJECT_TOP_LEVEL_INCLUDES": "./devenv/cmake/fetch-content-from-lockfile.cmake"
# in cmake preset file.
#
# Default consumer root is two levels above this file (lockfile next to a nested
# devenv/ directory). When this repository is the top-level CMake project, set
# MB_DEVENV_ROOT to ${sourceDir} in CMakePresets.json (lockfile beside cmake/).
#
# Lockfile entries:
# - With "package_name" (non-empty): served via the FIND_PACKAGE provider when
#   find_package(<package_name>) runs (FetchContent + set(<Package>_FOUND)).
# - Without "package_name" (omitted or ""): eager FetchContent during this
#   include. Use optional "cmake_include" (path under the repo root) to
#   FetchContent_Populate + include() that file — required when the dependency
#   has its own project() and CMAKE_PROJECT_TOP_LEVEL_INCLUDES would otherwise
#   nest project(). If "cmake_include" is omitted, sources are populated first;
#   if the root CMakeLists.txt looks like it calls project(), configuration
#   stops with a hint to set cmake_include; otherwise FetchContent_MakeAvailable
#   is used.
# - Optional "cmake_variables": JSON object whose string keys are CMake variable
#   names and whose values (string or number) are applied with set() before
#   include() or FetchContent_MakeAvailable (FIND_PACKAGE path: after defaults
#   such as INSTALL_GTEST for GTest, so the lockfile can override).

cmake_minimum_required(VERSION 3.24)

include(FetchContent)

if(NOT MB_DEVENV_FETCHCONTENT_LOCKFILE)
    set(MB_DEVENV_FETCHCONTENT_LOCKFILE
        "fetchcontent-lockfile.json"
        CACHE FILEPATH
        "Path to the dependency lockfile for the FetchContent."
    )
endif()

set(MB_DEVENV_ROOT
    ""
    CACHE PATH
    "Consumer project root (directory containing the lockfile). Empty uses two levels up from this file. When this repo is the top-level project, set to the preset source directory."
)

if(MB_DEVENV_ROOT)
    set(consumer_project_dir "${MB_DEVENV_ROOT}")
else()
    get_filename_component(
        consumer_project_dir
        "${CMAKE_CURRENT_LIST_DIR}/../.."
        ABSOLUTE
    )
endif()

message(TRACE "consumer_project_dir=\"${consumer_project_dir}\"")

# Resolve lockfile path for existence check (support relative to consumer or absolute)
set(lockfile_candidate
    "${consumer_project_dir}/${MB_DEVENV_FETCHCONTENT_LOCKFILE}"
)
if(IS_ABSOLUTE "${MB_DEVENV_FETCHCONTENT_LOCKFILE}")
    set(lockfile_candidate "${MB_DEVENV_FETCHCONTENT_LOCKFILE}")
endif()

if(EXISTS "${lockfile_candidate}")
    message(
        TRACE
        "MB_DEVENV_FETCHCONTENT_LOCKFILE=\"${MB_DEVENV_FETCHCONTENT_LOCKFILE}\""
    )
    file(
        REAL_PATH "${MB_DEVENV_FETCHCONTENT_LOCKFILE}"
        consumer_fetchcontent_lockfile
        BASE_DIRECTORY "${consumer_project_dir}"
        EXPAND_TILDE
    )
    message(
        DEBUG
        "Using FetchContent lockfile: \"${consumer_fetchcontent_lockfile}\""
    )

    # Force CMake to reconfigure the project if the lockfile changes
    set_property(
        DIRECTORY "${consumer_project_dir}"
        APPEND
        PROPERTY CMAKE_CONFIGURE_DEPENDS "${consumer_fetchcontent_lockfile}"
    )

    function(mb_devenv_apply_lockfile_cmake_variables dep_json error_prefix)
        string(
            JSON kind
            ERROR_VARIABLE kind_err
            TYPE "${dep_json}"
            "cmake_variables"
        )
        if(kind_err)
            return()
        endif()
        if(NOT kind STREQUAL "OBJECT")
            message(
                FATAL_ERROR
                "${error_prefix}: \"cmake_variables\" must be a JSON object, got \"${kind}\""
            )
        endif()
        string(JSON n ERROR_VARIABLE err LENGTH "${dep_json}" "cmake_variables")
        if(err)
            message(FATAL_ERROR "${error_prefix}: ${err}")
        endif()
        if(n EQUAL 0)
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
            set("${key}" "${val}" PARENT_SCOPE)
        endforeach()
    endfunction()

    # Eager FetchContent for entries with no package_name (or empty): script/module
    # dependencies that are not wired through find_package.
    file(READ "${consumer_fetchcontent_lockfile}" _mb_devenv_fc_root)
    string(
        JSON _mb_devenv_fc_deps
        ERROR_VARIABLE _mb_devenv_fc_err
        GET "${_mb_devenv_fc_root}"
        "dependencies"
    )
    if(NOT _mb_devenv_fc_err)
        string(
            JSON _mb_devenv_fc_n
            ERROR_VARIABLE _mb_devenv_fc_err
            LENGTH "${_mb_devenv_fc_deps}"
        )
        if(NOT _mb_devenv_fc_err AND _mb_devenv_fc_n GREATER 0)
            math(EXPR _mb_devenv_fc_max "${_mb_devenv_fc_n} - 1")
            foreach(_mb_devenv_fc_i RANGE "${_mb_devenv_fc_max}")
                set(_mb_devenv_fc_ep
                    "${consumer_fetchcontent_lockfile}, dependency ${_mb_devenv_fc_i}"
                )
                string(
                    JSON _mb_devenv_fc_dep
                    ERROR_VARIABLE _mb_devenv_fc_err
                    GET "${_mb_devenv_fc_deps}"
                    "${_mb_devenv_fc_i}"
                )
                if(_mb_devenv_fc_err)
                    message(
                        FATAL_ERROR
                        "${_mb_devenv_fc_ep}: ${_mb_devenv_fc_err}"
                    )
                endif()
                string(
                    JSON _mb_devenv_fc_pkg
                    ERROR_VARIABLE _mb_devenv_fc_pkg_err
                    GET "${_mb_devenv_fc_dep}"
                    "package_name"
                )
                if(
                    NOT _mb_devenv_fc_pkg_err
                    AND NOT "${_mb_devenv_fc_pkg}" STREQUAL ""
                )
                    continue()
                endif()
                string(
                    JSON _mb_devenv_fc_name
                    ERROR_VARIABLE _mb_devenv_fc_err
                    GET "${_mb_devenv_fc_dep}"
                    "name"
                )
                if(_mb_devenv_fc_err)
                    message(
                        FATAL_ERROR
                        "${_mb_devenv_fc_ep}: ${_mb_devenv_fc_err}"
                    )
                endif()
                string(
                    JSON _mb_devenv_fc_repo
                    ERROR_VARIABLE _mb_devenv_fc_err
                    GET "${_mb_devenv_fc_dep}"
                    "git_repository"
                )
                if(_mb_devenv_fc_err)
                    message(
                        FATAL_ERROR
                        "${_mb_devenv_fc_ep}: ${_mb_devenv_fc_err}"
                    )
                endif()
                string(
                    JSON _mb_devenv_fc_tag
                    ERROR_VARIABLE _mb_devenv_fc_err
                    GET "${_mb_devenv_fc_dep}"
                    "git_tag"
                )
                if(_mb_devenv_fc_err)
                    message(
                        FATAL_ERROR
                        "${_mb_devenv_fc_ep}: ${_mb_devenv_fc_err}"
                    )
                endif()
                string(
                    JSON _mb_devenv_fc_cmake_include
                    ERROR_VARIABLE _mb_devenv_fc_inc_err
                    GET "${_mb_devenv_fc_dep}"
                    "cmake_include"
                )
                message(
                    DEBUG
                    "FetchContent (lockfile, eager): ${_mb_devenv_fc_name} from ${_mb_devenv_fc_repo} @ ${_mb_devenv_fc_tag}"
                )
                FetchContent_Declare(
                    "${_mb_devenv_fc_name}"
                    GIT_REPOSITORY "${_mb_devenv_fc_repo}"
                    GIT_TAG "${_mb_devenv_fc_tag}"
                    GIT_SHALLOW ON
                    EXCLUDE_FROM_ALL
                    SYSTEM
                )
                if(
                    NOT _mb_devenv_fc_inc_err
                    AND NOT "${_mb_devenv_fc_cmake_include}" STREQUAL ""
                )
                    # Populate+include avoids nested project() from MakeAvailable while
                    # CMAKE_PROJECT_TOP_LEVEL_INCLUDES runs inside project().
                    if(POLICY CMP0169)
                        cmake_policy(PUSH)
                        cmake_policy(SET CMP0169 OLD)
                    endif()
                    FetchContent_Populate("${_mb_devenv_fc_name}")
                    if(POLICY CMP0169)
                        cmake_policy(POP)
                    endif()
                    mb_devenv_apply_lockfile_cmake_variables(
                        "${_mb_devenv_fc_dep}"
                        "${_mb_devenv_fc_ep}"
                    )
                    string(TOLOWER "${_mb_devenv_fc_name}" _mb_devenv_fc_lc)
                    set(_mb_devenv_fc_src_var "${_mb_devenv_fc_lc}_SOURCE_DIR")
                    include(
                        "${${_mb_devenv_fc_src_var}}/${_mb_devenv_fc_cmake_include}"
                    )
                else()
                    if(POLICY CMP0169)
                        cmake_policy(PUSH)
                        cmake_policy(SET CMP0169 OLD)
                    endif()
                    FetchContent_Populate("${_mb_devenv_fc_name}")
                    if(POLICY CMP0169)
                        cmake_policy(POP)
                    endif()
                    mb_devenv_apply_lockfile_cmake_variables(
                        "${_mb_devenv_fc_dep}"
                        "${_mb_devenv_fc_ep}"
                    )
                    string(TOLOWER "${_mb_devenv_fc_name}" _mb_devenv_fc_lc)
                    set(_mb_devenv_fc_src_var "${_mb_devenv_fc_lc}_SOURCE_DIR")
                    set(_mb_devenv_fc_root_cmakelists
                        "${${_mb_devenv_fc_src_var}}/CMakeLists.txt"
                    )
                    if(EXISTS "${_mb_devenv_fc_root_cmakelists}")
                        file(
                            READ "${_mb_devenv_fc_root_cmakelists}"
                            _mb_devenv_fc_root_c
                        )
                        string(
                            REGEX MATCH "(^|[\r\n])[ \t]*project[ \t]*\\("
                            _mb_devenv_fc_root_has_project
                            "${_mb_devenv_fc_root_c}"
                        )
                        if(_mb_devenv_fc_root_has_project)
                            message(
                                FATAL_ERROR
                                "FetchContent lockfile (\"${consumer_fetchcontent_lockfile}\"): "
                                "dependency \"${_mb_devenv_fc_name}\" has a top-level project() "
                                "in its CMakeLists.txt. With CMAKE_PROJECT_TOP_LEVEL_INCLUDES, "
                                "FetchContent_MakeAvailable would add that project while your "
                                "own project() is still configuring (nested project() is not "
                                "allowed).\n"
                                "Fix: add a \"cmake_include\" relative path to a .cmake file in that "
                                "repository."
                            )
                        endif()
                    endif()
                    FetchContent_MakeAvailable("${_mb_devenv_fc_name}")
                endif()
            endforeach()
        endif()
    endif()

    # For more on the protocol for this function, see:
    # https://cmake.org/cmake/help/latest/command/cmake_language.html#provider-commands
    function(mb_devenv_fetchcontent_provide_dependency method package_name)
        # Read the lockfile
        file(READ "${consumer_fetchcontent_lockfile}" root_obj)

        # Get the "dependencies" field and store it in dependencies_obj
        string(
            JSON dependencies_obj
            ERROR_VARIABLE error
            GET "${root_obj}"
            "dependencies"
        )
        if(error)
            message(FATAL_ERROR "${consumer_fetchcontent_lockfile}: ${error}")
        endif()

        # Get the length of the dependencies array
        string(
            JSON num_dependencies
            ERROR_VARIABLE error
            LENGTH "${dependencies_obj}"
        )
        if(error)
            message(FATAL_ERROR "${consumer_fetchcontent_lockfile}: ${error}")
        endif()

        if(num_dependencies EQUAL 0)
            return()
        endif()

        # Loop over each dependency object
        math(EXPR max_index "${num_dependencies} - 1")
        foreach(index RANGE "${max_index}")
            set(error_prefix
                "${consumer_fetchcontent_lockfile}, dependency ${index}"
            )

            # Get the dependency object at index
            # and store it in dep_obj
            string(
                JSON dep_obj
                ERROR_VARIABLE error
                GET "${dependencies_obj}"
                "${index}"
            )
            if(error)
                message(FATAL_ERROR "${error_prefix}: ${error}")
            endif()

            # Get the "name" field and store it in name
            string(JSON name ERROR_VARIABLE error GET "${dep_obj}" "name")
            if(error)
                message(FATAL_ERROR "${error_prefix}: ${error}")
            endif()

            # Optional "package_name": if absent or empty, this entry is only handled
            # by eager FetchContent above (not by find_package).
            string(
                JSON pkg_name
                ERROR_VARIABLE error
                GET "${dep_obj}"
                "package_name"
            )
            if(error OR "${pkg_name}" STREQUAL "")
                continue()
            endif()

            # Get the "git_repository" field and store it in repo
            string(
                JSON repo
                ERROR_VARIABLE error
                GET "${dep_obj}"
                "git_repository"
            )
            if(error)
                message(FATAL_ERROR "${error_prefix}: ${error}")
            endif()

            # Get the "git_tag" field and store it in tag
            string(JSON tag ERROR_VARIABLE error GET "${dep_obj}" "git_tag")
            if(error)
                message(FATAL_ERROR "${error_prefix}: ${error}")
            endif()

            if(method STREQUAL "FIND_PACKAGE")
                if(package_name STREQUAL pkg_name)
                    string(
                        APPEND debug
                        "Redirecting find_package calls for ${pkg_name} "
                        "to FetchContent logic.\n"
                    )
                    string(
                        APPEND debug
                        "Fetching ${repo} at "
                        "${tag} according to ${consumer_fetchcontent_lockfile}."
                    )
                    message(DEBUG "${debug}")
                    FetchContent_Declare(
                        "${name}"
                        GIT_REPOSITORY "${repo}"
                        GIT_TAG "${tag}"
                        GIT_SHALLOW ON
                        EXCLUDE_FROM_ALL
                        SYSTEM
                    )
                    set(INSTALL_GTEST OFF) # Disable GoogleTest installation
                    mb_devenv_apply_lockfile_cmake_variables(
                        "${dep_obj}"
                        "${error_prefix}"
                    )
                    FetchContent_MakeAvailable("${name}")

                    # Important! <PackageName>_FOUND tells CMake that `find_package` is
                    # not needed for this package anymore
                    set("${pkg_name}_FOUND" TRUE PARENT_SCOPE)
                endif()
            endif()
        endforeach()
    endfunction()

    cmake_language(
        SET_DEPENDENCY_PROVIDER mb_devenv_fetchcontent_provide_dependency
        SUPPORTED_METHODS FIND_PACKAGE
    )

    # Add this dir to the module path so that `find_package(...)` works
    list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_LIST_DIR}")
else()
    message(
        STATUS
        "FetchContent lockfile not found (${lockfile_candidate}), skipping lockfile dependency provider"
    )
endif()
