import AudioToolbox
@preconcurrency import AVFAudio
import Testing
@testable import AURouterCore

@Test @MainActor
func appleDelayExposesGenericParameterRows() async throws {
    let unit = try await instantiateAppleEffect(subtype: kAudioUnitSubType_Delay)
    let rows = AudioUnitParameterCatalog.rows(from: unit.auAudioUnit.parameterTree)
    #expect(!rows.isEmpty)
    #expect(rows.contains { $0.isWritable })
    #expect(
        rows.contains {
            $0.name.localizedCaseInsensitiveContains("delay")
                || $0.name.localizedCaseInsensitiveContains("time")
        }
    )
}

@Test @MainActor
func missingParameterTreeYieldsNoRows() {
    #expect(AudioUnitParameterCatalog.rows(from: nil).isEmpty)
}

@MainActor
private func instantiateAppleEffect(subtype: UInt32) async throws -> AVAudioUnit {
    try await withCheckedThrowingContinuation { continuation in
        AVAudioUnit.instantiate(
            with: AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: subtype,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            ),
            options: []
        ) { unit, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let unit {
                continuation.resume(returning: unit)
            } else {
                continuation.resume(throwing: AURouterError.unavailable("Audio Unit instantiation failed."))
            }
        }
    }
}
