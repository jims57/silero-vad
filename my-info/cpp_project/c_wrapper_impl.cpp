#include "WQVad.h"
#include "wqvad/wqvad.h"
#include <memory>
#include <fstream>
#include <vector>

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
