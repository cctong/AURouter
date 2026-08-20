#ifndef AUROUTER_REALTIME_H
#define AUROUTER_REALTIME_H

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <stdint.h>

#ifdef __OBJC__
#import <AVFAudio/AVFAudio.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ARAtomicFloat ARAtomicFloat;

ARAtomicFloat *ARAtomicFloatCreate(float initialValue);
void ARAtomicFloatDestroy(ARAtomicFloat *value);
void ARAtomicFloatStore(ARAtomicFloat *value, float newValue);
float ARAtomicFloatLoad(const ARAtomicFloat *value);

typedef struct ARStereoRingBuffer ARStereoRingBuffer;

ARStereoRingBuffer *ARStereoRingBufferCreate(
    uint32_t capacityFrames,
    uint32_t targetFrames,
    double inputSampleRate,
    double outputSampleRate
);
void ARStereoRingBufferDestroy(ARStereoRingBuffer *ring);
void ARStereoRingBufferReset(ARStereoRingBuffer *ring);
uint32_t ARStereoRingBufferWrite(
    ARStereoRingBuffer *ring,
    const float *left,
    const float *right,
    uint32_t frameCount
);
uint32_t ARStereoRingBufferRead(
    ARStereoRingBuffer *ring,
    float *left,
    float *right,
    uint32_t frameCount
);
uint32_t ARStereoRingBufferAvailableFrames(const ARStereoRingBuffer *ring);
double ARStereoRingBufferCurrentRatio(const ARStereoRingBuffer *ring);
uint64_t ARStereoRingBufferUnderrunCount(const ARStereoRingBuffer *ring);
uint64_t ARStereoRingBufferOverrunCount(const ARStereoRingBuffer *ring);

typedef struct ARInputCapture ARInputCapture;

OSStatus ARInputCaptureCreate(
    AudioDeviceID deviceID,
    uint32_t leftChannel,
    uint32_t rightChannel,
    ARInputCapture **capture
);
void ARInputCaptureSetRing(ARInputCapture *capture, ARStereoRingBuffer *ring);
OSStatus ARInputCaptureStart(ARInputCapture *capture);
void ARInputCaptureStop(ARInputCapture *capture);
void ARInputCaptureDestroy(ARInputCapture *capture);
double ARInputCaptureSampleRate(const ARInputCapture *capture);

#ifdef __OBJC__
OSStatus ARAVAudioEngineConnectSafely(
    AVAudioEngine *engine,
    AVAudioNode *source,
    AVAudioNode *destination,
    AVAudioFormat *format
);
OSStatus ARAVAudioEngineConnectSafelyFromBus(
    AVAudioEngine *engine,
    AVAudioNode *source,
    AVAudioNodeBus sourceBus,
    AVAudioNode *destination,
    AVAudioNodeBus destinationBus,
    AVAudioFormat *format
);
OSStatus ARAVAudioEngineConnectSafelyToPoints(
    AVAudioEngine *engine,
    AVAudioNode *source,
    AVAudioNodeBus sourceBus,
    NSArray<AVAudioConnectionPoint *> *destinations,
    AVAudioFormat *format
);
#endif

#ifdef __cplusplus
}
#endif

#endif
