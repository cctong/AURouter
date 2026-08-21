import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: RouterViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.statusMessage)
                    .font(AURouterLook.readoutFont)
                    .foregroundStyle(AURouterLook.legend)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                labeledMeter("IN", channel: .input)
                labeledMeter("OUT", channel: .output)
            }

            GainControl(gain: $viewModel.gain, isMuted: viewModel.isPanicMuted)

            HStack {
                Button(viewModel.isBusy ? "Starting…" : (viewModel.isRunning ? "Stop" : "Start")) {
                    viewModel.toggleRouting()
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRunning ? AURouterLook.tip : AURouterLook.face)
                .foregroundStyle(viewModel.isRunning ? AURouterLook.rack : AURouterLook.tip)
                .disabled((!viewModel.isRunning && !viewModel.canStart) || viewModel.isBusy)
                if viewModel.isPanicMuted {
                    Button("Restore Gain") {
                        viewModel.panicMute()
                    }
                    .tint(AURouterLook.tip)
                } else {
                    Button("Panic Mute", role: .destructive) {
                        viewModel.panicMute()
                    }
                    .tint(AURouterLook.clip)
                    .disabled(!viewModel.canPanic)
                }
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

            Rectangle()
                .fill(AURouterLook.legend.opacity(0.25))
                .frame(height: 1)

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
        .background(AURouterLook.rack)
        .preferredColorScheme(.dark)
        .onAppear { viewModel.setMeterSurface(.menuBar, visible: true) }
        .onDisappear { viewModel.setMeterSurface(.menuBar, visible: false) }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            viewModel.nudgeGain(percentSteps: press.key == .leftArrow ? -1 : 1)
            return .handled
        }
    }

    private var statusColor: Color {
        AURouterLook.statusColor(
            isRunning: viewModel.isRunning,
            isBusy: viewModel.isBusy,
            isMuted: viewModel.isPanicMuted
        )
    }

    private func labeledMeter(_ title: String, channel: RouteLevelMeter.Channel) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AURouterLook.legendFont)
                .foregroundStyle(AURouterLook.legend)
                .frame(width: 28, alignment: .leading)
            RouteLevelMeter(meters: viewModel.meters, channel: channel, isLive: viewModel.isRunning)
        }
    }
}
