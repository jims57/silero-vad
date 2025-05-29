#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting iOS XCFramework build for WQVad...${NC}"

# Configuration
PROJECT_NAME="WQVad"
LIBRARY_NAME="wqvad"
FRAMEWORK_NAME="WQVad"
BUILD_DIR="build"
XCFRAMEWORK_DIR="xcframework"

# Clean previous builds
echo -e "${YELLOW}Cleaning previous builds...${NC}"
rm -rf ${BUILD_DIR}
rm -rf ${XCFRAMEWORK_DIR}
rm -rf ${FRAMEWORK_NAME}.xcframework
rm -rf CMakeCache.txt CMakeFiles

# Verify ONNX Runtime XCFramework exists
ONNXRUNTIME_PATH="third_party/onnxruntime.xcframework"
if [ ! -d "${ONNXRUNTIME_PATH}" ]; then
    echo -e "${RED}❌ ONNX Runtime XCFramework not found at ${ONNXRUNTIME_PATH}${NC}"
    echo -e "${YELLOW}Please download ONNX Runtime XCFramework and place it in third_party/${NC}"
    exit 1
fi

# Verify Silero model exists
SILERO_MODEL_PATH="src/silero_vad_v5.onnx"
if [ ! -f "${SILERO_MODEL_PATH}" ]; then
    echo -e "${RED}❌ Silero VAD V5 model not found at ${SILERO_MODEL_PATH}${NC}"
    echo -e "${YELLOW}Please download silero_vad_v5.onnx and place it in src/${NC}"
    exit 1
fi

# Create build directories
mkdir -p ${BUILD_DIR}
mkdir -p ${XCFRAMEWORK_DIR}

# Create temporary include directory for compilation
mkdir -p ${BUILD_DIR}/temp_headers

# Create WQVad.h header first (needed for C wrapper compilation) - PURE C ONLY
echo -e "${YELLOW}Creating WQVad header file...${NC}"
cat > ${BUILD_DIR}/temp_headers/WQVad.h << 'EOF'
#ifndef WQVad_h
#define WQVad_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// WQVad C API for Objective-C integration

typedef struct WQVadContext WQVadContext;

/**
 * Create a new WQVad context with Silero VAD V5
 * @param modelData Pointer to the Silero VAD V5 model data in memory
 * @param modelSize Size of the model data in bytes
 * @param threshold VAD threshold (0.0 - 1.0, default 0.5)
 * @return WQVad context pointer, NULL on failure
 */
WQVadContext* wqvad_create(const void* modelData, size_t modelSize, float threshold);

/**
 * Create WQVad context from model file path
 * @param modelPath Path to silero_vad_v5.onnx file
 * @param threshold VAD threshold (0.0 - 1.0, default 0.5)
 * @return WQVad context pointer, NULL on failure
 */
WQVadContext* wqvad_create_from_file(const char* modelPath, float threshold);

/**
 * Process audio chunk (expects 512 samples for 16kHz)
 * @param context WQVad context
 * @param audioData Float audio samples (16kHz, mono)
 * @param numSamples Number of samples (should be 512)
 * @param outProbability Output voice probability
 * @return 1 if voice detected, 0 otherwise, -1 on error
 */
int wqvad_process_chunk(WQVadContext* context, 
                       const float* audioData, 
                       size_t numSamples,
                       float* outProbability);

/**
 * Process entire audio buffer and get speech segments
 * @param context WQVad context
 * @param audioData Float audio samples (16kHz, mono)
 * @param numSamples Total number of samples
 * @param outSegments Output array of speech segments (caller must free)
 * @param outNumSegments Number of segments returned
 * @return 0 on success, -1 on error
 */
int wqvad_process_audio(WQVadContext* context,
                       const float* audioData,
                       size_t numSamples,
                       float** outSegments,  // Array of [start_time, end_time] pairs
                       size_t* outNumSegments);

/**
 * Reset VAD state (call between different audio streams)
 * @param context WQVad context
 */
void wqvad_reset(WQVadContext* context);

/**
 * Get WQVad version string
 * @return Version string
 */
const char* wqvad_get_version(void);

/**
 * Free speech segments returned by wqvad_process_audio
 * @param segments Segments array to free
 */
void wqvad_free_segments(float* segments);

/**
 * Destroy WQVad context and free resources
 * @param context WQVad context to destroy
 */
void wqvad_destroy(WQVadContext* context);

// Utility functions for audio processing

/**
 * Convert 16-bit PCM to float samples
 * @param pcmData Input PCM data
 * @param numSamples Number of samples
 * @param outFloatData Output float array (caller must free)
 * @return 0 on success, -1 on error
 */
int wqvad_pcm_to_float(const int16_t* pcmData, 
                      size_t numSamples, 
                      float** outFloatData);

/**
 * Resample audio from one sample rate to another
 * @param inputData Input audio samples
 * @param inputSamples Number of input samples
 * @param fromRate Source sample rate
 * @param toRate Target sample rate
 * @param outData Output resampled data (caller must free)
 * @param outSamples Number of output samples
 * @return 0 on success, -1 on error
 */
int wqvad_resample_audio(const float* inputData,
                        size_t inputSamples,
                        int fromRate,
                        int toRate,
                        float** outData,
                        size_t* outSamples);

/**
 * Free audio data allocated by utility functions
 * @param data Data to free
 */
void wqvad_free_audio_data(float* data);

#ifdef __cplusplus
}
#endif

#endif /* WQVad_h */
EOF

# Create C wrapper implementation
echo -e "${YELLOW}Creating C wrapper implementation...${NC}"
cat > ${BUILD_DIR}/c_wrapper_impl.cpp << 'EOF'
#include "WQVad.h"
#include "wqvad/wqvad.h"
#include <memory>
#include <fstream>
#include <vector>
#include <cstdlib>

using namespace wqvad;

struct WQVadContext {
    std::unique_ptr<SileroVAD> vad;
    VadConfig config;
};

extern "C" {

WQVadContext* wqvad_create_from_file(const char* modelPath, float threshold) {
    try {
        auto context = std::make_unique<WQVadContext>();
        context->vad = std::make_unique<SileroVAD>();
        
        context->config.modelPath = modelPath;
        context->config.threshold = threshold;
        context->config.sampleRate = 16000;
        context->config.minSpeechDurationMs = 250;
        context->config.minSilenceDurationMs = 100;
        context->config.speechPadMs = 30;
        context->config.maxSpeechDurationS = 30.0f;
        
        if (!context->vad->initialize(context->config, modelPath)) {
            return nullptr;
        }
        
        return context.release();
    } catch (...) {
        return nullptr;
    }
}

WQVadContext* wqvad_create(const void* modelData, size_t modelSize, float threshold) {
    // For simplicity, write model data to temporary file
    // In production, you might want to use ONNX Runtime's memory provider
    const char* tempPath = "/tmp/silero_vad_v5.onnx";
    std::ofstream file(tempPath, std::ios::binary);
    if (!file.is_open()) {
        return nullptr;
    }
    file.write(static_cast<const char*>(modelData), modelSize);
    file.close();
    
    return wqvad_create_from_file(tempPath, threshold);
}

int wqvad_process_chunk(WQVadContext* context, 
                       const float* audioData, 
                       size_t numSamples,
                       float* outProbability) {
    if (!context || !audioData || !outProbability) {
        return -1;
    }
    
    try {
        std::vector<float> chunk(audioData, audioData + numSamples);
        VadResult result = context->vad->processChunk(chunk);
        
        *outProbability = result.probability;
        return result.isVoiceDetected ? 1 : 0;
    } catch (...) {
        return -1;
    }
}

int wqvad_process_audio(WQVadContext* context,
                       const float* audioData,
                       size_t numSamples,
                       float** outSegments,
                       size_t* outNumSegments) {
    if (!context || !audioData || !outSegments || !outNumSegments) {
        return -1;
    }
    
    try {
        std::vector<float> audio(audioData, audioData + numSamples);
        auto segments = context->vad->processAudio(audio);
        
        *outNumSegments = segments.size();
        if (segments.empty()) {
            *outSegments = nullptr;
            return 0;
        }
        
        // Allocate array for [start_time, end_time] pairs
        *outSegments = static_cast<float*>(malloc(segments.size() * 2 * sizeof(float)));
        
        for (size_t i = 0; i < segments.size(); ++i) {
            (*outSegments)[i * 2] = segments[i].startTime;
            (*outSegments)[i * 2 + 1] = segments[i].endTime;
        }
        
        return 0;
    } catch (...) {
        return -1;
    }
}

void wqvad_reset(WQVadContext* context) {
    if (context && context->vad) {
        context->vad->reset();
    }
}

const char* wqvad_get_version(void) {
    return "1.0.0-silero-v5";
}

void wqvad_free_segments(float* segments) {
    free(segments);
}

void wqvad_destroy(WQVadContext* context) {
    delete context;
}

int wqvad_pcm_to_float(const int16_t* pcmData, 
                      size_t numSamples, 
                      float** outFloatData) {
    if (!pcmData || !outFloatData) {
        return -1;
    }
    
    *outFloatData = static_cast<float*>(malloc(numSamples * sizeof(float)));
    for (size_t i = 0; i < numSamples; ++i) {
        (*outFloatData)[i] = static_cast<float>(pcmData[i]) / 32768.0f;
    }
    
    return 0;
}

int wqvad_resample_audio(const float* inputData,
                        size_t inputSamples,
                        int fromRate,
                        int toRate,
                        float** outData,
                        size_t* outSamples) {
    if (!inputData || !outData || !outSamples) {
        return -1;
    }
    
    try {
        std::vector<float> input(inputData, inputData + inputSamples);
        auto output = resampleAudio(input, fromRate, toRate);
        
        *outSamples = output.size();
        *outData = static_cast<float*>(malloc(output.size() * sizeof(float)));
        std::copy(output.begin(), output.end(), *outData);
        
        return 0;
    } catch (...) {
        return -1;
    }
}

void wqvad_free_audio_data(float* data) {
    free(data);
}

} // extern "C"
EOF

# iOS Device (arm64)
echo -e "${YELLOW}Building WQVad for iOS Device (arm64)...${NC}"
mkdir -p ${BUILD_DIR}/ios-arm64
cd ${BUILD_DIR}/ios-arm64

# Clean any existing cache in this directory
rm -rf CMakeCache.txt CMakeFiles

cmake ../../ \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path) \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-stdlib=libc++" \
    -DCMAKE_EXE_LINKER_FLAGS="-stdlib=libc++" \
    -DIOS=ON

# Build the project
make -j$(sysctl -n hw.ncpu)

cd ../..

# Check if the library was built
if [ ! -f "${BUILD_DIR}/ios-arm64/lib${LIBRARY_NAME}.a" ]; then
    echo -e "${RED}❌ Static library not found at ${BUILD_DIR}/ios-arm64/lib${LIBRARY_NAME}.a${NC}"
    echo -e "${YELLOW}Checking what files were generated:${NC}"
    find ${BUILD_DIR}/ios-arm64 -name "*.a" -o -name "*${LIBRARY_NAME}*"
    exit 1
fi

# Compile C wrapper and combine with library properly
echo -e "${YELLOW}Compiling C wrapper...${NC}"
cd ${BUILD_DIR}/ios-arm64

# Create a temporary directory for extracting object files
mkdir -p temp_objects
cd temp_objects

# Extract object files from the original library
ar x ../lib${LIBRARY_NAME}.a

# Go back to build directory and compile wrapper
cd ..
clang++ -c ../c_wrapper_impl.cpp \
    -arch arm64 \
    -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
    -mios-version-min=12.0 \
    -stdlib=libc++ \
    -std=c++17 \
    -I../temp_headers \
    -I../../include \
    -I../../third_party/onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Headers \
    -o c_wrapper_impl.o

# Create new library with all object files
echo -e "${YELLOW}Creating combined library...${NC}"
ar rcs lib${LIBRARY_NAME}_with_wrapper.a temp_objects/*.o c_wrapper_impl.o

# Clean up temporary objects
rm -rf temp_objects

cd ../..

# Create XCFramework directory structure for static library
echo -e "${YELLOW}Creating XCFramework from static library...${NC}"
mkdir -p ${FRAMEWORK_NAME}.xcframework/ios-arm64

# Copy the static library directly
cp ${BUILD_DIR}/ios-arm64/lib${LIBRARY_NAME}_with_wrapper.a ${FRAMEWORK_NAME}.xcframework/ios-arm64/lib${FRAMEWORK_NAME}.a

# Copy headers to a separate headers folder
mkdir -p ${FRAMEWORK_NAME}.xcframework/ios-arm64/Headers
cp ${BUILD_DIR}/temp_headers/WQVad.h ${FRAMEWORK_NAME}.xcframework/ios-arm64/Headers/

# Create Info.plist for XCFramework (minimal, just for the xcframework itself)
cat > ${FRAMEWORK_NAME}.xcframework/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>LibraryIdentifier</key>
            <string>ios-arm64</string>
            <key>LibraryPath</key>
            <string>lib${FRAMEWORK_NAME}.a</string>
            <key>HeadersPath</key>
            <string>Headers</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>ios</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
EOF

# Verify the XCFramework
echo -e "${YELLOW}Verifying XCFramework...${NC}"
if [ -d "${FRAMEWORK_NAME}.xcframework" ]; then
    echo -e "${GREEN}✅ Static library XCFramework created successfully!${NC}"
    echo -e "${GREEN}Location: $(pwd)/${FRAMEWORK_NAME}.xcframework${NC}"
    
    # Show contents
    echo -e "${YELLOW}XCFramework contents:${NC}"
    find ${FRAMEWORK_NAME}.xcframework -type f
    
    # Show library info
    echo -e "${YELLOW}Library architecture:${NC}"
    lipo -info ${FRAMEWORK_NAME}.xcframework/ios-arm64/lib${FRAMEWORK_NAME}.a
    
    # Show size
    echo -e "${YELLOW}XCFramework size:${NC}"
    du -sh ${FRAMEWORK_NAME}.xcframework
    
    echo -e "${GREEN}🎉 Build completed successfully!${NC}"
    echo -e "${GREEN}Static library XCFramework created - no Info.plist issues!${NC}"
    echo -e "${GREEN}Usage: Add both WQVad.xcframework and onnxruntime.xcframework to your Xcode project${NC}"
else
    echo -e "${RED}❌ XCFramework creation failed!${NC}"
    exit 1
fi

# Clean intermediate files
echo -e "${YELLOW}Cleaning up intermediate files...${NC}"
rm -rf ${BUILD_DIR}
rm -rf ${XCFRAMEWORK_DIR}
