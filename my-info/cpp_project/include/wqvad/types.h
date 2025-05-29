#ifndef WQVAD_TYPES_H
#define WQVAD_TYPES_H

#include <vector>
#include <string>

namespace wqvad {

struct VadConfig {
    std::string modelPath;
    int sampleRate = 16000;            // Silero VAD expects 16kHz
    float threshold = 0.5f;            // Voice probability threshold
    int minSpeechDurationMs = 250;     // Minimum speech duration
    int minSilenceDurationMs = 100;    // Minimum silence duration
    int speechPadMs = 30;              // Speech padding
    float maxSpeechDurationS = 30.0f;  // Maximum speech duration
    bool useOnnxRuntime = true;
};

struct VadResult {
    bool isVoiceDetected = false;
    float probability = 0.0f;         // Voice probability from Silero
    float energyLevel = 0.0f;
    long long timestamp = 0;
};

struct VadSegment {
    float startTime = 0.0f;           // Start time in seconds
    float endTime = 0.0f;             // End time in seconds
    float confidence = 0.0f;          // Average confidence in segment
    bool isSpeech = false;            // True if speech, false if silence
};

enum class VadModel {
    SILERO_V5 = 5
};

} // namespace wqvad

#endif // WQVAD_TYPES_H 