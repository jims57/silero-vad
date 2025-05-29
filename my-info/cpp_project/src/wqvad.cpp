#include "wqvad/wqvad.h"
#include "internal/wqvad_impl.h"
#include <memory>
#include <iostream>
#include <fstream>

namespace wqvad {

class SileroVAD::Impl {
private:
    // ONNX Runtime resources
    Ort::Env env;
    Ort::SessionOptions session_options;
    std::shared_ptr<Ort::Session> session = nullptr;
    Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeCPU);
    
    // Context and state management
    const int context_samples = 64;  // For 16kHz, 64 samples context
    std::vector<float> _context;     // Last 64 samples from previous chunk
    std::vector<float> _state;       // LSTM state (2 * 1 * 128)
    const unsigned int size_state = 2 * 1 * 128;
    
    // Model configuration
    VadConfig config;
    int window_size_samples;
    int effective_window_size;
    int sr_per_ms;
    
    // ONNX input/output setup
    std::vector<const char*> input_node_names = {"input", "state", "sr"};
    std::vector<const char*> output_node_names = {"output", "stateN"};
    std::vector<int64_t> sr;
    
    // VAD state tracking
    bool triggered = false;
    unsigned int temp_end = 0;
    unsigned int current_sample = 0;
    int prev_end = 0;
    int next_start = 0;
    std::vector<VadSegment> speeches;
    VadSegment current_speech;
    
    // Timing parameters
    int min_silence_samples;
    int min_silence_samples_at_max_speech;
    int min_speech_samples;
    float max_speech_samples;
    int speech_pad_samples;
    
public:
    Impl() : env(ORT_LOGGING_LEVEL_WARNING, "SileroVAD") {
        std::cout << "🔧 SileroVAD::Impl() constructor called" << std::endl;
        session_options.SetIntraOpNumThreads(1);
        session_options.SetInterOpNumThreads(1);
        session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        
        _state.resize(size_state, 0.0f);
        _context.assign(context_samples, 0.0f);
        sr.resize(1);
        std::cout << "✅ SileroVAD::Impl() constructor completed" << std::endl;
    }
    
    bool initialize(const VadConfig& cfg, const std::string& modelPath) {
        std::cout << "🔧 SileroVAD::initialize() called with model path: " << modelPath << std::endl;
        config = cfg;
        
        // Check if model file exists
        std::ifstream modelFile(modelPath, std::ios::binary);
        if (!modelFile.is_open()) {
            std::cerr << "❌ Model file does not exist or cannot be opened: " << modelPath << std::endl;
            return false;
        }
        modelFile.close();
        std::cout << "✅ Model file exists and can be opened" << std::endl;
        
        try {
            std::cout << "🔧 Creating ONNX session..." << std::endl;
            // Create ONNX session
            session = std::make_shared<Ort::Session>(env, modelPath.c_str(), session_options);
            std::cout << "✅ ONNX session created successfully" << std::endl;
            
            // Setup audio parameters
            sr_per_ms = config.sampleRate / 1000;  // 16000 / 1000 = 16
            window_size_samples = 32 * sr_per_ms;  // 32ms * 16 = 512 samples
            effective_window_size = window_size_samples + context_samples; // 512 + 64 = 576
            sr[0] = config.sampleRate;
            
            std::cout << "🔧 Audio parameters: sampleRate=" << config.sampleRate 
                      << ", window_size_samples=" << window_size_samples 
                      << ", effective_window_size=" << effective_window_size << std::endl;
            
            // Setup timing parameters
            min_speech_samples = sr_per_ms * config.minSpeechDurationMs;
            max_speech_samples = (config.sampleRate * config.maxSpeechDurationS - window_size_samples - 2 * speech_pad_samples);
            min_silence_samples = sr_per_ms * config.minSilenceDurationMs;
            min_silence_samples_at_max_speech = sr_per_ms * 98;
            speech_pad_samples = config.speechPadMs * sr_per_ms;
            
            std::cout << "✅ Timing parameters configured" << std::endl;
            
            reset();
            std::cout << "✅ SileroVAD initialized successfully" << std::endl;
            return true;
        } catch (const std::exception& e) {
            std::cerr << "❌ Failed to initialize Silero VAD: " << e.what() << std::endl;
            return false;
        }
    }
    
    VadResult processChunk(const std::vector<float>& audioChunk) {
        VadResult result;
        result.timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
            
        if (audioChunk.size() != window_size_samples) {
            std::cerr << "❌ Invalid chunk size: " << audioChunk.size() << ", expected: " << window_size_samples << std::endl;
            return result;
        }
        
        std::cout << "🔧 Processing audio chunk of size: " << audioChunk.size() << std::endl;
        
        try {
            // Build input with context
            std::vector<float> input_data(effective_window_size);
            std::copy(_context.begin(), _context.end(), input_data.begin());
            std::copy(audioChunk.begin(), audioChunk.end(), input_data.begin() + context_samples);
            
            // Create input tensors
            std::vector<int64_t> input_shape = {1, effective_window_size};
            std::vector<int64_t> state_shape = {2, 1, 128};
            std::vector<int64_t> sr_shape = {1};
            
            auto input_tensor = Ort::Value::CreateTensor<float>(
                memory_info, input_data.data(), input_data.size(), 
                input_shape.data(), input_shape.size());
                
            auto state_tensor = Ort::Value::CreateTensor<float>(
                memory_info, _state.data(), _state.size(),
                state_shape.data(), state_shape.size());
                
            auto sr_tensor = Ort::Value::CreateTensor<int64_t>(
                memory_info, sr.data(), sr.size(),
                sr_shape.data(), sr_shape.size());
            
            std::vector<Ort::Value> input_tensors;
            input_tensors.push_back(std::move(input_tensor));
            input_tensors.push_back(std::move(state_tensor));
            input_tensors.push_back(std::move(sr_tensor));
            
            // Run inference
            std::cout << "🔧 Running ONNX inference..." << std::endl;
            auto output_tensors = session->Run(
                Ort::RunOptions{nullptr},
                input_node_names.data(), input_tensors.data(), input_tensors.size(),
                output_node_names.data(), output_node_names.size());
            
            // Extract results
            float speech_prob = output_tensors[0].GetTensorMutableData<float>()[0];
            float* stateN = output_tensors[1].GetTensorMutableData<float>();
            
            std::cout << "✅ ONNX inference completed, speech probability: " << speech_prob << std::endl;
            
            // Update state and context
            std::memcpy(_state.data(), stateN, size_state * sizeof(float));
            std::copy(input_data.end() - context_samples, input_data.end(), _context.begin());
            current_sample += window_size_samples;
            
            // Process VAD logic
            result.probability = speech_prob;
            result.isVoiceDetected = speech_prob >= config.threshold;
            processVadLogic(speech_prob);
            
            std::cout << "✅ VAD result: isVoice=" << result.isVoiceDetected 
                      << ", probability=" << result.probability << std::endl;
            
        } catch (const std::exception& e) {
            std::cerr << "❌ Error during VAD processing: " << e.what() << std::endl;
        }
        
        return result;
    }
    
    std::vector<VadSegment> processAudio(const std::vector<float>& audioData) {
        reset();
        
        // Process audio in chunks
        for (size_t i = 0; i < audioData.size(); i += window_size_samples) {
            if (i + window_size_samples > audioData.size()) {
                break;
            }
            
            std::vector<float> chunk(audioData.begin() + i, 
                                   audioData.begin() + i + window_size_samples);
            processChunk(chunk);
        }
        
        // Finalize any remaining speech segment
        if (current_speech.startTime >= 0) {
            current_speech.endTime = static_cast<float>(audioData.size()) / config.sampleRate;
            speeches.push_back(current_speech);
        }
        
        return speeches;
    }
    
    void reset() {
        std::fill(_state.begin(), _state.end(), 0.0f);
        std::fill(_context.begin(), _context.end(), 0.0f);
        triggered = false;
        temp_end = 0;
        current_sample = 0;
        prev_end = 0;
        next_start = 0;
        speeches.clear();
        current_speech = VadSegment();
    }
    
    VadConfig getConfig() const {
        return config;
    }
    
private:
    void processVadLogic(float speech_prob) {
        // Convert samples to time
        float current_time = static_cast<float>(current_sample - window_size_samples) / config.sampleRate;
        
        if (speech_prob >= config.threshold) {
            if (temp_end != 0) {
                temp_end = 0;
                if (next_start < prev_end) {
                    next_start = current_sample - window_size_samples;
                }
            }
            if (!triggered) {
                triggered = true;
                current_speech.startTime = current_time;
                current_speech.isSpeech = true;
            }
            return;
        }
        
        // Handle max speech duration
        if (triggered && ((current_sample - current_speech.startTime * config.sampleRate) > max_speech_samples)) {
            if (prev_end > 0) {
                current_speech.endTime = static_cast<float>(prev_end) / config.sampleRate;
                speeches.push_back(current_speech);
                current_speech = VadSegment();
                if (next_start < prev_end) {
                    triggered = false;
                } else {
                    current_speech.startTime = static_cast<float>(next_start) / config.sampleRate;
                    current_speech.isSpeech = true;
                }
                prev_end = 0;
                next_start = 0;
                temp_end = 0;
            } else {
                current_speech.endTime = static_cast<float>(current_sample) / config.sampleRate;
                speeches.push_back(current_speech);
                current_speech = VadSegment();
                prev_end = 0;
                next_start = 0;
                temp_end = 0;
                triggered = false;
            }
            return;
        }
        
        // Handle silence
        if (speech_prob < (config.threshold - 0.15f)) {
            if (triggered) {
                if (temp_end == 0) {
                    temp_end = current_sample;
                }
                if (current_sample - temp_end > min_silence_samples_at_max_speech) {
                    prev_end = temp_end;
                }
                if ((current_sample - temp_end) >= min_silence_samples) {
                    current_speech.endTime = static_cast<float>(temp_end) / config.sampleRate;
                    if ((current_speech.endTime - current_speech.startTime) * config.sampleRate > min_speech_samples) {
                        speeches.push_back(current_speech);
                        current_speech = VadSegment();
                        prev_end = 0;
                        next_start = 0;
                        temp_end = 0;
                        triggered = false;
                    }
                }
            }
        }
    }
};

// SileroVAD implementation
SileroVAD::SileroVAD() : pImpl(std::make_unique<Impl>()) {}
SileroVAD::~SileroVAD() = default;

bool SileroVAD::initialize(const VadConfig& config, const std::string& modelPath) {
    return pImpl->initialize(config, modelPath);
}

VadResult SileroVAD::processChunk(const std::vector<float>& audioChunk) {
    return pImpl->processChunk(audioChunk);
}

std::vector<VadSegment> SileroVAD::processAudio(const std::vector<float>& audioData) {
    return pImpl->processAudio(audioData);
}

void SileroVAD::reset() {
    pImpl->reset();
}

VadConfig SileroVAD::getConfig() const {
    return pImpl->getConfig();
}

// Utility functions
std::string getVersion() {
    return "1.0.0-silero-v5";
}

bool isValidSampleRate(int sampleRate) {
    return sampleRate == 8000 || sampleRate == 16000;
}

std::vector<float> resampleAudio(const std::vector<float>& input, 
                                int inputSampleRate, 
                                int outputSampleRate) {
    if (inputSampleRate == outputSampleRate) {
        return input;
    }
    
    // Simple linear interpolation resampling
    float ratio = static_cast<float>(outputSampleRate) / inputSampleRate;
    size_t outputSize = static_cast<size_t>(input.size() * ratio);
    std::vector<float> output(outputSize);
    
    for (size_t i = 0; i < outputSize; ++i) {
        float srcIndex = i / ratio;
        size_t index1 = static_cast<size_t>(srcIndex);
        size_t index2 = std::min(index1 + 1, input.size() - 1);
        float fraction = srcIndex - index1;
        
        output[i] = input[index1] * (1.0f - fraction) + input[index2] * fraction;
    }
    
    return output;
}

} // namespace wqvad
