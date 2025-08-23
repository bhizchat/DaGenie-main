import Foundation
import Combine

final class RunManager: ObservableObject {
    static let shared = RunManager()
    private init() {}

    @Published var currentRunId: String? = nil
    private let storagePrefix = "runId.level."
    private let startAtPrefix = "runStartAt.level."

    private func key(for level: Int) -> String { "\(storagePrefix)\(level)" }
    private func startKey(for level: Int) -> String { "\(startAtPrefix)\(level)" }

    func startNewRun() -> String {
        let id = UUID().uuidString
        currentRunId = id
        return id
    }

    func setRun(_ id: String) {
        currentRunId = id
    }

    // MARK: - Per-level persistence
    @discardableResult
    func startNewRun(level: Int) -> String {
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key(for: level))
        currentRunId = id
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: startKey(for: level))
        return id
    }

    @discardableResult
    func resumeLastRun(level: Int) -> String? {
        if let id = UserDefaults.standard.string(forKey: key(for: level)), !id.isEmpty {
            currentRunId = id
            return id
        }
        return nil
    }

    func clearRun(level: Int) {
        UserDefaults.standard.removeObject(forKey: key(for: level))
        UserDefaults.standard.removeObject(forKey: startKey(for: level))
        currentRunId = nil
    }

    // MARK: - Unified cancellation
    /// Cancels the current run for the given level by deleting any persisted node
    /// documents and clearing the stored runId. Completion is always invoked on the
    /// main thread.
    func cancelCurrentRun(level: Int, completion: ((Bool) -> Void)? = nil) {
        guard let runId = currentRunId else {
            DispatchQueue.main.async { completion?(true) }
            return
        }
        print("[RunManager] cancelCurrentRun level=\(level) runId=\(runId)")
        JourneyPersistence.shared.deleteRun(level: level, runId: runId) { success in
            DispatchQueue.main.async {
                self.clearRun(level: level)
                completion?(success)
            }
        }
    }

    func runStartDate(level: Int) -> Date? {
        let ts = UserDefaults.standard.double(forKey: startKey(for: level))
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
}
