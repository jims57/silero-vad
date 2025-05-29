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
