
project(counter LANGUAGES C CXX)

file(GLOB c_headers                 ${CMAKE_CURRENT_LIST_DIR}/include/*.h)
file(GLOB cxx_headers               ${CMAKE_CURRENT_LIST_DIR}/include/*.hpp)
file(GLOB c_sources                 ${CMAKE_CURRENT_LIST_DIR}/*.c)
file(GLOB cxx_sources               ${CMAKE_CURRENT_LIST_DIR}/*.cpp)

add_executable(counter ${cxx_sources} ${c_sources})

add_dependencies(counter magic_enum argparse)

set_target_properties(counter
    PROPERTIES
        CXX_STANDARD ${CXX_STANDARD}
        CXX_STANDARD_REQUIRED YES
        CXX_EXTENSIONS NO
        INSTALL_RPATH_USE_LINK_PATH ON
)

target_include_directories(counter PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../../core/include ${CMAKE_CURRENT_LIST_DIR}/../argp ${CMAKE_BINARY_DIR} ${MAGICENUM_INCLUDE_DIR} ${ARGPARSE_INCLUDE_DIR})

# installation
install(TARGETS counter DESTINATION ${CMAKE_INSTALL_BINDIR})
