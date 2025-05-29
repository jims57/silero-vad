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
