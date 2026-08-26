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

@Test func fallbackSampleRatesPreferHardwareThenBroadcastRates() {
    #expect(AudioUnitFormatNegotiator.sampleRates(preferred: 16_000) == [16_000, 48_000, 44_100])
    #expect(AudioUnitFormatNegotiator.sampleRates(preferred: 48_000) == [48_000, 44_100])
    #expect(AudioUnitFormatNegotiator.sampleRates(preferred: 44_100) == [44_100, 48_000])
}

@Test @MainActor
func appleEffectKeepsUnsupportedLookingHardwareRateWhenAccepted() async throws {
    let unit = try await instantiateEffect(
        subtype: kAudioUnitSubType_DynamicsProcessor,
        manufacturer: kAudioUnitManufacturer_Apple
    )

    let prepared = try AudioUnitFormatNegotiator.prepareChain(
        [(unit: unit, displayName: "AUDynamicsProcessor")],
        sourceChannelCount: 1,
        sampleRate: 16_000
    )

    #expect(prepared.sampleRate == 16_000)
    #expect(prepared.formats == [AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1)])
}

@Test @MainActor
func emptyChainKeepsHardwareSampleRate() throws {
    let prepared = try AudioUnitFormatNegotiator.prepareChain(
        [],
        sourceChannelCount: 1,
        sampleRate: 16_000
    )

    #expect(prepared.sampleRate == 16_000)
    #expect(prepared.formats.isEmpty)
}

@Test @MainActor
func wavesMonoEffectUpsamplesFromUnsupportedHardwareRate() async throws {
    let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCC("RQ6M"),
        componentManufacturer: fourCC("ksWV"),
        componentFlags: 0,
        componentFlagsMask: 0
    )
    var query = description
    guard AudioComponentFindNext(nil, &query) != nil else { return }

    let unit = try await instantiate(description)
    let prepared = try AudioUnitFormatNegotiator.prepareChain(
        [(unit: unit, displayName: "REQ 6 (m)WaveShell-AU Compiled for 64 bits")],
        sourceChannelCount: 1,
        sampleRate: 16_000
    )

    #expect(prepared.sampleRate == 48_000)
    #expect(prepared.formats == [AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1)])
}


private func fourCC(_ value: String) -> UInt32 {
    value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
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
