### OS ###
# Note, in code we call them MB_DEVENV_OS_... instead of MB_DEVENV_...

if(WIN32)
    # one might still prefer the very common WIN32
    set(MB_DEVENV_WINDOWS TRUE)
endif()

if(APPLE OR (${CMAKE_SYSTEM_NAME} MATCHES "Darwin"))
    set(MB_DEVENV_MACOS TRUE)
endif()

if(UNIX AND NOT MB_DEVENV_MACOS)
    set(MB_DEVENV_LINUX TRUE)
endif()

if(UNIX)
    set(MB_DEVENV_UNIX TRUE)
endif()

# so far defined by toolchain we use
if(ANDROID)
    set(MB_DEVENV_ANDROID TRUE)
endif()

include(CheckCXXSourceCompiles)

check_cxx_source_compiles("
#include <string>
#ifndef _LIBCPP_VERSION
#error Not libc++
#endif
int main() {}
" MB_DEVENV_USING_LIBCPP)
