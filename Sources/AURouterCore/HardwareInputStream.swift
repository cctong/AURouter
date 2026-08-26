import AudioToolbox
@preconcurrency import AVFAudio
import CoreAudio
import Foundation

enum HardwareInputStream {
    /// AVAudioEngine reports `1 ch, 16000 Hz` until the HAL client format is set.
    static func apply(
        to inputNode: AVAudioInputNode,
        sampleRate: Double,
        channelCount: Int
    ) throws -> AVAudioFormat {
        guard channelCount > 0, sampleRate > 0 else {
            throw AURouterError.unavailable("The selected device has no active input stream.")
        }
        let current = inputNode.outputFormat(forBus: 0)
        if Int(current.channelCount) >= channelCount,
           abs(current.sampleRate - sampleRate) <= 0.5 {
            return current
        }
        guard let ioUnit = inputNode.audioUnit else {
            throw AURouterError.unavailable("The audio engine did not create its HAL input unit.")
        }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let status = AudioUnitSetProperty(
            ioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        try AURouterError.check(status, operation: "Set hardware input stream format")

        let applied = inputNode.outputFormat(forBus: 0)
        if Int(applied.channelCount) < channelCount || abs(applied.sampleRate - sampleRate) > 0.5 {
            throw AURouterError.unavailable(
                "This input device opened \(Int(applied.channelCount)) channels at \(Int(applied.sampleRate)) Hz, expected \(channelCount) channels at \(Int(sampleRate)) Hz."
            )
        }
        return applied
    }
}
