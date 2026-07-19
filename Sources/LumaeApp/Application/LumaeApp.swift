import SwiftUI
import AppKit
import LumaeCore

@main
struct LumaeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updateController = UpdateController()

    var body: some Scene {
        Window("Lumae", id: "main") {
            LibraryView()
                .environmentObject(model)
                .environmentObject(updateController)
                .frame(minWidth: 980, minHeight: 640)
                .background(MainWindowLifecycleBridge())
        }
        .commands {
            LumaeCommands(
                model: model,
                updateController: updateController
            )
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(updateController)
                .frame(width: 720, height: 620)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(updateController)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("Lumae")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var backgroundActivityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Lumae has no key window most of the time and often shows a
        // static (audio-less, video-less) wallpaper, which gives macOS no
        // signal that this process is doing meaningful work. Without this,
        // App Nap can throttle the timers that keep widgets updating and
        // the desktop-window watchdog responsive after the app has sat in
        // the background for a while.
        backgroundActivityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Rendering desktop wallpaper and widgets"
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainWindowLifecycle.isTerminating = true
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }
}

struct LumaeCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var updateController: UpdateController

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Wallpapers…") {
                model.presentImporter()
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Apply Selected Wallpaper") {
                Task { await model.applySelected() }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(model.selectedWallpaperID == nil)
        }

        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(updateController: updateController)
        }

        CommandMenu("Wallpaper") {
            Button(model.isPaused ? "Resume Wallpaper Playback" : "Pause Wallpaper Playback") {
                model.togglePause()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Button("Previous in Playlist") {
                model.advanceActivePlaylist(.previous)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(model.activePlaylist == nil)

            Button(model.activePlaylistIsRunning ? "Pause Playlist" : "Resume Playlist") {
                model.toggleActivePlaylist()
            }
            .disabled(model.activePlaylist == nil)

            Button("Next in Playlist") {
                model.advanceActivePlaylist(.next)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(model.activePlaylist == nil)
        }
    }
}
