cmake_minimum_required(VERSION 3.24)

include(FetchContent)

if(NOT MB_FETCHCONTENT_LOCKFILE)
    set(MB_FETCHCONTENT_LOCKFILE
        "fetchcontent-lockfile.json"
        CACHE FILEPATH
        "Path to the dependency lockfile for the FetchContent."
    )
endif()

set(consumer_project_dir "${CMAKE_CURRENT_LIST_DIR}/../..")
message(TRACE "consumer_project_dir=\"${consumer_project_dir}\"")

message(TRACE "MB_FETCHCONTENT_LOCKFILE=\"${MB_FETCHCONTENT_LOCKFILE}\"")
file(
    REAL_PATH
    "${MB_FETCHCONTENT_LOCKFILE}"
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

# For more on the protocol for this function, see:
# https://cmake.org/cmake/help/latest/command/cmake_language.html#provider-commands
function(mb_fetchcontent_provide_dependency method package_name)
    # Read the lockfile
    file(READ "${consumer_fetchcontent_lockfile}" root_obj)

    # Get the "dependencies" field and store it in dependencies_obj
    string(
        JSON
        dependencies_obj
        ERROR_VARIABLE error
        GET "${root_obj}"
        "dependencies"
    )
    if(error)
        message(FATAL_ERROR "${consumer_fetchcontent_lockfile}: ${error}")
    endif()

    # Get the length of the libraries array and store it in dependencies_obj
    string(
        JSON
        num_dependencies
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
            JSON
            dep_obj
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

        # Get the "package_name" field and store it in pkg_name
        string(
            JSON
            pkg_name
            ERROR_VARIABLE error
            GET "${dep_obj}"
            "package_name"
        )
        if(error)
            message(FATAL_ERROR "${error_prefix}: ${error}")
        endif()

        # Get the "git_repository" field and store it in repo
        string(JSON repo ERROR_VARIABLE error GET "${dep_obj}" "git_repository")
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
                    APPEND
                    debug
                    "Redirecting find_package calls for ${pkg_name} "
                    "to FetchContent logic.\n"
                )
                string(
                    APPEND
                    debug
                    "Fetching ${repo} at "
                    "${tag} according to ${consumer_fetchcontent_lockfile}."
                )
                message(DEBUG "${debug}")
                FetchContent_Declare(
                    "${name}"
                    GIT_REPOSITORY "${repo}"
                    GIT_TAG "${tag}"
                    EXCLUDE_FROM_ALL
                )
                set(INSTALL_GTEST OFF) # Disable GoogleTest installation
                FetchContent_MakeAvailable("${name}")

                # Important! <PackageName>_FOUND tells CMake that `find_package` is
                # not needed for this package anymore
                set("${pkg_name}_FOUND" TRUE PARENT_SCOPE)
            endif()
        endif()
    endforeach()
endfunction()

cmake_language(
    SET_DEPENDENCY_PROVIDER mb_fetchcontent_provide_dependency
    SUPPORTED_METHODS FIND_PACKAGE
)

# Add this dir to the module path so that `find_package(your-install-library)` works
list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_LIST_DIR}")
