import AudioToolbox
@preconcurrency import AVFAudio
import Testing
@testable import AURouterCore

private enum ProcessingGraphTestSource {
    nonisolated static func make(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, _, audioBufferList -> OSStatus in
            for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
                guard let data = buffer.mData else { continue }
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                data.assumingMemoryBound(to: Float.self)
                    .initialize(repeating: 0.1, count: sampleCount)
            }
            return noErr
        }
    }
}

@Suite(.serialized)
struct MonoProcessingGraphTests {
    @Test @MainActor
    func monoNoEffectGraphDuplicatesToStereo() async throws {
        let engine = AVAudioEngine()
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let mono = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 1))
        let stereo = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 2))
        let source = ProcessingGraphTestSource.make(format: mono)
        let upmixer = try await instantiateMatrixMixer()

        engine.attach(source)
        engine.attach(upmixer)
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: upmixer,
            format: mono,
            operation: "Test mono source connection"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upmixer,
            to: engine.mainMixerNode,
            format: stereo,
            operation: "Test mono duplication connection"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try MatrixMixerConfigurator.configure(
            upmixer,
            routes: try ChannelAdapter.routes(from: 1, to: 2)
        )

        try engine.start()
        try await Task.sleep(for: .milliseconds(50))
        engine.stop()
    }

    @Test @MainActor
    func crossDeviceStyleDuplicatedCaptureSelectsMonoThenReturnsStereo() async throws {
        let engine = AVAudioEngine()
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let mono = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 1))
        let stereo = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 2))
        let duplicatedCapture = ProcessingGraphTestSource.make(format: stereo)
        let inputSelector = try await instantiateMatrixMixer()
        let upmixer = try await instantiateMatrixMixer()

        engine.attach(duplicatedCapture)
        engine.attach(inputSelector)
        engine.attach(upmixer)
        try AudioGraphConnector.connect(
            engine,
            from: duplicatedCapture,
            to: inputSelector,
            format: stereo,
            operation: "Test cross-device capture connection"
        )
        try AudioGraphConnector.connect(
            engine,
            from: inputSelector,
            to: upmixer,
            format: mono,
            operation: "Test cross-device mono selection"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upmixer,
            to: engine.mainMixerNode,
            format: stereo,
            operation: "Test cross-device mono duplication"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try MatrixMixerConfigurator.configure(inputSelector, routes: [(0, 0, 1)])
        try MatrixMixerConfigurator.configure(
            upmixer,
            routes: try ChannelAdapter.routes(from: 1, to: 2)
        )

        try engine.start()
        try await Task.sleep(for: .milliseconds(50))
        engine.stop()
    }

    @Test @MainActor
    func installedMonoWavesEffectRendersInsideAdaptedStereoGraph() async throws {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: fourCC("ONRM"),
            componentManufacturer: fourCC("ksWV"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
        var query = description
        guard AudioComponentFindNext(nil, &query) != nil else { return }

        let engine = AVAudioEngine()
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let mono = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 1))
        let stereo = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 2))
        let source = ProcessingGraphTestSource.make(format: stereo)
        let effect = try await instantiate(description)
        let downmixer = try await instantiateMatrixMixer()
        let upmixer = try await instantiateMatrixMixer()
        let negotiated = try AudioUnitFormatNegotiator.prepare(
            effect,
            sourceChannelCount: 2,
            sampleRate: rate,
            displayName: "Clarity Vx (m)"
        )
        #expect(negotiated == AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1))

        engine.attach(source)
        engine.attach(downmixer)
        engine.attach(effect)
        engine.attach(upmixer)
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: downmixer,
            format: stereo,
            operation: "Test stereo source connection"
        )
        try AudioGraphConnector.connect(
            engine,
            from: downmixer,
            to: effect,
            format: mono,
            operation: "Test mono Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: effect,
            to: upmixer,
            format: mono,
            operation: "Test mono Audio Unit output"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upmixer,
            to: engine.mainMixerNode,
            format: stereo,
            operation: "Test stereo output connection"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try MatrixMixerConfigurator.configure(
            downmixer,
            routes: try ChannelAdapter.routes(from: 2, to: 1)
        )
        try MatrixMixerConfigurator.configure(
            upmixer,
            routes: try ChannelAdapter.routes(from: 1, to: 2)
        )

        try engine.start()
        try await Task.sleep(for: .milliseconds(100))
        engine.stop()
    }

    @Test @MainActor
    func installedStereoWavesEffectRendersFromAdaptedMonoGraph() async throws {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: fourCC("ONRS"),
            componentManufacturer: fourCC("ksWV"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
        var query = description
        guard AudioComponentFindNext(nil, &query) != nil else { return }

        let engine = AVAudioEngine()
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let mono = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 1))
        let stereo = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 2))
        let source = ProcessingGraphTestSource.make(format: mono)
        let effect = try await instantiate(description)
        let upmixer = try await instantiateMatrixMixer()
        let negotiated = try AudioUnitFormatNegotiator.prepare(
            effect,
            sourceChannelCount: 1,
            sampleRate: rate,
            displayName: "Clarity Vx (s)"
        )
        #expect(negotiated == AudioUnitProcessingFormat(inputChannels: 2, outputChannels: 2))

        engine.attach(source)
        engine.attach(upmixer)
        engine.attach(effect)
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: upmixer,
            format: mono,
            operation: "Test mono source connection"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upmixer,
            to: effect,
            format: stereo,
            operation: "Test stereo Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: effect,
            to: engine.mainMixerNode,
            format: stereo,
            operation: "Test stereo Audio Unit output"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try MatrixMixerConfigurator.configure(
            upmixer,
            routes: try ChannelAdapter.routes(from: 1, to: 2)
        )

        try engine.start()
        try await Task.sleep(for: .milliseconds(100))
        engine.stop()
    }

    @Test @MainActor
    func twoAppleEffectsRenderInSeries() async throws {
        let engine = AVAudioEngine()
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let stereo = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 2))
        let source = ProcessingGraphTestSource.make(format: stereo)
        let dynamics = try await instantiate(
            AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
        )
        let delay = try await instantiate(
            AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Delay,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
        )
        let first = try AudioUnitFormatNegotiator.prepare(
            dynamics,
            sourceChannelCount: 2,
            sampleRate: rate,
            displayName: "AUDynamicsProcessor"
        )
        let second = try AudioUnitFormatNegotiator.prepare(
            delay,
            sourceChannelCount: first.outputChannels,
            sampleRate: rate,
            displayName: "AUDelay"
        )
        let firstFormat = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: first.outputChannels)
        )
        let secondFormat = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: second.outputChannels)
        )

        engine.attach(source)
        engine.attach(dynamics)
        engine.attach(delay)
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: dynamics,
            format: stereo,
            operation: "Test first Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: dynamics,
            to: delay,
            format: firstFormat,
            operation: "Test second Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: delay,
            to: engine.mainMixerNode,
            format: secondFormat,
            operation: "Test chain output"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try engine.start()
        try await Task.sleep(for: .milliseconds(100))
        engine.stop()
    }

    @Test @MainActor
    func installedMonoThenStereoWavesEffectsRenderInSeries() async throws {
        let monoDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: fourCC("ONRM"),
            componentManufacturer: fourCC("ksWV"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let stereoDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: fourCC("ONRS"),
            componentManufacturer: fourCC("ksWV"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
        var monoQuery = monoDescription
        var stereoQuery = stereoDescription
        guard AudioComponentFindNext(nil, &monoQuery) != nil,
              AudioComponentFindNext(nil, &stereoQuery) != nil else { return }

        let engine = AVAudioEngine()
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let stereo = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 2))
        let source = ProcessingGraphTestSource.make(format: stereo)
        let monoEffect = try await instantiate(monoDescription)
        let stereoEffect = try await instantiate(stereoDescription)
        let downmixer = try await instantiateMatrixMixer()
        let upmixer = try await instantiateMatrixMixer()
        let first = try AudioUnitFormatNegotiator.prepare(
            monoEffect,
            sourceChannelCount: 2,
            sampleRate: rate,
            displayName: "Clarity Vx (m)"
        )
        #expect(first == AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1))
        let second = try AudioUnitFormatNegotiator.prepare(
            stereoEffect,
            sourceChannelCount: first.outputChannels,
            sampleRate: rate,
            displayName: "Clarity Vx (s)"
        )
        #expect(second == AudioUnitProcessingFormat(inputChannels: 2, outputChannels: 2))
        let mono = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 1))

        engine.attach(source)
        engine.attach(downmixer)
        engine.attach(monoEffect)
        engine.attach(upmixer)
        engine.attach(stereoEffect)
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: downmixer,
            format: stereo,
            operation: "Test stereo source connection"
        )
        try AudioGraphConnector.connect(
            engine,
            from: downmixer,
            to: monoEffect,
            format: mono,
            operation: "Test mono Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: monoEffect,
            to: upmixer,
            format: mono,
            operation: "Test mono Audio Unit output"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upmixer,
            to: stereoEffect,
            format: stereo,
            operation: "Test stereo Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: stereoEffect,
            to: engine.mainMixerNode,
            format: stereo,
            operation: "Test stereo chain output"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try MatrixMixerConfigurator.configure(
            downmixer,
            routes: try ChannelAdapter.routes(from: 2, to: 1)
        )
        try MatrixMixerConfigurator.configure(
            upmixer,
            routes: try ChannelAdapter.routes(from: 1, to: 2)
        )

        try engine.start()
        try await Task.sleep(for: .milliseconds(100))
        engine.stop()
    }

    @MainActor
    private func instantiateMatrixMixer() async throws -> AVAudioUnit {
        try await instantiate(
            AudioComponentDescription(
                componentType: kAudioUnitType_Mixer,
                componentSubType: kAudioUnitSubType_MatrixMixer,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            ),
            options: .loadInProcess
        )
    }

    @MainActor
    private func instantiate(
        _ description: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: options) { unit, error in
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
}

private func fourCC(_ value: String) -> UInt32 {
    value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}
