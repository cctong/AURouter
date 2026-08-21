import AudioToolbox
@preconcurrency import AVFAudio
import Foundation
import Testing
@testable import AURouterCore

@Test func persistedSlotDecodesLegacyJSONWithoutState() throws {
    let json = Data(#"{"effectID":"au.delay","bypassed":true}"#.utf8)
    let slot = try JSONDecoder().decode(PersistedSlot.self, from: json)
    #expect(slot.effectID == "au.delay")
    #expect(slot.bypassed)
    #expect(slot.state == nil)
}

@Test func persistedSlotRoundTripsStateData() throws {
    let slot = PersistedSlot(effectID: "au.delay", bypassed: false, state: Data([0x01, 0x02, 0x03]))
    let data = try JSONEncoder().encode(slot)
    let decoded = try JSONDecoder().decode(PersistedSlot.self, from: data)
    #expect(decoded == slot)
}

@Test @MainActor
func appleDelayFullStateRoundTripsThroughSnapshot() async throws {
    let unit = try await instantiateAppleEffect(subtype: kAudioUnitSubType_Delay)
    let rows = AudioUnitParameterCatalog.rows(from: unit.auAudioUnit.parameterTree)
    let writable = try #require(rows.first { $0.isWritable && !$0.isIndexed })
    let parameter = try #require(
        unit.auAudioUnit.parameterTree?.parameter(withAddress: writable.address)
    )
    let target: AUValue = abs(parameter.value - parameter.maxValue) < 0.01
        ? parameter.minValue
        : parameter.maxValue
    parameter.setValue(target, originator: nil)
    let snapshot = try #require(AudioUnitStateStore.snapshot(unit))

    let restoredUnit = try await instantiateAppleEffect(subtype: kAudioUnitSubType_Delay)
    AudioUnitStateStore.apply(snapshot, to: restoredUnit)
    let restored = try #require(
        restoredUnit.auAudioUnit.parameterTree?.parameter(withAddress: writable.address)
    )
    #expect(abs(restored.value - target) < 0.05)
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
