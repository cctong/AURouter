@preconcurrency import AVFAudio
import Foundation

/// Installs callbacks outside AudioRoutingEngine's MainActor isolation.
/// Core Audio invokes these closures on a real-time messenger queue.
enum AudioLevelTap {
    nonisolated static func install(on node: AVAudioNode, storage: AtomicLevel) {
        node.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
            guard let channels = buffer.floatChannelData else {
                storage.store(0)
                return
            }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            var peak: Float = 0
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameCount {
                    let sample = samples[frame]
                    let magnitude = sample < 0 ? -sample : sample
                    if magnitude > peak { peak = magnitude }
                }
            }
            storage.store(min(peak, 1))
        }
    }
}
