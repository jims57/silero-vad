#ifndef WQVAD_H
#define WQVAD_H

#include "types.h"
#include <vector>
#include <string>
#include <memory>

namespace wqvad {

class SileroVAD {
public:
    SileroVAD();
    ~SileroVAD();

    // Initialize with Silero VAD V5 model
    bool initialize(const VadConfig& config, const std::string& modelPath);
    
    // Process audio chunk and return VAD result (expects 512 samples for 16kHz)
    VadResult processChunk(const std::vector<float>& audioChunk);
    
    // Process entire audio buffer and return speech segments
    std::vector<VadSegment> processAudio(const std::vector<float>& audioData);
    
    // Reset VAD state
    void reset();
    
    // Get current configuration
    VadConfig getConfig() const;

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;
};

// Utility functions
std::string getVersion();
bool isValidSampleRate(int sampleRate);
std::vector<float> resampleAudio(const std::vector<float>& input, 
                                int inputSampleRate, 
                                int outputSampleRate);

} // namespace wqvad

#endif // WQVAD_H 