import AudioToolbox
@preconcurrency import AVFAudio
import CoreAudio
import Foundation

enum HardwareOutputStream {
    static func apply(to outputNode: AVAudioOutputNode, channelCount: Int) throws -> AVAudioFormat {
        let current = outputNode.inputFormat(forBus: 0)
        if Int(current.channelCount) >= channelCount, current.channelCount > 0 {
            return current
        }
        guard channelCount > 0 else {
            throw AURouterError.unavailable("The selected output device has no active output stream.")
        }
        guard let ioUnit = outputNode.audioUnit else {
            throw AURouterError.unavailable("The audio engine did not create its HAL output unit.")
        }

        let sampleRate = current.sampleRate > 0 ? current.sampleRate : 48_000
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
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
            kAudioUnitScope_Input,
            0,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        try AURouterError.check(status, operation: "Set hardware output channel count")

        let applied = outputNode.inputFormat(forBus: 0)
        if Int(applied.channelCount) < channelCount {
            throw AURouterError.unavailable(
                "This output device opened \(Int(applied.channelCount)) channels, so output pair \(channelCount - 1)–\(channelCount) is unavailable."
            )
        }
        return applied
    }
}
