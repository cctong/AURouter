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
    func crossDeviceStyleStereoSourceReachesGainWithoutInputMatrix() async throws {
        let engine = AVAudioEngine()
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let stereo = try #require(AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 2))
        let source = ProcessingGraphTestSource.make(format: stereo)
        let gain = AVAudioMixerNode()
        gain.outputVolume = 1

        engine.attach(source)
        engine.attach(gain)
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: gain,
            format: stereo,
            operation: "Test stereo source to gain"
        )
        try AudioGraphConnector.connect(
            engine,
            from: gain,
            to: engine.mainMixerNode,
            format: stereo,
            operation: "Test stereo gain to mixer"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
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
    func sampleRateConverterRendersSixteenKilohertzIntoAppleEffect() async throws {
        let hardwareRate = 16_000.0
        let processingRate = 48_000.0
        let monoHardware = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: hardwareRate, channelCount: 1)
        )
        let monoProcessing = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: processingRate, channelCount: 1)
        )
        let stereoHardware = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: hardwareRate, channelCount: 2)
        )
        let source = ProcessingGraphTestSource.make(format: monoHardware)
        let upConverter = try await instantiate(
            SampleRateConverter.componentDescription(),
            options: .loadInProcess
        )
        let effect = try await instantiate(
            AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Delay,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
        )
        let downConverter = try await instantiate(
            SampleRateConverter.componentDescription(),
            options: .loadInProcess
        )
        let upmixer = try await instantiateMatrixMixer()
        let negotiated = try AudioUnitFormatNegotiator.prepare(
            effect,
            sourceChannelCount: 1,
            sampleRate: processingRate,
            displayName: "AUDelay"
        )
        #expect(negotiated == AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1))

        let engine = AVAudioEngine()
        engine.attach(source)
        engine.attach(upConverter)
        engine.attach(effect)
        engine.attach(downConverter)
        engine.attach(upmixer)
        try SampleRateConverter.setStreamFormats(
            upConverter,
            input: monoHardware,
            output: monoProcessing
        )
        try SampleRateConverter.setStreamFormats(
            downConverter,
            input: monoProcessing,
            output: monoHardware
        )
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: upConverter,
            format: monoHardware,
            operation: "Test 16 kHz source connection"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upConverter,
            to: effect,
            format: monoProcessing,
            operation: "Test upsampled Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: effect,
            to: downConverter,
            format: monoProcessing,
            operation: "Test Audio Unit output into downsampler"
        )
        try AudioGraphConnector.connect(
            engine,
            from: downConverter,
            to: upmixer,
            format: monoHardware,
            operation: "Test downsampled mono into upmixer"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upmixer,
            to: engine.mainMixerNode,
            format: stereoHardware,
            operation: "Test stereo output connection"
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
    func installedMonoWavesEffectRendersFromSixteenKilohertzSource() async throws {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: fourCC("RQ6M"),
            componentManufacturer: fourCC("ksWV"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
        var query = description
        guard AudioComponentFindNext(nil, &query) != nil else { return }

        let hardwareRate = 16_000.0
        let effect = try await instantiate(description)
        let prepared = try AudioUnitFormatNegotiator.prepareChain(
            [(unit: effect, displayName: "REQ 6 (m)")],
            sourceChannelCount: 1,
            sampleRate: hardwareRate
        )
        #expect(prepared.sampleRate == 48_000)
        #expect(prepared.formats == [AudioUnitProcessingFormat(inputChannels: 1, outputChannels: 1)])

        let monoHardware = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: hardwareRate, channelCount: 1)
        )
        let monoProcessing = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: prepared.sampleRate, channelCount: 1)
        )
        let stereoHardware = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: hardwareRate, channelCount: 2)
        )
        let source = ProcessingGraphTestSource.make(format: monoHardware)
        let upConverter = try await instantiate(
            SampleRateConverter.componentDescription(),
            options: .loadInProcess
        )
        let downConverter = try await instantiate(
            SampleRateConverter.componentDescription(),
            options: .loadInProcess
        )
        let upmixer = try await instantiateMatrixMixer()

        let engine = AVAudioEngine()
        engine.attach(source)
        engine.attach(upConverter)
        engine.attach(effect)
        engine.attach(downConverter)
        engine.attach(upmixer)
        try SampleRateConverter.setStreamFormats(
            upConverter,
            input: monoHardware,
            output: monoProcessing
        )
        try SampleRateConverter.setStreamFormats(
            downConverter,
            input: monoProcessing,
            output: monoHardware
        )
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: upConverter,
            format: monoHardware,
            operation: "Test 16 kHz Waves source"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upConverter,
            to: effect,
            format: monoProcessing,
            operation: "Test upsampled Waves input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: effect,
            to: downConverter,
            format: monoProcessing,
            operation: "Test Waves output into downsampler"
        )
        try AudioGraphConnector.connect(
            engine,
            from: downConverter,
            to: upmixer,
            format: monoHardware,
            operation: "Test downsampled Waves into upmixer"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upmixer,
            to: engine.mainMixerNode,
            format: stereoHardware,
            operation: "Test Waves stereo output"
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

    @Test @MainActor
    func engineStyleSampleRateConversionPublishesMixerDimensions() async throws {
        let engine = AVAudioEngine()
        let hardwareRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let processingRate = abs(hardwareRate - 48_000) <= 0.5 ? 44_100.0 : 48_000.0
        let hardwareChannels = max(2, Int(engine.outputNode.inputFormat(forBus: 0).channelCount))
        let monoHardware = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: hardwareRate, channelCount: 1)
        )
        let stereoHardware = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: hardwareRate, channelCount: 2)
        )
        let hardwareOutput = try #require(
            AudioUnitFormatNegotiator.processingFormat(
                sampleRate: hardwareRate,
                channelCount: hardwareChannels
            )
        )
        let monoProcessing = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: processingRate, channelCount: 1)
        )
        let stereoProcessing = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: processingRate, channelCount: 2)
        )
        let source = ProcessingGraphTestSource.make(format: stereoHardware)
        let inputSelector = try await instantiateMatrixMixer()
        let upConverter = try await instantiate(
            SampleRateConverter.componentDescription(),
            options: .loadInProcess
        )
        let effect = try await instantiate(
            AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Delay,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
        )
        let upmixer = try await instantiateMatrixMixer()
        let downConverter = try await instantiate(
            SampleRateConverter.componentDescription(),
            options: .loadInProcess
        )
        let gain = AVAudioMixerNode()
        gain.outputVolume = 0
        let outputSelector = try await instantiateMatrixMixer()
        _ = try AudioUnitFormatNegotiator.prepare(
            effect,
            sourceChannelCount: 1,
            sampleRate: processingRate,
            displayName: "AUDelay"
        )

        engine.attach(source)
        engine.attach(inputSelector)
        engine.attach(upConverter)
        engine.attach(effect)
        engine.attach(upmixer)
        engine.attach(downConverter)
        engine.attach(gain)
        engine.attach(outputSelector)
        try MatrixMixerConfigurator.setStreamFormats(
            inputSelector,
            input: stereoHardware,
            output: monoHardware
        )
        try SampleRateConverter.setStreamFormats(
            upConverter,
            input: monoHardware,
            output: monoProcessing
        )
        try MatrixMixerConfigurator.setStreamFormats(
            upmixer,
            input: monoProcessing,
            output: stereoProcessing
        )
        try SampleRateConverter.setStreamFormats(
            downConverter,
            input: stereoProcessing,
            output: stereoHardware
        )
        try MatrixMixerConfigurator.setStreamFormats(
            outputSelector,
            input: stereoHardware,
            output: hardwareOutput
        )
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: inputSelector,
            format: stereoHardware,
            operation: "Test hardware capture into input selector"
        )
        try AudioGraphConnector.connect(
            engine,
            from: inputSelector,
            to: upConverter,
            format: monoHardware,
            operation: "Test selected mono into upsampler"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upConverter,
            to: effect,
            format: monoProcessing,
            operation: "Test upsampled Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: effect,
            to: upmixer,
            format: monoProcessing,
            operation: "Test Audio Unit output into processing-rate adapter"
        )
        try AudioGraphConnector.connect(
            engine,
            from: upmixer,
            to: downConverter,
            format: stereoProcessing,
            operation: "Test processing-rate adapter into downsampler"
        )
        try AudioGraphConnector.connect(
            engine,
            from: downConverter,
            to: gain,
            format: stereoHardware,
            operation: "Test downsampled stereo into gain"
        )
        try AudioGraphConnector.connect(
            engine,
            from: gain,
            to: outputSelector,
            format: stereoHardware,
            operation: "Test gain into output selector"
        )
        try AudioGraphConnector.connect(
            engine,
            from: outputSelector,
            to: engine.mainMixerNode,
            format: hardwareOutput,
            operation: "Test output selector into mixer"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try MatrixMixerConfigurator.configure(inputSelector, routes: [(0, 0, 1)])
        try MatrixMixerConfigurator.configure(
            upmixer,
            routes: try ChannelAdapter.routes(from: 1, to: 2)
        )
        try MatrixMixerConfigurator.configure(
            outputSelector,
            routes: [(0, 0, 1), (1, 1, 1)]
        )

        try engine.start()
        try await Task.sleep(for: .milliseconds(50))
        engine.stop()
    }

    @Test @MainActor
    func matrixWithHardwareLayoutFeedsPreparedAppleDelay() async throws {
        let engine = AVAudioEngine()
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let hardware = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let processing = try #require(
            AudioUnitFormatNegotiator.processingFormat(sampleRate: rate, channelCount: 2)
        )
        let source = ProcessingGraphTestSource.make(format: hardware)
        let matrix = try await instantiateMatrixMixer()
        let delay = try await instantiate(
            AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Delay,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
        )
        _ = try AudioUnitFormatNegotiator.prepare(
            delay,
            sourceChannelCount: 2,
            sampleRate: rate,
            displayName: "AUDelay"
        )
        engine.attach(source)
        engine.attach(matrix)
        engine.attach(delay)
        try MatrixMixerConfigurator.setStreamFormats(
            matrix,
            input: hardware,
            output: delay.inputFormat(forBus: 0)
        )
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: matrix,
            format: hardware,
            operation: "Connect hardware-layout source"
        )
        try AudioGraphConnector.connect(
            engine,
            from: matrix,
            to: delay,
            format: delay.inputFormat(forBus: 0),
            operation: "Connect Audio Unit input"
        )
        try AudioGraphConnector.connect(
            engine,
            from: delay,
            to: engine.mainMixerNode,
            format: processing,
            operation: "Connect Audio Unit output"
        )
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        try MatrixMixerConfigurator.configure(matrix, routes: [(0, 0, 1), (1, 1, 1)])
        try engine.start()
        try await Task.sleep(for: .milliseconds(50))
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
