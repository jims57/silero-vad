cmake_minimum_required(VERSION 3.15)
project(WQVad VERSION 1.0.0 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# iOS specific settings
if(IOS)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0")
    set(CMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "YOUR_TEAM_ID")
    set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")
    set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
    set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
endif()

# Find ONNX Runtime XCFramework
set(ONNXRUNTIME_ROOT_PATH "${CMAKE_CURRENT_SOURCE_DIR}/third_party/onnxruntime.xcframework")

if(IOS)
    # For iOS device
    set(ONNXRUNTIME_LIB_PATH "${ONNXRUNTIME_ROOT_PATH}/ios-arm64/onnxruntime.framework")
    set(ONNXRUNTIME_INCLUDE_PATH "${ONNXRUNTIME_LIB_PATH}/Headers")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    # For macOS
    set(ONNXRUNTIME_LIB_PATH "${ONNXRUNTIME_ROOT_PATH}/macos-arm64_x86_64/onnxruntime.framework")
    set(ONNXRUNTIME_INCLUDE_PATH "${ONNXRUNTIME_LIB_PATH}/Headers")
endif()

# Verify ONNX Runtime exists
if(NOT EXISTS "${ONNXRUNTIME_INCLUDE_PATH}")
    message(FATAL_ERROR "ONNX Runtime headers not found at: ${ONNXRUNTIME_INCLUDE_PATH}")
endif()

# Create imported target for ONNX Runtime
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION "${ONNXRUNTIME_LIB_PATH}/onnxruntime"
    INTERFACE_INCLUDE_DIRECTORIES "${ONNXRUNTIME_INCLUDE_PATH}"
)

# Library target
add_library(wqvad STATIC
    src/wqvad.cpp
)

# Include directories
target_include_directories(wqvad
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        src
        ${ONNXRUNTIME_INCLUDE_PATH}
)

# Link libraries
target_link_libraries(wqvad
    PRIVATE
        onnxruntime
)

# Compiler features and flags
target_compile_features(wqvad PUBLIC cxx_std_17)

# iOS specific compiler flags
if(IOS)
    target_compile_definitions(wqvad PRIVATE IOS_PLATFORM)
    target_compile_options(wqvad PRIVATE 
        -fembed-bitcode
        -fvisibility=hidden
    )
endif()

# Install rules
install(TARGETS wqvad
    EXPORT WQVadTargets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

install(DIRECTORY include/ DESTINATION include)

# Export configuration
install(EXPORT WQVadTargets
    FILE WQVadTargets.cmake
    NAMESPACE WQVad::
    DESTINATION lib/cmake/WQVad
)

# Copy Silero model to build directory
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/src/silero_vad_v5.onnx"
    "${CMAKE_CURRENT_BINARY_DIR}/silero_vad_v5.onnx"
    COPYONLY
)

# Examples and tests
if(NOT IOS)
    add_subdirectory(examples)
    add_subdirectory(tests)
endif()
