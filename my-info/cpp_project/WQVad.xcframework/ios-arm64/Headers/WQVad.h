#ifndef WQVad_h
#define WQVad_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// WQVad C API for Objective-C integration

typedef struct WQVadContext WQVadContext;
typedef struct WQVadStreamContext WQVadStreamContext;

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

/**
 * Process audio data and save detected speech segments as WAV files
 * @param context WQVad context
 * @param audioData Float audio samples (16kHz, mono)
 * @param numSamples Total number of samples
 * @param sampleRate Sample rate of the audio
 * @param outputDir Directory path to save segment WAV files
 * @return Number of segments saved, -1 on error
 */
int wqvad_process_audio_file(WQVadContext* context,
                            const float* audioData,
                            size_t numSamples,
                            int sampleRate,
                            const char* outputDir);

/**
 * Get sample indices for each speech segment (for PCM segmentation)
 * @param context WQVad context
 * @param audioData Float audio samples
 * @param numSamples Total number of samples
 * @param sampleRate Sample rate of the audio
 * @param outStartSamples Output array of segment start samples (caller must free)
 * @param outEndSamples Output array of segment end samples (caller must free)
 * @param outNumSegments Number of segments returned
 * @return 0 on success, -1 on error
 */
int wqvad_segment_audio(WQVadContext* context,
                       const float* audioData,
                       size_t numSamples,
                       int sampleRate,
                       size_t** outStartSamples,
                       size_t** outEndSamples,
                       size_t* outNumSegments);

/**
 * Free sample segment arrays returned by wqvad_segment_audio
 * @param startSamples Start samples array to free
 * @param endSamples End samples array to free
 */
void wqvad_free_sample_segments(size_t* startSamples, size_t* endSamples);

/**
 * Create a streaming context for continuous audio processing
 * @param vadContext The main VAD context
 * @param outputDir Directory to save detected segments
 * @param sampleRate Sample rate of the audio stream
 * @return Stream context pointer, NULL on failure
 */
WQVadStreamContext* wqvad_create_stream_context(WQVadContext* vadContext,
                                               const char* outputDir,
                                               int sampleRate);

/**
 * Create a streaming context for continuous audio processing with custom output sample rate
 * @param vadContext The main VAD context
 * @param outputDir Directory to save detected segments
 * @param sampleRate Sample rate of the audio stream
 * @param outputSampleRate Sample rate for saved WAV files (16000, 24000, 44100, 48000)
 * @return Stream context pointer, NULL on failure
 */
WQVadStreamContext* wqvad_create_stream_context_ex(WQVadContext* vadContext,
                                                  const char* outputDir,
                                                  int sampleRate,
                                                  int outputSampleRate);

/**
 * Process a chunk of streaming audio
 * @param streamContext Stream context
 * @param audioData Float audio samples
 * @param numSamples Number of samples in this chunk
 * @return Number of new segments detected in this chunk, -1 on error
 */
int wqvad_process_stream_chunk(WQVadStreamContext* streamContext,
                              const float* audioData,
                              size_t numSamples);

/**
 * Process a chunk of streaming audio with automatic resampling
 * @param streamContext Stream context
 * @param audioData Float audio samples (any sample rate)
 * @param numSamples Number of samples in this chunk
 * @param inputSampleRate Sample rate of the input audio
 * @return Number of new segments detected in this chunk, -1 on error
 */
int wqvad_process_stream_chunk_resampled(WQVadStreamContext* streamContext,
                                        const float* audioData,
                                        size_t numSamples,
                                        int inputSampleRate);

/**
 * Finalize streaming and save any remaining segments
 * @param streamContext Stream context
 * @return Total number of segments detected, -1 on error
 */
int wqvad_finalize_stream(WQVadStreamContext* streamContext);

/**
 * Destroy stream context
 * @param streamContext Stream context to destroy
 */
void wqvad_destroy_stream_context(WQVadStreamContext* streamContext);

#ifdef __cplusplus
}
#endif

#endif /* WQVad_h */
