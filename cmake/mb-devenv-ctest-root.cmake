# Include from the top-level CMakeLists.txt (after CMAKE_MODULE_PATH includes
# devenv/cmake, so
# enable_testing() runs at the top level when tests are enabled. Otherwise the
# build root has no CTestTestfile.cmake and ctest from the build directory
# finds no tests.

include_guard(GLOBAL)

# calls enable_testing() implicitly
include(CTest)
