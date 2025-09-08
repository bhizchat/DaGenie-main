//
//  DateGenieApp.swift
//  DateGenie
//
//  Created by VICTOR EDOCHIE on 7/16/25.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAnalytics
import FirebaseFirestore
import FirebaseAuth
import UIKit



@main
struct DateGenieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        FirebaseApp.configure()
        // Preemptive configure with cached install_date; userId/subTier will be set once auth completes
        AnalyticsManager.shared.configure(userId: nil, subscriptionTier: nil)
        
        // Ensure we always have an authenticated user (anonymous is fine for personal data isolation / rules)
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { result, error in
                if let error = error {
                    print("[Auth] Anonymous sign-in failed: \(error.localizedDescription)")
                } else if let user = result?.user {
                    print("[Auth] Anonymous sign-in succeeded uid=\(user.uid)")
                    // Persist deviceId for legacy data migration via rules (store as an array of deviceIds)
                    let deviceId = DeviceID.shared.id
                    Firestore.firestore().collection("users").document(user.uid)
                        .setData(["deviceIds": FieldValue.arrayUnion([deviceId])], merge: true) { err in
                            if let err = err { print("[Auth] Failed writing deviceId to users doc: \(err)") }
                            else { print("[Auth] Stored/Appended deviceId for uid=\(user.uid): \(deviceId)") }
                        }
                } else {
                    print("[Auth] Anonymous sign-in completed with no user object")
                }
            }
        } else {
            let uid = Auth.auth().currentUser?.uid ?? "nil"
            print("[Auth] Using existing auth uid=\(uid)")
            // Ensure deviceId is stored/appended as well
            if uid != "nil" {
                let deviceId = DeviceID.shared.id
                Firestore.firestore().collection("users").document(uid)
                    .setData(["deviceIds": FieldValue.arrayUnion([deviceId])], merge: true) { err in
                        if let err = err { print("[Auth] Failed writing deviceId to users doc: \(err)") }
                        else { print("[Auth] Stored/Appended deviceId for uid=\(uid): \(deviceId)") }
                    }
            }
        }
    }

    @StateObject private var authVM = AuthViewModel()
    @StateObject private var huntsRepo = HuntsRepository.shared
    @StateObject private var userRepo  = UserRepository.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authVM.user != nil {
                    // Projects + Profile tabs
                    ProjectsRootTab()
                        .task { await userRepo.loadProfile() }
                } else {
                    SignInView()
                }
            }
            .environmentObject(authVM)
            .environmentObject(huntsRepo)
            .environmentObject(userRepo)
            .accentColor(.accentPrimary)
            // Configure analytics once we know the user
            .onChange(of: authVM.user?.uid) { uid in
                if let uid = uid, let user = authVM.user {
                    let tier = SubscriptionManager.shared.isSubscribed ? "premium" : "free"
                    AnalyticsManager.shared.configure(userId: user.uid, subscriptionTier: tier)
                }
            }
        }
        .modelContainer(sharedModelContainer)
        // Scene phase monitoring for session tracking
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                AnalyticsManager.shared.startSession()
            case .background, .inactive:
                AnalyticsManager.shared.endSession()
            @unknown default:
                break
            }
        }
    }
}
