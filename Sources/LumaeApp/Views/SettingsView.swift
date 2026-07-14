import SwiftUI
import AppKit
import LumaeCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            PlaybackSettingsPane()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }
                .tag(SettingsTab.playback)

            LibrarySettingsPane()
                .tabItem { Label("Library", systemImage: "externaldrive") }
                .tag(SettingsTab.library)
        }
        .frame(minWidth: 680, minHeight: 560)
        .onDisappear { model.persistSoon() }
    }
}

enum SettingsTab {
    case general
    case playback
    case library
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPane {
            SettingsSection(
                title: "Startup",
                description: "Choose how Lumae behaves when you sign in and when the app reopens."
            ) {
                SettingsToggleRow(
                    title: "Launch at login",
                    detail: "Start Lumae automatically after you sign in.",
                    isOn: Binding(
                        get: { model.state.settings.launchAtLogin },
                        set: { value in
                            model.state.settings.launchAtLogin = value
                            try? model.launchAtLogin.setEnabled(value)
                            model.persistSoon()
                        }
                    )
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Restore last configuration",
                    detail: "Reapply the most recent wallpaper setup after launch.",
                    isOn: $model.state.settings.restoreLastConfiguration
                )
            }

            SettingsSection(
                title: "Interface",
                description: "Control optional interface and troubleshooting features."
            ) {
                SettingsValueRow(
                    title: "Menu bar control",
                    detail: "Quick access to playback and wallpaper actions.",
                    value: "Always shown"
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Diagnostic logging",
                    detail: "Write additional local logs for troubleshooting. No data is transmitted.",
                    isOn: $model.state.settings.diagnosticLoggingEnabled
                )
            }

            SettingsSection(title: "Status") {
                SettingsValueRow(
                    title: "Launch at login",
                    detail: "macOS may require approval in System Settings.",
                    value: model.launchAtLogin.statusDescription
                )
            }

            SettingsFootnote(
                "Lumae makes no network requests. The update-check preference is stored for future use, but this version does not include an updater."
            )
        }
    }
}

private struct PlaybackSettingsPane: View {
    @EnvironmentObject var model: AppModel
    private let frameRates = [15, 24, 30, 48, 60, 90, 120]

    var body: some View {
        SettingsPane {
            SettingsSection(
                title: "Video",
                description: "Balance visual quality, smoothness, and energy use."
            ) {
                SettingsPickerRow(
                    title: "Default scaling",
                    detail: "How wallpaper content is fitted to a display."
                ) {
                    Picker("Default scaling", selection: $model.state.settings.defaultScalingMode) {
                        ForEach(WallpaperScalingMode.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                SettingsDivider()

                SettingsPickerRow(
                    title: "Playback quality",
                    detail: "Higher quality can increase GPU and energy usage."
                ) {
                    Picker("Playback quality", selection: $model.state.settings.videoQuality) {
                        ForEach(VideoQuality.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                SettingsDivider()

                SettingsPickerRow(
                    title: "Maximum frame rate",
                    detail: "Caps playback when the source or display supports a higher rate."
                ) {
                    Picker("Maximum frame rate", selection: $model.state.settings.maximumFrameRate) {
                        ForEach(frameRates, id: \.self) { rate in
                            Text("\(rate) fps").tag(rate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            SettingsSection(
                title: "Audio",
                description: "Wallpaper audio can be distracting and is muted by default."
            ) {
                SettingsToggleRow(
                    title: "Mute wallpaper audio",
                    detail: "Keep video wallpapers silent.",
                    isOn: Binding(
                        get: { model.state.settings.audioBehavior == .muted },
                        set: { model.state.settings.audioBehavior = $0 ? .muted : .enabled }
                    )
                )
            }

            SettingsSection(
                title: "Power and interruptions",
                description: "Reduce unnecessary playback when your Mac or displays are not actively in use."
            ) {
                SettingsToggleRow(
                    title: "Pause while on battery",
                    detail: "Reduce energy use when disconnected from power.",
                    isOn: $model.state.settings.pauseWhileOnBattery
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Pause in Low Power Mode",
                    detail: "Respect the system Low Power Mode setting.",
                    isOn: $model.state.settings.pauseOnLowPowerMode
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Pause during full-screen apps",
                    detail: "Avoid decoding video behind full-screen content.",
                    isOn: $model.state.settings.pauseDuringFullScreenApps
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Pause when displays sleep",
                    detail: "Stop playback while connected displays are asleep.",
                    isOn: $model.state.settings.pauseWhenDisplaySleeps
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Resume after wake",
                    detail: "Continue playback after the Mac or displays wake.",
                    isOn: $model.state.settings.resumeAfterWake
                )
            }
        }
    }
}

private struct LibrarySettingsPane: View {
    @EnvironmentObject var model: AppModel

    private let cacheSizes: [(label: String, bytes: Int64)] = [
        ("256 MB", 268_435_456),
        ("512 MB", 536_870_912),
        ("1 GB", 1_073_741_824),
        ("2 GB", 2_147_483_648),
        ("5 GB", 5_368_709_120),
        ("10 GB", 10_737_418_240)
    ]

    var body: some View {
        SettingsPane {
            SettingsSection(
                title: "Importing",
                description: "Choose whether Lumae references files in place or keeps its own managed copy."
            ) {
                SettingsPickerRow(
                    title: "Import behavior",
                    detail: "Referencing originals uses no additional storage."
                ) {
                    Picker("Import behavior", selection: $model.state.settings.importBehavior) {
                        Text("Reference originals").tag(ImportBehavior.referenceOriginal)
                        Text("Copy to managed library").tag(ImportBehavior.copyToManagedLibrary)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Managed library location")
                        .font(.body.weight(.medium))

                    Text("Leave blank to use Lumae’s default Application Support folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(
                        "Optional custom folder path",
                        text: Binding(
                            get: { model.state.settings.managedLibraryPath ?? "" },
                            set: { model.state.settings.managedLibraryPath = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }

            SettingsSection(
                title: "Thumbnail cache",
                description: "Lumae stores local previews so large libraries remain responsive."
            ) {
                SettingsPickerRow(
                    title: "Maximum cache size",
                    detail: "Older unused thumbnails are removed first."
                ) {
                    Picker("Maximum cache size", selection: $model.state.settings.thumbnailCacheLimitBytes) {
                        ForEach(cacheSizes, id: \.bytes) { option in
                            Text(option.label).tag(option.bytes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                SettingsDivider()

                SettingsActionRow(
                    title: "Clean thumbnail cache",
                    detail: "Remove cached previews until the configured size limit is met.",
                    buttonTitle: "Clean Cache"
                ) {
                    Task {
                        try? await model.cache.cleanup(
                            limit: model.state.settings.thumbnailCacheLimitBytes
                        )
                    }
                }
            }

            SettingsFootnote(
                "Removing an item from Lumae never deletes its original file. Managed copies also remain until you explicitly remove them in Finder."
            )
        }
    }
}

private struct SettingsPane<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let description: String?
    let content: Content

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    init(title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        SettingsBaseRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct SettingsPickerRow<Accessory: View>: View {
    let title: String
    let detail: String?
    let accessory: Accessory

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        SettingsBaseRow(title: title, detail: detail) {
            accessory
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let detail: String?
    let value: String

    init(title: String, detail: String? = nil, value: String) {
        self.title = title
        self.detail = detail
        self.value = value
    }

    var body: some View {
        SettingsBaseRow(title: title, detail: detail) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 230, alignment: .trailing)
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let detail: String?
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        SettingsBaseRow(title: title, detail: detail) {
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
        }
    }
}

private struct SettingsBaseRow<Accessory: View>: View {
    let title: String
    let detail: String?
    let accessory: Accessory

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}

private struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
