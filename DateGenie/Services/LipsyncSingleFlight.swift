import Foundation

actor LipsyncSingleFlight {
    static let shared = LipsyncSingleFlight()

    private var inFlightKeys: Set<String> = []

    struct Result<T> {
        let value: T?
        let replayed: Bool
    }

    /// Ensures the operation for this runId executes at most once concurrently process-wide.
    /// If another caller triggers with the same runId while in-flight, it returns replayed=true without executing `operation`.
    // One-shot helper (legacy). Prefer tryEnter/leave for long-lived in-flight windows.
    @discardableResult
    func performOnce<T>(runId: String, operation: @Sendable () async throws -> T) async throws -> Result<T> {
        let key = runId
        if inFlightKeys.contains(key) { return Result(value: nil, replayed: true) }
        inFlightKeys.insert(key)
        defer { inFlightKeys.remove(key) }
        let value = try await operation()
        return Result(value: value, replayed: false)
    }

    // Long-lived gating: enter/leave using a custom key (e.g., "projectId::runId")
    func tryEnter(key: String) -> Bool {
        if inFlightKeys.contains(key) { return false }
        inFlightKeys.insert(key)
        return true
    }

    func leave(key: String) {
        inFlightKeys.remove(key)
    }
}


