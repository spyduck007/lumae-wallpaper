import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updateController: UpdateController

    var body: some View {
        Button(model.isPaused ? "Resume Playback" : "Pause Playback") {
            model.togglePause()
        }

        Button("Next Wallpaper") {
            model.advancePlaylist()
        }

        Divider()

        Button("Open Lumae") {
            MainWindowLifecycle.show(openWindow: openWindow)
        }

        SettingsLink {
            Text("Settings…")
        }

        CheckForUpdatesButton(updateController: updateController)

        Divider()

        Button("Quit Lumae") {
            NSApp.terminate(nil)
        }
    }
}
