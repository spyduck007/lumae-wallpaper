import Foundation
import LumaeCore

actor JSONStateStore {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumae", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    func load() throws -> PersistedApplicationState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return PersistedApplicationState()
        }
        let data = try Data(contentsOf: stateURL)
        do {
            return try decoder.decode(PersistedApplicationState.self, from: data)
        } catch {
            // The caller falls back to a blank in-memory state on decode
            // failure, and any subsequent save would otherwise overwrite
            // this file with that blank state, permanently destroying the
            // user's library. Preserve the unreadable file under a
            // separate name so the data isn't silently lost.
            backupUnreadableState(data)
            throw error
        }
    }

    func save(_ state: PersistedApplicationState) throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    private func backupUnreadableState(_ data: Data) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("state.unreadable-\(timestamp).json")
        try? data.write(to: backupURL, options: .atomic)
    }
}
