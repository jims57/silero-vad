#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始为WQVad构建iOS XCFramework...${NC}"

# Configuration
PROJECT_NAME="WQVad"
LIBRARY_NAME="wqvad"
FRAMEWORK_NAME="WQVad"
BUILD_DIR="build"
XCFRAMEWORK_DIR="xcframework"

# Clean previous builds
echo -e "${YELLOW}清理之前的构建...${NC}"
rm -rf ${BUILD_DIR}
rm -rf ${XCFRAMEWORK_DIR}
rm -rf ${FRAMEWORK_NAME}.xcframework
rm -rf CMakeCache.txt CMakeFiles

# Verify ONNX Runtime XCFramework exists
ONNXRUNTIME_PATH="third_party/onnxruntime.xcframework"
if [ ! -d "${ONNXRUNTIME_PATH}" ]; then
    echo -e "${RED}❌ 在${ONNXRUNTIME_PATH}找不到ONNX Runtime XCFramework${NC}"
    echo -e "${YELLOW}请下载ONNX Runtime XCFramework并将其放置在third_party/目录下${NC}"
    exit 1
fi

# Verify Silero model exists
SILERO_MODEL_PATH="src/wq_vad.onnx"
if [ ! -f "${SILERO_MODEL_PATH}" ]; then
    echo -e "${RED}❌ WQ VAD模型文件未找到: ${SILERO_MODEL_PATH}${NC}"
    echo -e "${YELLOW}请下载wq_vad.onnx并将其放置在src/目录下${NC}"
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
//
//  WQVad.h
//  WQVad语音活动检测C API接口
//
//  Created by Jimmy Gan on 2025-5-25.
//

#ifndef WQVad_h
#define WQVad_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// WQVad C API for Objective-C integration
// WQVad C API，用于Objective-C集成

typedef struct WQVadContext WQVadContext;
typedef struct WQVadStreamContext WQVadStreamContext;

/**
 * 创建新的WQVad上下文，使用WQ VAD模型
 * @param modelData 指向WQ VAD模型数据的内存指针
 * @param modelSize 模型数据的字节大小
 * @param threshold VAD阈值 (0.0 - 1.0, 默认0.5)
 * @return WQVad上下文指针，失败时返回NULL
 */
WQVadContext* wqvad_create(const void* modelData, size_t modelSize, float threshold);

/**
 * 从模型文件路径创建WQVad上下文
 * @param modelPath wq_vad.onnx文件路径
 * @param threshold VAD阈值 (0.0 - 1.0, 默认0.5)
 * @return WQVad上下文指针，失败时返回NULL
 */
WQVadContext* wqvad_create_from_file(const char* modelPath, float threshold);

/**
 * 处理音频块 (16kHz时需要512个采样点)
 * @param context WQVad上下文
 * @param audioData 浮点音频采样 (16kHz, 单声道)
 * @param numSamples 采样点数量 (应为512)
 * @param outProbability 输出语音概率
 * @return 检测到语音返回1，否则返回0，错误时返回-1
 */
int wqvad_process_chunk(WQVadContext* context, 
                       const float* audioData, 
                       size_t numSamples,
                       float* outProbability);

/**
 * 处理整个音频缓冲区并获取语音片段
 * @param context WQVad上下文
 * @param audioData 浮点音频采样 (16kHz, 单声道)
 * @param numSamples 总采样点数量
 * @param outSegments 输出语音片段数组 (调用者必须释放)
 * @param outNumSegments 返回的片段数量
 * @return 成功返回0，错误返回-1
 */
int wqvad_process_audio(WQVadContext* context,
                       const float* audioData,
                       size_t numSamples,
                       float** outSegments,  // Array of [start_time, end_time] pairs
                       size_t* outNumSegments);

/**
 * 重置VAD状态 (在不同音频流之间调用)
 * @param context WQVad上下文
 */
void wqvad_reset(WQVadContext* context);

/**
 * 获取WQVad版本字符串
 * @return 版本字符串
 */
const char* wqvad_get_version(void);

/**
 * 释放由wqvad_process_audio返回的语音片段
 * @param segments 要释放的片段数组
 */
void wqvad_free_segments(float* segments);

/**
 * 销毁WQVad上下文并释放资源
 * @param context 要销毁的WQVad上下文
 */
void wqvad_destroy(WQVadContext* context);

// 音频处理实用函数

/**
 * 将16位PCM转换为浮点采样
 * @param pcmData 输入PCM数据
 * @param numSamples 采样数量
 * @param outFloatData 输出浮点数组 (调用者必须释放)
 * @return 成功返回0，错误返回-1
 */
int wqvad_pcm_to_float(const int16_t* pcmData, 
                      size_t numSamples, 
                      float** outFloatData);

/**
 * 将音频从一个采样率重采样到另一个采样率
 * @param inputData 输入音频采样
 * @param inputSamples 输入采样数量
 * @param fromRate 源采样率
 * @param toRate 目标采样率
 * @param outData 输出重采样数据 (调用者必须释放)
 * @param outSamples 输出采样数量
 * @return 成功返回0，错误返回-1
 */
int wqvad_resample_audio(const float* inputData,
                        size_t inputSamples,
                        int fromRate,
                        int toRate,
                        float** outData,
                        size_t* outSamples);

/**
 * 释放由实用函数分配的音频数据
 * @param data 要释放的数据
 */
void wqvad_free_audio_data(float* data);

/**
 * 处理音频数据并将检测到的语音片段保存为WAV文件
 * @param context WQVad上下文
 * @param audioData 浮点音频采样 (16kHz, 单声道)
 * @param numSamples 总采样点数量
 * @param sampleRate 音频采样率
 * @param outputDir 保存片段WAV文件的目录路径
 * @return 保存的片段数量，错误返回-1
 */
int wqvad_process_audio_file(WQVadContext* context,
                            const float* audioData,
                            size_t numSamples,
                            int sampleRate,
                            const char* outputDir);

/**
 * 获取每个语音片段的采样索引 (用于PCM分割)
 * @param context WQVad上下文
 * @param audioData 浮点音频采样
 * @param numSamples 总采样点数量
 * @param sampleRate 音频采样率
 * @param outStartSamples 输出片段开始采样数组 (调用者必须释放)
 * @param outEndSamples 输出片段结束采样数组 (调用者必须释放)
 * @param outNumSegments 返回的片段数量
 * @return 成功返回0，错误返回-1
 */
int wqvad_segment_audio(WQVadContext* context,
                       const float* audioData,
                       size_t numSamples,
                       int sampleRate,
                       size_t** outStartSamples,
                       size_t** outEndSamples,
                       size_t* outNumSegments);

/**
 * 释放由wqvad_segment_audio返回的采样片段数组
 * @param startSamples 要释放的开始采样数组
 * @param endSamples 要释放的结束采样数组
 */
void wqvad_free_sample_segments(size_t* startSamples, size_t* endSamples);

/**
 * 为连续音频处理创建流上下文
 * @param vadContext 主VAD上下文
 * @param outputDir 保存检测片段的目录
 * @param sampleRate 音频流采样率
 * @return 流上下文指针，失败返回NULL
 */
WQVadStreamContext* wqvad_create_stream_context(WQVadContext* vadContext,
                                               const char* outputDir,
                                               int sampleRate);

/**
 * 为连续音频处理创建自定义输出采样率的流上下文
 * @param vadContext 主VAD上下文
 * @param outputDir 保存检测片段的目录
 * @param sampleRate 音频流采样率
 * @param outputSampleRate 保存WAV文件的采样率 (16000, 24000, 44100, 48000)
 * @return 流上下文指针，失败返回NULL
 */
WQVadStreamContext* wqvad_create_stream_context_ex(WQVadContext* vadContext,
                                                  const char* outputDir,
                                                  int sampleRate,
                                                  int outputSampleRate);

/**
 * 处理流音频块
 * @param streamContext 流上下文
 * @param audioData 浮点音频采样
 * @param numSamples 此块中的采样数量
 * @return 此块中检测到的新片段数量，错误返回-1
 */
int wqvad_process_stream_chunk(WQVadStreamContext* streamContext,
                              const float* audioData,
                              size_t numSamples);

/**
 * 处理带自动重采样的流音频块
 * @param streamContext 流上下文
 * @param audioData 浮点音频采样 (任意采样率)
 * @param numSamples 此块中的采样数量
 * @param inputSampleRate 输入音频的采样率
 * @return 此块中检测到的新片段数量，错误返回-1
 */
int wqvad_process_stream_chunk_resampled(WQVadStreamContext* streamContext,
                                        const float* audioData,
                                        size_t numSamples,
                                        int inputSampleRate);

/**
 * 完成流处理并保存任何剩余片段
 * @param streamContext 流上下文
 * @return 检测到的总片段数量，错误返回-1
 */
int wqvad_finalize_stream(WQVadStreamContext* streamContext);

/**
 * 销毁流上下文
 * @param streamContext 要销毁的流上下文
 */
void wqvad_destroy_stream_context(WQVadStreamContext* streamContext);

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
#include <iostream>
#include <algorithm>

using namespace wqvad;

struct WQVadContext {
    std::unique_ptr<SileroVAD> vad;
    VadConfig config;
};

struct WQVadStreamContext {
    WQVadContext* vadContext;
    std::string outputDir;
    int sampleRate;
    int outputSampleRate;
    size_t totalSamplesProcessed;
    int segmentCounter;
    std::vector<float> accumulatedAudio;  // Store all audio for segment extraction
    bool inSpeech;
    size_t speechStartSample;
    size_t speechEndSample;
    int consecutiveSilenceWindows;  // Track consecutive silence windows
    int consecutiveSpeechWindows;  // Track consecutive speech windows
};

// Helper function to segment audio data based on VAD results
static std::vector<std::pair<size_t, size_t>> segmentAudioByVad(
    const float* audioData, 
    size_t numSamples, 
    const std::vector<VadSegment>& vadSegments,
    int sampleRate) {
    
    std::vector<std::pair<size_t, size_t>> sampleSegments;
    float totalDuration = static_cast<float>(numSamples) / sampleRate;
    
    for (const auto& segment : vadSegments) {
        // Skip segments that start at 0 and span nearly the entire audio
        if (segment.startTime == 0.0f && segment.endTime >= totalDuration * 0.95f) {
            std::cout << "⚠️ Skipping segment that spans entire audio" << std::endl;
            continue;
        }
        
        size_t startSample = static_cast<size_t>(segment.startTime * sampleRate);
        size_t endSample = static_cast<size_t>(segment.endTime * sampleRate);
        
        // Ensure we don't exceed bounds
        startSample = std::min(startSample, numSamples);
        endSample = std::min(endSample, numSamples);
        
        if (startSample < endSample) {
            sampleSegments.push_back({startSample, endSample});
        }
    }
    
    return sampleSegments;
}

// Helper function to save audio segments as WAV files
static bool saveSegmentsAsWav(const float* audioData, 
                      size_t numSamples,
                      const std::vector<VadSegment>& vadSegments,
                      int sampleRate,
                      const std::string& outputDir) {
    
    auto sampleSegments = segmentAudioByVad(audioData, numSamples, vadSegments, sampleRate);
    
    for (size_t i = 0; i < sampleSegments.size(); ++i) {
        auto [startSample, endSample] = sampleSegments[i];
        size_t segmentLength = endSample - startSample;
        
        std::string filename = outputDir + "/segment_" + std::to_string(i + 1) + ".wav";
        
        // Write WAV header and data
        std::ofstream file(filename, std::ios::binary);
        if (!file.is_open()) {
            std::cerr << "❌ Failed to create file: " << filename << std::endl;
            return false;
        }
        
        // WAV header
        struct WavHeader {
            char riff[4] = {'R', 'I', 'F', 'F'};
            uint32_t fileSize;
            char wave[4] = {'W', 'A', 'V', 'E'};
            char fmt[4] = {'f', 'm', 't', ' '};
            uint32_t fmtSize = 16;
            uint16_t audioFormat = 1; // PCM
            uint16_t numChannels = 1; // Mono
            uint32_t sampleRate;
            uint32_t byteRate;
            uint16_t blockAlign = 2;
            uint16_t bitsPerSample = 16;
            char data[4] = {'d', 'a', 't', 'a'};
            uint32_t dataSize;
        } header;
        
        header.sampleRate = sampleRate;
        header.byteRate = sampleRate * 1 * 16 / 8;
        header.dataSize = segmentLength * 2;
        header.fileSize = header.dataSize + sizeof(WavHeader) - 8;
        
        // Convert float to 16-bit PCM
        std::vector<int16_t> pcmData(segmentLength);
        for (size_t j = 0; j < segmentLength; ++j) {
            float sample = audioData[startSample + j];
            sample = std::max(-1.0f, std::min(1.0f, sample)); // Clamp
            pcmData[j] = static_cast<int16_t>(sample * 32767.0f);
        }
        
        // Write header and data
        file.write(reinterpret_cast<const char*>(&header), sizeof(header));
        file.write(reinterpret_cast<const char*>(pcmData.data()), pcmData.size() * sizeof(int16_t));
        
        file.close();
        std::cout << "💾 Saved segment " << (i + 1) << " to: " << filename << std::endl;
    }
    
    return true;
}

extern "C" {

WQVadContext* wqvad_create_from_file(const char* modelPath, float threshold) {
    try {
        auto context = std::make_unique<WQVadContext>();
        context->vad = std::make_unique<SileroVAD>();
        
        context->config.modelPath = modelPath;
        context->config.threshold = threshold;
        context->config.sampleRate = 16000;
        context->config.minSpeechDurationMs = 250;
        context->config.minSilenceDurationMs = 100;  // Keep original value
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

int wqvad_process_audio_file(WQVadContext* context,
                            const float* audioData,
                            size_t numSamples,
                            int sampleRate,
                            const char* outputDir) {
    if (!context || !audioData || !outputDir) {
        return -1;
    }
    
    try {
        std::vector<float> audio(audioData, audioData + numSamples);
        auto segments = context->vad->processAudio(audio);
        
        // Save segments as WAV files
        if (!saveSegmentsAsWav(audioData, numSamples, segments, sampleRate, outputDir)) {
            return -1;
        }
        
        return static_cast<int>(segments.size());
    } catch (...) {
        return -1;
    }
}

int wqvad_segment_audio(WQVadContext* context,
                       const float* audioData,
                       size_t numSamples,
                       int sampleRate,
                       size_t** outStartSamples,
                       size_t** outEndSamples,
                       size_t* outNumSegments) {
    if (!context || !audioData || !outStartSamples || !outEndSamples || !outNumSegments) {
        return -1;
    }
    
    try {
        std::vector<float> audio(audioData, audioData + numSamples);
        auto vadSegments = context->vad->processAudio(audio);
        auto sampleSegments = segmentAudioByVad(audioData, numSamples, vadSegments, sampleRate);
        
        *outNumSegments = sampleSegments.size();
        if (sampleSegments.empty()) {
            *outStartSamples = nullptr;
            *outEndSamples = nullptr;
            return 0;
        }
        
        // Allocate arrays for start and end samples
        *outStartSamples = static_cast<size_t*>(malloc(sampleSegments.size() * sizeof(size_t)));
        *outEndSamples = static_cast<size_t*>(malloc(sampleSegments.size() * sizeof(size_t)));
        
        for (size_t i = 0; i < sampleSegments.size(); ++i) {
            (*outStartSamples)[i] = sampleSegments[i].first;
            (*outEndSamples)[i] = sampleSegments[i].second;
        }
        
        return 0;
    } catch (...) {
        return -1;
    }
}

void wqvad_free_sample_segments(size_t* startSamples, size_t* endSamples) {
    free(startSamples);
    free(endSamples);
}

WQVadStreamContext* wqvad_create_stream_context(WQVadContext* vadContext,
                                               const char* outputDir,
                                               int sampleRate) {
    return wqvad_create_stream_context_ex(vadContext, outputDir, sampleRate, 16000);
}

WQVadStreamContext* wqvad_create_stream_context_ex(WQVadContext* vadContext,
                                                  const char* outputDir,
                                                  int sampleRate,
                                                  int outputSampleRate) {
    if (!vadContext || !outputDir) {
        return nullptr;
    }
    
    try {
        auto streamContext = std::make_unique<WQVadStreamContext>();
        streamContext->vadContext = vadContext;
        streamContext->outputDir = outputDir;
        streamContext->sampleRate = 16000;  // Always use 16kHz internally for VAD
        streamContext->outputSampleRate = outputSampleRate;  // Use specified rate for output
        streamContext->totalSamplesProcessed = 0;
        streamContext->segmentCounter = 0;
        streamContext->inSpeech = false;
        streamContext->speechStartSample = 0;
        streamContext->speechEndSample = 0;
        streamContext->consecutiveSilenceWindows = 0;
        streamContext->consecutiveSpeechWindows = 0;
        
        // Reset VAD state for new stream
        vadContext->vad->reset();
        
        return streamContext.release();
    } catch (...) {
        return nullptr;
    }
}

int wqvad_process_stream_chunk(WQVadStreamContext* streamContext,
                              const float* audioData,
                              size_t numSamples) {
    if (!streamContext || !audioData) {
        return -1;
    }
    
    try {
        // Store audio for later segment extraction
        streamContext->accumulatedAudio.insert(
            streamContext->accumulatedAudio.end(),
            audioData,
            audioData + numSamples
        );
        
        int newSegments = 0;
        
        // Process in 512-sample windows (required by Silero VAD for 16kHz)
        const size_t windowSize = 512;
        // Calculate how many consecutive windows we need for minimum durations
        const int minSilenceWindows = (streamContext->sampleRate * streamContext->vadContext->config.minSilenceDurationMs / 1000) / windowSize + 1;
        const int minSpeechWindows = 2; // Require at least 2 consecutive speech windows to start a segment
        
        for (size_t offset = 0; offset < numSamples; offset += windowSize) {
            if (offset + windowSize > numSamples) {
                // Not enough samples for a full window, save for next chunk
                break;
            }
            
            std::vector<float> window(audioData + offset, audioData + offset + windowSize);
            VadResult result = streamContext->vadContext->vad->processChunk(window);
            
            size_t currentSample = streamContext->totalSamplesProcessed + offset;
            
            if (result.isVoiceDetected) {
                streamContext->consecutiveSpeechWindows++;
                streamContext->consecutiveSilenceWindows = 0;
                
                if (!streamContext->inSpeech && streamContext->consecutiveSpeechWindows >= minSpeechWindows) {
                    // Start of speech - require multiple consecutive speech windows
                    streamContext->inSpeech = true;
                    // Go back to the start of the first speech window
                    streamContext->speechStartSample = currentSample - (streamContext->consecutiveSpeechWindows - 1) * windowSize;
                    std::cout << "🎤 Speech started at sample " << streamContext->speechStartSample 
                             << " (prob: " << result.probability << ")" << std::endl;
                }
                
                if (streamContext->inSpeech) {
                    // Update speech end to current position
                    streamContext->speechEndSample = currentSample + windowSize;
                }
            } else {
                streamContext->consecutiveSilenceWindows++;
                streamContext->consecutiveSpeechWindows = 0;
                
                if (streamContext->inSpeech && streamContext->consecutiveSilenceWindows >= minSilenceWindows) {
                    // End of speech - we've had enough consecutive silence windows
                    streamContext->inSpeech = false;
                    
                    // Check minimum speech duration
                    size_t speechDuration = streamContext->speechEndSample - streamContext->speechStartSample;
                    size_t minSpeechSamples = streamContext->sampleRate * 
                        streamContext->vadContext->config.minSpeechDurationMs / 1000;
                    
                    if (speechDuration >= minSpeechSamples) {
                        // Save segment
                        size_t segmentStart = streamContext->speechStartSample;
                        size_t segmentEnd = streamContext->speechEndSample;
                        
                        // Apply speech padding
                        int padSamples = streamContext->sampleRate * streamContext->vadContext->config.speechPadMs / 1000;
                        if (segmentStart >= padSamples) {
                            segmentStart -= padSamples;
                        } else {
                            segmentStart = 0;
                        }
                        
                        if (segmentEnd + padSamples <= streamContext->accumulatedAudio.size()) {
                            segmentEnd += padSamples;
                        } else {
                            segmentEnd = streamContext->accumulatedAudio.size();
                        }
                        
                        if (segmentEnd > segmentStart && segmentEnd <= streamContext->accumulatedAudio.size()) {
                            streamContext->segmentCounter++;
                            std::string filename = streamContext->outputDir + "/segment_" + 
                                                 std::to_string(streamContext->segmentCounter) + ".wav";
                            
                            // Extract segment audio
                            size_t segmentLength = segmentEnd - segmentStart;
                            std::vector<float> segmentAudio(segmentLength);
                            std::copy(streamContext->accumulatedAudio.begin() + segmentStart,
                                     streamContext->accumulatedAudio.begin() + segmentEnd,
                                     segmentAudio.begin());
                            
                            // Resample to output sample rate if needed
                            std::vector<float> outputAudio;
                            if (streamContext->outputSampleRate != streamContext->sampleRate) {
                                float resampleRatio = (float)streamContext->outputSampleRate / streamContext->sampleRate;
                                size_t outputLength = static_cast<size_t>(segmentLength * resampleRatio);
                                outputAudio.resize(outputLength);
                                
                                for (size_t i = 0; i < outputLength; i++) {
                                    float srcIndex = i / resampleRatio;
                                    size_t index1 = static_cast<size_t>(srcIndex);
                                    size_t index2 = std::min(index1 + 1, segmentLength - 1);
                                    float fraction = srcIndex - index1;
                                    
                                    outputAudio[i] = segmentAudio[index1] * (1.0f - fraction) + 
                                                    segmentAudio[index2] * fraction;
                                }
                            } else {
                                outputAudio = segmentAudio;
                            }
                            
                            // Normalize audio volume
                            float maxAbsValue = 0.0f;
                            for (const auto& sample : outputAudio) {
                                maxAbsValue = std::max(maxAbsValue, std::abs(sample));
                            }
                            
                            if (maxAbsValue > 0.0f) {
                                // Normalize to 90% of maximum to avoid clipping
                                float normalizeGain = 0.9f / maxAbsValue;
                                for (auto& sample : outputAudio) {
                                    sample *= normalizeGain;
                                }
                            }
                            
                            // Write WAV file
                            std::ofstream file(filename, std::ios::binary);
                            if (file.is_open()) {
                                // WAV header
                                struct WavHeader {
                                    char riff[4] = {'R', 'I', 'F', 'F'};
                                    uint32_t fileSize;
                                    char wave[4] = {'W', 'A', 'V', 'E'};
                                    char fmt[4] = {'f', 'm', 't', ' '};
                                    uint32_t fmtSize = 16;
                                    uint16_t audioFormat = 1;
                                    uint16_t numChannels = 1;
                                    uint32_t sampleRate;
                                    uint32_t byteRate;
                                    uint16_t blockAlign = 2;
                                    uint16_t bitsPerSample = 16;
                                    char data[4] = {'d', 'a', 't', 'a'};
                                    uint32_t dataSize;
                                } header;
                                
                                header.sampleRate = streamContext->outputSampleRate;
                                header.byteRate = streamContext->outputSampleRate * 2;
                                header.dataSize = outputAudio.size() * 2;
                                header.fileSize = header.dataSize + sizeof(WavHeader) - 8;
                                
                                // Convert float to PCM
                                std::vector<int16_t> pcmData(outputAudio.size());
                                for (size_t i = 0; i < outputAudio.size(); ++i) {
                                    float sample = outputAudio[i];
                                    sample = std::max(-1.0f, std::min(1.0f, sample));
                                    pcmData[i] = static_cast<int16_t>(sample * 32767.0f);
                                }
                                
                                file.write(reinterpret_cast<const char*>(&header), sizeof(header));
                                file.write(reinterpret_cast<const char*>(pcmData.data()), 
                                         pcmData.size() * sizeof(int16_t));
                                
                                file.close();
                                std::cout << "💾 Saved segment " << streamContext->segmentCounter 
                                         << " to: " << filename 
                                         << " (duration: " << (float)outputAudio.size()/streamContext->outputSampleRate << "s)"
                                         << " @ " << streamContext->outputSampleRate << "Hz"
                                         << std::endl;
                                newSegments++;
                            }
                        }
                    } else {
                        std::cout << "⚠️ Skipping short segment (duration: " 
                                 << (float)speechDuration/streamContext->sampleRate << "s)" << std::endl;
                    }
                    
                    // Reset consecutive counters
                    streamContext->consecutiveSilenceWindows = 0;
                    streamContext->consecutiveSpeechWindows = 0;
                }
            }
        }
        
        streamContext->totalSamplesProcessed += numSamples;
        return newSegments;
    } catch (...) {
        return -1;
    }
}

int wqvad_finalize_stream(WQVadStreamContext* streamContext) {
    if (!streamContext) {
        return -1;
    }
    
    try {
        // If we're still in speech, save the final segment
        if (streamContext->inSpeech && streamContext->speechStartSample < streamContext->accumulatedAudio.size()) {
            // Use the last speech end sample or the end of audio
            size_t segmentEnd = streamContext->speechEndSample > 0 ? 
                               streamContext->speechEndSample : 
                               streamContext->accumulatedAudio.size();
            size_t segmentStart = streamContext->speechStartSample;
            
            // Check minimum speech duration
            size_t speechDuration = segmentEnd - segmentStart;
            size_t minSpeechSamples = streamContext->sampleRate * 
                streamContext->vadContext->config.minSpeechDurationMs / 1000;
            
            if (speechDuration >= minSpeechSamples) {
                // Apply speech padding
                int padSamples = streamContext->sampleRate * streamContext->vadContext->config.speechPadMs / 1000;
                if (segmentStart >= padSamples) {
                    segmentStart -= padSamples;
                } else {
                    segmentStart = 0;
                }
                
                if (segmentEnd + padSamples <= streamContext->accumulatedAudio.size()) {
                    segmentEnd += padSamples;
                } else {
                    segmentEnd = streamContext->accumulatedAudio.size();
                }
                
                streamContext->segmentCounter++;
                std::string filename = streamContext->outputDir + "/segment_" + 
                                     std::to_string(streamContext->segmentCounter) + ".wav";
                
                // Extract segment audio
                size_t segmentLength = segmentEnd - segmentStart;
                std::vector<float> segmentAudio(segmentLength);
                std::copy(streamContext->accumulatedAudio.begin() + segmentStart,
                         streamContext->accumulatedAudio.begin() + segmentEnd,
                         segmentAudio.begin());
                
                // Resample to output sample rate if needed
                std::vector<float> outputAudio;
                if (streamContext->outputSampleRate != streamContext->sampleRate) {
                    float resampleRatio = (float)streamContext->outputSampleRate / streamContext->sampleRate;
                    size_t outputLength = static_cast<size_t>(segmentLength * resampleRatio);
                    outputAudio.resize(outputLength);
                    
                    for (size_t i = 0; i < outputLength; i++) {
                        float srcIndex = i / resampleRatio;
                        size_t index1 = static_cast<size_t>(srcIndex);
                        size_t index2 = std::min(index1 + 1, segmentLength - 1);
                        float fraction = srcIndex - index1;
                        
                        outputAudio[i] = segmentAudio[index1] * (1.0f - fraction) + 
                                        segmentAudio[index2] * fraction;
                    }
                } else {
                    outputAudio = segmentAudio;
                }
                
                // Normalize audio volume
                float maxAbsValue = 0.0f;
                for (const auto& sample : outputAudio) {
                    maxAbsValue = std::max(maxAbsValue, std::abs(sample));
                }
                
                if (maxAbsValue > 0.0f) {
                    // Normalize to 90% of maximum to avoid clipping
                    float normalizeGain = 0.9f / maxAbsValue;
                    for (auto& sample : outputAudio) {
                        sample *= normalizeGain;
                    }
                }
                
                // Write final segment
                std::ofstream file(filename, std::ios::binary);
                if (file.is_open()) {
                    struct WavHeader {
                        char riff[4] = {'R', 'I', 'F', 'F'};
                        uint32_t fileSize;
                        char wave[4] = {'W', 'A', 'V', 'E'};
                        char fmt[4] = {'f', 'm', 't', ' '};
                        uint32_t fmtSize = 16;
                        uint16_t audioFormat = 1;
                        uint16_t numChannels = 1;
                        uint32_t sampleRate;
                        uint32_t byteRate;
                        uint16_t blockAlign = 2;
                        uint16_t bitsPerSample = 16;
                        char data[4] = {'d', 'a', 't', 'a'};
                        uint32_t dataSize;
                    } header;
                    
                    header.sampleRate = streamContext->outputSampleRate;
                    header.byteRate = streamContext->outputSampleRate * 2;
                    header.dataSize = outputAudio.size() * 2;
                    header.fileSize = header.dataSize + sizeof(WavHeader) - 8;
                    
                    std::vector<int16_t> pcmData(outputAudio.size());
                    for (size_t i = 0; i < outputAudio.size(); ++i) {
                        float sample = outputAudio[i];
                        sample = std::max(-1.0f, std::min(1.0f, sample));
                        pcmData[i] = static_cast<int16_t>(sample * 32767.0f);
                    }
                    
                    file.write(reinterpret_cast<const char*>(&header), sizeof(header));
                    file.write(reinterpret_cast<const char*>(pcmData.data()), 
                             pcmData.size() * sizeof(int16_t));
                    
                    file.close();
                    std::cout << "💾 Saved final segment " << streamContext->segmentCounter 
                             << " to: " << filename 
                             << " (duration: " << (float)outputAudio.size()/streamContext->outputSampleRate << "s)"
                             << " @ " << streamContext->outputSampleRate << "Hz"
                             << std::endl;
                }
            }
        }
        
        return streamContext->segmentCounter;
    } catch (...) {
        return -1;
    }
}

void wqvad_destroy_stream_context(WQVadStreamContext* streamContext) {
    delete streamContext;
}

int wqvad_process_stream_chunk_resampled(WQVadStreamContext* streamContext,
                                        const float* audioData,
                                        size_t numSamples,
                                        int inputSampleRate) {
    if (!streamContext || !audioData) {
        return -1;
    }
    
    try {
        // If input is already 16kHz, process directly
        if (inputSampleRate == 16000) {
            return wqvad_process_stream_chunk(streamContext, audioData, numSamples);
        }
        
        // Resample to 16kHz
        float resampleRatio = 16000.0f / inputSampleRate;
        size_t targetFrameCount = static_cast<size_t>(numSamples * resampleRatio);
        std::vector<float> resampledData(targetFrameCount);
        
        // Simple linear interpolation resampling
        for (size_t i = 0; i < targetFrameCount; i++) {
            float srcIndex = i / resampleRatio;
            size_t index1 = static_cast<size_t>(srcIndex);
            size_t index2 = std::min(index1 + 1, numSamples - 1);
            float fraction = srcIndex - index1;
            
            resampledData[i] = audioData[index1] * (1.0f - fraction) + audioData[index2] * fraction;
        }
        
        // Process the resampled data
        return wqvad_process_stream_chunk(streamContext, resampledData.data(), targetFrameCount);
    } catch (const std::exception& e) {
        std::cerr << "❌ Error in stream chunk resampling: " << e.what() << std::endl;
        return -1;
    }
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
