import Foundation

public struct PersistedSlot: Hashable, Codable, Sendable {
    public var effectID: String
    public var bypassed: Bool
    public var state: Data?

    public init(effectID: String, bypassed: Bool = false, state: Data? = nil) {
        self.effectID = effectID
        self.bypassed = bypassed
        self.state = state
    }
}

public struct LastSession: Hashable, Codable, Sendable {
    public var route: RouteConfiguration
    public var chain: [PersistedSlot]
    public var gain: Double

    public init(route: RouteConfiguration, chain: [PersistedSlot], gain: Double) {
        self.route = route
        self.chain = chain
        self.gain = gain
    }
}

public struct RestoredOutputDestination: Equatable, Sendable {
    public var deviceUID: String
    public var pairIDs: [String]
}

public struct RestoredSession: Equatable, Sendable {
    public var inputDeviceUID: String
    public var inputSelectionID: String
    public var outputs: [RestoredOutputDestination]
    public var chain: [PersistedSlot]
    public var gain: Double

    public var outputDeviceUID: String { outputs.first?.deviceUID ?? "" }
    public var outputPairIDs: [String] { outputs.first?.pairIDs ?? [] }
}

public enum LastSessionStore {
    public static let key = "org.openpatch.AURouter.lastSession"

    public static func load(from defaults: UserDefaults = .standard) -> LastSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LastSession.self, from: data)
    }

    public static func save(_ session: LastSession, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }
}

public struct RoutingProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var session: LastSession

    public init(id: UUID = UUID(), name: String, session: LastSession) {
        self.id = id
        self.name = name
        self.session = session
    }
}

public enum RoutingProfileStore {
    public static let key = "org.openpatch.AURouter.profiles"

    public static func load(from defaults: UserDefaults = .standard) -> [RoutingProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([RoutingProfile].self, from: data) else {
            return []
        }
        return profiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func save(_ profiles: [RoutingProfile], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }
}


public enum LastSessionRestorer {
    public static func restore(
        _ session: LastSession,
        inputDevices: [AudioDevice],
        outputDevices: [AudioDevice],
        effects: [AudioEffectDescriptor]
    ) -> RestoredSession {
        let input = inputDevices.first { $0.uid == session.route.inputDeviceUID }
            ?? inputDevices.first { $0.isDefaultInput }
            ?? inputDevices.first
        let inputSelectionID: String
        if let input, input.uid == session.route.inputDeviceUID,
           input.inputSelections.contains(where: { $0.id == session.route.inputSelection.id }) {
            inputSelectionID = session.route.inputSelection.id
        } else {
            inputSelectionID = input?.inputSelections.first?.id ?? ""
        }

        var restoredOutputs: [RestoredOutputDestination] = []
        for destination in session.route.outputs {
            guard let device = outputDevices.first(where: { $0.uid == destination.deviceUID }) else {
                continue
            }
            let available = Set(device.outputStereoPairs.map(\.id))
            let kept = destination.pairs.map(\.id).filter { available.contains($0) }
            let pairIDs: [String]
            if kept.isEmpty {
                pairIDs = device.outputStereoPairs.first.map { [$0.id] } ?? []
            } else {
                pairIDs = Array(kept.prefix(OutputRoute.maximumPairCount))
            }
            restoredOutputs.append(
                RestoredOutputDestination(deviceUID: device.uid, pairIDs: pairIDs)
            )
        }
        if restoredOutputs.isEmpty,
           let fallback = outputDevices.first(where: \.isDefaultOutput) ?? outputDevices.first {
            restoredOutputs = [
                RestoredOutputDestination(
                    deviceUID: fallback.uid,
                    pairIDs: fallback.outputStereoPairs.first.map { [$0.id] } ?? []
                )
            ]
        }

        let knownEffectIDs = Set(effects.map(\.id))
        let chain = Array(
            session.chain
                .filter { knownEffectIDs.contains($0.effectID) }
                .prefix(EffectChain.maximumLength)
        )

        return RestoredSession(
            inputDeviceUID: input?.uid ?? "",
            inputSelectionID: inputSelectionID,
            outputs: restoredOutputs,
            chain: chain,
            gain: min(2, max(0, session.gain))
        )
    }
}
