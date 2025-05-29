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

# Create WQVad.h header first (needed for C wrapper compilation)
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

# Compile C wrapper and add to library
echo -e "${YELLOW}Compiling C wrapper...${NC}"
cd ${BUILD_DIR}/ios-arm64
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

# Add wrapper to the library
ar rcs lib${LIBRARY_NAME}_with_wrapper.a lib${LIBRARY_NAME}.a c_wrapper_impl.o

cd ../..

# Create Framework structure for iOS Device
echo -e "${YELLOW}Creating framework structure for iOS Device...${NC}"
IOS_FRAMEWORK_DIR="${XCFRAMEWORK_DIR}/ios-arm64/${FRAMEWORK_NAME}.framework"
mkdir -p ${IOS_FRAMEWORK_DIR}/Headers
mkdir -p ${IOS_FRAMEWORK_DIR}/Modules
mkdir -p ${IOS_FRAMEWORK_DIR}/Resources

# Copy the combined library
cp ${BUILD_DIR}/ios-arm64/lib${LIBRARY_NAME}_with_wrapper.a ${IOS_FRAMEWORK_DIR}/${FRAMEWORK_NAME}

# Extract ONNX Runtime library from XCFramework and combine
echo -e "${YELLOW}Combining WQVad with ONNX Runtime library...${NC}"
ONNXRUNTIME_LIB="${ONNXRUNTIME_PATH}/ios-arm64/onnxruntime.framework/onnxruntime"
if [ -f "${ONNXRUNTIME_LIB}" ]; then
    # Create a combined library that includes both wqvad and onnxruntime
    libtool -static -o ${IOS_FRAMEWORK_DIR}/${FRAMEWORK_NAME}_combined \
        ${BUILD_DIR}/ios-arm64/lib${LIBRARY_NAME}_with_wrapper.a \
        ${ONNXRUNTIME_LIB}
    
    # Replace the original with the combined library
    mv ${IOS_FRAMEWORK_DIR}/${FRAMEWORK_NAME}_combined ${IOS_FRAMEWORK_DIR}/${FRAMEWORK_NAME}
    
    echo -e "${GREEN}✅ Successfully combined libraries${NC}"
else
    echo -e "${RED}❌ ONNX Runtime library not found, using WQVad only${NC}"
fi

# Copy main header file to framework
cp ${BUILD_DIR}/temp_headers/WQVad.h ${IOS_FRAMEWORK_DIR}/Headers/

# Copy public headers
echo -e "${YELLOW}Copying public headers...${NC}"
cp -r include/wqvad/* ${IOS_FRAMEWORK_DIR}/Headers/

# Copy ONNX Runtime headers (required for compilation)
ONNXRUNTIME_HEADERS="${ONNXRUNTIME_PATH}/ios-arm64/onnxruntime.framework/Headers"
if [ -d "${ONNXRUNTIME_HEADERS}" ]; then
    cp -r ${ONNXRUNTIME_HEADERS}/* ${IOS_FRAMEWORK_DIR}/Headers/
    echo -e "${GREEN}✅ Copied ONNX Runtime headers${NC}"
fi

# Copy Silero model to Resources
echo -e "${YELLOW}Copying Silero VAD V5 model to framework resources...${NC}"
cp ${SILERO_MODEL_PATH} ${IOS_FRAMEWORK_DIR}/Resources/

# Create Info.plist for iOS Device
cat > ${IOS_FRAMEWORK_DIR}/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.wq.${FRAMEWORK_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>12.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>
</dict>
</plist>
EOF

# Create module.modulemap
cat > ${IOS_FRAMEWORK_DIR}/Modules/module.modulemap << EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    export *
    module * { export * }
    
    explicit module WQVadCPP {
        header "wqvad.h"
        header "types.h"
        requires cplusplus
    }
}
EOF

# Verify framework structure before creating XCFramework
echo -e "${YELLOW}Verifying framework structure...${NC}"
echo "Framework directory contents:"
find ${IOS_FRAMEWORK_DIR} -type f | head -20

# Create XCFramework
echo -e "${YELLOW}Creating XCFramework...${NC}"
xcodebuild -create-xcframework \
    -framework ${IOS_FRAMEWORK_DIR} \
    -output ${FRAMEWORK_NAME}.xcframework

# Verify the XCFramework
echo -e "${YELLOW}Verifying XCFramework...${NC}"
if [ -d "${FRAMEWORK_NAME}.xcframework" ]; then
    echo -e "${GREEN}✅ XCFramework created successfully!${NC}"
    echo -e "${GREEN}Location: $(pwd)/${FRAMEWORK_NAME}.xcframework${NC}"
    
    # Show framework info
    echo -e "${YELLOW}Framework contents:${NC}"
    find ${FRAMEWORK_NAME}.xcframework -type f | head -20
    
    # Show architectures
    echo -e "${YELLOW}Supported architectures:${NC}"
    lipo -info ${FRAMEWORK_NAME}.xcframework/ios-arm64/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME} 2>/dev/null || echo "iOS Device: arm64"
    
    # Show bundle size
    echo -e "${YELLOW}Framework size:${NC}"
    du -sh ${FRAMEWORK_NAME}.xcframework
    
else
    echo -e "${RED}❌ XCFramework creation failed!${NC}"
    exit 1
fi

# Clean intermediate files
echo -e "${YELLOW}Cleaning up intermediate files...${NC}"
rm -rf ${BUILD_DIR}
rm -rf ${XCFRAMEWORK_DIR}

echo -e "${GREEN}🎉 Build completed successfully!${NC}"
echo -e "${GREEN}You can now drag ${FRAMEWORK_NAME}.xcframework into your iOS project.${NC}"
echo -e "${GREEN}The framework includes:${NC}"
echo -e "${GREEN}- Silero VAD V5 model bundled in Resources${NC}"
echo -e "${GREEN}- ONNX Runtime statically linked${NC}"
echo -e "${GREEN}- C API for Objective-C integration${NC}"
echo -e "${GREEN}- C++ API for advanced usage${NC}"

# Show usage example
echo -e "${YELLOW}Usage in your iOS project:${NC}"
echo -e "${GREEN}1. Drag WQVad.xcframework to your project${NC}"
echo -e "${GREEN}2. Import: #import <WQVad/WQVad.h>${NC}"
echo -e "${GREEN}3. Use: ${NC}"
cat << 'EOF'
// Get model path from bundle
NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"silero_vad_v5" ofType:@"onnx"];
WQVadContext *vad = wqvad_create_from_file([modelPath UTF8String], 0.5);

// Process audio (512 samples of 16kHz float audio)
float probability;
int isVoice = wqvad_process_chunk(vad, audioSamples, 512, &probability);

// Clean up
wqvad_destroy(vad);
EOF
