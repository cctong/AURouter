@preconcurrency import AVFAudio
import AURouterRealtime
import Foundation

/// Single-producer/single-consumer stereo bridge for independently clocked devices.
/// Storage, interpolation, and drift correction all run in preallocated C memory.
final class AdaptiveAudioRingBuffer: @unchecked Sendable {
    let storage: OpaquePointer

    init(
        capacityFrames: UInt32,
        targetFrames: UInt32,
        inputSampleRate: Double,
        outputSampleRate: Double
    ) throws {
        guard let storage = ARStereoRingBufferCreate(
            capacityFrames,
            targetFrames,
            inputSampleRate,
            outputSampleRate
        ) else {
            throw AURouterError.unavailable("Unable to allocate the cross-device audio buffer.")
        }
        self.storage = storage
    }

    deinit {
        ARStereoRingBufferDestroy(storage)
    }

    func reset() {
        ARStereoRingBufferReset(storage)
    }

    func write(left: [Float], right: [Float]) -> UInt32 {
        let count = min(left.count, right.count)
        return left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ARStereoRingBufferWrite(
                    storage,
                    leftBuffer.baseAddress,
                    rightBuffer.baseAddress,
                    UInt32(count)
                )
            }
        }
    }

    func read(left: inout [Float], right: inout [Float]) -> UInt32 {
        let count = min(left.count, right.count)
        return left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                ARStereoRingBufferRead(
                    storage,
                    leftBuffer.baseAddress,
                    rightBuffer.baseAddress,
                    UInt32(count)
                )
            }
        }
    }

    var availableFrames: UInt32 {
        ARStereoRingBufferAvailableFrames(storage)
    }

    var currentRatio: Double {
        ARStereoRingBufferCurrentRatio(storage)
    }

    var underrunCount: UInt64 {
        ARStereoRingBufferUnderrunCount(storage)
    }

    var overrunCount: UInt64 {
        ARStereoRingBufferOverrunCount(storage)
    }
}

enum CrossDeviceSourceNodeFactory {
    nonisolated static func make(
        format: AVAudioFormat,
        ring: AdaptiveAudioRingBuffer
    ) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                return kAudio_ParamError
            }
            _ = ARStereoRingBufferRead(ring.storage, left, right, frameCount)
            return noErr
        }
    }
}

enum CrossDeviceInputRate {
    static func resolved(captured: Double, catalog: Double) -> Double {
        captured > 0 ? captured : catalog
    }
}

public enum CrossDeviceBridge {
    public static func targetLatencyFrames(bufferHint: UInt32) -> UInt32 {
        max(bufferHint * 8, 2_048)
    }

    public static func latencyMilliseconds(frames: UInt32, sampleRate: Double) -> Int {
        guard sampleRate > 0 else { return 0 }
        return Int((Double(frames) / sampleRate * 1_000).rounded())
    }
}


final class CrossDeviceAudioBridge: @unchecked Sendable {
    let sourceNode: AVAudioSourceNode

    private let ring: AdaptiveAudioRingBuffer
    private let capture: OpaquePointer
    private var started = false

    init(
        inputDevice: AudioDevice,
        inputSelection: InputChannelSelection,
        outputSampleRate: Double,
        targetLatencyFrames: UInt32
    ) throws {
        let requestedCapacity = max(targetLatencyFrames * 8, 16_384)
        let channelMap = ChannelAdapter.captureChannelMap(inputSelection)
        var captureStorage: OpaquePointer?
        let status = ARInputCaptureCreate(
            inputDevice.id,
            UInt32(channelMap.left),
            UInt32(channelMap.right),
            &captureStorage
        )
        try AURouterError.check(status, operation: "Open input device")
        guard let captureStorage else {
            throw AURouterError.unavailable("The input device returned no capture stream.")
        }

        let ring: AdaptiveAudioRingBuffer
        do {
            ring = try AdaptiveAudioRingBuffer(
                capacityFrames: requestedCapacity,
                targetFrames: targetLatencyFrames,
                inputSampleRate: CrossDeviceInputRate.resolved(
                    captured: ARInputCaptureSampleRate(captureStorage),
                    catalog: inputDevice.nominalSampleRate
                ),
                outputSampleRate: outputSampleRate
            )
        } catch {
            ARInputCaptureDestroy(captureStorage)
            throw error
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 2,
            interleaved: false
        ) else {
            ARInputCaptureDestroy(captureStorage)
            throw AURouterError.unavailable("Unable to create the cross-device stereo format.")
        }

        ARInputCaptureSetRing(captureStorage, ring.storage)
        self.ring = ring
        capture = captureStorage
        sourceNode = CrossDeviceSourceNodeFactory.make(format: format, ring: ring)
    }

    deinit {
        ARInputCaptureStop(capture)
        ARInputCaptureDestroy(capture)
    }

    func start() throws {
        try AURouterError.check(ARInputCaptureStart(capture), operation: "Start input device")
        started = true
    }

    func stop() {
        guard started else { return }
        ARInputCaptureStop(capture)
        started = false
    }
}
