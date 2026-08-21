import AVFAudio
import Foundation

public enum AudioUnitStateStore {
    public static func snapshot(_ unit: AVAudioUnit) -> Data? {
        let audioUnit = unit.auAudioUnit
        guard let state = audioUnit.fullStateForDocument ?? audioUnit.fullState else {
            return nil
        }
        return try? PropertyListSerialization.data(
            fromPropertyList: state,
            format: .binary,
            options: 0
        )
    }

    public static func apply(_ data: Data, to unit: AVAudioUnit) {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return
        }
        let audioUnit = unit.auAudioUnit
        audioUnit.fullStateForDocument = plist
        audioUnit.fullState = plist
    }
}
