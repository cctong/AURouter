import AppKit
import AURouterCore
@preconcurrency import AVFAudio
@preconcurrency import AVFoundation
import Combine
import CoreAudioKit
import Foundation
import ServiceManagement


struct EffectChainSlot: Identifiable, Hashable {
    let id: UUID
    var effectID: String
    var bypassed: Bool

    init(effectID: String, bypassed: Bool = false) {
        self.id = UUID()
        self.effectID = effectID
        self.bypassed = bypassed
    }
}

struct OutputDestination: Identifiable, Hashable {
    let id: UUID
    var pairID: String

    init(pairID: String) {
        self.id = UUID()
        self.pairID = pairID
    }
}


struct OutputDeviceSlot: Identifiable, Hashable {
    let id: UUID
    var deviceUID: String
    var pairSlots: [OutputDestination]

    init(deviceUID: String, pairIDs: [String] = []) {
        self.id = UUID()
        self.deviceUID = deviceUID
        self.pairSlots = pairIDs.map { OutputDestination(pairID: $0) }
    }
}


@MainActor
final class RouterViewModel: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var effects: [AudioEffectDescriptor] = []
    @Published private(set) var isScanningEffects = false
    @Published var selectedInputDeviceUID = "" {
        didSet { selectDefaultInputSelection() }
    }
    @Published var selectedOutputDeviceUID = "" {
        didSet { selectDefaultOutputPair() }
    }
    @Published var selectedInputSelectionID = "" {
        didSet { persistSession() }
    }
    @Published var outputDestinations: [OutputDestination] = [] {
        didSet { persistSession() }
    }
    @Published var extraOutputSlots: [OutputDeviceSlot] = [] {
        didSet { persistSession() }
    }
    @Published var chain: [EffectChainSlot] = [] {
        didSet { persistSession() }
    }
    @Published var gain: Double = 0 {
        didSet {
            router.setGain(Float(gain))
            persistSession()
        }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var outputLevel: Float = 0
    @Published private(set) var statusMessage = "Select a route, then start monitoring."
    @Published private(set) var errorMessage: String?
    @Published private(set) var profiles: [RoutingProfile] = RoutingProfileStore.load()
    @Published private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled


    private let router = AudioRoutingEngine()
    private var meterTask: Task<Void, Never>?
    private var plugInWindowController: NSWindowController?
    private var plugInSlotID: UUID?
    private var hostedUnits: [UUID: AVAudioUnit] = [:]
    private var hostingTasks: [UUID: Task<AVAudioUnit, Error>] = [:]
    private var sessionToRestore = LastSessionStore.load()
    private var suppressPersistence = false
    private var hardwareObserver: AudioHardwareObserver?
    private var knownDeviceUIDs: Set<String> = []
    private var runningInputRate: Double?
    private var runningOutputRate: Double?
    private var runningOutputUIDs: Set<String> = []
    private var runningOutputRates: [String: Double] = [:]

    var inputDevices: [AudioDevice] {
        devices.filter(\.supportsInputRouting)
    }

    var outputDevices: [AudioDevice] {
        devices.filter(\.supportsOutputRouting)
    }

    var selectedInputDevice: AudioDevice? {
        inputDevices.first { $0.uid == selectedInputDeviceUID }
    }

    var selectedOutputDevice: AudioDevice? {
        outputDevices.first { $0.uid == selectedOutputDeviceUID }
    }

    var inputSelections: [InputChannelSelection] {
        selectedInputDevice?.inputSelections ?? []
    }

    var outputPairs: [ChannelPair] {
        selectedOutputDevice?.outputStereoPairs ?? []
    }

    var canStart: Bool {
        !isBusy
            && selectedInputDevice != nil
            && selectedOutputDevice != nil
            && selectedInputSelection != nil
            && !selectedOutputPairs.isEmpty
            && extraOutputSlots.allSatisfy { slot in
                outputDevices.contains { $0.uid == slot.deviceUID }
                    && slot.pairSlots.contains { destination in
                        extraOutputPairs(for: slot).contains { $0.id == destination.pairID }
                    }
            }
    }

    var canAddOutputPair: Bool {
        !isRunning
            && outputDestinations.count < OutputRoute.maximumPairCount
            && !unusedOutputPairs.isEmpty
    }

    var canAddOutputDevice: Bool {
        !isRunning
            && 1 + extraOutputSlots.count < OutputRoute.maximumDeviceCount
            && !unusedOutputDevices.isEmpty
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            errorMessage = error.localizedDescription
        }
    }


    var unusedOutputDevices: [AudioDevice] {
        let used = Set([selectedOutputDeviceUID] + extraOutputSlots.map(\.deviceUID))
        return outputDevices.filter { !used.contains($0.uid) }
    }

    var selectedOutputPairs: [ChannelPair] {
        outputDestinations.compactMap { destination in
            outputPairs.first { $0.id == destination.pairID }
        }
    }

    var unusedOutputPairs: [ChannelPair] {
        let used = Set(outputDestinations.map(\.pairID))
        return outputPairs.filter { !used.contains($0.id) }
    }

    func extraOutputPairs(for slot: OutputDeviceSlot) -> [ChannelPair] {
        outputDevices.first { $0.uid == slot.deviceUID }?.outputStereoPairs ?? []
    }

    func unusedExtraOutputPairs(for slot: OutputDeviceSlot) -> [ChannelPair] {
        let used = Set(slot.pairSlots.map(\.pairID))
        return extraOutputPairs(for: slot).filter { !used.contains($0.id) }
    }

    func canAddExtraOutputPair(for slot: OutputDeviceSlot) -> Bool {
        !isRunning
            && slot.pairSlots.count < OutputRoute.maximumPairCount
            && !unusedExtraOutputPairs(for: slot).isEmpty
    }

    var canAddEffect: Bool {
        !isRunning && chain.count < EffectChain.maximumLength && !effects.isEmpty
    }

    func canOpenPlugInUI(for slotID: UUID) -> Bool {
        chain.contains { $0.id == slotID }
    }

    func effectTitle(for slot: EffectChainSlot) -> String {
        guard let effect = effects.first(where: { $0.id == slot.effectID }) else {
            return "Missing Audio Unit"
        }
        return "\(effect.manufacturerName) — \(effect.name)"
    }

    init() {
        refreshCatalogs()
        knownDeviceUIDs = Set(devices.map(\.uid))
        hardwareObserver = AudioHardwareObserver { [weak self] in
            Task { @MainActor in
                self?.handleHardwareChange()
            }
        }
        Task { await scanEffectsOutOfProcess() }
    }

    deinit {
        meterTask?.cancel()
        hardwareObserver?.invalidate()
        MainActor.assumeIsolated {
            plugInWindowController?.close()
            plugInWindowController = nil
        }
    }

    func refreshCatalogs() {
        suppressPersistence = true
        defer { suppressPersistence = false }
        do {
            devices = try AudioDeviceCatalog.devices().filter {
                $0.supportsInputRouting || $0.supportsOutputRouting
            }
            if effects.isEmpty {
                effects = AudioEffectCatalog.builtInEffects
            }
            if let session = sessionToRestore {
                applyRestoredSession(session)
            } else {
                if !inputDevices.contains(where: { $0.uid == selectedInputDeviceUID }) {
                    selectedInputDeviceUID = inputDevices.first(where: \.isDefaultInput)?.uid
                        ?? inputDevices.first?.uid
                        ?? ""
                }
                if !outputDevices.contains(where: { $0.uid == selectedOutputDeviceUID }) {
                    selectedOutputDeviceUID = outputDevices.first(where: \.isDefaultOutput)?.uid
                        ?? outputDevices.first?.uid
                        ?? ""
                }
            }
            errorMessage = nil
            if inputDevices.isEmpty || outputDevices.isEmpty {
                statusMessage = "An input device and a stereo output device are required."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleHardwareChange() {
        let listed = try? AudioDeviceCatalog.devices()
        let currentUIDs: Set<String>
        if let listed {
            currentUIDs = Set(listed.map(\.uid))
        } else {
            currentUIDs = knownDeviceUIDs
        }
        let change = AudioHardwareChangeEvaluator.evaluate(
            currentUIDs: currentUIDs,
            runningInputUID: isRunning ? selectedInputDeviceUID : nil,
            runningOutputUID: isRunning ? selectedOutputDeviceUID : nil,
            runningInputRate: isRunning ? runningInputRate : nil,
            runningOutputRate: isRunning ? runningOutputRate : nil,
            currentInputRate: listed?.first { $0.uid == selectedInputDeviceUID }?.nominalSampleRate,
            currentOutputRate: listed?.first { $0.uid == selectedOutputDeviceUID }?.nominalSampleRate,
            runningOutputUIDs: isRunning ? runningOutputUIDs : [],
            runningOutputRates: isRunning ? runningOutputRates : [:],
            currentOutputRates: Dictionary(
                uniqueKeysWithValues: (listed ?? []).compactMap { device in
                    runningOutputUIDs.contains(device.uid) ? (device.uid, device.nominalSampleRate) : nil
                }
            )
        )
        let previousRoutable = knownDeviceUIDs
        switch change {
        case let .stopRoute(message):
            stop()
            refreshCatalogs()
            errorMessage = message
        case .refreshCatalog:
            refreshCatalogs()
            let newRoutable = Set(devices.map(\.uid)).subtracting(previousRoutable)
            if !isRunning,
               !newRoutable.isEmpty,
               !inputDevices.isEmpty,
               !outputDevices.isEmpty {
                statusMessage = "Audio devices updated."
            }
        }
        knownDeviceUIDs = Set(devices.map(\.uid))
    }

    func toggleRouting() {
        if isRunning {
            stop()
        } else {
            Task { await start() }
        }
    }

    func stop() {
        meterTask?.cancel()
        meterTask = nil
        hardwareObserver?.clearSampleRateWatches()
        runningInputRate = nil
        runningOutputRate = nil
        runningOutputUIDs = []
        runningOutputRates = [:]
        router.stop()
        isRunning = false
        inputLevel = 0
        outputLevel = 0
        statusMessage = "Routing stopped."
    }

    func openPlugInUI(for slotID: UUID) {
        Task { await presentPlugInUI(for: slotID) }
    }

    func addEffect(_ descriptor: AudioEffectDescriptor) {
        guard canAddEffect else { return }
        let slot = EffectChainSlot(effectID: descriptor.id)
        chain.append(slot)
        Task { _ = try? await hostedUnit(for: slot.id) }
    }

    func addOutputPair(_ pair: ChannelPair) {
        guard canAddOutputPair else { return }
        outputDestinations.append(OutputDestination(pairID: pair.id))
    }

    func setOutputPair(_ id: UUID, to pair: ChannelPair) {
        guard !isRunning, let index = outputDestinations.firstIndex(where: { $0.id == id }) else { return }
        outputDestinations[index].pairID = pair.id
    }

    func removeOutputPair(_ id: UUID) {
        guard !isRunning, outputDestinations.count > 1 else { return }
        outputDestinations.removeAll { $0.id == id }
    }

    func addOutputDevice(_ device: AudioDevice) {
        guard canAddOutputDevice else { return }
        let firstPair = device.outputStereoPairs.first?.id ?? ""
        extraOutputSlots.append(OutputDeviceSlot(deviceUID: device.uid, pairIDs: firstPair.isEmpty ? [] : [firstPair]))
    }

    func setExtraOutputDevice(_ slotID: UUID, to device: AudioDevice) {
        guard !isRunning, let index = extraOutputSlots.firstIndex(where: { $0.id == slotID }) else { return }
        extraOutputSlots[index].deviceUID = device.uid
        extraOutputSlots[index].pairSlots = device.outputStereoPairs.first.map {
            [OutputDestination(pairID: $0.id)]
        } ?? []
    }

    func addExtraOutputPair(_ pair: ChannelPair, on slotID: UUID) {
        guard let index = extraOutputSlots.firstIndex(where: { $0.id == slotID }),
              canAddExtraOutputPair(for: extraOutputSlots[index]) else { return }
        extraOutputSlots[index].pairSlots.append(OutputDestination(pairID: pair.id))
    }

    func setExtraOutputPair(_ pairID: UUID, on slotID: UUID, to pair: ChannelPair) {
        guard !isRunning,
              let slotIndex = extraOutputSlots.firstIndex(where: { $0.id == slotID }),
              let pairIndex = extraOutputSlots[slotIndex].pairSlots.firstIndex(where: { $0.id == pairID }) else { return }
        extraOutputSlots[slotIndex].pairSlots[pairIndex].pairID = pair.id
    }

    func removeExtraOutputPair(_ pairID: UUID, on slotID: UUID) {
        guard !isRunning,
              let slotIndex = extraOutputSlots.firstIndex(where: { $0.id == slotID }),
              extraOutputSlots[slotIndex].pairSlots.count > 1 else { return }
        extraOutputSlots[slotIndex].pairSlots.removeAll { $0.id == pairID }
    }

    func removeOutputDevice(_ slotID: UUID) {
        guard !isRunning else { return }
        extraOutputSlots.removeAll { $0.id == slotID }
    }



    func removeSlot(_ id: UUID) {
        guard !isRunning else { return }
        if plugInSlotID == id {
            closePlugInUI()
        }
        hostingTasks[id]?.cancel()
        hostingTasks[id] = nil
        hostedUnits[id] = nil
        chain.removeAll { $0.id == id }
    }

    func moveSlot(_ id: UUID, by offset: Int) {
        guard !isRunning, let index = chain.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard chain.indices.contains(destination) else { return }
        chain.swapAt(index, destination)
    }

    func setBypassed(_ id: UUID, _ bypassed: Bool) {
        guard let index = chain.firstIndex(where: { $0.id == id }) else { return }
        chain[index].bypassed = bypassed
        if isRunning {
            router.setEffectBypassed(at: index, bypassed)
        } else {
            hostedUnits[id]?.auAudioUnit.shouldBypassEffect = bypassed
        }
    }

    private func closePlugInUI() {
        plugInWindowController?.close()
        plugInWindowController = nil
        plugInSlotID = nil
    }

    private func presentPlugInUI(for slotID: UUID) async {
        guard chain.contains(where: { $0.id == slotID }) else { return }
        do {
            let unit = try await hostedUnit(for: slotID)
            let unitName = unit.name
            let viewController = await unit.auAudioUnit.requestViewController()
            guard chain.contains(where: { $0.id == slotID }) else { return }
            guard let viewController else {
                errorMessage = "This Audio Unit does not provide a custom interface."
                return
            }
            closePlugInUI()
            let window = NSWindow(contentViewController: viewController)
            window.title = unitName
            window.styleMask.insert(.resizable)
            window.setContentSize(
                NSSize(
                    width: max(viewController.view.fittingSize.width, 480),
                    height: max(viewController.view.fittingSize.height, 320)
                )
            )
            let controller = NSWindowController(window: window)
            plugInWindowController = controller
            plugInSlotID = slotID
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hostedUnit(for slotID: UUID) async throws -> AVAudioUnit {
        if let unit = hostedUnits[slotID] {
            return unit
        }
        if let task = hostingTasks[slotID] {
            return try await task.value
        }
        guard let slot = chain.first(where: { $0.id == slotID }),
              let descriptor = effects.first(where: { $0.id == slot.effectID }) else {
            throw AURouterError.unavailable("The Audio Unit is no longer in the chain.")
        }
        let task = Task { @MainActor in
            try await router.instantiateEffect(descriptor)
        }
        hostingTasks[slotID] = task
        do {
            let unit = try await task.value
            hostedUnits[slotID] = unit
            hostingTasks[slotID] = nil
            unit.auAudioUnit.shouldBypassEffect = slot.bypassed
            return unit
        } catch {
            hostingTasks[slotID] = nil
            throw error
        }
    }

    private func hostChain() {
        let slots = chain
        Task {
            for slot in slots {
                _ = try? await hostedUnit(for: slot.id)
            }
        }
    }

    func panicMute() {
        gain = 0
        statusMessage = "Panic mute engaged."
    }

    func clearError() {
        errorMessage = nil
    }

    private var selectedInputSelection: InputChannelSelection? {
        inputSelections.first { $0.id == selectedInputSelectionID }
    }


    private func start() async {
        guard let inputDevice = selectedInputDevice,
              let inputSelection = selectedInputSelection else { return }


        isBusy = true
        errorMessage = nil
        statusMessage = "Requesting audio input access…"
        defer { isBusy = false }

        guard await requestAudioPermission() else {
            errorMessage = "Audio input permission is required. Enable AURouter in System Settings → Privacy & Security → Microphone."
            statusMessage = "Permission denied."
            return
        }

        do {
            statusMessage = "Building the real-time graph…"
            let outputRoutes = currentOutputRoutes()
            guard let primary = outputRoutes.first,
                  let primaryDevice = outputDevices.first(where: { $0.uid == primary.deviceUID }) else { return }
            let extraDevices = outputRoutes.dropFirst().compactMap { destination in
                outputDevices.first { $0.uid == destination.deviceUID }
            }
            guard extraDevices.count == outputRoutes.count - 1 else { return }
            let route = RouteConfiguration(
                inputDeviceUID: inputDevice.uid,
                inputSelection: inputSelection,
                outputs: outputRoutes
            )
            var routed: [RoutedEffect] = []
            var units: [AVAudioUnit] = []
            for slot in chain {
                guard let descriptor = effects.first(where: { $0.id == slot.effectID }) else { continue }
                routed.append(RoutedEffect(descriptor: descriptor, bypassed: slot.bypassed))
                units.append(try await hostedUnit(for: slot.id))
            }
            try await router.start(
                inputDevice: inputDevice,
                outputDevice: primaryDevice,
                extraOutputDevices: extraDevices,
                route: route,
                effects: routed,
                units: units,
                gain: Float(gain)
            )
            isRunning = true
            runningInputRate = inputDevice.nominalSampleRate
            runningOutputRate = primaryDevice.nominalSampleRate
            runningOutputUIDs = Set(outputRoutes.map(\.deviceUID))
            runningOutputRates = Dictionary(
                uniqueKeysWithValues: ([primaryDevice] + extraDevices).map { ($0.uid, $0.nominalSampleRate) }
            )
            hardwareObserver?.watchSampleRates(
                of: [inputDevice.id, primaryDevice.id] + extraDevices.map(\.id)
            )
            statusMessage = "Live: \(inputDevice.name) → \(outputRoutes.count) outputs"
            startMeterPolling()
        } catch {
            router.stop()
            isRunning = false
            errorMessage = error.localizedDescription
            statusMessage = "Unable to start routing."
        }
    }

    private func requestAudioPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func selectDefaultInputSelection() {
        guard let device = selectedInputDevice else {
            selectedInputSelectionID = ""
            persistSession()
            return
        }
        if !device.inputSelections.contains(where: { $0.id == selectedInputSelectionID }) {
            selectedInputSelectionID = device.inputSelections.first?.id ?? ""
        }
        persistSession()
    }

    private func selectDefaultOutputPair() {
        guard let device = selectedOutputDevice else {
            outputDestinations = []
            extraOutputSlots = []
            persistSession()
            return
        }
        let available = Set(device.outputStereoPairs.map(\.id))
        outputDestinations = outputDestinations.filter { available.contains($0.pairID) }
        if outputDestinations.isEmpty, let first = device.outputStereoPairs.first {
            outputDestinations = [OutputDestination(pairID: first.id)]
        }
        extraOutputSlots = extraOutputSlots.compactMap { slot in
            guard outputDevices.contains(where: { $0.uid == slot.deviceUID }),
                  slot.deviceUID != selectedOutputDeviceUID else { return nil }
            let pairs = extraOutputPairs(for: slot)
            let availableIDs = Set(pairs.map(\.id))
            var filtered = slot
            filtered.pairSlots = slot.pairSlots.filter { availableIDs.contains($0.pairID) }
            if filtered.pairSlots.isEmpty, let first = pairs.first {
                filtered.pairSlots = [OutputDestination(pairID: first.id)]
            }
            return filtered.pairSlots.isEmpty ? nil : filtered
        }
        persistSession()
    }

    private func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.inputLevel = self.router.inputLevel
                self.outputLevel = self.router.outputLevel
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func scanEffectsOutOfProcess() async {
        isScanningEffects = true
        let scanned = await Task.detached(priority: .utility) {
            AudioEffectProcessScanner.scan()
        }.value
        if !scanned.isEmpty {
            effects = scanned
        }
        if let session = sessionToRestore {
            suppressPersistence = true
            let restored = LastSessionRestorer.restore(
                session,
                inputDevices: inputDevices,
                outputDevices: outputDevices,
                effects: effects
            )
            chain = restored.chain.map {
                EffectChainSlot(effectID: $0.effectID, bypassed: $0.bypassed)
            }
            suppressPersistence = false
            sessionToRestore = nil
            hostChain()
        }
        isScanningEffects = false
    }

    private func applyRestoredSession(_ session: LastSession) {
        let restored = LastSessionRestorer.restore(
            session,
            inputDevices: inputDevices,
            outputDevices: outputDevices,
            effects: effects
        )
        selectedInputDeviceUID = restored.inputDeviceUID
        selectedOutputDeviceUID = restored.outputDeviceUID
        selectedInputSelectionID = restored.inputSelectionID
        outputDestinations = restored.outputPairIDs.map { OutputDestination(pairID: $0) }
        extraOutputSlots = restored.outputs.dropFirst().map {
            OutputDeviceSlot(deviceUID: $0.deviceUID, pairIDs: $0.pairIDs)
        }
        chain = restored.chain.map {
            EffectChainSlot(effectID: $0.effectID, bypassed: $0.bypassed)
        }
        gain = restored.gain
        hostChain()
    }

    private func currentOutputRoutes() -> [OutputDeviceRoute] {
        var routes: [OutputDeviceRoute] = []
        if !selectedOutputDeviceUID.isEmpty, !selectedOutputPairs.isEmpty {
            routes.append(
                OutputDeviceRoute(deviceUID: selectedOutputDeviceUID, pairs: selectedOutputPairs)
            )
        }
        for slot in extraOutputSlots {
            let pairs = extraOutputPairs(for: slot).filter { pair in
                slot.pairSlots.contains { $0.pairID == pair.id }
            }
            if !slot.deviceUID.isEmpty, !pairs.isEmpty {
                routes.append(OutputDeviceRoute(deviceUID: slot.deviceUID, pairs: pairs))
            }
        }
        return routes
    }

    func saveProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let session = makeSession() else { return }
        if let index = profiles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            profiles[index].session = session
        } else {
            profiles.append(RoutingProfile(name: trimmed, session: session))
        }
        profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        RoutingProfileStore.save(profiles)
        statusMessage = "Saved profile “\(trimmed)”."
    }

    func loadProfile(_ profile: RoutingProfile) {
        if isRunning {
            stop()
        }
        suppressPersistence = true
        applyRestoredSession(profile.session)
        suppressPersistence = false
        persistSession()
        statusMessage = "Loaded profile “\(profile.name)”."
    }

    func deleteProfile(_ profile: RoutingProfile) {
        profiles.removeAll { $0.id == profile.id }
        RoutingProfileStore.save(profiles)
    }

    private func makeSession() -> LastSession? {
        guard let inputSelection = selectedInputSelection,
              !currentOutputRoutes().isEmpty,
              !selectedInputDeviceUID.isEmpty else { return nil }
        return LastSession(
            route: RouteConfiguration(
                inputDeviceUID: selectedInputDeviceUID,
                inputSelection: inputSelection,
                outputs: currentOutputRoutes()
            ),
            chain: chain.map { PersistedSlot(effectID: $0.effectID, bypassed: $0.bypassed) },
            gain: gain
        )
    }

    private func persistSession() {
        guard !suppressPersistence, let session = makeSession() else { return }
        LastSessionStore.save(session)
    }
}
