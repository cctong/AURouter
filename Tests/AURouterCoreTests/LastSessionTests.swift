import Foundation
import Testing
@testable import AURouterCore

private let inputDevice = AudioDevice(
    id: 1,
    uid: "input-a",
    name: "Input A",
    manufacturer: "Tests",
    inputChannelCount: 4,
    outputChannelCount: 0,
    nominalSampleRate: 48_000,
    bufferFrameSize: 128,
    isDefaultInput: true,
    isDefaultOutput: false
)

private let otherInput = AudioDevice(
    id: 2,
    uid: "input-b",
    name: "Input B",
    manufacturer: "Tests",
    inputChannelCount: 2,
    outputChannelCount: 0,
    nominalSampleRate: 48_000,
    bufferFrameSize: 128,
    isDefaultInput: false,
    isDefaultOutput: false
)

private let outputDevice = AudioDevice(
    id: 3,
    uid: "output-a",
    name: "Output A",
    manufacturer: "Tests",
    inputChannelCount: 0,
    outputChannelCount: 8,
    nominalSampleRate: 48_000,
    bufferFrameSize: 256,
    isDefaultInput: false,
    isDefaultOutput: true
)

private let dynamics = AudioEffectCatalog.builtInEffects[0]
private let delay = AudioEffectCatalog.builtInEffects[3]

private let savedSession = LastSession(
    route: RouteConfiguration(
        inputDeviceUID: inputDevice.uid,
        outputDeviceUID: outputDevice.uid,
        inputSelection: .mono(channel: 3),
        outputPair: ChannelPair(left: 6, right: 7)
    ),
    chain: [
        PersistedSlot(effectID: dynamics.id, bypassed: false),
        PersistedSlot(effectID: delay.id, bypassed: true)
    ],
    gain: 0.25
)

@Test func restoreKeepsSavedRouteChainAndGain() {
    let restored = LastSessionRestorer.restore(
        savedSession,
        inputDevices: [inputDevice, otherInput],
        outputDevices: [outputDevice],
        effects: AudioEffectCatalog.builtInEffects
    )

    #expect(restored.inputDeviceUID == "input-a")
    #expect(restored.outputDeviceUID == "output-a")
    #expect(restored.inputSelectionID == InputChannelSelection.mono(channel: 3).id)
    #expect(restored.outputPairIDs == [ChannelPair(left: 6, right: 7).id])
    #expect(restored.chain == savedSession.chain)
    #expect(restored.gain == 0.25)
}

@Test func restoreFallsBackWhenInputDeviceIsMissing() {
    let restored = LastSessionRestorer.restore(
        savedSession,
        inputDevices: [otherInput],
        outputDevices: [outputDevice],
        effects: AudioEffectCatalog.builtInEffects
    )

    #expect(restored.inputDeviceUID == "input-b")
    #expect(restored.inputSelectionID == otherInput.inputSelections.first?.id)
    #expect(restored.outputDeviceUID == "output-a")
    #expect(restored.chain.count == 2)
}

@Test func restoreDropsUnknownEffectsAndClampsGain() {
    let session = LastSession(
        route: savedSession.route,
        chain: savedSession.chain + [PersistedSlot(effectID: "missing-au", bypassed: false)],
        gain: 4
    )
    let restored = LastSessionRestorer.restore(
        session,
        inputDevices: [inputDevice],
        outputDevices: [outputDevice],
        effects: [dynamics]
    )

    #expect(restored.chain == [PersistedSlot(effectID: dynamics.id, bypassed: false)])
    #expect(restored.gain == 2)
}

@Test func lastSessionRoundTripsThroughUserDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "org.openpatch.AURouter.tests.lastSession"))
    defaults.removePersistentDomain(forName: "org.openpatch.AURouter.tests.lastSession")
    LastSessionStore.save(savedSession, to: defaults)
    let loaded = try #require(LastSessionStore.load(from: defaults))
    #expect(loaded == savedSession)
}

@Test func routingProfileStoreOverwritesSameName() throws {
    let defaults = try #require(UserDefaults(suiteName: "org.openpatch.AURouter.tests.profiles"))
    defaults.removePersistentDomain(forName: "org.openpatch.AURouter.tests.profiles")
    let first = RoutingProfile(name: "Live PA", session: savedSession)
    let quieter = LastSession(route: savedSession.route, chain: savedSession.chain, gain: 0.1)
    let second = RoutingProfile(name: "Live PA", session: quieter)
    RoutingProfileStore.save([first], to: defaults)
    var profiles = RoutingProfileStore.load(from: defaults)
    if let index = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(second.name) == .orderedSame }) {
        profiles[index].session = second.session
    } else {
        profiles.append(second)
    }
    RoutingProfileStore.save(profiles, to: defaults)
    let loaded = RoutingProfileStore.load(from: defaults)
    #expect(loaded.count == 1)
    #expect(loaded[0].session.gain == 0.1)
}

