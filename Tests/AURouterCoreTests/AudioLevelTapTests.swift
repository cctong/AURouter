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

}
