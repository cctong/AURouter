import AudioToolbox
@preconcurrency import AVFAudio
import Foundation

enum MatrixMixerConfigurator {
    static func setStreamFormats(
        _ matrix: AVAudioUnit,
        input: AVAudioFormat,
        output: AVAudioFormat
    ) throws {
        let audioUnit = matrix.auAudioUnit
        guard audioUnit.inputBusses.count > 0, audioUnit.outputBusses.count > 0 else {
            throw AURouterError.audioUnit("The matrix mixer does not expose audio busses.")
        }
        do {
            try audioUnit.inputBusses[0].setFormat(input)
            try audioUnit.outputBusses[0].setFormat(output)
        } catch {
            throw AURouterError.audioUnit(
                "The matrix mixer rejected \(Int(input.channelCount))→\(Int(output.channelCount)) channels at \(Int(input.sampleRate)) Hz."
            )
        }
    }

    static func configure(
        _ matrix: AVAudioUnit,
        routes: [(Int, Int, Float)]
    ) throws {
        let unit = matrix.audioUnit

        var dimensions = [UInt32](repeating: 0, count: 2)
        var dimensionSize = UInt32(MemoryLayout<UInt32>.size * dimensions.count)
        let dimensionStatus = dimensions.withUnsafeMutableBytes { bytes in
            AudioUnitGetProperty(
                unit,
                kAudioUnitProperty_MatrixDimensions,
                kAudioUnitScope_Global,
                0,
                bytes.baseAddress!,
                &dimensionSize
            )
        }
        try AURouterError.check(dimensionStatus, operation: "Read matrix mixer dimensions")
        let inputCount = Int(dimensions[0])
        let outputCount = Int(dimensions[1])
        guard inputCount > 0, outputCount > 0 else {
            throw AURouterError.audioUnit("The matrix mixer reported an empty channel matrix.")
        }

        let levels = try MatrixLevels.make(
            inputChannels: inputCount,
            outputChannels: outputCount,
            routes: routes.map { (input: $0.0, output: $0.1, gain: $0.2) }
        )
        let levelStatus = levels.withUnsafeBytes { bytes in
            AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_MatrixLevels,
                kAudioUnitScope_Global,
                0,
                bytes.baseAddress!,
                UInt32(bytes.count)
            )
        }
        try AURouterError.check(levelStatus, operation: "Configure matrix mixer routes")
    }
}
