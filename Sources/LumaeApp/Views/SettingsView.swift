import SwiftUI
import LumaeCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = SettingsTab.general
    var body: some View {
        TabView(selection: $tab) {
            Form {
                Toggle("Launch Lumae at login", isOn: Binding(get: { model.state.settings.launchAtLogin }, set: { value in model.state.settings.launchAtLogin = value; try? model.launchAtLogin.setEnabled(value); model.persistSoon() }))
                Toggle("Restore last wallpaper configuration", isOn: $model.state.settings.restoreLastConfiguration)
                Toggle("Show menu bar control", isOn: $model.state.settings.menuBarVisible)
                Toggle("Enable diagnostic logging", isOn: $model.state.settings.diagnosticLoggingEnabled)
                LabeledContent("Launch status", value: model.launchAtLogin.statusDescription)
                Text("Lumae makes no network requests. Update checks are only a stored preference in this version; no updater is included.").font(.caption).foregroundStyle(.secondary)
            }.padding().tabItem { Label("General", systemImage: "gear") }.tag(SettingsTab.general)
            Form {
                Picker("Default scaling", selection: $model.state.settings.defaultScalingMode) { ForEach(WallpaperScalingMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Quality", selection: $model.state.settings.videoQuality) { ForEach(VideoQuality.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Stepper("Maximum frame rate: \(model.state.settings.maximumFrameRate) fps", value: $model.state.settings.maximumFrameRate, in: 15...120, step: 5)
                Toggle("Mute wallpaper audio", isOn: Binding(get: { model.state.settings.audioBehavior == .muted }, set: { model.state.settings.audioBehavior = $0 ? .muted : .enabled }))
                Toggle("Pause while on battery", isOn: $model.state.settings.pauseWhileOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $model.state.settings.pauseOnLowPowerMode)
                Toggle("Pause during full-screen apps", isOn: $model.state.settings.pauseDuringFullScreenApps)
                Toggle("Pause when displays sleep", isOn: $model.state.settings.pauseWhenDisplaySleeps)
                Toggle("Resume after wake", isOn: $model.state.settings.resumeAfterWake)
            }.padding().tabItem { Label("Playback", systemImage: "play.rectangle") }.tag(SettingsTab.playback)
            Form {
                Picker("Import behavior", selection: $model.state.settings.importBehavior) { Text("Reference originals").tag(ImportBehavior.referenceOriginal); Text("Copy to managed library").tag(ImportBehavior.copyToManagedLibrary) }
                TextField("Managed library path (optional)", text: Binding(get: { model.state.settings.managedLibraryPath ?? "" }, set: { model.state.settings.managedLibraryPath = $0.isEmpty ? nil : $0 }))
                Stepper("Thumbnail cache: \(model.state.settings.thumbnailCacheLimitBytes / 1_073_741_824) GB", value: $model.state.settings.thumbnailCacheLimitBytes, in: 268_435_456...10_737_418_240, step: 268_435_456)
                Button("Clean Thumbnail Cache") { Task { try? await model.cache.cleanup(limit: model.state.settings.thumbnailCacheLimitBytes) } }
                Text("Removing an item from Lumae never deletes the original. Managed copies also remain until explicitly removed in Finder.").font(.caption).foregroundStyle(.secondary)
            }.padding().tabItem { Label("Library", systemImage: "externaldrive") }.tag(SettingsTab.library)
        }.onDisappear { model.persistSoon() }
    }
}
enum SettingsTab { case general, playback, library }
