import Foundation
import Security
#if canImport(FirebaseFirestore)
import FirebaseFirestore
import FirebaseAuth
#endif

final class JourneyPersistence {
    static let shared = JourneyPersistence()
    private init() {}

    #if canImport(FirebaseFirestore)
    private var db: Firestore { Firestore.firestore() }
    private func nodesCollection(ownerId: String, level: Int) -> CollectionReference {
        db.collection("journeys").document(ownerId)
            .collection("levels").document("\(level)")
            .collection("nodes")
    }
    private func legacyOwnerIds(for uid: String, completion: @escaping ([String]) -> Void) {
        db.collection("users").document(uid).getDocument { snap, _ in
            let arr = snap?.data()? ["deviceIds"] as? [String] ?? []
            completion(arr)
        }
    }
    #endif

    func saveNode(step: String, missionIndex: Int, media: CapturedMedia, durationSeconds: Int?) {
        let level = LevelStore.shared.currentLevel
        #if canImport(FirebaseFirestore)
        guard let remote = media.remoteURL else { print("[JourneyPersistence] saveNode aborted: missing remoteURL"); return }
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        guard let runId = RunManager.shared.currentRunId else {
            print("[JourneyPersistence] saveNode aborted: missing runId; ensure RunManager has a run for this level before saving")
            return
        }
        print("[JourneyPersistence] saveNode owner=\(uid) level=\(level) step=\(step) missionIndex=\(missionIndex)")
        let node = JourneyNode(
            id: media.id,
            step: JourneyStep(rawValue: step) ?? .game,
            level: level,
            missionIndex: missionIndex,
            runId: runId,
            media: JourneyNodeMedia(
                id: media.id,
                type: media.type == .photo ? "photo" : "video",
                caption: media.caption,
                remoteURL: remote.absoluteString,
                localFilename: media.localURL.lastPathComponent,
                durationSeconds: durationSeconds,
                createdAt: Date()
            ),
            createdAt: Date()
        )
        let data = try? JSONEncoder().encode(node)
        guard let dataUnwrapped = data,
              let payload = try? JSONSerialization.jsonObject(with: dataUnwrapped) as? [String: Any] else { return }
        db.collection("journeys").document(uid)
            .collection("levels").document("\(level)")
            .collection("nodes").document(media.id.uuidString)
            .setData(payload, merge: true) { err in
                if let err = err {
                    print("[JourneyPersistence] saveNode Firestore error: \(err.localizedDescription)")
                } else {
                    print("[JourneyPersistence] saveNode success docId=\(media.id.uuidString)")
                }
            }
        #endif
    }

    func saveLevelHeader(level: Int) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        // Minimal payload to avoid breakage when the model evolves
        let payload: [String: Any] = [
            "level": level,
            "createdAt": Timestamp(date: Date())
        ]
        db.collection("journeys").document(uid)
            .collection("levels").document("\(level)")
            .setData(payload, merge: true)
        #endif
    }

    // Marks a level as completed and stores the runId that represents the snapshot
    func finalizeLevel(level: Int, runId: String, totalPoints: Int? = nil, completedAt: Date = Date(), completion: @escaping (Bool) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        var payload: [String: Any] = [
            "level": level,
            "completedAt": Timestamp(date: completedAt),
            "completedRunId": runId
        ]
        if let pts = totalPoints { payload["totalPoints"] = pts }
        db.collection("journeys").document(uid)
            .collection("levels").document("\(level)")
            .setData(payload, merge: true) { err in
                if let err = err {
                    print("[JourneyPersistence] finalizeLevel error: \(err.localizedDescription)")
                    completion(false)
                } else {
                    print("[JourneyPersistence] finalizeLevel success level=\(level) runId=\(runId)")
                    completion(true)
                }
            }
        #else
        completion(true)
        #endif
    }

    // Lists completed levels (those with completedAt) in ascending level order
    struct LevelSummary { let level: Int; let runId: String; let completedAt: Date }
    func listCompletedLevels(completion: @escaping ([LevelSummary]) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        db.collection("journeys").document(uid)
            .collection("levels")
            .order(by: "level", descending: false)
            .getDocuments { snap, err in
                if let err = err { print("[JourneyPersistence] listCompletedLevels error: \(err.localizedDescription)"); DispatchQueue.main.async { completion([]) }; return }
                let results: [LevelSummary] = (snap?.documents ?? []).compactMap { doc in
                    let data = doc.data()
                    guard let level = data["level"] as? Int,
                          let ts = data["completedAt"] as? Timestamp,
                          let runId = data["completedRunId"] as? String else { return nil }
                    return LevelSummary(level: level, runId: runId, completedAt: ts.dateValue())
                }
                DispatchQueue.main.async { completion(results) }
            }
        #else
        DispatchQueue.main.async { completion([]) }
        #endif
    }

    func markPointsClaimed(level: Int, runId: String, claimedAt: Date = Date(), completion: @escaping (Bool) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        let payload: [String: Any] = ["claimedAt": Timestamp(date: claimedAt)]
        db.collection("journeys").document(uid).collection("levels").document("\(level)")
            .setData(payload, merge: true) { err in
                completion(err == nil)
            }
        #else
        completion(true)
        #endif
    }

    /// Deletes a single node document by its id for the current user and level.
    func deleteNode(level: Int, runId: String, nodeId: String, completion: @escaping (Bool) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        db.collection("journeys").document(uid)
            .collection("levels").document("\(level)")
            .collection("nodes").document(nodeId)
            .delete { err in
                if let err = err {
                    print("[JourneyPersistence] deleteNode error: \(err.localizedDescription)")
                    completion(false)
                } else {
                    print("[JourneyPersistence] deleteNode success id=\(nodeId)")
                    completion(true)
                }
            }
        #else
        completion(true)
        #endif
    }

    // MARK: Load for replay
    /// Loads the most recent media for each step (game/task/checkpoint) for the current level.
    /// Completion is invoked on the main queue.
    func loadLatestForCurrentLevel(completion: @escaping (_ game: CapturedMedia?, _ task: CapturedMedia?, _ checkpoint: CapturedMedia?) -> Void) {
        #if canImport(FirebaseFirestore)
        let level = LevelStore.shared.currentLevel
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        let deviceId = DeviceID.shared.id

        func decodeAndComplete(_ snap: QuerySnapshot?) {
            var game: CapturedMedia? = nil
            var task: CapturedMedia? = nil
            var checkpoint: CapturedMedia? = nil
            guard let docs = snap?.documents else { DispatchQueue.main.async { completion(nil, nil, nil) }; return }
            for doc in docs {
                // decode JourneyNode
                if let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                   let node = try? JSONDecoder().decode(JourneyNode.self, from: data) {
                    guard let remote = URL(string: node.media.remoteURL) else { continue }
                    let type: MediaType = node.media.type == "photo" ? .photo : .video
                    let media = CapturedMedia(localURL: remote, type: type, caption: node.media.caption, remoteURL: remote, uploadProgress: 1.0)
                    switch node.step {
                    case .game: if game == nil { game = media }
                    case .task: if task == nil { task = media }
                    case .checkpoint: if checkpoint == nil { checkpoint = media }
                    case .date_plan: break // not used in this legacy loader
                    }
                    if game != nil && task != nil && checkpoint != nil { break }
                }
            }
            DispatchQueue.main.async { completion(game, task, checkpoint) }
        }

        // First try current auth uid
        nodesCollection(ownerId: uid, level: level)
            .order(by: "createdAt", descending: true)
            .getDocuments { snap, _ in
                if let count = snap?.documents.count, count > 0 {
                    print("[JourneyPersistence] loadLatestForCurrentLevel owner=uid docs=\(count)")
                    decodeAndComplete(snap)
                } else {
                    // Fallback: try any legacy deviceIds stored on the user profile
                    self.legacyOwnerIds(for: uid) { ownerIds in
                        let idsToTry: [String] = ownerIds.isEmpty && uid != deviceId ? [deviceId] : ownerIds
                        if idsToTry.isEmpty {
                            print("[JourneyPersistence] loadLatestForCurrentLevel -> no docs under uid (no legacy ids)")
                            decodeAndComplete(nil)
                            return
                        }
                        func tryNext(_ index: Int) {
                            if index >= idsToTry.count { print("[JourneyPersistence] loadLatestForCurrentLevel -> no docs under any legacy deviceId"); decodeAndComplete(nil); return }
                            let owner = idsToTry[index]
                            self.nodesCollection(ownerId: owner, level: level)
                                .order(by: "createdAt", descending: true)
                                .getDocuments { s, _ in
                                    if let c = s?.documents.count, c > 0 {
                                        print("[JourneyPersistence] loadLatestForCurrentLevel owner=legacy(\(owner)) docs=\(c)")
                                        decodeAndComplete(s)
                                    } else {
                                        tryNext(index + 1)
                                    }
                                }
                        }
                        tryNext(0)
                    }
                }
            }
        #else
        DispatchQueue.main.async { completion(nil, nil, nil) }
        #endif
    }

    /// Loads most recent media per step for given level + missionIndex.
    func loadFor(level: Int, missionIndex: Int, completion: @escaping (_ game: CapturedMedia?, _ task: CapturedMedia?, _ checkpoint: CapturedMedia?) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        let deviceId = DeviceID.shared.id
        guard let runId = RunManager.shared.currentRunId else {
            print("[JourneyPersistence] loadFor(level: \(level), missionIndex: \(missionIndex)) aborted: missing runId")
            DispatchQueue.main.async { completion(nil, nil, nil) }
            return
        }

        func handleSnapshot(_ snap: QuerySnapshot?, ownerLabel: String) -> (CapturedMedia?, CapturedMedia?, CapturedMedia?, Int) {
            var game: CapturedMedia? = nil
            var task: CapturedMedia? = nil
            var checkpoint: CapturedMedia? = nil
            guard let docs = snap?.documents else { return (nil, nil, nil, 0) }
            print("[JourneyPersistence] loadFor(level: \(level), missionIndex: \(missionIndex)) owner=\(ownerLabel) -> docs: \(docs.count)")
            for doc in docs {
                let raw = doc.data()
                let hasMI = raw["missionIndex"] != nil
                if let data = try? JSONSerialization.data(withJSONObject: raw),
                   let node = try? JSONDecoder().decode(JourneyNode.self, from: data) {
                    guard let remote = URL(string: node.media.remoteURL) else { continue }
                    let type: MediaType = node.media.type == "photo" ? .photo : .video
                    let media = CapturedMedia(localURL: remote, type: type, caption: node.media.caption, remoteURL: remote, uploadProgress: 1.0)
                    switch node.step {
                    case .game: if game == nil { game = media }
                    case .task: if task == nil { task = media }
                    case .checkpoint: if checkpoint == nil { checkpoint = media }
                    case .date_plan: break
                    }
                    print("[JourneyPersistence] matched doc step=\(node.step.rawValue) hasMissionIndex=\(hasMI)")
                    if game != nil && task != nil && checkpoint != nil { break }
                }
            }
            return (game, task, checkpoint, docs.count)
        }

        // Try current uid
        nodesCollection(ownerId: uid, level: level)
            .whereField("runId", isEqualTo: runId)
            .whereField("missionIndex", isEqualTo: missionIndex)
            .order(by: "createdAt", descending: true)
            .getDocuments { snap, _ in
                let (g, t, c, count) = handleSnapshot(snap, ownerLabel: "uid")
                if count > 0 {
                    if g == nil && t == nil && c == nil { print("[JourneyPersistence] loadFor -> no matches; likely legacy records without missionIndex") }
                    DispatchQueue.main.async { completion(g, t, c) }
                } else {
                    // Fallback: iterate all legacy deviceIds recorded for this user
                    self.legacyOwnerIds(for: uid) { ownerIds in
                        let idsToTry: [String] = ownerIds.isEmpty && uid != deviceId ? [deviceId] : ownerIds
                        if idsToTry.isEmpty {
                            print("[JourneyPersistence] loadFor -> no legacy ids; returning empty")
                            DispatchQueue.main.async { completion(nil, nil, nil) }
                            return
                        }
                        func tryNext(_ index: Int) {
                            if index >= idsToTry.count {
                                print("[JourneyPersistence] loadFor -> no matches in uid or any deviceId; will rely on legacy level-wide fallback if invoked by caller")
                                DispatchQueue.main.async { completion(nil, nil, nil) }
                                return
                            }
                            let owner = idsToTry[index]
                            self.nodesCollection(ownerId: owner, level: level)
                                .whereField("runId", isEqualTo: runId)
                                .whereField("missionIndex", isEqualTo: missionIndex)
                                .order(by: "createdAt", descending: true)
                                .getDocuments { s, _ in
                                    let (gg, tt, cc, cnt) = handleSnapshot(s, ownerLabel: "deviceId(\(owner))")
                                    if cnt > 0 {
                                        DispatchQueue.main.async { completion(gg, tt, cc) }
                                    } else {
                                        tryNext(index + 1)
                                    }
                                }
                        }
                        tryNext(0)
                    }
                }
            }
        #else
        DispatchQueue.main.async { completion(nil, nil, nil) }
        #endif
    }

    /// Loads media for a specific finalized run (used by Journey replay)
    func loadFor(level: Int, runId: String, missionIndex: Int, completion: @escaping (_ game: CapturedMedia?, _ task: CapturedMedia?, _ checkpoint: CapturedMedia?) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        nodesCollection(ownerId: uid, level: level)
            .whereField("runId", isEqualTo: runId)
            .whereField("missionIndex", isEqualTo: missionIndex)
            .order(by: "createdAt", descending: true)
            .getDocuments { snap, _ in
                var g: CapturedMedia? = nil
                var t: CapturedMedia? = nil
                var c: CapturedMedia? = nil
                guard let docs = snap?.documents else { DispatchQueue.main.async { completion(nil, nil, nil) }; return }
                for doc in docs {
                    if let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                       let node = try? JSONDecoder().decode(JourneyNode.self, from: data),
                       let remote = URL(string: node.media.remoteURL) {
                        let type: MediaType = node.media.type == "photo" ? .photo : .video
                        let media = CapturedMedia(localURL: remote, type: type, caption: node.media.caption, remoteURL: remote, uploadProgress: 1.0)
                        switch node.step {
                        case .game: if g == nil { g = media }
                        case .task: if t == nil { t = media }
                        case .checkpoint: if c == nil { c = media }
                        case .date_plan: break
                        }
                        if g != nil && t != nil && c != nil { break }
                    }
                }
                DispatchQueue.main.async { completion(g, t, c) }
            }
        #else
        DispatchQueue.main.async { completion(nil, nil, nil) }
        #endif
    }

    // Date Plan loader shim: date_plan first, fallback to legacy/quest best-of
    func loadQuest(level: Int, runId: String, missionIndex: Int, completion: @escaping (CapturedMedia?) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        // 1) Try new date_plan step
        nodesCollection(ownerId: uid, level: level)
            .whereField("runId", isEqualTo: runId)
            .whereField("missionIndex", isEqualTo: missionIndex)
            .whereField("step", isEqualTo: "date_plan")
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments { snap, _ in
                if let doc = snap?.documents.first,
                   let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                   let node = try? JSONDecoder().decode(JourneyNode.self, from: data),
                   let remote = URL(string: node.media.remoteURL) {
                    let type: MediaType = node.media.type == "photo" ? .photo : .video
                    let media = CapturedMedia(localURL: remote, type: type, caption: node.media.caption, remoteURL: remote, uploadProgress: 1.0)
                    DispatchQueue.main.async { completion(media) }
                    return
                }
                // 2) Fallback to old quest step
                self.nodesCollection(ownerId: uid, level: level)
                    .whereField("runId", isEqualTo: runId)
                    .whereField("missionIndex", isEqualTo: missionIndex)
                    .whereField("step", isEqualTo: "quest")
                    .order(by: "createdAt", descending: true)
                    .limit(to: 1)
                    .getDocuments { s2, _ in
                        if let doc = s2?.documents.first,
                           let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                           let node = try? JSONDecoder().decode(JourneyNode.self, from: data),
                           let remote = URL(string: node.media.remoteURL) {
                            let type: MediaType = node.media.type == "photo" ? .photo : .video
                            let media = CapturedMedia(localURL: remote, type: type, caption: node.media.caption, remoteURL: remote, uploadProgress: 1.0)
                            DispatchQueue.main.async { completion(media) }
                            return
                        }
                        // 3) Fallback to legacy best-of
                        self.loadFor(level: level, runId: runId, missionIndex: missionIndex) { g, t, c in
                            let best = c ?? t ?? g
                            DispatchQueue.main.async { completion(best) }
                        }
                    }
            }
        #else
        DispatchQueue.main.async { completion(nil) }
        #endif
    }

    // Aggregate completion for quest (or legacy best-of)
    func aggregateCompletionForRun(level: Int, runId: String, missionCount: Int, completion: @escaping (Set<Int>) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        nodesCollection(ownerId: uid, level: level)
            .whereField("runId", isEqualTo: runId)
            .getDocuments { snap, _ in
                var completed = Set<Int>()
                guard let docs = snap?.documents else { DispatchQueue.main.async { completion(completed) }; return }
                for doc in docs {
                    if let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                       let node = try? JSONDecoder().decode(JourneyNode.self, from: data) {
                        // Count as complete if quest step exists OR any legacy step exists
                        if node.step == .game || node.step == .task || node.step == .checkpoint || node.step == .date_plan || node.step.rawValue == "quest" {
                            if node.missionIndex >= 0 && node.missionIndex < missionCount {
                                completed.insert(node.missionIndex)
                            }
                        }
                    }
                }
                DispatchQueue.main.async { completion(completed) }
            }
        #else
        DispatchQueue.main.async { completion([]) }
        #endif
    }

    struct MediaItem { let id: String; let remoteURL: URL; let type: MediaType; let createdAt: Date }
    func loadAllMediaForRun(level: Int, runId: String, completion: @escaping ([MediaItem]) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        nodesCollection(ownerId: uid, level: level)
            .whereField("runId", isEqualTo: runId)
            .getDocuments { snap, _ in
                var items: [MediaItem] = []
                guard let docs = snap?.documents else { DispatchQueue.main.async { completion(items) }; return }
                for doc in docs {
                    if let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                       let node = try? JSONDecoder().decode(JourneyNode.self, from: data),
                       let remote = URL(string: node.media.remoteURL) {
                        let type: MediaType = node.media.type == "photo" ? .photo : .video
                        let created = node.media.createdAt
                        items.append(MediaItem(id: node.id.uuidString, remoteURL: remote, type: type, createdAt: created))
                    }
                }
                // Sort client-side by createdAt ascending so first-captured appears first
                items.sort { $0.createdAt < $1.createdAt }
                DispatchQueue.main.async { completion(items) }
            }
        #else
        DispatchQueue.main.async { completion([]) }
        #endif
    }

    /// Aggregates which steps exist per mission for a given level+run. Returns a
    /// dictionary keyed by missionIndex with a set of steps present in storage.
    func aggregateStepsForRun(level: Int, runId: String, completion: @escaping ([Int: Set<JourneyStep>]) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        nodesCollection(ownerId: uid, level: level)
            .whereField("runId", isEqualTo: runId)
            .getDocuments { snap, _ in
                var map: [Int: Set<JourneyStep>] = [:]
                guard let docs = snap?.documents else { DispatchQueue.main.async { completion(map) }; return }
                for doc in docs {
                    if let data = try? JSONSerialization.data(withJSONObject: doc.data()),
                       let node = try? JSONDecoder().decode(JourneyNode.self, from: data) {
                        var set = map[node.missionIndex] ?? []
                        set.insert(node.step)
                        map[node.missionIndex] = set
                    }
                }
                DispatchQueue.main.async { completion(map) }
            }
        #else
        DispatchQueue.main.async { completion([:]) }
        #endif
    }
}

extension JourneyPersistence {
    /// Deletes all node documents for a given level + runId.
    func deleteRun(level: Int, runId: String, completion: @escaping (Bool) -> Void) {
        #if canImport(FirebaseFirestore)
        let uid: String = Auth.auth().currentUser?.uid ?? DeviceID.shared.id
        let query = nodesCollection(ownerId: uid, level: level).whereField("runId", isEqualTo: runId)
        query.getDocuments { snap, err in
            if let err = err { print("[JourneyPersistence] deleteRun query error: \(err.localizedDescription)"); completion(false); return }
            guard let docs = snap?.documents, !docs.isEmpty else { print("[JourneyPersistence] deleteRun -> no docs for runId=\(runId)"); completion(true); return }
            let batch = self.db.batch()
            docs.forEach { batch.deleteDocument($0.reference) }
            batch.commit { e in
                if let e = e {
                    print("[JourneyPersistence] deleteRun commit error: \(e.localizedDescription)")
                    completion(false)
                } else {
                    print("[JourneyPersistence] deleteRun success runId=\(runId) count=\(docs.count)")
                    completion(true)
                }
            }
        }
        #else
        completion(true)
        #endif
    }
}

final class DeviceID {
    static let shared = DeviceID()
    private let key = "anon_device_id"
    let id: String
    private init() {
        // 1) If Keychain has it, prefer that.
        if let saved = KeychainHelper.read(key) {
            id = saved
            return
        }
        // 2) Migrate from prior UserDefaults storage if present.
        if let legacy = UserDefaults.standard.string(forKey: key), !legacy.isEmpty {
            _ = KeychainHelper.save(key, value: legacy)
            id = legacy
            return
        }
        // 3) Otherwise create a fresh, stable ID and store in Keychain.
        let newId = UUID().uuidString.uppercased()
        _ = KeychainHelper.save(key, value: newId)
        id = newId
    }
}

enum KeychainHelper {
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
    @discardableResult
    static func save(_ key: String, value: String) -> Bool {
        let data = value.data(using: .utf8)!
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecValueData as String: data]
        SecItemDelete(add as CFDictionary)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
