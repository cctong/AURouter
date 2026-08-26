import AudioToolbox
@preconcurrency import AVFAudio
import Testing
@testable import AURouterCore

private enum TestAudioSource {
    nonisolated static func make(sample: Float = 0.25) -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, _, audioBufferList -> OSStatus in
            for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
                guard let data = buffer.mData else { continue }
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                data.assumingMemoryBound(to: Float.self)
                    .initialize(repeating: sample, count: sampleCount)
            }
            return noErr
        }
    }
}

@Suite(.serialized)
struct AudioLevelTapTests {
    @Test @MainActor
    func realTimeCallbackPublishesLevelWithoutMainActorIsolation() async throws {
        let engine = AVAudioEngine()
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputFormat.sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let source = TestAudioSource.make()
        let meter = AtomicLevel()

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        AudioLevelTap.install(on: source, storage: meter)
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try engine.start()
        defer {
            source.removeTap(onBus: 0)
            engine.stop()
        }

        for _ in 0..<50 where meter.load() == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(meter.load() > 0)
    }

    @Test @MainActor
    func removingTapFromDetachedNodeDoesNotAbort() {
        AudioLevelTap.remove(from: AVAudioMixerNode())
    }

    @Test @MainActor
    func negativeSamplesPublishMagnitudePeak() async throws {
        let peak = try await publishedPeak(sample: -0.5)
        #expect(abs(peak - 0.5) < 0.01)
    }

    @Test @MainActor
    func positiveSamplesPublishMagnitudePeak() async throws {
        let peak = try await publishedPeak(sample: 0.25)
        #expect(abs(peak - 0.25) < 0.01)
    }

    @Test @MainActor
    func peaksAboveOneClampToOne() async throws {
        let peak = try await publishedPeak(sample: 1.5)
        #expect(peak == 1)
    }

    @MainActor
    private func publishedPeak(sample: Float) async throws -> Float {
        let engine = AVAudioEngine()
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputFormat.sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let source = TestAudioSource.make(sample: sample)
        let meter = AtomicLevel()

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        AudioLevelTap.install(on: source, storage: meter)
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try engine.start()
        defer {
            source.removeTap(onBus: 0)
            engine.stop()
        }

        for _ in 0..<80 where meter.load() == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        return meter.load()
    }


    @Test @MainActor
    func sameDeviceIOFormatsMatchHardwareDevice() throws {
        let devices = try AudioDeviceCatalog.devices()
        guard let device = devices.first(where: { $0.supportsRouting }) else { return }
        let engine = AVAudioEngine()
        defer { restoreDefaultOutputDevice() }
        let inputNode = engine.inputNode
        let outputNode = engine.outputNode
        try selectCurrentDevice(device.id, on: outputNode)

        let inputFormat = try HardwareInputStream.apply(
            to: inputNode,
            sampleRate: device.nominalSampleRate,
            channelCount: device.inputChannelCount
        )
        let outputFormat = try HardwareOutputStream.apply(
            to: outputNode,
            sampleRate: device.nominalSampleRate,
            channelCount: device.outputChannelCount
        )
        #expect(Int(inputFormat.channelCount) == device.inputChannelCount)
        #expect(abs(inputFormat.sampleRate - device.nominalSampleRate) <= 0.5)
        #expect(Int(outputFormat.channelCount) >= device.outputChannelCount)
        #expect(abs(outputFormat.sampleRate - device.nominalSampleRate) <= 0.5)
    }

    @Test @MainActor
    func sameDeviceRouteStartsWithNoEffects() async throws {
        let devices = try AudioDeviceCatalog.devices()
        guard let device = devices.first(where: { $0.supportsRouting }) else { return }
        guard let inputSelection = device.inputSelections.first,
              let outputPair = device.outputStereoPairs.first else {
            return
        }
        defer { restoreDefaultOutputDevice() }
        let engine = AudioRoutingEngine()
        let route = RouteConfiguration(
            inputDeviceUID: device.uid,
            outputDeviceUID: device.uid,
            inputSelection: inputSelection,
            outputPair: outputPair
        )
        try await engine.start(
            inputDevice: device,
            outputDevice: device,
            route: route,
            gain: 0
        )
        engine.stop()


    }

    @Test @MainActor
    func defaultInputToDefaultOutputRouteStarts() async throws {
        let devices = try AudioDeviceCatalog.devices()
        guard let input = devices.first(where: \.isDefaultInput) ?? devices.first(where: \.supportsInputRouting),
              let output = devices.first(where: \.isDefaultOutput) ?? devices.first(where: \.supportsOutputRouting),
              let inputSelection = input.inputSelections.first,
              let outputPair = output.outputStereoPairs.first else {
            return
        }
        defer { restoreDefaultOutputDevice() }
        let engine = AudioRoutingEngine()
        let route = RouteConfiguration(
            inputDeviceUID: input.uid,
            outputDeviceUID: output.uid,
            inputSelection: inputSelection,
            outputPair: outputPair
        )
        try await engine.start(
            inputDevice: input,
            outputDevice: output,
            route: route,
            gain: 0
        )
        engine.stop()
    }


    @Test @MainActor
    func sameDeviceRouteStartsWithBluetoothExtraOutput() async throws {
        let devices = try AudioDeviceCatalog.devices()
        guard let input = devices.first(where: { $0.uid.contains("Audient") })
                ?? devices.first(where: { $0.supportsRouting }),
              let extra = devices.first(where: {
                  $0.supportsOutputRouting && ($0.name.contains("BTD") || $0.uid.contains("Sennheiser"))
              }),
              let inputSelection = input.inputSelections.first,
              let outputPair = input.outputStereoPairs.first,
              let extraPair = extra.outputStereoPairs.first else {
            return
        }
        defer { restoreDefaultOutputDevice() }
        let engine = AudioRoutingEngine()
        let route = RouteConfiguration(
            inputDeviceUID: input.uid,
            inputSelection: inputSelection,
            outputs: [
                OutputDeviceRoute(deviceUID: input.uid, pairs: [outputPair]),
                OutputDeviceRoute(deviceUID: extra.uid, pairs: [extraPair])
            ]
        )
        try await engine.start(
            inputDevice: input,
            outputDevice: input,
            extraOutputDevices: [extra],
            route: route,
            gain: 0
        )
        engine.stop()
    }

    @Test @MainActor
    func sameDeviceRouteStartsWithExtraOutput() async throws {
        let devices = try AudioDeviceCatalog.devices()
        guard let input = devices.first(where: { $0.supportsRouting }),
              let extra = devices.first(where: {
                  $0.supportsOutputRouting && $0.uid != input.uid
              }),
              let inputSelection = input.inputSelections.first,
              let outputPair = input.outputStereoPairs.first,
              let extraPair = extra.outputStereoPairs.first else {
            return
        }
        defer { restoreDefaultOutputDevice() }
        let engine = AudioRoutingEngine()
        let route = RouteConfiguration(
            inputDeviceUID: input.uid,
            inputSelection: inputSelection,
            outputs: [
                OutputDeviceRoute(deviceUID: input.uid, pairs: [outputPair]),
                OutputDeviceRoute(deviceUID: extra.uid, pairs: [extraPair])
            ]
        )
        try await engine.start(
            inputDevice: input,
            outputDevice: input,
            extraOutputDevices: [extra],
            route: route,
            gain: 0
        )
        engine.stop()
    }

    @Test @MainActor
    func lastSessionStyleRouteStartsWithWavesAndExtraOutput() async throws {
        let devices = try AudioDeviceCatalog.devices()
        guard let input = devices.first(where: { $0.uid.contains("Audient") })
                ?? devices.first(where: { $0.supportsRouting }),
              let extra = devices.first(where: {
                  $0.supportsOutputRouting && ($0.name.contains("BTD") || $0.uid.contains("Sennheiser"))
              }) ?? devices.first(where: {
                  $0.supportsOutputRouting && $0.uid != input.uid
              }),
              let inputSelection = input.inputSelections.first(where: {
                  if case .mono(let channel) = $0 { return channel == 0 }
                  return false
              }) ?? input.inputSelections.first,
              let outputPair = input.outputStereoPairs.last
                ?? input.outputStereoPairs.first,
              let extraPair = extra.outputStereoPairs.first else {
            return
        }

        let plugins: [(UInt32, String)] = [
            (fourCC("RQ6M"), "REQ 6 (m)"),
            (fourCC("ONRM"), "Clarity Vx (m)"),
            (fourCC("MXVM"), "MaxxVolume (m)"),
            (fourCC("WVBM"), "Waves plugin")
        ]
        var effects: [RoutedEffect] = []
        var units: [AVAudioUnit] = []
        let router = AudioRoutingEngine()
        defer { restoreDefaultOutputDevice() }
        for (subtype, name) in plugins {
            let description = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: subtype,
                componentManufacturer: fourCC("ksWV"),
                componentFlags: 0,
                componentFlagsMask: 0
            )
            var query = description
            guard AudioComponentFindNext(nil, &query) != nil else { continue }
            let descriptor = AudioEffectDescriptor(
                componentType: description.componentType,
                componentSubType: description.componentSubType,
                componentManufacturer: description.componentManufacturer,
                name: name,
                manufacturerName: "Waves"
            )
            effects.append(RoutedEffect(descriptor: descriptor))
            let unit = try await router.instantiateEffect(descriptor)
            try? unit.auAudioUnit.allocateRenderResources()
            units.append(unit)
        }
        guard !effects.isEmpty else { return }

        let route = RouteConfiguration(
            inputDeviceUID: input.uid,
            inputSelection: inputSelection,
            outputs: [
                OutputDeviceRoute(deviceUID: input.uid, pairs: [outputPair]),
                OutputDeviceRoute(deviceUID: extra.uid, pairs: [extraPair])
            ]
        )
        try await router.start(
            inputDevice: input,
            outputDevice: input,
            extraOutputDevices: [extra],
            route: route,
            effects: effects,
            units: units,
            gain: 0
        )
        router.stop()

    }

    @Test @MainActor
    func persistedLastSessionRoutePublishesOutput() async throws {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/org.openpatch.AURouter.plist")
        guard let plist = NSDictionary(contentsOf: plistURL),
              let data = plist["org.openpatch.AURouter.lastSession"] as? Data,
              let session = try? JSONDecoder().decode(LastSession.self, from: data) else {
            return
        }
        let devices = try AudioDeviceCatalog.devices()
        guard let input = devices.first(where: { $0.uid == session.route.inputDeviceUID }),
              let output = devices.first(where: { $0.uid == session.route.outputDeviceUID }) else {
            return
        }
        let router = AudioRoutingEngine()
        defer { restoreDefaultOutputDevice() }
        var effects: [RoutedEffect] = []
        var units: [AVAudioUnit] = []
        for slot in session.chain {
            let parts = slot.effectID.split(separator: "-").compactMap { UInt32($0) }
            guard parts.count == 3 else { continue }
            let descriptor = AudioEffectDescriptor(
                componentType: parts[0],
                componentSubType: parts[1],
                componentManufacturer: parts[2],
                name: slot.effectID,
                manufacturerName: "Saved"
            )
            var query = descriptor.componentDescription
            guard AudioComponentFindNext(nil, &query) != nil else { continue }
            let unit = try await router.instantiateEffect(descriptor)
            unit.auAudioUnit.shouldBypassEffect = slot.bypassed
            effects.append(RoutedEffect(descriptor: descriptor, bypassed: slot.bypassed, state: slot.state))
            units.append(unit)
        }
        guard !effects.isEmpty else { return }
        try await router.start(
            inputDevice: input,
            outputDevice: output,
            extraOutputDevices: [],
            route: session.route,
            effects: effects,
            units: units,
            gain: 0
        )
        try await Task.sleep(for: .milliseconds(400))
        for (slot, unit) in zip(session.chain, units) {
            if let state = slot.state {
                AudioUnitStateStore.apply(state, to: unit)
            }
        }
        router.setGain(Float(session.gain))
        try await Task.sleep(for: .milliseconds(400))
        if router.inputLevel > 0.001 {
            #expect(router.outputLevel > 0.0002)
        }
        router.stop()



    }

}

private func fourCC(_ value: String) -> UInt32 {
    value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

@MainActor
private func selectCurrentDevice(_ deviceID: AudioDeviceID, on outputNode: AVAudioOutputNode) throws {
    guard let ioUnit = outputNode.audioUnit else {
        throw AURouterError.unavailable("The audio engine did not create its HAL output unit.")
    }
    var selectedDevice = deviceID
    let status = AudioUnitSetProperty(
        ioUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &selectedDevice,
        UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    try AURouterError.check(status, operation: "Select test Core Audio device")
}


@MainActor
private func restoreDefaultOutputDevice() {
    guard let defaultOutput = try? AudioDeviceCatalog.devices().first(where: \.isDefaultOutput) else {
        return
    }
    let engine = AVAudioEngine()
    try? selectCurrentDevice(defaultOutput.id, on: engine.outputNode)
    engine.stop()
}
