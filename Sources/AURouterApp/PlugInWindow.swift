import AppKit
import AVFAudio
import CoreAudioKit


@MainActor
final class PlugInWindowController: NSWindowController {
    private var sizeObservation: NSKeyValueObservation?

    convenience init(viewController: NSViewController, title: String, generic: Bool) {
        _ = viewController.view
        viewController.view.layoutSubtreeIfNeeded()
        let window = NSWindow(contentViewController: viewController)
        window.title = title
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)
        self.init(window: window)
        applySize(from: viewController, generic: generic)
        sizeObservation = viewController.observe(\.preferredContentSize, options: [.new]) { [weak self] controller, _ in
            Task { @MainActor in
                self?.applySize(from: controller, generic: generic)
            }
        }
    }

    private func applySize(from viewController: NSViewController, generic: Bool) {
        guard let window else { return }
        let size = Self.resolvedSize(for: viewController, generic: generic)
        window.setContentSize(size)
        if generic {
            window.contentMinSize = NSSize(width: 360, height: 200)
            window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
            return
        }
        window.contentMinSize = size
        let mask = viewController.view.autoresizingMask
        let stretches = mask.contains(.width) && mask.contains(.height)
        window.contentMaxSize = stretches ? NSSize(width: 10_000, height: 10_000) : size
    }

    static func resolvedSize(for viewController: NSViewController, generic: Bool) -> NSSize {
        if generic {
            let preferred = viewController.preferredContentSize
            if preferred.width >= 32, preferred.height >= 32 {
                return preferred
            }
            return NSSize(width: 480, height: 420)
        }
        viewController.view.layoutSubtreeIfNeeded()
        let preferred = viewController.preferredContentSize
        if preferred.width >= 32, preferred.height >= 32 {
            return preferred
        }
        let fitting = viewController.view.fittingSize
        if fitting.width >= 32, fitting.height >= 32 {
            return fitting
        }
        let frame = viewController.view.frame.size
        if frame.width >= 32, frame.height >= 32 {
            return frame
        }
        return NSSize(width: 480, height: 320)
    }

    static func selectViewConfiguration(for audioUnit: AUAudioUnit) {
        let candidates = [
            AUAudioUnitViewConfiguration(width: 0, height: 0, hostHasController: false),
            AUAudioUnitViewConfiguration(width: 800, height: 500, hostHasController: false),
            AUAudioUnitViewConfiguration(width: 400, height: 300, hostHasController: false)
        ]
        let supported = audioUnit.supportedViewConfigurations(candidates)
        if supported.contains(0) {
            audioUnit.select(candidates[0])
        } else if let index = supported.first {
            audioUnit.select(candidates[index])
        }
    }
}
