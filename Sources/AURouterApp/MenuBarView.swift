import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: RouterViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                labeledMeter("In", level: viewModel.inputLevel)
                labeledMeter("Out", level: viewModel.outputLevel)
            }

            HStack {
                Text("Gain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.gain, in: 0...2)
                Text(String(format: "%.0f%%", viewModel.gain * 100))
                    .monospacedDigit()
                    .font(.caption)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack {
                Button(viewModel.isRunning ? "Stop" : "Start") {
                    viewModel.toggleRouting()
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRunning ? .red : .accentColor)
                .disabled(!viewModel.isRunning && !viewModel.canStart)
                Button("Panic Mute", role: .destructive) {
                    viewModel.panicMute()
                }
                .disabled(!viewModel.isRunning)
            }

            if !viewModel.profiles.isEmpty {
                Menu("Profiles") {
                    ForEach(viewModel.profiles) { profile in
                        Button(profile.name) {
                            viewModel.loadProfile(profile)
                        }
                    }
                }
            }

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { viewModel.launchesAtLogin },
                    set: { viewModel.setLaunchesAtLogin($0) }
                )
            )
            .toggleStyle(.switch)

            Divider()

            HStack {
                Button("Show AURouter") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func labeledMeter(_ title: String, level: Float) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            LevelMeter(level: level)
        }
    }
}
