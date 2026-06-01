# Suppress warnings for vendored targets (consumer -Werror / -Wconversion still apply otherwise).
# INTERFACE: applies to TUs that link or include through the dependency (header-only).
# Other library types: applies only to that target's own sources.
function(mb_devenv_suppress_third_party_warnings target)
    if(NOT TARGET ${target})
        message(
            FATAL_ERROR
            "mb_devenv_suppress_third_party_warnings: no target '${target}'"
        )
    endif()
    get_target_property(_mb_devenv_tw_type ${target} TYPE)
    if(_mb_devenv_tw_type STREQUAL "INTERFACE_LIBRARY")
        set(_mb_devenv_tw_scope INTERFACE)
    else()
        set(_mb_devenv_tw_scope PRIVATE)
    endif()
    if(MSVC)
        target_compile_options(${target} ${_mb_devenv_tw_scope} /w)
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang|IntelLLVM|Intel")
        target_compile_options(${target} ${_mb_devenv_tw_scope} -w)
    endif()
endfunction()
