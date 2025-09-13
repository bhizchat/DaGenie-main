//  HuntsRepository.swift
//  DateGenie
//
//  Handles fetching of hunt templates with simple in-memory cache.
//
import Foundation
import FirebaseFirestore

@MainActor
final class HuntsRepository: ObservableObject {
    static let shared = HuntsRepository()
    private init() {}

    @Published private(set) var hunts: [HuntTemplate] = []

    private let db = Firestore.firestore()

    func refresh() async throws {
        let snap = try await db.collection("hunts").getDocuments()
        let decoded: [HuntTemplate] = snap.documents.compactMap { try? $0.data(as: HuntTemplate.self) }
        self.hunts = decoded.sorted { ($0.title) < ($1.title) }
    }
}
