import AppKit
import SwiftUI
import LumaeCore

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updateController: UpdateController

    @State private var switchingSceneID: UUID?

    var body: some View {
        sceneControls

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

    @ViewBuilder
    private var sceneControls: some View {
        if model.scenes.isEmpty {
            Text("No Saved Scenes")
                .foregroundStyle(.secondary)
        } else {
            Menu {
                if let activeScene = model.activeScene {
                    Label(
                        model.activeSceneHasChanges
                            ? "Current: \(activeScene.name) (Modified)"
                            : "Current: \(activeScene.name)",
                        systemImage: model.activeSceneHasChanges
                            ? "pencil.circle"
                            : "checkmark.circle"
                    )
                    .disabled(true)

                    if model.activeSceneHasChanges {
                        Button("Save Current Setup to “\(activeScene.name)”") {
                            model.saveCurrentSetup(toScene: activeScene.id)
                        }
                    }

                    Divider()
                } else {
                    Text("No Active Scene")
                    Divider()
                }

                ForEach(model.scenes) { scene in
                    Button {
                        switchToScene(scene.id)
                    } label: {
                        sceneMenuLabel(scene)
                    }
                    .disabled(
                        switchingSceneID != nil
                            || (model.state.activeSceneID == scene.id
                                && !model.activeSceneHasChanges)
                    )
                }
            } label: {
                Label(sceneMenuTitle, systemImage: "square.stack.3d.up.fill")
            }

            Divider()
        }
    }

    @ViewBuilder
    private func sceneMenuLabel(_ scene: DesktopScene) -> some View {
        let isActive = model.state.activeSceneID == scene.id
        let missingCount = model.sceneMissingWallpaperCount(scene)

        if switchingSceneID == scene.id {
            Label(scene.name, systemImage: "arrow.triangle.2.circlepath")
        } else if isActive && model.activeSceneHasChanges {
            Label(scene.name, systemImage: "pencil.circle.fill")
        } else if isActive {
            Label(scene.name, systemImage: "checkmark")
        } else if missingCount > 0 {
            Label("\(scene.name) — \(missingCount) missing", systemImage: "exclamationmark.triangle")
        } else if model.state.defaultSceneID == scene.id {
            Label(scene.name, systemImage: "star.fill")
        } else {
            Text(scene.name)
        }
    }

    private var sceneMenuTitle: String {
        guard let activeScene = model.activeScene else {
            return "Select Scene"
        }
        return model.activeSceneHasChanges
            ? "\(activeScene.name) — Modified"
            : activeScene.name
    }

    private func switchToScene(_ id: UUID) {
        guard switchingSceneID == nil else { return }
        switchingSceneID = id
        Task {
            await model.activateScene(id: id)
            switchingSceneID = nil
        }
    }
}
