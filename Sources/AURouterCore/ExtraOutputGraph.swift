import AudioToolbox
@preconcurrency import AVFAudio
import AURouterRealtime
import CoreAudio
import Foundation

enum ExtraOutputSinkFactory {
    nonisolated static func make(rings: [AdaptiveAudioRingBuffer]) -> AVAudioSinkNode {
        let storages = rings.map(\.storage)
        return AVAudioSinkNode { _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: audioBufferList)
            )
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                return kAudio_ParamError
            }
            for storage in storages {
                _ = ARStereoRingBufferWrite(storage, left, right, frameCount)
            }
            return noErr
        }
    }
}

final class ExtraOutputGraph: @unchecked Sendable {
    let ring: AdaptiveAudioRingBuffer

    private let engine: AVAudioEngine
    private let matrix: AVAudioUnit
    private let pairs: [ChannelPair]
    private var started = false

    init(
        device: AudioDevice,
        pairs: [ChannelPair],
        processingSampleRate: Double,
        matrix: AVAudioUnit,
        targetLatencyFrames: UInt32
    ) throws {
        let requestedCapacity = max(targetLatencyFrames * 8, 16_384)
        let ring = try AdaptiveAudioRingBuffer(
            capacityFrames: requestedCapacity,
            targetFrames: targetLatencyFrames,
            inputSampleRate: processingSampleRate,
            outputSampleRate: device.nominalSampleRate
        )
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: device.nominalSampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw AURouterError.unavailable("Unable to create an extra output format.")
        }

        let engine = AVAudioEngine()
        let source = CrossDeviceSourceNodeFactory.make(format: sourceFormat, ring: ring)
        let outputNode = engine.outputNode
        try ExtraOutputGraph.setCurrentDevice(device.id, on: outputNode)
        let hardwareOutputFormat = outputNode.inputFormat(forBus: 0)
        guard hardwareOutputFormat.channelCount > 0 else {
            throw AURouterError.unavailable("The extra output device has no active output stream.")
        }

        engine.attach(source)
        engine.attach(matrix)
        try AudioGraphConnector.connect(
            engine,
            from: source,
            to: matrix,
            format: sourceFormat,
            operation: "Connect extra output source"
        )
        try AudioGraphConnector.connect(
            engine,
            from: matrix,
            to: outputNode,
            format: hardwareOutputFormat,
            operation: "Connect extra hardware output"
        )

        self.ring = ring
        self.engine = engine
        self.matrix = matrix
        self.pairs = pairs
    }

    func prepare() throws {
        engine.prepare()
        try MatrixMixerConfigurator.configure(matrix, routes: pairs.flatMap { pair in
            [(0, pair.left, 1), (1, pair.right, 1)]
        })
    }

    func start() throws {
        try engine.start()
        started = true
    }

    func stop() {
        guard started else { return }
        engine.stop()
        started = false
    }

    private static func setCurrentDevice(_ deviceID: AudioDeviceID, on outputNode: AVAudioOutputNode) throws {
        guard let ioUnit = outputNode.audioUnit else {
            throw AURouterError.unavailable("The extra output engine did not create its HAL output unit.")
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
        try AURouterError.check(status, operation: "Select extra Core Audio output device")
    }
}
