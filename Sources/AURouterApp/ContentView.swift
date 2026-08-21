import AURouterCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RouterViewModel
    @State private var isSavingProfile = false
    @State private var profileName = ""
    @State private var isAddingEffect = false
    @State private var effectQuery = ""
    @State private var profileToDelete: RoutingProfile?
    @State private var dropTargetID: UUID?


    var body: some View {
        VStack(spacing: 0) {
            transport
            Rectangle()
                .fill(AURouterLook.legend.opacity(0.25))
                .frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    inputModule
                    PatchCord(isLive: viewModel.isRunning)
                    if viewModel.chain.isEmpty {
                        addEffectButton(emptySlot: true)
                    } else {
                        ForEach(Array(viewModel.chain.enumerated()), id: \.element.id) { index, slot in
                            chainSlotView(slot: slot, index: index)
                            if index < viewModel.chain.count - 1 {
                                PatchCord(
                                    isLive: viewModel.isRunning && !slot.bypassed,
                                    isUnplugged: slot.bypassed
                                )
                            }
                        }
                    }
                    PatchCord(
                        isLive: viewModel.isRunning && !(viewModel.chain.last?.bypassed ?? false),
                        isUnplugged: viewModel.chain.last?.bypassed ?? false
                    )
                    gainModule
                    PatchCord(isLive: viewModel.isRunning && !viewModel.isPanicMuted)
                    outputModule
                    if !viewModel.chain.isEmpty {
                        addEffectButton(emptySlot: false)
                            .padding(.top, 12)
                    }
                }
                .padding(16)
            }
        }
        .background(AURouterLook.rack)
        .preferredColorScheme(.dark)
        .alert(
            viewModel.errorTitle,
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .alert("Save Profile", isPresented: $isSavingProfile) {
            TextField("Name", text: $profileName)
            Button("Save") {
                viewModel.saveProfile(named: profileName)
                profileName = ""
            }
            Button("Cancel", role: .cancel) {
                profileName = ""
            }
        }
        .confirmationDialog(
            "Delete Profile?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete “\(profileToDelete?.name ?? "Profile")”", role: .destructive) {
                if let profile = profileToDelete {
                    viewModel.deleteProfile(profile)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear { viewModel.setMeterSurface(.mainWindow, visible: true) }
        .onDisappear { viewModel.setMeterSurface(.mainWindow, visible: false) }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            viewModel.nudgeGain(percentSteps: press.key == .leftArrow ? -1 : 1)
            return .handled
        }
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(transportLED)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(routeSummary)
                        .font(AURouterLook.routeFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(transportCaption)
                        .font(AURouterLook.readoutFont)
                        .foregroundStyle(transportCaptionColor)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if viewModel.isScanningEffects {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AURouterLook.tip)
                        .help("Scanning Audio Units in an isolated process")
                }
                profilesMenu
                panicButton
                startButton
            }
            GainControl(gain: $viewModel.gain, isMuted: viewModel.isPanicMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AURouterLook.rack)
    }

    private var transportLED: Color {
        AURouterLook.statusColor(
            isRunning: viewModel.isRunning,
            isBusy: viewModel.isBusy,
            isMuted: viewModel.isPanicMuted
        )
    }

    private var transportCaption: String {
        if viewModel.isPanicMuted {
            return "Muted. Restore Gain or raise the fader."
        }
        if viewModel.isBusy {
            return viewModel.statusMessage
        }
        if viewModel.isRunning && viewModel.gain == 0 {
            return "Raise gain to hear output."
        }
        if viewModel.isRunning {
            return clockingCaption
        }
        if let reason = viewModel.startBlockedReason {
            return reason
        }
        return clockingCaption
    }

    private var transportCaptionColor: Color {
        if viewModel.isPanicMuted { return AURouterLook.clip }
        if viewModel.isRunning && viewModel.gain == 0 { return AURouterLook.warn }
        if viewModel.isBusy { return AURouterLook.warn }
        return AURouterLook.legend
    }

    private var profilesMenu: some View {
        Menu("Profiles") {
            Button("Save As…") {
                profileName = ""
                isSavingProfile = true
            }
            .disabled(!viewModel.canStart && viewModel.chain.isEmpty)
            if !viewModel.profiles.isEmpty {
                Divider()
                ForEach(viewModel.profiles) { profile in
                    Button(profile.name) {
                        viewModel.loadProfile(profile)
                    }
                }
                Divider()
                ForEach(viewModel.profiles) { profile in
                    Button("Delete \(profile.name)…", role: .destructive) {
                        profileToDelete = profile
                    }
                }
            }
        }
    }

    private var panicButton: some View {
        Button(
            viewModel.isPanicMuted ? "Restore Gain" : "Panic Mute",
            systemImage: viewModel.isPanicMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
        ) {
            viewModel.panicMute()
        }
        .buttonStyle(.bordered)
        .tint(viewModel.isPanicMuted ? AURouterLook.tip : AURouterLook.clip)
        .disabled(!viewModel.canPanic)
        .help(viewModel.isPanicMuted ? "Restore the previous output gain." : "Silence output immediately.")
    }

    private var startButton: some View {
        Button {
            viewModel.toggleRouting()
        } label: {
            if viewModel.isBusy {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AURouterLook.tip)
                    Text("Starting…")
                }
            } else {
                Text(viewModel.isRunning ? "Stop" : "Start")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRunning ? AURouterLook.tip : AURouterLook.face)
        .foregroundStyle(viewModel.isRunning ? AURouterLook.rack : AURouterLook.tip)
        .disabled((!viewModel.isRunning && !viewModel.canStart) || viewModel.isBusy)
        .help(startHelp)
    }

    private var startHelp: String {
        if viewModel.isBusy { return viewModel.statusMessage }
        if viewModel.isRunning { return "Stop the live route." }
        return viewModel.startBlockedReason ?? "Start routing this path."
    }

    private var inputModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INPUT")
                    .font(AURouterLook.legendFont)
                    .foregroundStyle(AURouterLook.legend)
                Spacer()
                if let device = viewModel.selectedInputDevice {
                    formatCaption(device)
                }
            }
            Picker("Device", selection: $viewModel.selectedInputDeviceUID) {
                ForEach(viewModel.inputDevices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .labelsHidden()
            .lockedWhileRunning(viewModel.isRunning)
            Picker("Channels", selection: $viewModel.selectedInputSelectionID) {
                ForEach(viewModel.inputSelections) { selection in
                    Text(selection.displayName).tag(selection.id)
                }
            }
            .labelsHidden()
            .lockedWhileRunning(viewModel.isRunning)
            RouteLevelMeter(meters: viewModel.meters, channel: .input, isLive: viewModel.isRunning)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .patchChrome(isLive: viewModel.isRunning)
    }

    private var gainModule: some View {
        HStack {
            Text("GAIN")
                .font(AURouterLook.legendFont)
                .foregroundStyle(AURouterLook.legend)
            Spacer()
            Text(viewModel.isPanicMuted ? "MUTE" : String(format: "%.0f%%", viewModel.gain * 100))
                .font(AURouterLook.readoutFont)
                .foregroundStyle(viewModel.isPanicMuted ? AURouterLook.clip : AURouterLook.legend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .patchChrome(isLive: viewModel.isRunning, isMuted: viewModel.isPanicMuted)
    }

    private var outputModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OUTPUT")
                    .font(AURouterLook.legendFont)
                    .foregroundStyle(AURouterLook.legend)
                Spacer()
                if let device = viewModel.selectedOutputDevice {
                    formatCaption(device)
                }
            }
            Picker("Device", selection: $viewModel.selectedOutputDeviceUID) {
                ForEach(viewModel.outputDevices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .labelsHidden()
            .lockedWhileRunning(viewModel.isRunning)
            ForEach(viewModel.outputDestinations) { destination in
                pairRow(
                    binding: outputPairBinding(for: destination),
                    pairs: viewModel.outputPairs,
                    canRemove: viewModel.outputDestinations.count > 1,
                    onRemove: { viewModel.removeOutputPair(destination.id) },
                    showsAdd: destination.id == viewModel.outputDestinations.last?.id,
                    unused: viewModel.unusedOutputPairs,
                    canAdd: viewModel.canAddOutputPair,
                    onAdd: { viewModel.addOutputPair($0) }
                )
            }
            ForEach(viewModel.extraOutputSlots) { slot in
                Rectangle()
                    .fill(AURouterLook.legend.opacity(0.2))
                    .frame(height: 1)
                    .padding(.vertical, 2)
                HStack {
                    Picker("Device", selection: extraDeviceBinding(for: slot)) {
                        ForEach(extraDeviceChoices(for: slot)) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .lockedWhileRunning(viewModel.isRunning)
                    Button(role: .destructive) {
                        viewModel.removeOutputDevice(slot.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .lockedWhileRunning(viewModel.isRunning)
                }
                ForEach(slot.pairSlots) { destination in
                    pairRow(
                        binding: extraPairBinding(for: destination, on: slot),
                        pairs: viewModel.extraOutputPairs(for: slot),
                        canRemove: slot.pairSlots.count > 1,
                        onRemove: { viewModel.removeExtraOutputPair(destination.id, on: slot.id) },
                        showsAdd: destination.id == slot.pairSlots.last?.id,
                        unused: viewModel.unusedExtraOutputPairs(for: slot),
                        canAdd: viewModel.canAddExtraOutputPair(for: slot),
                        onAdd: { viewModel.addExtraOutputPair($0, on: slot.id) }
                    )
                }
            }
            Menu("Add output") {
                ForEach(viewModel.unusedOutputDevices) { device in
                    Button(device.name) {
                        viewModel.addOutputDevice(device)
                    }
                }
            }
            .disabled(!viewModel.canAddOutputDevice)
            .help(viewModel.isRunning ? "Stop routing to change devices." : "Route to another output device")
            RouteLevelMeter(meters: viewModel.meters, channel: .output, isLive: viewModel.isRunning)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .patchChrome(isLive: viewModel.isRunning)
    }

    private func pairRow(
        binding: Binding<String>,
        pairs: [ChannelPair],
        canRemove: Bool,
        onRemove: @escaping () -> Void,
        showsAdd: Bool,
        unused: [ChannelPair],
        canAdd: Bool,
        onAdd: @escaping (ChannelPair) -> Void
    ) -> some View {
        HStack {
            Picker("Channels", selection: binding) {
                ForEach(pairs) { pair in
                    Text(pair.displayName).tag(pair.id)
                }
            }
            .labelsHidden()
            .lockedWhileRunning(viewModel.isRunning)
            if canRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .lockedWhileRunning(viewModel.isRunning)
            }
            if showsAdd {
                Menu {
                    ForEach(unused) { pair in
                        Button(pair.displayName) {
                            onAdd(pair)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(!canAdd)
                .help(viewModel.isRunning ? "Stop routing to change devices." : "Add an output pair")
            }
        }
    }

    @ViewBuilder
    private func addEffectButton(emptySlot: Bool) -> some View {
        if emptySlot {
            Button {
                openEffectSearch()
            } label: {
                Text("Add Audio Unit")
                    .font(AURouterLook.legendFont)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AURouterLook.tip)
            .background(AURouterLook.face, in: RoundedRectangle(cornerRadius: AURouterLook.corner))
            .overlay(
                RoundedRectangle(cornerRadius: AURouterLook.corner)
                    .strokeBorder(
                        AURouterLook.tip.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .disabled(!viewModel.canAddEffect)
            .help(viewModel.addEffectBlockedReason ?? "Add an Audio Unit to the chain.")
            .popover(isPresented: $isAddingEffect, arrowEdge: .bottom) {
                effectSearchPopover
            }
        } else {
            Button("Add Audio Unit") {
                openEffectSearch()
            }
            .disabled(!viewModel.canAddEffect)
            .help(viewModel.addEffectBlockedReason ?? "Add an Audio Unit to the chain.")
            .popover(isPresented: $isAddingEffect, arrowEdge: .top) {
                effectSearchPopover
            }
        }
    }

    private func openEffectSearch() {
        effectQuery = ""
        isAddingEffect = true
    }

    private var effectSearchPopover: some View {
        EffectSearchPopover(
            query: $effectQuery,
            groups: filteredEffects,
            onSelect: { effect in
                viewModel.addEffect(effect)
                isAddingEffect = false
            }
        )
        .frame(width: 300, height: 360)
        .preferredColorScheme(.dark)
    }

    private var routeSummary: String {
        let inputName = viewModel.selectedInputDevice?.name ?? "Input"
        let inputChannel = viewModel.inputSelections.first {
            $0.id == viewModel.selectedInputSelectionID
        }?.displayName
        let input = inputChannel.map { "\(inputName) · \($0)" } ?? inputName
        let inserts: String
        switch viewModel.chain.count {
        case 0: inserts = "dry"
        case 1: inserts = "1 AU"
        default: inserts = "\(viewModel.chain.count) AUs"
        }
        let outputName = viewModel.selectedOutputDevice?.name ?? "Output"
        let extraCount = viewModel.extraOutputSlots.count
        let pairNames = viewModel.selectedOutputPairs.map(\.displayName).joined(separator: ", ")
        let extras = extraCount == 0 ? "" : " + \(extraCount) more"
        let output = pairNames.isEmpty ? outputName + extras : "\(outputName) · \(pairNames)\(extras)"
        return "\(input) → \(inserts) → \(output)"
    }

    private var clockingCaption: String {
        guard let input = viewModel.selectedInputDevice,
              let output = viewModel.selectedOutputDevice else {
            return "Choose input and output."
        }
        if !viewModel.extraOutputSlots.isEmpty {
            return "Split to \(1 + viewModel.extraOutputSlots.count) outputs · \(latencyCaption(input: input, output: output))"
        }
        if input.id == output.id {
            return "Same clock · \(Int(output.nominalSampleRate)) Hz"
        }
        return "Different clocks · \(latencyCaption(input: input, output: output))"
    }

    private func latencyCaption(input: AudioDevice, output: AudioDevice) -> String {
        let frames = CrossDeviceBridge.targetLatencyFrames(
            bufferHint: max(input.bufferFrameSize, output.bufferFrameSize)
        )
        let milliseconds = CrossDeviceBridge.latencyMilliseconds(
            frames: frames,
            sampleRate: output.nominalSampleRate
        )
        return "~\(milliseconds) ms"
    }

    private var effectsByManufacturer: [(name: String, effects: [AudioEffectDescriptor])] {
        Dictionary(grouping: viewModel.effects, by: \.manufacturerName)
            .map { manufacturer, effects in
                (
                    name: manufacturer,
                    effects: effects.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filteredEffects: [(name: String, effects: [AudioEffectDescriptor])] {
        let query = effectQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return effectsByManufacturer }
        return effectsByManufacturer.compactMap { group in
            let effects = group.effects.filter {
                $0.name.localizedStandardContains(query)
                    || $0.manufacturerName.localizedStandardContains(query)
            }
            return effects.isEmpty ? nil : (name: group.name, effects: effects)
        }
    }

    private func outputPairBinding(for destination: OutputDestination) -> Binding<String> {
        Binding(
            get: {
                viewModel.outputDestinations.first { $0.id == destination.id }?.pairID ?? destination.pairID
            },
            set: { newID in
                if let pair = viewModel.outputPairs.first(where: { $0.id == newID }) {
                    viewModel.setOutputPair(destination.id, to: pair)
                }
            }
        )
    }

    private func extraDeviceBinding(for slot: OutputDeviceSlot) -> Binding<String> {
        Binding(
            get: {
                viewModel.extraOutputSlots.first { $0.id == slot.id }?.deviceUID ?? slot.deviceUID
            },
            set: { uid in
                if let device = viewModel.outputDevices.first(where: { $0.uid == uid }) {
                    viewModel.setExtraOutputDevice(slot.id, to: device)
                }
            }
        )
    }

    private func extraDeviceChoices(for slot: OutputDeviceSlot) -> [AudioDevice] {
        viewModel.outputDevices.filter { device in
            device.uid == slot.deviceUID
                || viewModel.unusedOutputDevices.contains { $0.uid == device.uid }
        }
    }

    private func extraPairBinding(
        for destination: OutputDestination,
        on slot: OutputDeviceSlot
    ) -> Binding<String> {
        Binding(
            get: {
                viewModel.extraOutputSlots
                    .first { $0.id == slot.id }?
                    .pairSlots
                    .first { $0.id == destination.id }?
                    .pairID ?? destination.pairID
            },
            set: { newID in
                if let pair = viewModel.extraOutputPairs(for: slot).first(where: { $0.id == newID }) {
                    viewModel.setExtraOutputPair(destination.id, on: slot.id, to: pair)
                }
            }
        )
    }

    private func formatCaption(_ device: AudioDevice) -> some View {
        Text("\(Int(device.nominalSampleRate)) Hz · \(device.bufferFrameSize) fr")
            .font(AURouterLook.readoutFont)
            .foregroundStyle(AURouterLook.legend)
    }

    private func bypassBinding(for slot: EffectChainSlot) -> Binding<Bool> {
        Binding(
            get: { viewModel.chain.first { $0.id == slot.id }?.bypassed ?? false },
            set: { viewModel.setBypassed(slot.id, $0) }
        )
    }

    @ViewBuilder
    private func chainSlotView(slot: EffectChainSlot, index: Int) -> some View {
        ChainGraphNode(
            title: viewModel.effectTitle(for: slot),
            isRunning: viewModel.isRunning,
            isDropTarget: dropTargetID == slot.id,
            bypass: bypassBinding(for: slot),
            canOpenUI: viewModel.canOpenPlugInUI(for: slot.id),
            onOpenUI: { viewModel.openPlugInUI(for: slot.id) },
            onRemove: { viewModel.removeSlot(slot.id) }
        )
        .reorderDrag(
            slotID: slot.id,
            title: viewModel.effectTitle(for: slot),
            isEnabled: !viewModel.isRunning,
            targetIndex: index,
            onMove: { viewModel.moveSlot($0, to: $1) },
            isTargeted: { dropTargetID = $0 }
        )
    }
}

private struct ChainGraphNode: View {
    let title: String
    let isRunning: Bool
    let isDropTarget: Bool
    @Binding var bypass: Bool
    let canOpenUI: Bool
    let onOpenUI: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AURouterLook.legend)
                    .help(isRunning ? "Stop to reorder the chain." : "Drag to reorder")
                Text(title)
                    .font(.system(size: 13, weight: .semibold).width(.condensed))
                    .foregroundStyle(bypass ? AURouterLook.legend : Color.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onOpenUI) {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(!canOpenUI)
                .help("Open Plug-in UI")
            }
            HStack(spacing: 8) {
                Toggle("Bypass", isOn: $bypass)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark")
                }
                .disabled(isRunning)
                .help(isRunning ? "Stop to change the chain." : "Remove from chain")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .patchChrome(isLive: isRunning && !bypass)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isDropTarget ? AURouterLook.tip : Color.clear,
                    lineWidth: 1.5
                )
        )
    }
}

private struct EffectSearchPopover: View {
    @Binding var query: String
    let groups: [(name: String, effects: [AudioEffectDescriptor])]
    let onSelect: (AudioEffectDescriptor) -> Void
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search Audio Units", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($queryFocused)
            if groups.isEmpty {
                Text("No matching Audio Units.")
                    .foregroundStyle(AURouterLook.legend)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.effects) { effect in
                                Button(effect.name) {
                                    onSelect(effect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .padding(12)
        .onAppear { queryFocused = true }
    }
}

private extension View {
    func reorderDrag(
        slotID: UUID,
        title: String,
        isEnabled: Bool,
        targetIndex: Int,
        onMove: @escaping (UUID, Int) -> Void,
        isTargeted: @escaping (UUID?) -> Void
    ) -> some View {
        modifier(
            ReorderDragModifier(
                slotID: slotID,
                title: title,
                isEnabled: isEnabled,
                targetIndex: targetIndex,
                onMove: onMove,
                isTargeted: isTargeted
            )
        )
    }
}

private struct ReorderDragModifier: ViewModifier {
    let slotID: UUID
    let title: String
    let isEnabled: Bool
    let targetIndex: Int
    let onMove: (UUID, Int) -> Void
    let isTargeted: (UUID?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(slotID.uuidString) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .padding(10)
                        .background(AURouterLook.face, in: RoundedRectangle(cornerRadius: 6))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let id = UUID(uuidString: raw) else {
                        return false
                    }
                    onMove(id, targetIndex)
                    isTargeted(nil)
                    return true
                } isTargeted: { targeted in
                    isTargeted(targeted ? slotID : nil)
                }
        } else {
            content
        }
    }
}
