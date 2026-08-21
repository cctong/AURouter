import SwiftUI

@main
struct AURouterApp: App {
    @StateObject private var viewModel = RouterViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 520, minHeight: 640)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        if viewModel.isPanicMuted { return "speaker.slash.fill" }
        if viewModel.isRunning { return "waveform.circle.fill" }
        return "waveform"
    }
}
