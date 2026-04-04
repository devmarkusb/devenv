# Global CMAKE_CXX_FLAGS from presets (e.g. MaxWarnClang) may include -Wno-* options that not every
# toolchain implements. Apple Clang does not support -Wno-character-conversion (unknown warning option
# under -Werror); strip it so FetchContent deps such as GoogleTest still build.

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")
    if(CMAKE_CXX_FLAGS MATCHES "character-conversion")
        string(
            REPLACE "-Wno-character-conversion"
            ""
            _mb_devenv_cxx_flags
            "${CMAKE_CXX_FLAGS}"
        )
        string(
            REGEX REPLACE "  +"
            " "
            _mb_devenv_cxx_flags
            "${_mb_devenv_cxx_flags}"
        )
        string(STRIP "${_mb_devenv_cxx_flags}" _mb_devenv_cxx_flags)
        set(CMAKE_CXX_FLAGS
            "${_mb_devenv_cxx_flags}"
            CACHE STRING
            "Flags used by the CXX compiler during all build types."
            FORCE
        )
    endif()
endif()
