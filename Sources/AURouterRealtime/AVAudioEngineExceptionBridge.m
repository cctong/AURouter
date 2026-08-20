#import "AURouterRealtime.h"

OSStatus ARAVAudioEngineConnectSafely(
    AVAudioEngine *engine,
    AVAudioNode *source,
    AVAudioNode *destination,
    AVAudioFormat *format
) {
    @try {
        [engine connect:source to:destination format:format];
        return noErr;
    } @catch (NSException *exception) {
        return kAudioUnitErr_FormatNotSupported;
    }
}

OSStatus ARAVAudioEngineConnectSafelyFromBus(
    AVAudioEngine *engine,
    AVAudioNode *source,
    AVAudioNodeBus sourceBus,
    AVAudioNode *destination,
    AVAudioNodeBus destinationBus,
    AVAudioFormat *format
) {
    @try {
        [engine connect:source to:destination fromBus:sourceBus toBus:destinationBus format:format];
        return noErr;
    } @catch (NSException *exception) {
        return kAudioUnitErr_FormatNotSupported;
    }
}

OSStatus ARAVAudioEngineConnectSafelyToPoints(
    AVAudioEngine *engine,
    AVAudioNode *source,
    AVAudioNodeBus sourceBus,
    NSArray<AVAudioConnectionPoint *> *destinations,
    AVAudioFormat *format
) {
    @try {
        [engine connect:source toConnectionPoints:destinations fromBus:sourceBus format:format];
        return noErr;
    } @catch (NSException *exception) {
        return kAudioUnitErr_FormatNotSupported;
    }
}

void ARAVAudioNodeRemoveTapSafely(AVAudioNode *node, AVAudioNodeBus bus) {
    @try {
        if (node.engine == nil) {
            return;
        }
        [node removeTapOnBus:bus];
    } @catch (NSException *exception) {
    }
}

