cmake_minimum_required(VERSION 3.20)

if(APPLE)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS deployment target")
endif()

project(kicad_bridge C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(kicad_bridge STATIC
    src/bridge_sch.c
    src/bridge_sch_edit.c
    src/bridge_pcb.c
    src/bridge_drc.c
    src/bridge_pcb_edit.c
    src/bridge_3d.c src/bridge_swift.c
)

target_include_directories(kicad_bridge PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(kicad_bridge PRIVATE m)

# macOS arm64 only for Phase 1
if(APPLE)
    set_target_properties(kicad_bridge PROPERTIES
        OSX_ARCHITECTURES "arm64"
        XCODE_ATTRIBUTE_MACOSX_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}"
    )
endif()

# Expose build artifact path for Xcode integration
set(KICAD_BRIDGE_LIB "${CMAKE_BINARY_DIR}/libkicad_bridge.a" CACHE INTERNAL "kicad_bridge archive path")
