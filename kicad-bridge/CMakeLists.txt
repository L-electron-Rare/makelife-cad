cmake_minimum_required(VERSION 3.20)
project(kicad_bridge C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(kicad_bridge STATIC
    src/bridge_sch.c
    src/bridge_pcb.c
    src/bridge_drc.c
)

target_include_directories(kicad_bridge PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(kicad_bridge PRIVATE m)

# macOS arm64 only for Phase 1
if(APPLE)
    set_target_properties(kicad_bridge PROPERTIES
        OSX_ARCHITECTURES "arm64"
    )
endif()

# Expose build artifact path for Xcode integration
set(KICAD_BRIDGE_LIB "${CMAKE_BINARY_DIR}/libkicad_bridge.a" PARENT_SCOPE)
