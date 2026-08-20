import AudioToolbox
@preconcurrency import AVFAudio
import CoreAudio
import Foundation

@MainActor
public final class AudioRoutingEngine {
    private var engine: AVAudioEngine?
    private var inputMatrix: AVAudioUnit?
    private var outputMatrix: AVAudioUnit?
    private var gainNode: AVAudioMixerNode?
    private var sourceNode: AVAudioSourceNode?
    private var crossDeviceBridge: CrossDeviceAudioBridge?
    private var extraOutputs: [ExtraOutputGraph] = []
    private var adapterMatrices: [AVAudioUnit] = []
    private let inputMeter = AtomicLevel()
    private let outputMeter = AtomicLevel()

    public private(set) var activeEffects: [AVAudioUnit] = []
    public private(set) var isRunning = false

    public init() {}

    public var inputLevel: Float { inputMeter.load() }
    public var outputLevel: Float { outputMeter.load() }

    public func start(
        inputDevice: AudioDevice,
        outputDevice: AudioDevice,
        extraOutputDevices: [AudioDevice] = [],
        route: RouteConfiguration,
        effects: [RoutedEffect] = [],
        units: [AVAudioUnit] = [],
        gain: Float = 0
    ) async throws {
        stop()
        try route.validate(
            inputDevice: inputDevice,
            outputDevices: [outputDevice] + extraOutputDevices
        )
        try EffectChain.validate(effects)
        if !units.isEmpty, units.count != effects.count {
            throw AURouterError.invalidRoute("Hosted Audio Units do not match the effect chain.")
        }

        if inputDevice.id == outputDevice.id {
            try await startSameDevice(
                device: inputDevice,
                extraOutputDevices: extraOutputDevices,
                route: route,
                effects: effects,
                units: units,
                gain: gain
            )
        } else {
            try await startCrossDevice(
                inputDevice: inputDevice,
                outputDevice: outputDevice,
                extraOutputDevices: extraOutputDevices,
                route: route,
                effects: effects,
                units: units,
                gain: gain
            )
        }
    }

    private func startSameDevice(
        device: AudioDevice,
        extraOutputDevices: [AudioDevice],
        route: RouteConfiguration,
        effects: [RoutedEffect],
        units: [AVAudioUnit],
        gain: Float
    ) async throws {
        let newEngine = AVAudioEngine()
        let inputSelector = try await instantiateMatrixMixer()
        let outputSelector = try await instantiateMatrixMixer()
        let newGainNode = AVAudioMixerNode()
        newGainNode.outputVolume = clampGain(gain)
        var extras: [ExtraOutputGraph] = []
        do {
            let inputNode = newEngine.inputNode
            let outputNode = newEngine.outputNode
            try setCurrentDevice(device.id, on: outputNode)

            let hardwareInputFormat = inputNode.outputFormat(forBus: 0)
            let hardwareOutputFormat = outputNode.inputFormat(forBus: 0)
            guard hardwareInputFormat.channelCount > 0 else {
                throw AURouterError.unavailable("The selected device has no active input stream.")
            }
            guard hardwareOutputFormat.channelCount > 0 else {
                throw AURouterError.unavailable("The selected device has no active output stream.")
            }

            let sampleRate = hardwareOutputFormat.sampleRate
            guard let stereoFormat = AudioUnitFormatNegotiator.processingFormat(
                sampleRate: sampleRate,
                channelCount: 2
            ), let sourceFormat = AudioUnitFormatNegotiator.processingFormat(
                sampleRate: sampleRate,
                channelCount: route.inputSelection.channelCount
            ) else {
                throw AURouterError.unavailable("Unable to create the stereo processing format.")
            }

            let chain = try await prepareEffectChain(
                effects,
                units: units,
                sourceChannelCount: route.inputSelection.channelCount,
                sampleRate: sampleRate
            )
            newEngine.attach(inputSelector)
            newEngine.attach(outputSelector)
            newEngine.attach(newGainNode)
            for item in chain {
                newEngine.attach(item.unit)
            }

            extras = try await makeExtraOutputs(
                route: route,
                extraDevices: extraOutputDevices,
                processingSampleRate: sampleRate,
                bufferHint: device.bufferFrameSize
            )

            try AudioGraphConnector.connect(
                newEngine,
                from: inputNode,
                to: inputSelector,
                fromBus: 0,
                toBus: 0,
                format: hardwareInputFormat,
                operation: "Connect hardware input"
            )

            let adapters = try await connectProcessingChain(
                engine: newEngine,
                source: inputSelector,
                sourceFormat: sourceFormat,
                effects: chain,
                gainNode: newGainNode,
                sampleRate: sampleRate
            )
            try connectGain(
                newGainNode,
                to: outputSelector,
                on: newEngine,
                format: stereoFormat,
                extras: extras
            )
            try AudioGraphConnector.connect(
                newEngine,
                from: outputSelector,
                to: outputNode,
                fromBus: 0,
                toBus: 0,
                format: hardwareOutputFormat,
                operation: "Connect hardware output"
            )

            AudioLevelTap.install(on: inputSelector, storage: inputMeter)
            AudioLevelTap.install(on: newGainNode, storage: outputMeter)
            inputMeter.store(0)
            outputMeter.store(0)

            newEngine.prepare()
            for extra in extras {
                try extra.prepare()
            }

            try MatrixMixerConfigurator.configure(
                inputSelector,
                routes: ChannelAdapter.inputSelectionRoutes(route.inputSelection)
            )
            for adapter in adapters {
                try MatrixMixerConfigurator.configure(adapter.unit, routes: adapter.routes)
            }
            try MatrixMixerConfigurator.configure(
                outputSelector,
                routes: route.outputMatrixRoutes()
            )

            try newEngine.start()
            for extra in extras {
                try extra.start()
            }

            engine = newEngine
            inputMatrix = inputSelector
            outputMatrix = outputSelector
            gainNode = newGainNode
            sourceNode = nil
            crossDeviceBridge = nil
            extraOutputs = extras
            adapterMatrices = adapters.map(\.unit)
            activeEffects = chain.map(\.unit)
            isRunning = true
        } catch {
            extras.forEach { $0.stop() }
            AudioLevelTap.remove(from: inputSelector)
            AudioLevelTap.remove(from: newGainNode)
            newEngine.stop()
            throw error
        }
    }

    private func startCrossDevice(
        inputDevice: AudioDevice,
        outputDevice: AudioDevice,
        extraOutputDevices: [AudioDevice],
        route: RouteConfiguration,
        effects: [RoutedEffect],
        units: [AVAudioUnit],
        gain: Float
    ) async throws {
        let newEngine = AVAudioEngine()
        let outputSelector = try await instantiateMatrixMixer()
        let newGainNode = AVAudioMixerNode()
        newGainNode.outputVolume = clampGain(gain)
        let outputNode = newEngine.outputNode
        try setCurrentDevice(outputDevice.id, on: outputNode)

        let hardwareOutputFormat = outputNode.inputFormat(forBus: 0)
        guard hardwareOutputFormat.channelCount > 0 else {
            throw AURouterError.unavailable("The selected output device has no active output stream.")
        }
        let sampleRate = hardwareOutputFormat.sampleRate
        guard let stereoFormat = AudioUnitFormatNegotiator.processingFormat(
            sampleRate: sampleRate,
            channelCount: 2
        ), let sourceFormat = AudioUnitFormatNegotiator.processingFormat(
            sampleRate: sampleRate,
            channelCount: route.inputSelection.channelCount
        ) else {
            throw AURouterError.unavailable("Unable to create the stereo processing format.")
        }

        let chain = try await prepareEffectChain(
            effects,
            units: units,
            sourceChannelCount: route.inputSelection.channelCount,
            sampleRate: sampleRate
        )

        let targetLatencyFrames = CrossDeviceBridge.targetLatencyFrames(
            bufferHint: max(inputDevice.bufferFrameSize, outputDevice.bufferFrameSize)
        )
        let bridge = try CrossDeviceAudioBridge(
            inputDevice: inputDevice,
            inputSelection: route.inputSelection,
            outputSampleRate: sampleRate,
            targetLatencyFrames: targetLatencyFrames
        )
        let newSourceNode = bridge.sourceNode
        let inputSelector = try await instantiateMatrixMixer()

        newEngine.attach(newSourceNode)
        newEngine.attach(inputSelector)
        newEngine.attach(outputSelector)
        newEngine.attach(newGainNode)
        var extras: [ExtraOutputGraph] = []
        do {
            extras = try await makeExtraOutputs(
                route: route,
                extraDevices: extraOutputDevices,
                processingSampleRate: sampleRate,
                bufferHint: max(inputDevice.bufferFrameSize, outputDevice.bufferFrameSize)
            )
            try AudioGraphConnector.connect(
                newEngine,
                from: newSourceNode,
                to: inputSelector,
                format: stereoFormat,
                operation: "Connect cross-device source"
            )
            let adapters = try await connectProcessingChain(
                engine: newEngine,
                source: inputSelector,
                sourceFormat: sourceFormat,
                effects: chain,
                gainNode: newGainNode,
                sampleRate: sampleRate
            )
            try connectGain(
                newGainNode,
                to: outputSelector,
                on: newEngine,
                format: stereoFormat,
                extras: extras
            )
            try AudioGraphConnector.connect(
                newEngine,
                from: outputSelector,
                to: outputNode,
                fromBus: 0,
                toBus: 0,
                format: hardwareOutputFormat,
                operation: "Connect hardware output"
            )

            AudioLevelTap.install(on: inputSelector, storage: inputMeter)
            AudioLevelTap.install(on: newGainNode, storage: outputMeter)
            inputMeter.store(0)
            outputMeter.store(0)

            newEngine.prepare()
            for extra in extras {
                try extra.prepare()
            }
            let crossInputRoutes: [(Int, Int, Float)] = route.inputSelection.channelCount == 1
                ? [(0, 0, 1)]
                : try ChannelAdapter.routes(from: 2, to: 2)
            try MatrixMixerConfigurator.configure(inputSelector, routes: crossInputRoutes)
            for adapter in adapters {
                try MatrixMixerConfigurator.configure(adapter.unit, routes: adapter.routes)
            }
            try MatrixMixerConfigurator.configure(
                outputSelector,
                routes: route.outputMatrixRoutes()
            )

            try newEngine.start()
            try bridge.start()
            for extra in extras {
                try extra.start()
            }

            engine = newEngine
            inputMatrix = inputSelector
            outputMatrix = outputSelector
            gainNode = newGainNode
            sourceNode = newSourceNode
            crossDeviceBridge = bridge
            extraOutputs = extras
            adapterMatrices = adapters.map(\.unit)
            activeEffects = chain.map(\.unit)
            isRunning = true
        } catch {
            extras.forEach { $0.stop() }
            bridge.stop()
            AudioLevelTap.remove(from: inputSelector)
            AudioLevelTap.remove(from: newGainNode)
            newEngine.stop()
            throw error
        }
    }

    deinit {
        extraOutputs.forEach { $0.stop() }
        crossDeviceBridge?.stop()
        if let inputMatrix { AudioLevelTap.remove(from: inputMatrix) }
        if let gainNode { AudioLevelTap.remove(from: gainNode) }
        engine?.stop()
    }

    public func stop() {
        guard let engine else { return }
        extraOutputs.forEach { $0.stop() }
        extraOutputs = []
        crossDeviceBridge?.stop()
        if let inputMatrix { AudioLevelTap.remove(from: inputMatrix) }
        if let gainNode { AudioLevelTap.remove(from: gainNode) }
        engine.stop()
        self.engine = nil
        inputMatrix = nil
        outputMatrix = nil
        gainNode = nil
        sourceNode = nil
        crossDeviceBridge = nil
        adapterMatrices = []
        activeEffects = []
        isRunning = false
        inputMeter.store(0)
        outputMeter.store(0)
    }

    public func setGain(_ gain: Float) {
        gainNode?.outputVolume = clampGain(gain)
    }

    public func setEffectBypassed(at index: Int, _ bypassed: Bool) {
        guard activeEffects.indices.contains(index) else { return }
        activeEffects[index].auAudioUnit.shouldBypassEffect = bypassed
    }

    private func clampGain(_ gain: Float) -> Float {
        max(0, min(gain, 2))
    }

    private func setCurrentDevice(_ deviceID: AudioDeviceID, on outputNode: AVAudioOutputNode) throws {
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
        try AURouterError.check(status, operation: "Select Core Audio device")
    }

    private func instantiateMatrixMixer() async throws -> AVAudioUnit {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_MatrixMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return try await instantiate(description, options: .loadInProcess)
    }

    private func makeExtraOutputs(
        route: RouteConfiguration,
        extraDevices: [AudioDevice],
        processingSampleRate: Double,
        bufferHint: UInt32
    ) async throws -> [ExtraOutputGraph] {
        let destinations = Array(route.outputs.dropFirst())
        guard destinations.count == extraDevices.count else {
            throw AURouterError.invalidRoute("Output devices do not match the route.")
        }
        var graphs: [ExtraOutputGraph] = []
        let targetLatencyFrames = CrossDeviceBridge.targetLatencyFrames(bufferHint: bufferHint)
        for (destination, device) in zip(destinations, extraDevices) {
            let matrix = try await instantiateMatrixMixer()
            graphs.append(
                try ExtraOutputGraph(
                    device: device,
                    pairs: destination.pairs,
                    processingSampleRate: processingSampleRate,
                    matrix: matrix,
                    targetLatencyFrames: targetLatencyFrames
                )
            )
        }
        return graphs
    }

    private func connectGain(
        _ gain: AVAudioMixerNode,
        to outputSelector: AVAudioUnit,
        on engine: AVAudioEngine,
        format: AVAudioFormat,
        extras: [ExtraOutputGraph]
    ) throws {
        if extras.isEmpty {
            try AudioGraphConnector.connect(
                engine,
                from: gain,
                to: outputSelector,
                format: format,
                operation: "Connect stereo gain stage"
            )
            return
        }
        let sink = ExtraOutputSinkFactory.make(rings: extras.map(\.ring))
        engine.attach(sink)
        try AudioGraphConnector.connect(
            engine,
            from: gain,
            to: [
                AVAudioConnectionPoint(node: outputSelector, bus: 0),
                AVAudioConnectionPoint(node: sink, bus: 0)
            ],
            fromBus: 0,
            format: format,
            operation: "Connect stereo gain split"
        )
    }


    private struct ConfiguredMatrix {
        let unit: AVAudioUnit
        let routes: [(Int, Int, Float)]
    }

    private func prepareEffectChain(
        _ effects: [RoutedEffect],
        units: [AVAudioUnit],
        sourceChannelCount: Int,
        sampleRate: Double
    ) async throws -> [(unit: AVAudioUnit, format: AudioUnitProcessingFormat)] {
        var chain: [(unit: AVAudioUnit, format: AudioUnitProcessingFormat)] = []
        var channels = sourceChannelCount
        for index in effects.indices {
            let effect = effects[index]
            let unit: AVAudioUnit
            if units.indices.contains(index) {
                unit = units[index]
            } else {
                unit = try await instantiateEffect(effect.descriptor)
            }
            let format = try AudioUnitFormatNegotiator.prepare(
                unit,
                sourceChannelCount: channels,
                sampleRate: sampleRate,
                displayName: effect.descriptor.name
            )
            unit.auAudioUnit.shouldBypassEffect = effect.bypassed
            chain.append((unit: unit, format: format))
            channels = format.outputChannels
        }
        return chain
    }

    private func connectProcessingChain(
        engine: AVAudioEngine,
        source: AVAudioNode,
        sourceFormat: AVAudioFormat,
        effects: [(unit: AVAudioUnit, format: AudioUnitProcessingFormat)],
        gainNode: AVAudioMixerNode,
        sampleRate: Double
    ) async throws -> [ConfiguredMatrix] {
        var adapters: [ConfiguredMatrix] = []
        var precedingNode = source
        var precedingChannels = Int(sourceFormat.channelCount)

        for effect in effects {
            if precedingChannels != effect.format.inputChannels {
                let adapter = try await instantiateMatrixMixer()
                engine.attach(adapter)
                let inputFormat = try processingFormat(sampleRate, channels: precedingChannels)
                let outputFormat = try processingFormat(sampleRate, channels: effect.format.inputChannels)
                try AudioGraphConnector.connect(
                    engine,
                    from: precedingNode,
                    to: adapter,
                    format: inputFormat,
                    operation: "Connect pre-effect channel adapter"
                )
                try AudioGraphConnector.connect(
                    engine,
                    from: adapter,
                    to: effect.unit,
                    format: outputFormat,
                    operation: "Connect Audio Unit input"
                )
                adapters.append(
                    ConfiguredMatrix(
                        unit: adapter,
                        routes: try ChannelAdapter.routes(
                            from: precedingChannels,
                            to: effect.format.inputChannels
                        )
                    )
                )
            } else {
                try AudioGraphConnector.connect(
                    engine,
                    from: precedingNode,
                    to: effect.unit,
                    format: try processingFormat(sampleRate, channels: precedingChannels),
                    operation: "Connect Audio Unit input"
                )
            }
            precedingNode = effect.unit
            precedingChannels = effect.format.outputChannels
        }

        if precedingChannels != 2 {
            let adapter = try await instantiateMatrixMixer()
            engine.attach(adapter)
            try AudioGraphConnector.connect(
                engine,
                from: precedingNode,
                to: adapter,
                format: try processingFormat(sampleRate, channels: precedingChannels),
                operation: "Connect post-effect channel adapter"
            )
            try AudioGraphConnector.connect(
                engine,
                from: adapter,
                to: gainNode,
                format: try processingFormat(sampleRate, channels: 2),
                operation: "Connect stereo gain stage"
            )
            adapters.append(
                ConfiguredMatrix(
                    unit: adapter,
                    routes: try ChannelAdapter.routes(from: precedingChannels, to: 2)
                )
            )
        } else {
            try AudioGraphConnector.connect(
                engine,
                from: precedingNode,
                to: gainNode,
                format: try processingFormat(sampleRate, channels: 2),
                operation: "Connect stereo gain stage"
            )
        }
        return adapters
    }

    private func processingFormat(_ sampleRate: Double, channels: Int) throws -> AVAudioFormat {
        guard let format = AudioUnitFormatNegotiator.processingFormat(
            sampleRate: sampleRate,
            channelCount: channels
        ) else {
            throw AURouterError.unavailable("Unable to create the processing format.")
        }
        return format
    }

    public func instantiateEffect(_ effect: AudioEffectDescriptor) async throws -> AVAudioUnit {
        try await instantiate(effect.componentDescription, options: [])
    }

    private func instantiate(
        _ description: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: options) { audioUnit, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let audioUnit {
                    continuation.resume(returning: audioUnit)
                } else {
                    continuation.resume(
                        throwing: AURouterError.audioUnit("The Audio Unit returned no instance.")
                    )
                }
            }
        }
    }

}
