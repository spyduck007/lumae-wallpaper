import Foundation
import LumaeCore

actor JSONStateStore {
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private var stateURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lumae", isDirectory: true).appendingPathComponent("state.json") }
    func load() throws -> PersistedApplicationState { guard FileManager.default.fileExists(atPath: stateURL.path) else { return PersistedApplicationState() }; return try decoder.decode(PersistedApplicationState.self, from: Data(contentsOf: stateURL)) }
    func save(_ state: PersistedApplicationState) throws { try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true); try encoder.encode(state).write(to: stateURL, options: .atomic) }
}
