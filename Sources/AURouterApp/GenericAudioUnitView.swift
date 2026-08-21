import AppKit
import AURouterCore
import AVFAudio
import SwiftUI

@MainActor
protocol PlugInVisibilityControlling: AnyObject {
    func setPlugInVisible(_ visible: Bool)
}

@MainActor
final class GenericAudioUnitSession: ObservableObject {
    let rows: [AudioUnitParameterRow]
    @Published var values: [AUParameterAddress: AUValue]
    private let tree: AUParameterTree?
    private let parameters: [AUParameterAddress: AUParameter]
    nonisolated(unsafe) private var observerToken: (AUParameterTree, AUParameterObserverToken)?

    init(unit: AVAudioUnit) {
        let tree = unit.auAudioUnit.parameterTree
        let rows = AudioUnitParameterCatalog.rows(from: tree)
        var parameters: [AUParameterAddress: AUParameter] = [:]
        var values: [AUParameterAddress: AUValue] = [:]
        for row in rows {
            guard let parameter = tree?.parameter(withAddress: row.address) else { continue }
            parameters[row.address] = parameter
            values[row.address] = parameter.value
        }
        self.tree = tree
        self.rows = rows
        self.parameters = parameters
        self.values = values
    }

    deinit {
        stopObserving()
    }

    func startObserving() {
        guard observerToken == nil, let tree else { return }
        resync()
        let token = tree.token(byAddingParameterObserver: { [weak self] address, value in
            Task { @MainActor in
                self?.values[address] = value
            }
        })
        observerToken = (tree, token)
    }

    nonisolated func stopObserving() {
        if let (tree, token) = observerToken {
            tree.removeParameterObserver(token)
            observerToken = nil
        }
    }

    func resync() {
        var next = values
        for (address, parameter) in parameters {
            next[address] = parameter.value
        }
        values = next
    }

    func setValue(_ value: AUValue, for row: AudioUnitParameterRow) {
        let clamped = min(max(value, row.minValue), row.maxValue)
        parameters[row.address]?.setValue(clamped, originator: nil)
        values[row.address] = clamped
    }

    func displayString(for row: AudioUnitParameterRow) -> String {
        guard var current = values[row.address] ?? parameters[row.address]?.value else {
            return ""
        }
        if row.isIndexed {
            let index = Int(current.rounded())
            if row.valueStrings.indices.contains(index) {
                return row.valueStrings[index]
            }
        }
        let formatted = parameters[row.address]?.string(fromValue: &current)
            ?? String(format: "%.2f", current)
        if row.unitName.isEmpty {
            return formatted
        }
        return "\(formatted) \(row.unitName)"
    }
}


struct GenericAudioUnitView: View {
    @ObservedObject var session: GenericAudioUnitSession

    var body: some View {
        if session.rows.isEmpty {
            Text("This Audio Unit has no automatable parameters.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        } else {
            List(session.rows) { row in
                parameterRow(row)
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func parameterRow(_ row: AudioUnitParameterRow) -> some View {
        let value = Binding(
            get: { session.values[row.address] ?? row.minValue },
            set: { session.setValue($0, for: row) }
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.name)
                Spacer()
                Text(session.displayString(for: row))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            if row.isWritable {
                if row.isIndexed {
                    Picker(row.name, selection: indexedBinding(row, value: value)) {
                        ForEach(Array(row.valueStrings.enumerated()), id: \.offset) { index, title in
                            Text(title).tag(index)
                        }
                    }
                    .labelsHidden()
                    .disabled(!row.isWritable)
                } else {
                    Slider(
                        value: value,
                        in: row.minValue...max(row.maxValue, row.minValue)
                    )
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(session.displayString(for: row))
    }

    private func indexedBinding(
        _ row: AudioUnitParameterRow,
        value: Binding<AUValue>
    ) -> Binding<Int> {
        Binding(
            get: {
                let index = Int((session.values[row.address] ?? 0).rounded())
                return min(max(index, 0), max(row.valueStrings.count - 1, 0))
            },
            set: { value.wrappedValue = AUValue($0) }
        )
    }
}

@MainActor
final class GenericAudioUnitHostingController: NSHostingController<GenericAudioUnitView>, PlugInVisibilityControlling {
    private let session: GenericAudioUnitSession

    init(session: GenericAudioUnitSession) {
        self.session = session
        super.init(rootView: GenericAudioUnitView(session: session))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlugInVisible(_ visible: Bool) {
        if visible {
            session.startObserving()
        } else {
            session.stopObserving()
        }
    }
}

enum GenericAudioUnitHost {
    @MainActor
    static func viewController(for unit: AVAudioUnit) -> NSViewController {
        let session = GenericAudioUnitSession(unit: unit)
        let controller = GenericAudioUnitHostingController(session: session)
        controller.title = unit.auAudioUnit.audioUnitName ?? unit.name
        controller.preferredContentSize = NSSize(width: 480, height: 420)
        return controller
    }
}
