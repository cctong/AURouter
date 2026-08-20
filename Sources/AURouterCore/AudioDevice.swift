import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let manufacturer: String
    public let inputChannelCount: Int
    public let outputChannelCount: Int
    public let nominalSampleRate: Double
    public let bufferFrameSize: UInt32
    public let isDefaultInput: Bool
    public let isDefaultOutput: Bool

    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        manufacturer: String,
        inputChannelCount: Int,
        outputChannelCount: Int,
        nominalSampleRate: Double,
        bufferFrameSize: UInt32,
        isDefaultInput: Bool,
        isDefaultOutput: Bool
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.manufacturer = manufacturer
        self.inputChannelCount = inputChannelCount
        self.outputChannelCount = outputChannelCount
        self.nominalSampleRate = nominalSampleRate
        self.bufferFrameSize = bufferFrameSize
        self.isDefaultInput = isDefaultInput
        self.isDefaultOutput = isDefaultOutput
    }

    public var supportsRouting: Bool {
        supportsInputRouting && supportsOutputRouting
    }

    public var supportsInputRouting: Bool {
        inputChannelCount >= 1
    }

    public var supportsOutputRouting: Bool {
        outputChannelCount >= 2
    }

    public var inputStereoPairs: [ChannelPair] {
        ChannelPair.available(channelCount: inputChannelCount)
    }

    public var inputSelections: [InputChannelSelection] {
        InputChannelSelection.available(channelCount: inputChannelCount)
    }

    public var outputStereoPairs: [ChannelPair] {
        ChannelPair.available(channelCount: outputChannelCount)
    }
}

public enum InputChannelSelection: Identifiable, Hashable, Codable, Sendable {
    case mono(channel: Int)
    case stereo(pair: ChannelPair)

    public var id: String {
        switch self {
        case .mono(let channel):
            "mono-\(channel)"
        case .stereo(let pair):
            "stereo-\(pair.id)"
        }
    }

    public var displayName: String {
        switch self {
        case .mono(let channel):
            "Channel \(channel + 1) (Mono)"
        case .stereo(let pair):
            "\(pair.displayName) (Stereo)"
        }
    }

    public var channelCount: Int {
        switch self {
        case .mono: 1
        case .stereo: 2
        }
    }

    public var hardwareChannels: [Int] {
        switch self {
        case .mono(let channel): [channel]
        case .stereo(let pair): [pair.left, pair.right]
        }
    }

    public static func available(channelCount: Int) -> [InputChannelSelection] {
        guard channelCount > 0 else { return [] }
        let mono = (0..<channelCount).map { InputChannelSelection.mono(channel: $0) }
        let stereo = ChannelPair.available(channelCount: channelCount).map {
            InputChannelSelection.stereo(pair: $0)
        }
        return mono + stereo
    }
}

public struct ChannelPair: Identifiable, Hashable, Codable, Sendable {
    public let left: Int
    public let right: Int

    public var id: String { "\(left)-\(right)" }
    public var displayName: String { "Channels \(left + 1)–\(right + 1)" }

    public init(left: Int, right: Int) {
        self.left = left
        self.right = right
    }

    public static func available(channelCount: Int) -> [ChannelPair] {
        guard channelCount >= 2 else { return [] }
        return stride(from: 0, to: channelCount - 1, by: 2).map {
            ChannelPair(left: $0, right: $0 + 1)
        }
    }
}

public enum OutputRoute {
    public static let maximumPairCount = 4
    public static let maximumDeviceCount = 4
}

public struct OutputDeviceRoute: Hashable, Codable, Sendable {
    public var deviceUID: String
    public var pairs: [ChannelPair]

    public init(deviceUID: String, pairs: [ChannelPair]) {
        self.deviceUID = deviceUID
        self.pairs = pairs
    }

    public func matrixRoutes() -> [(Int, Int, Float)] {
        pairs.flatMap { pair in
            [(0, pair.left, 1), (1, pair.right, 1)]
        }
    }
}

public struct RouteConfiguration: Hashable, Codable, Sendable {
    public let inputDeviceUID: String
    public let inputSelection: InputChannelSelection
    public let outputs: [OutputDeviceRoute]

    public var outputDeviceUID: String { outputs.first?.deviceUID ?? "" }
    public var outputPairs: [ChannelPair] { outputs.first?.pairs ?? [] }

    public init(
        inputDeviceUID: String,
        inputSelection: InputChannelSelection,
        outputs: [OutputDeviceRoute]
    ) {
        self.inputDeviceUID = inputDeviceUID
        self.inputSelection = inputSelection
        self.outputs = outputs
    }

    public init(
        inputDeviceUID: String,
        outputDeviceUID: String,
        inputSelection: InputChannelSelection,
        outputPairs: [ChannelPair]
    ) {
        self.init(
            inputDeviceUID: inputDeviceUID,
            inputSelection: inputSelection,
            outputs: [OutputDeviceRoute(deviceUID: outputDeviceUID, pairs: outputPairs)]
        )
    }

    public init(
        inputDeviceUID: String,
        outputDeviceUID: String,
        inputSelection: InputChannelSelection,
        outputPair: ChannelPair
    ) {
        self.init(
            inputDeviceUID: inputDeviceUID,
            outputDeviceUID: outputDeviceUID,
            inputSelection: inputSelection,
            outputPairs: [outputPair]
        )
    }

    public init(
        inputDeviceUID: String,
        outputDeviceUID: String,
        inputPair: ChannelPair,
        outputPair: ChannelPair
    ) {
        self.init(
            inputDeviceUID: inputDeviceUID,
            outputDeviceUID: outputDeviceUID,
            inputSelection: .stereo(pair: inputPair),
            outputPairs: [outputPair]
        )
    }

    public func outputMatrixRoutes() -> [(Int, Int, Float)] {
        outputs.first?.matrixRoutes() ?? []
    }

    public func validate(inputDevice: AudioDevice, outputDevice: AudioDevice) throws {
        try validate(inputDevice: inputDevice, outputDevices: [outputDevice])
    }

    public func validate(inputDevice: AudioDevice, outputDevices: [AudioDevice]) throws {
        guard inputDevice.uid == inputDeviceUID else {
            throw AURouterError.invalidRoute("The selected input route belongs to a different device.")
        }
        switch inputSelection {
        case .mono(let channel):
            guard channel >= 0, channel < inputDevice.inputChannelCount else {
                throw AURouterError.invalidRoute("The input channel is unavailable.")
            }
        case .stereo(let pair):
            guard pair.left >= 0,
                  pair.right >= 0,
                  pair.left < inputDevice.inputChannelCount,
                  pair.right < inputDevice.inputChannelCount,
                  pair.left != pair.right else {
                throw AURouterError.invalidRoute("The input channel pair is unavailable.")
            }
        }
        guard !outputs.isEmpty else {
            throw AURouterError.invalidRoute("Select at least one output device.")
        }
        guard outputs.count <= OutputRoute.maximumDeviceCount else {
            throw AURouterError.invalidRoute(
                "A route can host at most \(OutputRoute.maximumDeviceCount) output devices."
            )
        }
        guard outputs.count == outputDevices.count else {
            throw AURouterError.invalidRoute("Output devices do not match the route.")
        }
        let uniqueUIDs = Set(outputs.map(\.deviceUID))
        guard uniqueUIDs.count == outputs.count else {
            throw AURouterError.invalidRoute("Each output device can appear only once.")
        }
        for (destination, device) in zip(outputs, outputDevices) {
            guard device.uid == destination.deviceUID else {
                throw AURouterError.invalidRoute("The selected output route belongs to a different device.")
            }
            guard !destination.pairs.isEmpty else {
                throw AURouterError.invalidRoute("Select at least one output pair.")
            }
            guard destination.pairs.count <= OutputRoute.maximumPairCount else {
                throw AURouterError.invalidRoute(
                    "A route can host at most \(OutputRoute.maximumPairCount) output pairs."
                )
            }
            for pair in destination.pairs {
                guard pair.left >= 0,
                      pair.right >= 0,
                      pair.left < device.outputChannelCount,
                      pair.right < device.outputChannelCount,
                      pair.left != pair.right else {
                    throw AURouterError.invalidRoute("The output channel pair is unavailable.")
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case inputDeviceUID
        case outputDeviceUID
        case inputSelection
        case outputPair
        case outputPairs
        case outputs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputDeviceUID = try container.decode(String.self, forKey: .inputDeviceUID)
        inputSelection = try container.decode(InputChannelSelection.self, forKey: .inputSelection)
        if let outputs = try container.decodeIfPresent([OutputDeviceRoute].self, forKey: .outputs),
           !outputs.isEmpty {
            self.outputs = outputs
        } else {
            let deviceUID = try container.decode(String.self, forKey: .outputDeviceUID)
            let pairs: [ChannelPair]
            if let listed = try container.decodeIfPresent([ChannelPair].self, forKey: .outputPairs),
               !listed.isEmpty {
                pairs = listed
            } else if let pair = try container.decodeIfPresent(ChannelPair.self, forKey: .outputPair) {
                pairs = [pair]
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .outputPairs,
                    in: container,
                    debugDescription: "A route needs at least one output pair."
                )
            }
            outputs = [OutputDeviceRoute(deviceUID: deviceUID, pairs: pairs)]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputDeviceUID, forKey: .inputDeviceUID)
        try container.encode(inputSelection, forKey: .inputSelection)
        try container.encode(outputs, forKey: .outputs)
        try container.encode(outputDeviceUID, forKey: .outputDeviceUID)
        try container.encode(outputPairs, forKey: .outputPairs)
    }
}
