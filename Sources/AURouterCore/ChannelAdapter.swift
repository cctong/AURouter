import Foundation

enum ChannelAdapter {
    static func routes(from inputChannels: Int, to outputChannels: Int) throws -> [(Int, Int, Float)] {
        switch (inputChannels, outputChannels) {
        case (1, 1):
            [(0, 0, 1)]
        case (1, 2):
            [(0, 0, 1), (0, 1, 1)]
        case (2, 1):
            [(0, 0, 0.5), (1, 0, 0.5)]
        case (2, 2):
            [(0, 0, 1), (1, 1, 1)]
        default:
            throw AURouterError.invalidRoute(
                "Only mono and stereo channel adaptation is supported."
            )
        }
    }

    static func inputSelectionRoutes(_ selection: InputChannelSelection) -> [(Int, Int, Float)] {
        switch selection {
        case .mono(let channel):
            [(channel, 0, 1)]
        case .stereo(let pair):
            [(pair.left, 0, 1), (pair.right, 1, 1)]
        }
    }

    static func captureChannelMap(_ selection: InputChannelSelection) -> (left: Int, right: Int) {
        switch selection {
        case .mono(let channel):
            (channel, channel)
        case .stereo(let pair):
            (pair.left, pair.right)
        }
    }
}
