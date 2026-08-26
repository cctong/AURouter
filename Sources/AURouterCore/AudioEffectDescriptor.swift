import AudioToolbox
import Foundation

public struct AudioEffectDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let componentType: UInt32
    public let componentSubType: UInt32
    public let componentManufacturer: UInt32
    public let name: String
    public let manufacturerName: String

    public var id: String {
        "\(componentType)-\(componentSubType)-\(componentManufacturer)"
    }

    public var componentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    public init(
        componentType: UInt32,
        componentSubType: UInt32,
        componentManufacturer: UInt32,
        name: String,
        manufacturerName: String
    ) {
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.name = name
        self.manufacturerName = manufacturerName
    }
}

public struct RoutedEffect: Hashable, Sendable {
    public var descriptor: AudioEffectDescriptor
    public var bypassed: Bool
    public var state: Data?

    public init(descriptor: AudioEffectDescriptor, bypassed: Bool = false, state: Data? = nil) {
        self.descriptor = descriptor
        self.bypassed = bypassed
        self.state = state
    }
}

public enum EffectChain {
    public static let maximumLength = 8

    public static func validate(_ effects: [RoutedEffect]) throws {
        guard effects.count <= maximumLength else {
            throw AURouterError.invalidRoute(
                "A route can host at most \(maximumLength) Audio Units."
            )
        }
    }
}

public enum AudioEffectCatalog {
    /// A launch-safe fallback that does not ask the component manager to load third-party bundles.
    public static let builtInEffects: [AudioEffectDescriptor] = [
        apple(kAudioUnitSubType_DynamicsProcessor, "AUDynamicsProcessor"),
        apple(kAudioUnitSubType_PeakLimiter, "AUPeakLimiter"),
        apple(kAudioUnitSubType_NBandEQ, "AUNBandEQ"),
        apple(kAudioUnitSubType_Delay, "AUDelay"),
        apple(kAudioUnitSubType_Distortion, "AUDistortion"),
        apple(kAudioUnitSubType_Reverb2, "AUReverb2")
    ]

    public static func parseAUValList(_ output: String) -> [AudioEffectDescriptor] {
        let parsed = output.split(whereSeparator: \.isNewline).compactMap { line -> AudioEffectDescriptor? in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 5,
                  fields[0] == "aufx",
                  let subtype = fourCC(String(fields[1])),
                  let manufacturer = fourCC(String(fields[2])),
                  let dashIndex = fields.firstIndex(of: "-") else {
                return nil
            }

            let description = fields[(dashIndex + 1)...].joined(separator: " ")
            let parts = description.split(separator: ":", maxSplits: 1).map(String.init)
            let manufacturerName = parts.count == 2 ? parts[0] : "Unknown"
            let name = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespaces) : description
            return AudioEffectDescriptor(
                componentType: kAudioUnitType_Effect,
                componentSubType: subtype,
                componentManufacturer: manufacturer,
                name: name,
                manufacturerName: manufacturerName
            )
        }

        return Array(Dictionary(grouping: parsed, by: \.id).compactMap(\.value.first))
            .sorted { lhs, rhs in
                if lhs.manufacturerName != rhs.manufacturerName {
                    return lhs.manufacturerName.localizedStandardCompare(rhs.manufacturerName) == .orderedAscending
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func apple(_ subtype: UInt32, _ name: String) -> AudioEffectDescriptor {
        AudioEffectDescriptor(
            componentType: kAudioUnitType_Effect,
            componentSubType: subtype,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            name: name,
            manufacturerName: "Apple"
        )
    }

    private static func fourCC(_ value: String) -> UInt32? {
        let bytes = Array(value.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
