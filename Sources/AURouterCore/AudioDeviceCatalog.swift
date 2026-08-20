import CoreAudio
import Foundation

public enum AudioDeviceCatalog {
    public static func devices() throws -> [AudioDevice] {
        let defaultInput = try? defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let defaultOutput = try? defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let ids: [AudioDeviceID] = try propertyArray(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )

        return try ids.compactMap { id in
            let isAlive: UInt32 = (try? scalarProperty(
                objectID: id,
                selector: kAudioDevicePropertyDeviceIsAlive,
                scope: kAudioObjectPropertyScopeGlobal
            )) ?? 1
            guard isAlive != 0 else { return nil }

            return AudioDevice(
                id: id,
                uid: try stringProperty(id, kAudioDevicePropertyDeviceUID),
                name: try stringProperty(id, kAudioObjectPropertyName),
                manufacturer: (try? stringProperty(id, kAudioObjectPropertyManufacturer)) ?? "Unknown",
                inputChannelCount: try channelCount(deviceID: id, scope: kAudioDevicePropertyScopeInput),
                outputChannelCount: try channelCount(deviceID: id, scope: kAudioDevicePropertyScopeOutput),
                nominalSampleRate: try scalarProperty(
                    objectID: id,
                    selector: kAudioDevicePropertyNominalSampleRate,
                    scope: kAudioObjectPropertyScopeGlobal
                ),
                bufferFrameSize: try scalarProperty(
                    objectID: id,
                    selector: kAudioDevicePropertyBufferFrameSize,
                    scope: kAudioObjectPropertyScopeGlobal
                ),
                isDefaultInput: id == defaultInput,
                isDefaultOutput: id == defaultOutput
            )
        }
        .sorted { lhs, rhs in
            if lhs.supportsRouting != rhs.supportsRouting {
                return lhs.supportsRouting
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func device(uid: String) throws -> AudioDevice? {
        try devices().first { $0.uid == uid }
    }

    private static func defaultDevice(selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
        try scalarProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: selector,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func stringProperty(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        try AURouterError.check(status, operation: "Read Core Audio string property")
        guard let unmanaged else {
            throw AURouterError.unavailable("A Core Audio string property was empty.")
        }
        return unmanaged.takeRetainedValue() as String
    }

    private static func scalarProperty<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        defer { raw.deallocate() }
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, raw)
        try AURouterError.check(status, operation: "Read Core Audio scalar property")
        return raw.load(as: T.self)
    }

    private static func propertyArray<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> [T] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try AURouterError.check(
            AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size),
            operation: "Read Core Audio property size"
        )
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<T>.alignment
        )
        defer { raw.deallocate() }
        try AURouterError.check(
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, raw),
            operation: "Read Core Audio property array"
        )
        return Array(
            UnsafeBufferPointer(start: raw.assumingMemoryBound(to: T.self), count: count)
        )
    }

    private static func channelCount(
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try AURouterError.check(
            AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size),
            operation: "Read device stream configuration size"
        )

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        try AURouterError.check(
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw),
            operation: "Read device stream configuration"
        )
        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
