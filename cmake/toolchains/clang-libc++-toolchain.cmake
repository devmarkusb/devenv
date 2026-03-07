# To be used e.g. by CMakePresets presets like
# "cacheVariables": {
#     "CMAKE_TOOLCHAIN_FILE": "devenv/cmake/toolchains/...-toolchain.cmake"
# }
# You can also set MB_SANITIZER as cache var (see below for allowed values).

include(${CMAKE_CURRENT_LIST_DIR}/clang-toolchain.cmake)

if(NOT CMAKE_CXX_FLAGS MATCHES "-stdlib=libc\\+\\+")
    string(APPEND CMAKE_CXX_FLAGS " -stdlib=libc++")
endif()
