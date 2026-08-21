import SwiftUI

struct RouteMeterLevels: Equatable {
    var input: Float = 0
    var output: Float = 0
}

enum MeterSurface: Hashable {
    case mainWindow
    case menuBar
}

@MainActor
final class RouteMeterState: ObservableObject {
    @Published private(set) var levels = RouteMeterLevels()

    func publish(input: Float, output: Float) {
        let next = RouteMeterLevels(input: input, output: output)
        guard next != levels else { return }
        levels = next
    }

    func reset() {
        publish(input: 0, output: 0)
    }
}

struct RouteLevelMeter: View {
    @ObservedObject var meters: RouteMeterState
    var channel: Channel
    var isLive: Bool = false

    enum Channel {
        case input
        case output
    }

    var body: some View {
        LevelMeter(level: level, isLive: isLive)
    }

    private var level: Float {
        switch channel {
        case .input: meters.levels.input
        case .output: meters.levels.output
        }
    }
}
