
project(hicops-core LANGUAGES C CXX)

set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# set(CMAKE_CUDA_SEPARABLE_COMPILATION ON)

if (USE_GPU)
    enable_language(CUDA)
endif()

include_directories(BEFORE ${CMAKE_CURRENT_LIST_DIR}/include)

set(CMAKE_INSTALL_DEFAULT_COMPONENT_NAME library)

#----------------------------------------------------------------------------------------#
# Locate sources and headers for this project
# - headers are included so they will show up in IDEs
#
file(GLOB c_headers                 ${CMAKE_CURRENT_LIST_DIR}/include/*.h)
file(GLOB cxx_headers               ${CMAKE_CURRENT_LIST_DIR}/include/*.hpp )
file(GLOB c_sources                 ${CMAKE_CURRENT_LIST_DIR}/*.c)
file(GLOB cxx_sources               ${CMAKE_CURRENT_LIST_DIR}/*.cpp)

if (USE_GPU)
    file(GLOB cuda_sources              ${CMAKE_CURRENT_LIST_DIR}/*/*/*.cu)
endif()

# all the headers
set(hicops_glob_headers
    ${c_headers} ${cxx_headers})


add_library (hicops-core SHARED ${c_sources} ${cxx_sources} ${cuda_sources})

# add CUDA architecture property
set_property(TARGET hicops-core  PROPERTY CUDA_ARCHITECTURES 60 70 80)

# set CUDA_SEPARABLE_COMPILATION to ON
set_property(TARGET hicops-core PROPERTY CUDA_SEPARABLE_COMPILATION ON)

# to include the generated config.hpp
include_directories(${CMAKE_BINARY_DIR})

if (USE_TIMEMORY)
    target_link_libraries(hicops-core timemory-hicops)
endif()

set_target_properties(hicops-core
    PROPERTIES
        CXX_STANDARD ${CXX_STANDARD}
        CXX_STANDARD_REQUIRED YES
        CXX_EXTENSIONS NO
)

install(TARGETS hicops-core DESTINATION lib)

INSTALL (
    DIRECTORY ${CMAKE_CURRENT_LIST_DIR}/include/
    DESTINATION include
    FILES_MATCHING PATTERN "*.h*")
