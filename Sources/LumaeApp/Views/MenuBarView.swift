import SwiftUI
struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updateController: UpdateController
    var body: some View {
        Button(model.isPaused ? "Resume Playback" : "Pause Playback") { model.togglePause() }
        Button("Next Wallpaper") { model.advancePlaylist() }
        Divider()
        Button("Open Lumae") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.title == "Lumae" }?.makeKeyAndOrderFront(nil) }
        SettingsLink { Text("Settings…") }
        CheckForUpdatesButton(updateController: updateController)
        Divider()
        Button("Quit Lumae") { NSApp.terminate(nil) }
    }
}
