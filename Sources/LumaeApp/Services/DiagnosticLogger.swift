import Foundation
import os
struct DiagnosticLogger {
    static let shared = DiagnosticLogger(); private let logger = Logger(subsystem: "com.lumae.wallpaper", category: "runtime")
    var enabled = false
    func info(_ message: String) { if enabled { logger.info("\(message, privacy: .public)") } }
    func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}
