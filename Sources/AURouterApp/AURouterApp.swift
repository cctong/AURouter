import SwiftUI

@main
struct AURouterApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            RouterRootView()
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("AURouter", systemImage: "waveform") {
            RouterMenuBarRoot()
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private enum RouterRuntime {
    static let viewModel = RouterViewModel()
}

private struct RouterRootView: View {
    var body: some View {
        HostedContent()
    }
}

private struct HostedContent: View {
    @ObservedObject private var viewModel = RouterRuntime.viewModel

    var body: some View {
        ContentView(viewModel: viewModel)
            .frame(minWidth: 520, minHeight: 640)
    }
}

private struct RouterMenuBarRoot: View {
    var body: some View {
        HostedMenuBar()
    }
}

private struct HostedMenuBar: View {
    @ObservedObject private var viewModel = RouterRuntime.viewModel

    var body: some View {
        MenuBarView(viewModel: viewModel)
    }
}
