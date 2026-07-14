import SwiftUI
import AppKit
import LumaeCore

@main
struct LumaeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updateController = UpdateController()

    var body: some Scene {
        WindowGroup("Lumae") {
            LibraryView()
                .environmentObject(model)
                .environmentObject(updateController)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands { LumaeCommands(model: model, updateController: updateController) }
        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(updateController)
                .frame(width: 720, height: 620)
        }
        MenuBarExtra("Lumae", systemImage: "sparkles.rectangle.stack") {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(updateController)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
}

struct LumaeCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var updateController: UpdateController
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Wallpapers…") { model.presentImporter() }.keyboardShortcut("i", modifiers: [.command])
            Button("Apply Selected Wallpaper") { Task { await model.applySelected() } }
                .keyboardShortcut(.return, modifiers: [.command]).disabled(model.selectedWallpaperID == nil)
        }
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(updateController: updateController)
        }

        CommandMenu("Wallpaper") {
            Button(model.isPaused ? "Resume Playback" : "Pause Playback") { model.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Next in Playlist") { model.advancePlaylist() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
    }
}
