import SwiftUI
import AppKit
import LumaeCore

@main
struct LumaeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Lumae") {
            LibraryView().environmentObject(model).frame(minWidth: 980, minHeight: 640)
        }
        .commands { LumaeCommands(model: model) }
        Settings { SettingsView().environmentObject(model).frame(width: 680, height: 560) }
        MenuBarExtra("Lumae", systemImage: "sparkles.rectangle.stack", isInserted: Binding(get: { model.state.settings.menuBarVisible }, set: { model.state.settings.menuBarVisible = $0; model.persistSoon() })) {
            MenuBarView().environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
}

struct LumaeCommands: Commands {
    @ObservedObject var model: AppModel
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Wallpapers…") { model.presentImporter() }.keyboardShortcut("i", modifiers: [.command])
            Button("Apply Selected Wallpaper") { Task { await model.applySelected() } }
                .keyboardShortcut(.return, modifiers: [.command]).disabled(model.selectedWallpaperID == nil)
        }
        CommandMenu("Wallpaper") {
            Button(model.isPaused ? "Resume Playback" : "Pause Playback") { model.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Next in Playlist") { model.advancePlaylist() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
    }
}
