cmake_minimum_required(VERSION 3.22)
project(kicad-svg-helper LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0)

# ---- KiCad source and build paths ----
# These must point to a completed KiCad build
set(KICAD_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../kicad"
    CACHE PATH "Path to KiCad source tree")
set(KICAD_BUILD_DIR "${KICAD_SRC_DIR}/build"
    CACHE PATH "Path to KiCad build directory")

# ---- Find wxWidgets ----
set(wxWidgets_CONFIG_EXECUTABLE "/opt/homebrew/opt/wxwidgets/bin/wx-config"
    CACHE PATH "Path to wx-config")
find_package(wxWidgets REQUIRED COMPONENTS core base)
include(${wxWidgets_USE_FILE})

# ---- KiCad include paths ----
set(KICAD_INCLUDE_DIRS
    ${KICAD_SRC_DIR}/include
    ${KICAD_SRC_DIR}/eeschema
    ${KICAD_SRC_DIR}/common
    ${KICAD_SRC_DIR}/libs/kimath/include
    ${KICAD_SRC_DIR}/libs/kiplatform/include
    ${KICAD_SRC_DIR}/libs/core/include
    ${KICAD_SRC_DIR}/libs/sexpr/include
    ${KICAD_SRC_DIR}/thirdparty
    ${KICAD_SRC_DIR}/thirdparty/nlohmann_json/include
    ${KICAD_SRC_DIR}/thirdparty/fmt/include
    ${KICAD_SRC_DIR}/thirdparty/clipper2/Clipper2Lib/include
    ${KICAD_SRC_DIR}/thirdparty/nanosvg/include
    ${KICAD_SRC_DIR}/thirdparty/argparse/include
    ${KICAD_BUILD_DIR}   # For generated headers (config.h etc.)
)

# ---- KiCad libraries ----
# Shared libs (from KiCad build)
set(KICAD_FRAMEWORK_DIR "${KICAD_BUILD_DIR}/kicad/KiCad.app/Contents/Frameworks")

find_library(LIB_KICOMMON kicommon PATHS ${KICAD_FRAMEWORK_DIR} NO_DEFAULT_PATH)
find_library(LIB_KIGAL kigal PATHS ${KICAD_FRAMEWORK_DIR} NO_DEFAULT_PATH)
find_library(LIB_KIAPI kiapi PATHS ${KICAD_FRAMEWORK_DIR} NO_DEFAULT_PATH)

# Static libs (from KiCad build)
set(LIB_COMMON "${KICAD_BUILD_DIR}/common/libcommon.a")
set(LIB_CORE "${KICAD_BUILD_DIR}/libs/core/libcore.a")
set(LIB_KIMATH "${KICAD_BUILD_DIR}/libs/kimath/libkimath.a")
set(LIB_KIPLATFORM "${KICAD_BUILD_DIR}/libs/kiplatform/libkiplatform.a")
set(LIB_SEXPR "${KICAD_BUILD_DIR}/libs/sexpr/libsexpr.a")
set(LIB_PADS "${KICAD_BUILD_DIR}/common/io/pads/libpads_common.a")
set(LIB_SCRIPTING "${KICAD_BUILD_DIR}/scripting/libscripting.a")

# Third-party static libs
set(LIB_FMT "${KICAD_BUILD_DIR}/thirdparty/fmt/libfmt.a")
set(LIB_CLIPPER2 "${KICAD_BUILD_DIR}/thirdparty/clipper2/libclipper2.a")
set(LIB_NANODBC "${KICAD_BUILD_DIR}/thirdparty/nanodbc/libnanodbc.a")
set(LIB_NANOSVG "${KICAD_BUILD_DIR}/thirdparty/nanosvg/libnanosvg.a")
set(LIB_TINYSPLINE "${KICAD_BUILD_DIR}/thirdparty/tinyspline_lib/libtinyspline_lib.a")
set(LIB_DXFLIB "${KICAD_BUILD_DIR}/thirdparty/dxflib_qcad/libdxflib_qcad.a")
set(LIB_POTRACE "${KICAD_BUILD_DIR}/thirdparty/potrace/libpotrace.a")
set(LIB_GLAD "${KICAD_BUILD_DIR}/thirdparty/glad/libglad.a")
set(LIB_JSON_VALIDATOR "${KICAD_BUILD_DIR}/thirdparty/json_schema_validator/libnlohmann_json_schema_validator.a")
set(LIB_DELAUNATOR "${KICAD_BUILD_DIR}/thirdparty/delaunator/libdelaunator.a")
set(LIB_ZINT "${KICAD_BUILD_DIR}/thirdparty/zint/libzint.a")

# ---- System / Homebrew libraries ----
find_package(PkgConfig REQUIRED)
pkg_check_modules(CAIRO REQUIRED cairo)
find_package(Boost REQUIRED COMPONENTS locale)
find_package(Freetype REQUIRED)
find_package(HarfBuzz REQUIRED)
find_package(Fontconfig REQUIRED)
find_library(LIB_UNIXODBC odbc PATHS /opt/homebrew/lib)
find_library(LIB_NGSPICE ngspice PATHS /opt/homebrew/opt/libngspice/lib)

# ---- OpenCascade ----
set(OCC_INCLUDE_DIR "/opt/homebrew/opt/opencascade/include/opencascade")
find_library(LIB_OCC_TKSTEP TKDESTEP PATHS /opt/homebrew/lib)
find_library(LIB_OCC_TKXDESTEP TKXSBase PATHS /opt/homebrew/lib)

# ---- Build the helper ----
add_executable(kicad-svg-helper
    kicad_svg_helper.cpp
)

target_include_directories(kicad-svg-helper PRIVATE
    ${KICAD_INCLUDE_DIRS}
    ${CAIRO_INCLUDE_DIRS}
    ${Boost_INCLUDE_DIRS}
    ${FREETYPE_INCLUDE_DIRS}
    ${HarfBuzz_INCLUDE_DIRS}
    ${Fontconfig_INCLUDE_DIRS}
    ${OCC_INCLUDE_DIR}
    /opt/homebrew/include
)

target_compile_definitions(kicad-svg-helper PRIVATE
    WXUSINGDLL
    wxDEBUG_LEVEL=0
    KICAD_BUILD_ARCH_ARM
    KICAD_CONFIG_DIR=kicad
    KICAD_SIGNAL_INTEGRITY
    KICAD_UPDATE_CHECK
    GL_SILENCE_DEPRECATION=1
)

target_link_libraries(kicad-svg-helper PRIVATE
    # KiCad shared libs
    ${LIB_KICOMMON}
    ${LIB_KIGAL}
    ${LIB_KIAPI}
    # KiCad static libs
    ${LIB_COMMON}
    ${LIB_PADS}
    ${LIB_CORE}
    ${LIB_KIMATH}
    ${LIB_KIPLATFORM}
    ${LIB_SEXPR}
    ${LIB_SCRIPTING}
    # KiCad thirdparty
    ${LIB_FMT}
    ${LIB_CLIPPER2}
    ${LIB_NANODBC}
    ${LIB_NANOSVG}
    ${LIB_TINYSPLINE}
    ${LIB_DXFLIB}
    ${LIB_POTRACE}
    ${LIB_GLAD}
    ${LIB_JSON_VALIDATOR}
    ${LIB_DELAUNATOR}
    ${LIB_ZINT}
    # wxWidgets
    ${wxWidgets_LIBRARIES}
    # System
    ${CAIRO_LIBRARIES}
    ${Boost_LIBRARIES}
    ${FREETYPE_LIBRARIES}
    ${HarfBuzz_LIBRARIES}
    ${Fontconfig_LIBRARIES}
    ${LIB_UNIXODBC}
    ${LIB_NGSPICE}
    # macOS frameworks
    "-framework IOKit"
    "-framework Carbon"
    "-framework Cocoa"
    "-framework OpenGL"
    "-framework Security"
    "-framework CoreFoundation"
    "-framework WebKit"
)

# Set RPATH for finding KiCad dylibs
set_target_properties(kicad-svg-helper PROPERTIES
    INSTALL_RPATH "@executable_path/../Frameworks"
    BUILD_RPATH "${KICAD_FRAMEWORK_DIR};/opt/homebrew/lib"
)
