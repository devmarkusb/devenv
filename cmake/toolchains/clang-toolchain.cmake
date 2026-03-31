# To be used e.g. by CMakePresets presets like
# "cacheVariables": {
#     "CMAKE_TOOLCHAIN_FILE": "devenv/cmake/toolchains/...-toolchain.cmake"
# }
# You can also set MB_DEVENV_SANITIZER as cache var (see below for allowed values).

include_guard(GLOBAL)

set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)

if(MB_DEVENV_SANITIZER STREQUAL "MaxSan")
    set(SANITIZER_FLAGS
        "-fsanitize=address -fsanitize=leak -fsanitize=pointer-compare -fsanitize=pointer-subtract -fsanitize=undefined -fsanitize-undefined-trap-on-error"
    )
elseif(MB_DEVENV_SANITIZER STREQUAL "TSan")
    set(SANITIZER_FLAGS "-fsanitize=thread")
elseif(MB_DEVENV_SANITIZER STREQUAL "MSan")
    set(_mb_devenv_msan_supp "${CMAKE_CURRENT_LIST_DIR}/msan.supp")
    set(ENV{MSAN_OPTIONS} "suppressions=${_mb_devenv_msan_supp}")
    set(MSAN_IGNORELIST "${_mb_devenv_msan_supp}")
    set(SANITIZER_FLAGS
        "-fsanitize=memory -fsanitize-ignorelist=${MSAN_IGNORELIST}"
    )
endif()

set(CMAKE_C_FLAGS_DEBUG_INIT "${SANITIZER_FLAGS}")
set(CMAKE_CXX_FLAGS_DEBUG_INIT "${SANITIZER_FLAGS}")

set(RELEASE_FLAGS "-O3 ${SANITIZER_FLAGS}")

set(CMAKE_C_FLAGS_RELWITHDEBINFO_INIT "${RELEASE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO_INIT "${RELEASE_FLAGS}")

set(CMAKE_C_FLAGS_RELEASE_INIT "${RELEASE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "${RELEASE_FLAGS}")

# Top-level CMakeLists directory (consumer root or this repo); works for submodule and standalone.
list(APPEND CMAKE_PREFIX_PATH "${CMAKE_SOURCE_DIR}")
