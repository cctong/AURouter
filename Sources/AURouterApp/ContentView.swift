import AURouterCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RouterViewModel
    @State private var isSavingProfile = false
    @State private var profileName = ""
    @State private var isAddingEffect = false
    @State private var effectQuery = ""
    var body: some View {
        VStack(spacing: 0) {
            transport
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    inputColumn
                    Divider()
                    outputColumn
                }
                .frame(maxWidth: .infinity)
                Divider()
                chainColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .alert(
            "AURouter",
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
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(viewModel.isRunning ? Color.green : Color.secondary)
                .frame(width: 9, height: 9)
            Text(routeSummary)
                .font(.headline)
                .lineLimit(1)
            Spacer()
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
                        Button("Delete \(profile.name)", role: .destructive) {
                            viewModel.deleteProfile(profile)
                        }
                    }
                }
            }
            Menu {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { viewModel.launchesAtLogin },
                        set: { viewModel.setLaunchesAtLogin($0) }
                    )
                )
            } label: {
                Image(systemName: "gearshape")
            }
            .menuIndicator(.hidden)
            .help("Settings")
            Button("Panic Mute", systemImage: "speaker.slash.fill") {
                viewModel.panicMute()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!viewModel.isRunning)
            Button(viewModel.isRunning ? "Stop" : "Start") {
                viewModel.toggleRouting()
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRunning ? .red : .accentColor)
            .disabled(!viewModel.isRunning && !viewModel.canStart)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var inputColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            columnTitle("Input")
            Picker("Device", selection: $viewModel.selectedInputDeviceUID) {
                ForEach(viewModel.inputDevices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .disabled(viewModel.isRunning)
            Picker("Channels", selection: $viewModel.selectedInputSelectionID) {
                ForEach(viewModel.inputSelections) { selection in
                    Text(selection.displayName).tag(selection.id)
                }
            }
            .disabled(viewModel.isRunning)
            if let device = viewModel.selectedInputDevice {
                formatCaption(device)
            }
            LevelMeter(level: viewModel.inputLevel)
        }
        .padding(16)
    }

    private var outputColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            columnTitle("Output")
            Picker("Device", selection: $viewModel.selectedOutputDeviceUID) {
                ForEach(viewModel.outputDevices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .disabled(viewModel.isRunning)
            ForEach(viewModel.outputDestinations) { destination in
                HStack {
                    Picker("Channels", selection: outputPairBinding(for: destination)) {
                        ForEach(viewModel.outputPairs) { pair in
                            Text(pair.displayName).tag(pair.id)
                        }
                    }
                    .disabled(viewModel.isRunning)
                    if viewModel.outputDestinations.count > 1 {
                        Button(role: .destructive) {
                            viewModel.removeOutputPair(destination.id)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.isRunning)
                    }
                    if destination.id == viewModel.outputDestinations.last?.id {
                        Menu {
                            ForEach(viewModel.unusedOutputPairs) { pair in
                                Button(pair.displayName) {
                                    viewModel.addOutputPair(pair)
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!viewModel.canAddOutputPair)
                    }
                }
            }
            ForEach(viewModel.extraOutputSlots) { slot in
                Divider()
                HStack {
                    Picker("Device", selection: extraDeviceBinding(for: slot)) {
                        ForEach(extraDeviceChoices(for: slot)) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .disabled(viewModel.isRunning)
                    Button(role: .destructive) {
                        viewModel.removeOutputDevice(slot.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isRunning)
                }
                ForEach(slot.pairSlots) { destination in
                    HStack {
                        Picker("Channels", selection: extraPairBinding(for: destination, on: slot)) {
                            ForEach(viewModel.extraOutputPairs(for: slot)) { pair in
                                Text(pair.displayName).tag(pair.id)
                            }
                        }
                        .disabled(viewModel.isRunning)
                        if slot.pairSlots.count > 1 {
                            Button(role: .destructive) {
                                viewModel.removeExtraOutputPair(destination.id, on: slot.id)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.isRunning)
                        }
                        if destination.id == slot.pairSlots.last?.id {
                            Menu {
                                ForEach(viewModel.unusedExtraOutputPairs(for: slot)) { pair in
                                    Button(pair.displayName) {
                                        viewModel.addExtraOutputPair(pair, on: slot.id)
                                    }
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!viewModel.canAddExtraOutputPair(for: slot))
                        }
                    }
                }
            }
            Menu("Add output device") {
                ForEach(viewModel.unusedOutputDevices) { device in
                    Button(device.name) {
                        viewModel.addOutputDevice(device)
                    }
                }
            }
            .disabled(!viewModel.canAddOutputDevice)
            if let device = viewModel.selectedOutputDevice {
                formatCaption(device)
            }
            LevelMeter(level: viewModel.outputLevel)
            HStack {
                Text("Gain")
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.gain, in: 0...2)
                Text(String(format: "%.0f%%", viewModel.gain * 100))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var chainColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            columnTitle("Chain")
            ScrollView {
                VStack(spacing: 0) {
                    GraphPort(title: inputPortTitle, subtitle: inputPortSubtitle)
                    GraphEdge()
                    if viewModel.chain.isEmpty {
                        GraphPort(title: "Dry", subtitle: "no Audio Unit")
                    } else {
                        ForEach(Array(viewModel.chain.enumerated()), id: \.element.id) { index, slot in
                            ChainGraphNode(
                                title: viewModel.effectTitle(for: slot),
                                isRunning: viewModel.isRunning,
                                isFirst: index == 0,
                                isLast: index == viewModel.chain.count - 1,
                                bypass: bypassBinding(for: slot),
                                canOpenUI: viewModel.canOpenPlugInUI(for: slot.id),
                                onOpenUI: { viewModel.openPlugInUI(for: slot.id) },
                                onMoveUp: { viewModel.moveSlot(slot.id, by: -1) },
                                onMoveDown: { viewModel.moveSlot(slot.id, by: 1) },
                                onRemove: { viewModel.removeSlot(slot.id) }
                            )
                            if index < viewModel.chain.count - 1 {
                                GraphEdge()
                            }
                        }
                    }
                    GraphEdge()
                    GraphPort(
                        title: "Gain",
                        subtitle: String(format: "%.0f%%", viewModel.gain * 100)
                    )
                    if graphOutputs.count <= 1 {
                        GraphEdge()
                        if let output = graphOutputs.first {
                            GraphPort(title: output.title, subtitle: output.subtitle)
                        } else {
                            GraphPort(title: "Output", subtitle: nil)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(graphOutputs) { output in
                                VStack(spacing: 0) {
                                    GraphEdge()
                                    GraphPort(title: output.title, subtitle: output.subtitle)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            HStack {
                Button("Add Audio Unit") {
                    effectQuery = ""
                    isAddingEffect = true
                }
                .disabled(!viewModel.canAddEffect)
                .popover(isPresented: $isAddingEffect) {
                    EffectSearchPopover(
                        query: $effectQuery,
                        groups: filteredEffects,
                        onSelect: { effect in
                            viewModel.addEffect(effect)
                            isAddingEffect = false
                        }
                    )
                    .frame(width: 300, height: 360)
                }
                if viewModel.isScanningEffects {
                    ProgressView()
                        .controlSize(.small)
                        .help("Scanning Audio Units in an isolated process")
                }
            }
            Text(clockingCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
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
            return "Select input and output devices."
        }
        if !viewModel.extraOutputSlots.isEmpty {
            return "Split to \(1 + viewModel.extraOutputSlots.count) output devices · \(latencyCaption(input: input, output: output))"
        }
        if input.id == output.id {
            return "Same-device clock · \(Int(output.nominalSampleRate)) Hz"
        }
        return "Adaptive cross-device bridge · \(latencyCaption(input: input, output: output))"
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
    private var graphOutputs: [GraphOutputPort] {
        var ports: [GraphOutputPort] = []
        if let device = viewModel.selectedOutputDevice {
            let pairs = viewModel.selectedOutputPairs
            if pairs.isEmpty {
                ports.append(GraphOutputPort(id: device.uid, title: device.name, subtitle: nil))
            } else {
                for pair in pairs {
                    ports.append(
                        GraphOutputPort(
                            id: "\(device.uid)-\(pair.id)",
                            title: device.name,
                            subtitle: pair.displayName
                        )
                    )
                }
            }
        }
        for slot in viewModel.extraOutputSlots {
            let title = viewModel.outputDevices.first { $0.uid == slot.deviceUID }?.name ?? "Output"
            let pairs = viewModel.extraOutputPairs(for: slot).filter { pair in
                slot.pairSlots.contains { $0.pairID == pair.id }
            }
            if pairs.isEmpty {
                ports.append(GraphOutputPort(id: slot.id.uuidString, title: title, subtitle: nil))
            } else {
                for pair in pairs {
                    ports.append(
                        GraphOutputPort(
                            id: "\(slot.id.uuidString)-\(pair.id)",
                            title: title,
                            subtitle: pair.displayName
                        )
                    )
                }
            }
        }
        return ports
    }

    private var inputPortTitle: String {
        viewModel.selectedInputDevice?.name ?? "Input"
    }

    private var inputPortSubtitle: String? {
        viewModel.inputSelections.first { $0.id == viewModel.selectedInputSelectionID }?.displayName
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



    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func formatCaption(_ device: AudioDevice) -> some View {
        Text("\(Int(device.nominalSampleRate)) Hz · \(device.bufferFrameSize) frames")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func bypassBinding(for slot: EffectChainSlot) -> Binding<Bool> {
        Binding(
            get: { viewModel.chain.first { $0.id == slot.id }?.bypassed ?? false },
            set: { viewModel.setBypassed(slot.id, $0) }
        )
    }
}

private struct GraphOutputPort: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
}

private struct GraphPort: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(dash: [4, 3]))
        )
    }
}

private struct GraphEdge: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.secondary.opacity(0.45))
                .frame(width: 2, height: 12)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }
}

private struct ChainGraphNode: View {
    let title: String
    let isRunning: Bool
    let isFirst: Bool
    let isLast: Bool
    @Binding var bypass: Bool
    let canOpenUI: Bool
    let onOpenUI: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 8) {
                Toggle("Bypass", isOn: $bypass)
                    .disabled(!isRunning)
                Spacer()
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(isRunning || isFirst)
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(isRunning || isLast)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark")
                }
                .disabled(isRunning)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(bypass ? 0.2 : 0.45), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(bypass ? Color.secondary.opacity(0.35) : Color.accentColor.opacity(0.45))
        )
        .opacity(bypass ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if canOpenUI {
                onOpenUI()
            }
        }
        .help("Open Plug-in UI")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the Audio Unit interface")
    }
}

private struct EffectSearchPopover: View {
    @Binding var query: String
    let groups: [(name: String, effects: [AudioEffectDescriptor])]
    let onSelect: (AudioEffectDescriptor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search Audio Units", text: $query)
                .textFieldStyle(.roundedBorder)
            if groups.isEmpty {
                Text("No matching Audio Units.")
                    .foregroundStyle(.secondary)
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
    }
}

struct LevelMeter: View {
    let level: Float
    @State private var peak: Float = 0
    @State private var peakDate: Date = .distantPast

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let held = heldPeak(now: context.date)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(level > 0.9 ? Color.red : level > 0.7 ? Color.yellow : Color.green)
                        .frame(width: geometry.size.width * CGFloat(max(0, min(level, 1))))
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2, height: 10)
                        .offset(x: max(0, geometry.size.width * CGFloat(max(0, min(held, 1))) - 2))
                }
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Audio level")
        .accessibilityValue("\(Int(level * 100)) percent")
        .onChange(of: level) { _, newValue in
            if newValue >= peak {
                peak = newValue
                peakDate = Date()
            }
        }
    }

    private func heldPeak(now: Date) -> Float {
        if level >= peak {
            return level
        }
        let elapsed = now.timeIntervalSince(peakDate)
        if elapsed < 0.8 {
            return peak
        }
        return max(level, peak - Float(elapsed - 0.8) * 1.25)
    }
}
