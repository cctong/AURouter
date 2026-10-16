import CoreAudio
import Foundation

public enum AudioHardwareChange: Equatable, Sendable {
    case refreshCatalog
    case stopRoute(String)
    case restartRoute(String)
    case resumeRoute
}

public struct AudioHardwareResumeTarget: Equatable, Sendable {
    public var inputUID: String
    public var outputUIDs: Set<String>
    public var inputRate: Double
    public var outputRates: [String: Double]

    public init(
        inputUID: String,
        outputUIDs: Set<String>,
        inputRate: Double,
        outputRates: [String: Double]
    ) {
        self.inputUID = inputUID
        self.outputUIDs = outputUIDs
        self.inputRate = inputRate
        self.outputRates = outputRates
    }
}

public enum AudioHardwareChangeEvaluator {
    public static func evaluate(
        currentUIDs: Set<String>,
        runningInputUID: String?,
        runningOutputUID: String?,
        runningInputRate: Double? = nil,
        runningOutputRate: Double? = nil,
        currentInputRate: Double? = nil,
        currentOutputRate: Double? = nil,
        runningOutputUIDs: Set<String> = [],
        runningOutputRates: [String: Double] = [:],
        currentOutputRates: [String: Double] = [:],
        pendingResume: AudioHardwareResumeTarget? = nil
    ) -> AudioHardwareChange {
        if let runningInputUID, !currentUIDs.contains(runningInputUID) {
            return .stopRoute("The input device was disconnected.")
        }
        let outputUIDs = runningOutputUIDs.union(Set([runningOutputUID].compactMap { $0 }))
        if outputUIDs.contains(where: { !currentUIDs.contains($0) }) {
            let message = outputUIDs.count > 1
                ? "An output device was disconnected."
                : "The output device was disconnected."
            return .stopRoute(message)
        }
        if let runningInputRate, let currentInputRate,
           abs(runningInputRate - currentInputRate) > 0.5 {
            return .restartRoute("The input device sample rate changed.")
        }
        var previousRates = runningOutputRates
        if previousRates.isEmpty, let uid = runningOutputUID, let rate = runningOutputRate {
            previousRates[uid] = rate
        }
        var currentRates = currentOutputRates
        if let uid = runningOutputUID, let rate = currentOutputRate {
            currentRates[uid] = currentRates[uid] ?? rate
        }
        for (uid, previous) in previousRates {
            if let current = currentRates[uid], abs(previous - current) > 0.5 {
                let message = previousRates.count > 1
                    ? "An output device sample rate changed."
                    : "The output device sample rate changed."
                return .restartRoute(message)
            }
        }
        if let pendingResume, runningInputUID == nil {
            return resumeChange(
                pendingResume,
                currentUIDs: currentUIDs,
                currentInputRate: currentInputRate,
                currentOutputRates: currentRates
            )
        }
        return .refreshCatalog
    }

    private static func resumeChange(
        _ pending: AudioHardwareResumeTarget,
        currentUIDs: Set<String>,
        currentInputRate: Double?,
        currentOutputRates: [String: Double]
    ) -> AudioHardwareChange {
        let required = pending.outputUIDs.union([pending.inputUID])
        guard required.isSubset(of: currentUIDs) else {
            return .refreshCatalog
        }
        guard let currentInputRate, abs(pending.inputRate - currentInputRate) <= 0.5 else {
            return .refreshCatalog
        }
        for (uid, previous) in pending.outputRates {
            guard let current = currentOutputRates[uid], abs(previous - current) <= 0.5 else {
                return .refreshCatalog
            }
        }
        return .resumeRoute
    }
}

public final class AudioHardwareObserver: @unchecked Sendable {
    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var rateAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private let queue = DispatchQueue(label: "org.openpatch.AURouter.hardware")
    private let block: AudioObjectPropertyListenerBlock
    private var registered = false
    private var watchedDeviceIDs: [AudioDeviceID] = []

    public init(onChange: @escaping @Sendable () -> Void) {
        block = { _, _ in onChange() }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            queue,
            block
        )
        registered = status == noErr
    }

    deinit {
        invalidate()
    }

    public func watchSampleRates(of deviceIDs: [AudioDeviceID]) {
        clearSampleRateWatches()
        var seen: Set<AudioDeviceID> = []
        for deviceID in deviceIDs where seen.insert(deviceID).inserted {
            let status = AudioObjectAddPropertyListenerBlock(
                deviceID,
                &rateAddress,
                queue,
                block
            )
            if status == noErr {
                watchedDeviceIDs.append(deviceID)
            }
        }
    }

    public func clearSampleRateWatches() {
        for deviceID in watchedDeviceIDs {
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &rateAddress,
                queue,
                block
            )
        }
        watchedDeviceIDs = []
    }

    public func invalidate() {
        clearSampleRateWatches()
        guard registered else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            queue,
            block
        )
        registered = false
    }
}
