# To be used e.g. by CMakePresets presets like
# "cacheVariables": {
#     "CMAKE_TOOLCHAIN_FILE": "devenv/cmake/toolchains/...-toolchain.cmake"
# }
# You can also set MB_SANITIZER as cache var (see below for allowed values).

include_guard(GLOBAL)

set(CMAKE_C_COMPILER cl)
set(CMAKE_CXX_COMPILER cl)

if(MB_SANITIZER STREQUAL "MaxSan")
    # /Zi flag (add debug symbol) is needed when using address sanitizer
    # See C5072: https://learn.microsoft.com/en-us/cpp/error-messages/compiler-warnings/compiler-warning-c5072
    set(SANITIZER_FLAGS "/fsanitize=address /Zi")
endif()

set(CMAKE_CXX_FLAGS_DEBUG_INIT "/EHsc /permissive- ${SANITIZER_FLAGS}")
set(CMAKE_C_FLAGS_DEBUG_INIT "/EHsc /permissive- ${SANITIZER_FLAGS}")

set(RELEASE_FLAGS "/EHsc /permissive- /O2 ${SANITIZER_FLAGS}")

set(CMAKE_C_FLAGS_RELWITHDEBINFO_INIT "${RELEASE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO_INIT "${RELEASE_FLAGS}")

set(CMAKE_C_FLAGS_RELEASE_INIT "${RELEASE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "${RELEASE_FLAGS}")

# Add this dir to the module path so that `find_package(your-install-library)` works
list(APPEND CMAKE_PREFIX_PATH "../..")
