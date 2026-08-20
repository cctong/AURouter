import AudioToolbox
@preconcurrency import AVFAudio
import Testing
@testable import AURouterCore

@Suite(.serialized)
struct MatrixMixerLifecycleTests {
    @Test @MainActor
    func preparedMatrixMixerExposesDimensionsAndAcceptsLevels() async throws {
        let engine = AVAudioEngine()
        let matrix = try await instantiateMatrixMixer()
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            _ = frameCount
            return noErr
        }
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )

        engine.attach(source)
        engine.attach(matrix)
        engine.connect(source, to: matrix, format: format)
        engine.connect(matrix, to: engine.mainMixerNode, format: format)

        // Matrix dimensions are only published after the engine allocates render resources.
        engine.prepare()
        try MatrixMixerConfigurator.configure(
            matrix,
            routes: [(0, 0, 1), (1, 1, 1)]
        )
    }

    @MainActor
    private func instantiateMatrixMixer() async throws -> AVAudioUnit {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_MatrixMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: .loadInProcess) { unit, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: AURouterError.audioUnit("No matrix mixer instance."))
                }
            }
        }
    }
}
