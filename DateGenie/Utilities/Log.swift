import Foundation
import os.log

enum Log {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DateGenie", category: "app")

    static func info(_ message: String, _ meta: [String: Any]? = nil) {
        logger.log("\(message, privacy: .public) \(String(describing: meta), privacy: .public)")
    }

    static func warn(_ message: String, _ meta: [String: Any]? = nil) {
        logger.warning("\(message, privacy: .public) \(String(describing: meta), privacy: .public)")
    }

    static func error(_ message: String, _ meta: [String: Any]? = nil) {
        logger.error("\(message, privacy: .public) \(String(describing: meta), privacy: .public)")
    }
}


