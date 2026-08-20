import AudioToolbox
@preconcurrency import AVFAudio
import AURouterRealtime
import Foundation

struct AudioUnitProcessingFormat: Equatable, Sendable {
    let inputChannels: Int
    let outputChannels: Int
}

enum AudioUnitFormatNegotiator {
    static func candidates(sourceChannelCount: Int) -> [AudioUnitProcessingFormat] {
        if sourceChannelCount == 1 {
            return [
                AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1),
                AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 2),
                AudioUnitProcessingFormat(inputChannels: 2, outputChannels: 2)
            ]
        }
        return [
            AudioUnitProcessingFormat(inputChannels: 2, outputChannels: 2),
            AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 2),
            AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1)
        ]
    }

    static func prepare(
        _ unit: AVAudioUnit,
        sourceChannelCount: Int,
        sampleRate: Double,
        displayName: String
    ) throws -> AudioUnitProcessingFormat {
        let audioUnit = unit.auAudioUnit
        guard audioUnit.inputBusses.count > 0, audioUnit.outputBusses.count > 0 else {
            throw AURouterError.audioUnit(
                "\(displayName) does not expose a main audio input and output."
            )
        }

        for candidate in candidates(sourceChannelCount: sourceChannelCount) {
            guard let inputFormat = processingFormat(
                sampleRate: sampleRate,
                channelCount: candidate.inputChannels
            ), let outputFormat = processingFormat(
                sampleRate: sampleRate,
                channelCount: candidate.outputChannels
            ) else { continue }
            do {
                try audioUnit.inputBusses[0].setFormat(inputFormat)
                try audioUnit.outputBusses[0].setFormat(outputFormat)
                return candidate
            } catch {
                continue
            }
        }

        let rate = Int(sampleRate)
        let intent = sourceChannelCount == 1 ? "mono" : "stereo"
        throw AURouterError.audioUnit(
            "\(displayName) cannot process a \(intent) route at \(rate) Hz. "
                + "Supported host layouts are mono, mono-to-stereo, and stereo."
        )
    }

    static func prepare(
        _ unit: AVAudioUnit,
        for format: AVAudioFormat,
        displayName: String
    ) throws {
        let audioUnit = unit.auAudioUnit
        guard audioUnit.inputBusses.count > 0, audioUnit.outputBusses.count > 0 else {
            throw AURouterError.audioUnit(
                "\(displayName) does not expose a main audio input and output."
            )
        }

        do {
            try audioUnit.inputBusses[0].setFormat(format)
            try audioUnit.outputBusses[0].setFormat(format)
        } catch {
            let channels = format.channelCount
            let rate = Int(format.sampleRate)
            throw AURouterError.audioUnit(
                "\(displayName) does not support \(channels)-channel audio at \(rate) Hz. "
                    + "Choose a stereo version of the plug-in."
            )
        }
    }

    static func processingFormat(sampleRate: Double, channelCount: Int) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        )
    }
}

enum AudioGraphConnector {
    static func connect(
        _ engine: AVAudioEngine,
        from source: AVAudioNode,
        to destination: AVAudioNode,
        format: AVAudioFormat,
        operation: String
    ) throws {
        let status = ARAVAudioEngineConnectSafely(engine, source, destination, format)
        try AURouterError.check(status, operation: operation)
    }

    static func connect(
        _ engine: AVAudioEngine,
        from source: AVAudioNode,
        to destination: AVAudioNode,
        fromBus: AVAudioNodeBus,
        toBus: AVAudioNodeBus,
        format: AVAudioFormat,
        operation: String
    ) throws {
        let status = ARAVAudioEngineConnectSafelyFromBus(
            engine,
            source,
            UInt(fromBus),
            destination,
            UInt(toBus),
            format
        )
        try AURouterError.check(status, operation: operation)
    }

    static func connect(
        _ engine: AVAudioEngine,
        from source: AVAudioNode,
        to destinations: [AVAudioConnectionPoint],
        fromBus: AVAudioNodeBus,
        format: AVAudioFormat,
        operation: String
    ) throws {
        let status = ARAVAudioEngineConnectSafelyToPoints(
            engine,
            source,
            UInt(fromBus),
            destinations,
            format
        )
        try AURouterError.check(status, operation: operation)
    }
}
