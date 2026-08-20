import AudioToolbox
import AVFAudio

public struct AudioUnitParameterRow: Equatable, Identifiable, Sendable {
    public var id: AUParameterAddress { address }
    public let address: AUParameterAddress
    public let name: String
    public let minValue: AUValue
    public let maxValue: AUValue
    public let unitName: String
    public let valueStrings: [String]
    public let isWritable: Bool

    public var isIndexed: Bool { !valueStrings.isEmpty }
}

public enum AudioUnitParameterCatalog {
    public static func rows(from tree: AUParameterTree?) -> [AudioUnitParameterRow] {
        guard let tree else { return [] }
        return tree.children.flatMap { flatten($0, path: []) }
    }

    private static func flatten(_ node: AUParameterNode, path: [String]) -> [AudioUnitParameterRow] {
        if let parameter = node as? AUParameter {
            if parameter.flags.contains(.flag_MeterReadOnly) {
                return []
            }
            let name = (path + [parameter.displayName]).filter { !$0.isEmpty }.joined(separator: " · ")
            return [
                AudioUnitParameterRow(
                    address: parameter.address,
                    name: name.isEmpty ? "Parameter \(parameter.address)" : name,
                    minValue: parameter.minValue,
                    maxValue: parameter.maxValue,
                    unitName: parameter.unitName ?? "",
                    valueStrings: parameter.valueStrings ?? [],
                    isWritable: parameter.flags.contains(.flag_IsWritable)
                )
            ]
        }
        guard let group = node as? AUParameterGroup else { return [] }
        let nextPath = path + [group.displayName].filter { !$0.isEmpty }
        return group.children.flatMap { flatten($0, path: nextPath) }
    }
}
