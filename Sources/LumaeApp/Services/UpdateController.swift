import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    let standardUpdaterController: SPUStandardUpdaterController

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var configurationIssue: String?

    private var canCheckObservation: NSKeyValueObservation?

    init() {
        standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        guard Self.hasConfiguredPublicKey else {
            configurationIssue = "Run scripts/setup-updater.sh once on your Mac, then rebuild Lumae."
            return
        }

        standardUpdaterController.startUpdater()
        observeUpdaterAvailability()
    }

    var updater: SPUUpdater {
        standardUpdaterController.updater
    }

    var isConfigured: Bool {
        configurationIssue == nil
    }

    var currentVersionDescription: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        standardUpdaterController.checkForUpdates(nil)
    }

    private func observeUpdaterAvailability() {
        canCheckObservation = updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.canCheckForUpdates = self.updater.canCheckForUpdates
            }
        }
    }

    private static var hasConfiguredPublicKey: Bool {
        guard let key = Bundle.main.object(
            forInfoDictionaryKey: "SUPublicEDKey"
        ) as? String else {
            return false
        }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("REPLACE_WITH_")
    }
}
