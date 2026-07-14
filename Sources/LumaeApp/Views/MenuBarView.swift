import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updateController: UpdateController

    var body: some View {
        Button(model.isPaused ? "Resume Wallpaper Playback" : "Pause Wallpaper Playback") {
            model.togglePause()
        }

        if let playlist = model.activePlaylist {
            Divider()

            Text(playlist.name)

            Button("Previous Wallpaper") {
                model.advanceActivePlaylist(.previous)
            }

            Button(playlist.isRunning ? "Pause Playlist" : "Resume Playlist") {
                model.toggleActivePlaylist()
            }

            Button("Next Wallpaper") {
                model.advanceActivePlaylist(.next)
            }
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
