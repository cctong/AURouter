import AudioToolbox
@preconcurrency import AVFAudio
import Testing
@testable import AURouterCore

@Test @MainActor
func stereoAppleEffectAcceptsProcessingFormat() async throws {
    let unit = try await instantiateEffect(
        subtype: kAudioUnitSubType_DynamicsProcessor,
        manufacturer: kAudioUnitManufacturer_Apple
    )
    let format = try #require(
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )
    )

    try AudioUnitFormatNegotiator.prepare(
        unit,
        for: format,
        displayName: "AUDynamicsProcessor"
    )
}

@Test func negotiationPrefersNativeLayoutsBeforeAdapters() {
    #expect(
        AudioUnitFormatNegotiator.candidates(sourceChannelCount: 1) == [
            AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1),
            AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 2),
            AudioUnitProcessingFormat(inputChannels: 2, outputChannels: 2)
        ]
    )
    #expect(
        AudioUnitFormatNegotiator.candidates(sourceChannelCount: 2) == [
            AudioUnitProcessingFormat(inputChannels: 2, outputChannels: 2),
            AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 2),
            AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1)
        ]
    )
}

@Test @MainActor
func appleEffectNegotiatesNativeMono() async throws {
    let unit = try await instantiateEffect(
        subtype: kAudioUnitSubType_DynamicsProcessor,
        manufacturer: kAudioUnitManufacturer_Apple
    )

    let result = try AudioUnitFormatNegotiator.prepare(
        unit,
        sourceChannelCount: 1,
        sampleRate: 48_000,
        displayName: "AUDynamicsProcessor"
    )

    #expect(result == AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1))
}

@MainActor
private func instantiateEffect(subtype: UInt32, manufacturer: UInt32) async throws -> AVAudioUnit {
    try await instantiate(
        AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: subtype,
            componentManufacturer: manufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    )
}

@MainActor
private func instantiate(_ description: AudioComponentDescription) async throws -> AVAudioUnit {
    try await withCheckedThrowingContinuation { continuation in
        AVAudioUnit.instantiate(with: description, options: []) { unit, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let unit {
                continuation.resume(returning: unit)
            } else {
                continuation.resume(throwing: AURouterError.audioUnit("No Audio Unit instance"))
            }
        }
    }
}
