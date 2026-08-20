#include "AURouterRealtime.h"

#include <stddef.h>
#include <stdlib.h>

struct ARInputCapture {
    AudioUnit unit;
    ARStereoRingBuffer *ring;
    AudioBufferList *buffers;
    uint32_t maximumFrames;
    double sampleRate;
};

static OSStatus inputCallback(
    void *reference,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *timeStamp,
    UInt32 busNumber,
    UInt32 frameCount,
    AudioBufferList *data
) {
    (void)busNumber;
    (void)data;
    ARInputCapture *capture = reference;
    if (capture == NULL || capture->ring == NULL || frameCount > capture->maximumFrames) {
        return kAudioUnitErr_TooManyFramesToProcess;
    }

    UInt32 byteCount = frameCount * sizeof(float);
    capture->buffers->mBuffers[0].mDataByteSize = byteCount;
    capture->buffers->mBuffers[1].mDataByteSize = byteCount;
    OSStatus status = AudioUnitRender(
        capture->unit,
        flags,
        timeStamp,
        1,
        frameCount,
        capture->buffers
    );
    if (status != noErr) {
        return status;
    }

    ARStereoRingBufferWrite(
        capture->ring,
        capture->buffers->mBuffers[0].mData,
        capture->buffers->mBuffers[1].mData,
        frameCount
    );
    return noErr;
}

static void disposeCapture(ARInputCapture *capture) {
    if (capture == NULL) {
        return;
    }
    if (capture->unit != NULL) {
        AudioOutputUnitStop(capture->unit);
        AudioUnitUninitialize(capture->unit);
        AudioComponentInstanceDispose(capture->unit);
    }
    if (capture->buffers != NULL) {
        free(capture->buffers->mBuffers[0].mData);
        free(capture->buffers->mBuffers[1].mData);
        free(capture->buffers);
    }
    free(capture);
}

OSStatus ARInputCaptureCreate(
    AudioDeviceID deviceID,
    uint32_t leftChannel,
    uint32_t rightChannel,
    ARInputCapture **result
) {
    if (result == NULL) {
        return kAudio_ParamError;
    }
    *result = NULL;

    ARInputCapture *capture = calloc(1, sizeof(ARInputCapture));
    if (capture == NULL) {
        return kAudio_MemFullError;
    }

    AudioComponentDescription description = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0
    };
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    if (component == NULL) {
        disposeCapture(capture);
        return kAudioUnitErr_FailedInitialization;
    }

    OSStatus status = AudioComponentInstanceNew(component, &capture->unit);
    if (status != noErr) {
        disposeCapture(capture);
        return status;
    }

    UInt32 enabled = 1;
    status = AudioUnitSetProperty(
        capture->unit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input,
        1,
        &enabled,
        sizeof(enabled)
    );
    if (status != noErr) { disposeCapture(capture); return status; }

    UInt32 disabled = 0;
    status = AudioUnitSetProperty(
        capture->unit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output,
        0,
        &disabled,
        sizeof(disabled)
    );
    if (status != noErr) { disposeCapture(capture); return status; }

    status = AudioUnitSetProperty(
        capture->unit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        sizeof(deviceID)
    );
    if (status != noErr) { disposeCapture(capture); return status; }

    AudioStreamBasicDescription deviceFormat = {0};
    UInt32 formatSize = sizeof(deviceFormat);
    status = AudioUnitGetProperty(
        capture->unit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input,
        1,
        &deviceFormat,
        &formatSize
    );
    if (status != noErr) { disposeCapture(capture); return status; }
    capture->sampleRate = deviceFormat.mSampleRate;

    AudioStreamBasicDescription clientFormat = {
        .mSampleRate = deviceFormat.mSampleRate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = sizeof(float),
        .mFramesPerPacket = 1,
        .mBytesPerFrame = sizeof(float),
        .mChannelsPerFrame = 2,
        .mBitsPerChannel = 8 * sizeof(float),
        .mReserved = 0
    };
    status = AudioUnitSetProperty(
        capture->unit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output,
        1,
        &clientFormat,
        sizeof(clientFormat)
    );
    if (status != noErr) { disposeCapture(capture); return status; }

    SInt32 channelMap[2] = {(SInt32)leftChannel, (SInt32)rightChannel};
    status = AudioUnitSetProperty(
        capture->unit,
        kAudioOutputUnitProperty_ChannelMap,
        kAudioUnitScope_Output,
        1,
        channelMap,
        sizeof(channelMap)
    );
    if (status != noErr) { disposeCapture(capture); return status; }

    capture->maximumFrames = 4096;
    UInt32 maximumSize = sizeof(capture->maximumFrames);
    UInt32 reportedMaximum = 0;
    if (AudioUnitGetProperty(
            capture->unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &reportedMaximum,
            &maximumSize
        ) == noErr && reportedMaximum > capture->maximumFrames) {
        capture->maximumFrames = reportedMaximum;
    }

    size_t bufferListSize = offsetof(AudioBufferList, mBuffers) + 2 * sizeof(AudioBuffer);
    capture->buffers = calloc(1, bufferListSize);
    if (capture->buffers == NULL) { disposeCapture(capture); return kAudio_MemFullError; }
    capture->buffers->mNumberBuffers = 2;
    for (UInt32 channel = 0; channel < 2; channel++) {
        capture->buffers->mBuffers[channel].mNumberChannels = 1;
        capture->buffers->mBuffers[channel].mDataByteSize = capture->maximumFrames * sizeof(float);
        capture->buffers->mBuffers[channel].mData = calloc(capture->maximumFrames, sizeof(float));
        if (capture->buffers->mBuffers[channel].mData == NULL) {
            disposeCapture(capture);
            return kAudio_MemFullError;
        }
    }

    AURenderCallbackStruct callback = {
        .inputProc = inputCallback,
        .inputProcRefCon = capture
    };
    status = AudioUnitSetProperty(
        capture->unit,
        kAudioOutputUnitProperty_SetInputCallback,
        kAudioUnitScope_Global,
        0,
        &callback,
        sizeof(callback)
    );
    if (status != noErr) { disposeCapture(capture); return status; }

    status = AudioUnitInitialize(capture->unit);
    if (status != noErr) { disposeCapture(capture); return status; }

    *result = capture;
    return noErr;
}

void ARInputCaptureSetRing(ARInputCapture *capture, ARStereoRingBuffer *ring) {
    if (capture != NULL) {
        capture->ring = ring;
    }
}

OSStatus ARInputCaptureStart(ARInputCapture *capture) {
    if (capture == NULL || capture->unit == NULL || capture->ring == NULL) {
        return kAudio_ParamError;
    }
    return AudioOutputUnitStart(capture->unit);
}

void ARInputCaptureStop(ARInputCapture *capture) {
    if (capture != NULL && capture->unit != NULL) {
        AudioOutputUnitStop(capture->unit);
    }
}

void ARInputCaptureDestroy(ARInputCapture *capture) {
    disposeCapture(capture);
}

double ARInputCaptureSampleRate(const ARInputCapture *capture) {
    return capture == NULL ? 0 : capture->sampleRate;
}
