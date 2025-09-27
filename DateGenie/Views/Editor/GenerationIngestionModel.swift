import Foundation

// Actor-based ingestion tracker to gate the Export CTA on editor reality
actor GenerationIngestionModel {
    private(set) var runId: String? = nil
    private(set) var expected: Int = 0
    private var deliveredIds: Set<String> = []
    private var appendedIds: Set<String> = []
    private var failedIds: Set<String> = []
    private var skippedIds: Set<String> = []
    private(set) var isRebuilding: Bool = false

    // Debounced readiness flag snapshot for UI polling
    private(set) var isComplete: Bool = false

    func begin(runId: String, expected: Int) {
        self.runId = runId
        self.expected = expected
        deliveredIds.removeAll()
        appendedIds.removeAll()
        failedIds.removeAll()
        skippedIds.removeAll()
        isRebuilding = false
        isComplete = false
        logSnapshot()
    }

    func markDelivered(runId: String?, sceneId: String) {
        guard self.runId == runId || (runId ?? "").isEmpty else { return }
        deliveredIds.insert(sceneId)
        logSnapshot()
    }

    func markAppended(runId: String?, sceneId: String) async {
        guard self.runId == runId || (runId ?? "").isEmpty else { return }
        appendedIds.insert(sceneId)
        await recomputeDebounced()
        logSnapshot()
    }

    func markFailed(runId: String?, sceneId: String) async {
        guard self.runId == runId || (runId ?? "").isEmpty else { return }
        failedIds.insert(sceneId)
        await recomputeDebounced()
        logSnapshot()
    }

    func markSkipped(runId: String?, sceneId: String) async {
        guard self.runId == runId || (runId ?? "").isEmpty else { return }
        skippedIds.insert(sceneId)
        await recomputeDebounced()
        logSnapshot()
    }

    func rebuilding(_ on: Bool) async {
        isRebuilding = on
        await recomputeDebounced()
        logSnapshot()
    }

    func progressString() -> String {
        guard expected > 0 else { return "…" }
        return "\(min(appendedIds.count, expected))/\(expected)"
    }

    private func recomputeDebounced() async {
        // Failure-aware readiness: appended + failed + skipped must reach expected
        let contributed = appendedIds.count + failedIds.count + skippedIds.count
        let ready = (expected > 0 && contributed == expected && !isRebuilding)
        if ready == isComplete { return }
        // One-tick debounce on main runloop semantics using small async delay
        try? await Task.sleep(nanoseconds: 10_000_000) // ~10ms
        // Re-evaluate after delay
        let finalContrib = appendedIds.count + failedIds.count + skippedIds.count
        let finalReady = (expected > 0 && finalContrib == expected && !isRebuilding)
        if finalReady != isComplete {
            let gateLeft = (appendedIds.count == expected)
            let gateRight = (finalContrib == expected)
            print("[Ingest] gate_flip runId=\(runId ?? "") new_isComplete=\(finalReady) gate_left=\(gateLeft) gate_right=\(gateRight)")
        }
        isComplete = finalReady
    }

    // Lightweight accessors for observability
    func deliveredCount() -> Int { deliveredIds.count }
    func appendedCount() -> Int { appendedIds.count }
    func expectedCount() -> Int { expected }
    func failedCount() -> Int { failedIds.count }
    func skippedCount() -> Int { skippedIds.count }

    func sealExpectedToCurrent() async {
        // On timeout, converge the planned expectation down to the
        // terminal contribution that the editor currently accounts for.
        // This mirrors the readiness gate which uses (appended + failed + skipped).
        let terminalContributed = appendedIds.count + failedIds.count + skippedIds.count
        if terminalContributed > 0 {
            // Allow shrink so the gate can resolve when scenes are missing
            expected = min(expected, terminalContributed)
            await recomputeDebounced()
            logSnapshot()
        }
    }

    // If server provides a finalized expected (excluding failed/stuck), update and recompute.
    func updateExpectedFinal(_ expectedFinal: Int) async {
        if expectedFinal > 0 { expected = expectedFinal }
        await recomputeDebounced()
        logSnapshot()
    }

    private func logSnapshot() {
        print("[Ingest] snapshot runId=\(runId ?? "") planned=\(expected) expected=\(expected) delivered=\(deliveredIds.count) appended=\(appendedIds.count) failed=\(failedIds.count) skipped=\(skippedIds.count) rebuilding=\(isRebuilding) isComplete=\(isComplete)")
    }
}


