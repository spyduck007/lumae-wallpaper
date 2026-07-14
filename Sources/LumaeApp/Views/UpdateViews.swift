import Sparkle
import SwiftUI

struct CheckForUpdatesButton: View {
    @ObservedObject var updateController: UpdateController

    var body: some View {
        Button("Check for Updates…") {
            updateController.checkForUpdates()
        }
        .disabled(
            !updateController.isConfigured
                || !updateController.canCheckForUpdates
        )
    }
}

struct UpdaterSettingsRows: View {
    @ObservedObject private var updateController: UpdateController
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updateController: UpdateController) {
        self.updateController = updateController
        let updater = updateController.updater
        _automaticallyChecksForUpdates = State(
            initialValue: updateController.isConfigured
                ? updater.automaticallyChecksForUpdates
                : false
        )
        _automaticallyDownloadsUpdates = State(
            initialValue: updateController.isConfigured
                ? updater.automaticallyDownloadsUpdates
                : false
        )
    }

    var body: some View {
        SettingsValueRow(
            title: "Installed version",
            detail: "The version currently running from this application bundle.",
            value: updateController.currentVersionDescription
        )

        SettingsDivider()

        SettingsToggleRow(
            title: "Automatically check for updates",
            detail: "Check the signed GitHub Releases feed once per day.",
            isOn: $automaticallyChecksForUpdates
        )
        .disabled(!updateController.isConfigured)
        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
            updateController.updater.automaticallyChecksForUpdates = newValue
        }

        SettingsDivider()

        SettingsToggleRow(
            title: "Automatically download updates",
            detail: "Download verified updates in the background and install them when Lumae quits.",
            isOn: $automaticallyDownloadsUpdates
        )
        .disabled(
            !updateController.isConfigured
                || !automaticallyChecksForUpdates
        )
        .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
            updateController.updater.automaticallyDownloadsUpdates = newValue
        }

        SettingsDivider()

        SettingsActionRow(
            title: "Check now",
            detail: updateController.configurationIssue
                ?? "Ask GitHub Releases whether a newer signed version is available.",
            buttonTitle: "Check for Updates"
        ) {
            updateController.checkForUpdates()
        }
        .disabled(
            !updateController.isConfigured
                || !updateController.canCheckForUpdates
        )
    }
}
