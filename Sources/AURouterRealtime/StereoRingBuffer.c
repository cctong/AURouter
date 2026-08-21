#include "AURouterRealtime.h"

#include <math.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

struct ARStereoRingBuffer {
    float *left;
    float *right;
    uint32_t capacity;
    uint32_t mask;
    uint32_t target;
    double baseRatio;
    double readFraction;
    bool primed;
    _Atomic uint64_t writeFrame;
    _Atomic uint64_t readFrame;
    _Atomic double currentRatio;
    _Atomic uint64_t underruns;
    _Atomic uint64_t overruns;
};

static uint32_t nextPowerOfTwo(uint32_t value) {
    uint32_t result = 1;
    while (result < value && result <= UINT32_MAX / 2) {
        result <<= 1;
    }
    return result;
}

static uint32_t availableFrames(const ARStereoRingBuffer *ring) {
    uint64_t write = atomic_load_explicit(&ring->writeFrame, memory_order_acquire);
    uint64_t read = atomic_load_explicit(&ring->readFrame, memory_order_acquire);
    uint64_t available = write - read;
    return (uint32_t)(available > ring->capacity ? ring->capacity : available);
}

ARStereoRingBuffer *ARStereoRingBufferCreate(
    uint32_t capacityFrames,
    uint32_t targetFrames,
    double inputSampleRate,
    double outputSampleRate
) {
    if (capacityFrames < 8 || targetFrames < 2 ||
        inputSampleRate <= 0 || outputSampleRate <= 0) {
        return NULL;
    }

    uint32_t capacity = nextPowerOfTwo(capacityFrames);
    if (capacity < capacityFrames) {
        return NULL;
    }

    ARStereoRingBuffer *ring = calloc(1, sizeof(ARStereoRingBuffer));
    if (ring == NULL) {
        return NULL;
    }
    ring->left = calloc(capacity, sizeof(float));
    ring->right = calloc(capacity, sizeof(float));
    if (ring->left == NULL || ring->right == NULL) {
        ARStereoRingBufferDestroy(ring);
        return NULL;
    }

    ring->capacity = capacity;
    ring->mask = capacity - 1;
    ring->target = targetFrames < capacity / 2 ? targetFrames : capacity / 2;
    ring->baseRatio = inputSampleRate / outputSampleRate;
    atomic_init(&ring->writeFrame, 0);
    atomic_init(&ring->readFrame, 0);
    atomic_init(&ring->currentRatio, ring->baseRatio);
    atomic_init(&ring->underruns, 0);
    atomic_init(&ring->overruns, 0);
    return ring;
}

void ARStereoRingBufferDestroy(ARStereoRingBuffer *ring) {
    if (ring == NULL) {
        return;
    }
    free(ring->left);
    free(ring->right);
    free(ring);
}

void ARStereoRingBufferReset(ARStereoRingBuffer *ring) {
    if (ring == NULL) {
        return;
    }
    atomic_store_explicit(&ring->writeFrame, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->readFrame, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->currentRatio, ring->baseRatio, memory_order_relaxed);
    ring->readFraction = 0;
    ring->primed = false;
}

uint32_t ARStereoRingBufferWrite(
    ARStereoRingBuffer *ring,
    const float *left,
    const float *right,
    uint32_t frameCount
) {
    if (ring == NULL || left == NULL || right == NULL || frameCount == 0) {
        return 0;
    }

    uint64_t write = atomic_load_explicit(&ring->writeFrame, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&ring->readFrame, memory_order_acquire);
    uint64_t used = write - read;
    uint32_t freeFrames = used >= ring->capacity ? 0 : ring->capacity - (uint32_t)used;
    uint32_t framesToWrite = frameCount < freeFrames ? frameCount : freeFrames;
    if (framesToWrite < frameCount) {
        atomic_fetch_add_explicit(&ring->overruns, 1, memory_order_relaxed);
    }

    uint32_t start = (uint32_t)write & ring->mask;
    uint32_t firstSpan = framesToWrite;
    if (start + framesToWrite > ring->capacity) {
        firstSpan = ring->capacity - start;
    }
    memcpy(ring->left + start, left, firstSpan * sizeof(float));
    memcpy(ring->right + start, right, firstSpan * sizeof(float));
    if (firstSpan < framesToWrite) {
        uint32_t secondSpan = framesToWrite - firstSpan;
        memcpy(ring->left, left + firstSpan, secondSpan * sizeof(float));
        memcpy(ring->right, right + firstSpan, secondSpan * sizeof(float));
    }
    atomic_store_explicit(&ring->writeFrame, write + framesToWrite, memory_order_release);
    return framesToWrite;
}

uint32_t ARStereoRingBufferRead(
    ARStereoRingBuffer *ring,
    float *left,
    float *right,
    uint32_t frameCount
) {
    if (ring == NULL || left == NULL || right == NULL || frameCount == 0) {
        return 0;
    }

    uint64_t read = atomic_load_explicit(&ring->readFrame, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&ring->writeFrame, memory_order_acquire);
    uint32_t available = (uint32_t)(write - read);
    if (!ring->primed) {
        if (available < ring->target) {
            memset(left, 0, frameCount * sizeof(float));
            memset(right, 0, frameCount * sizeof(float));
            return 0;
        }
        ring->primed = true;
    }

    double error = ((double)available - (double)ring->target) / (double)ring->target;
    double correction = error * 0.001;
    if (correction > 0.005) correction = 0.005;
    if (correction < -0.005) correction = -0.005;
    double ratio = ring->baseRatio * (1.0 + correction);
    atomic_store_explicit(&ring->currentRatio, ratio, memory_order_relaxed);

    double lastPosition = ring->readFraction + (double)(frameCount - 1) * ratio;
    uint64_t finalSourceFrame = (uint64_t)floor(lastPosition) + 1;
    if (finalSourceFrame >= available) {
        atomic_fetch_add_explicit(&ring->underruns, 1, memory_order_relaxed);
        memset(left, 0, frameCount * sizeof(float));
        memset(right, 0, frameCount * sizeof(float));
        return 0;
    }

    double position = ring->readFraction;
    for (uint32_t frame = 0; frame < frameCount; frame++) {
        uint64_t whole = (uint64_t)position;
        float fraction = (float)(position - (double)whole);
        uint32_t first = (uint32_t)(read + whole) & ring->mask;
        uint32_t second = (first + 1) & ring->mask;
        left[frame] = ring->left[first] + (ring->left[second] - ring->left[first]) * fraction;
        right[frame] = ring->right[first] + (ring->right[second] - ring->right[first]) * fraction;
        position += ratio;
    }

    uint64_t consumed = (uint64_t)position;
    ring->readFraction = position - (double)consumed;
    atomic_store_explicit(&ring->readFrame, read + consumed, memory_order_release);
    return frameCount;
}

uint32_t ARStereoRingBufferAvailableFrames(const ARStereoRingBuffer *ring) {
    return ring == NULL ? 0 : availableFrames(ring);
}

double ARStereoRingBufferCurrentRatio(const ARStereoRingBuffer *ring) {
    return ring == NULL ? 1 : atomic_load_explicit(&ring->currentRatio, memory_order_relaxed);
}

uint64_t ARStereoRingBufferUnderrunCount(const ARStereoRingBuffer *ring) {
    return ring == NULL ? 0 : atomic_load_explicit(&ring->underruns, memory_order_relaxed);
}

uint64_t ARStereoRingBufferOverrunCount(const ARStereoRingBuffer *ring) {
    return ring == NULL ? 0 : atomic_load_explicit(&ring->overruns, memory_order_relaxed);
}
