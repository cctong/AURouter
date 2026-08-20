import SwiftUI

@main
struct AURouterApp: App {
    @StateObject private var viewModel = RouterViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 780, minHeight: 520)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.isRunning ? "waveform.circle.fill" : "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}
