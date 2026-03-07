# To be used e.g. by CMakePresets presets like
# "cacheVariables": {
#     "CMAKE_TOOLCHAIN_FILE": "devenv/cmake/toolchains/...-toolchain.cmake"
# }
# You can also set MB_SANITIZER as cache var (see below for allowed values).

include_guard(GLOBAL)

set(CMAKE_C_COMPILER cc)
set(CMAKE_CXX_COMPILER c++)

if(MB_SANITIZER STREQUAL "MaxSan")
    set(SANITIZER_FLAGS
        "-fsanitize=address -fsanitize=pointer-compare -fsanitize=pointer-subtract -fsanitize=undefined"
    )
elseif(MB_SANITIZER STREQUAL "TSan")
    set(SANITIZER_FLAGS "-fsanitize=thread")
elseif(MB_SANITIZER STREQUAL "MSan")
    set(SANITIZER_FLAGS "-fsanitize=memory MSAN_OPTIONS=suppressions=${CMAKE_CURRENT_LIST_DIR}/msan.supp")
endif()

set(CMAKE_C_FLAGS_DEBUG_INIT "${SANITIZER_FLAGS}")
set(CMAKE_CXX_FLAGS_DEBUG_INIT "${SANITIZER_FLAGS}")

set(RELEASE_FLAGS "-O3 ${SANITIZER_FLAGS}")

set(CMAKE_C_FLAGS_RELWITHDEBINFO_INIT "${RELEASE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO_INIT "${RELEASE_FLAGS}")

set(CMAKE_C_FLAGS_RELEASE_INIT "${RELEASE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "${RELEASE_FLAGS}")

# Add this dir to the module path so that `find_package(your-install-library)` works
list(APPEND CMAKE_PREFIX_PATH "../..")
