import Accelerate
@preconcurrency import AVFAudio
import AURouterRealtime
import Foundation

/// Installs callbacks outside AudioRoutingEngine's MainActor isolation.
/// Core Audio invokes these closures on a real-time messenger queue.
enum AudioLevelTap {
    nonisolated static func install(on node: AVAudioNode, storage: AtomicLevel) {
        node.installTap(onBus: 0, bufferSize: 2_048, format: nil) { buffer, _ in
            guard let channels = buffer.floatChannelData else {
                storage.store(0)
                return
            }
            let frameCount = vDSP_Length(buffer.frameLength)
            guard frameCount > 0 else {
                storage.store(0)
                return
            }
            let channelCount = Int(buffer.format.channelCount)
            var peak: Float = 0
            for channel in 0..<channelCount {
                var channelPeak: Float = 0
                vDSP_maxmgv(channels[channel], 1, &channelPeak, frameCount)
                if channelPeak > peak { peak = channelPeak }
            }
            storage.store(min(peak, 1))
        }
    }

    nonisolated static func remove(from node: AVAudioNode) {
        ARAVAudioNodeRemoveTapSafely(node, 0)
    }

}
