#include "AURouterRealtime.h"

#include <stdatomic.h>
#include <stdlib.h>

struct ARAtomicFloat {
    _Atomic float value;
};

ARAtomicFloat *ARAtomicFloatCreate(float initialValue) {
    ARAtomicFloat *box = malloc(sizeof(ARAtomicFloat));
    if (box != NULL) {
        atomic_init(&box->value, initialValue);
    }
    return box;
}

void ARAtomicFloatDestroy(ARAtomicFloat *value) {
    free(value);
}

void ARAtomicFloatStore(ARAtomicFloat *value, float newValue) {
    if (value != NULL) {
        atomic_store_explicit(&value->value, newValue, memory_order_relaxed);
    }
}

float ARAtomicFloatLoad(const ARAtomicFloat *value) {
    if (value == NULL) {
        return 0.0f;
    }
    return atomic_load_explicit(&value->value, memory_order_relaxed);
}
