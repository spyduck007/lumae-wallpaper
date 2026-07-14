import AppKit
import SwiftUI

@MainActor
enum MainWindowLifecycle {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("com.lumae.wallpaper.main-window")
    static var isTerminating = false

    static func show(openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    static func hideDockAfterMainWindowCloses() {
        guard !isTerminating else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier == windowIdentifier }
    }
}


struct MainWindowLifecycleBridge: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var closeObserver: NSObjectProtocol?

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            detach()

            self.window = window
            window.identifier = MainWindowLifecycle.windowIdentifier

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    MainWindowLifecycle.hideDockAfterMainWindowCloses()
                }
            }
        }

        func detach() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            closeObserver = nil
            window = nil
        }

        deinit {
            detach()
        }
    }
}
