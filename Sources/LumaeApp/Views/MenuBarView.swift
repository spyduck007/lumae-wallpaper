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

        if !model.scenes.isEmpty {
            Menu("Scenes") {
                ForEach(model.scenes) { scene in
                    Button {
                        Task { await model.activateScene(id: scene.id) }
                    } label: {
                        if model.state.activeSceneID == scene.id
                            && !model.activeSceneHasChanges {
                            Label(scene.name, systemImage: "checkmark")
                        } else {
                            Text(scene.name)
                        }
                    }
                }
            }

            Divider()
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
