//
//  PushNotificationManager.swift
//  DateGenie
//
//  Handles APNs registration, FCM token upload, and permission prompt.
//  The permission request should be called after the user has experienced
//  core value (e.g. after first date plan) – call `PushNotificationManager.shared.requestAuthorization()` at that moment.
//
import Foundation
import SwiftUI
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import UIKit

final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    private override init() { super.init() }

    private let db = Firestore.firestore()

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Call this once the user has seen the main value (e.g. after first plan)
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    private func uploadFCMToken(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).setData(["fcmToken": token], merge: true)
        // Subscribe device to user topic for background nudges during long runs
        Messaging.messaging().subscribe(toTopic: "user_\(uid)") { err in
            print(err == nil ? "[Push] sub ok" : "[Push] sub err \(String(describing: err))")
        }
    }
}

// MARK: - AppDelegate bridge for SwiftUI
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushNotificationManager.shared.configure()
        return true
    }

    // Lock the app to portrait orientation globally
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // Best-effort background fetch on silent push to nudge a server-truth read
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Only react in background; foreground is handled by live observers
        guard application.applicationState != .active else { completionHandler(.noData); return }
        guard let uid = Auth.auth().currentUser?.uid else { completionHandler(.noData); return }
        let pid = ProjectsRepository.shared.projects.first?.id
        let sid = RunManager.shared.currentStoryboardId ?? "default"
        guard let projectId = pid else { completionHandler(.noData); return }

        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("musicVideos").document(projectId)
            .collection("storyboards").document(sid)

        Task.detached(priority: .background) {
            do {
                print("[Push] fetch.server_check path=\(ref.path) sid=\(sid)")
                _ = try await ref.getDocument(source: .server) // bypass cache; warms state
                // Optional success log to confirm the run
                if let d = try? await ref.getDocument(source: .server).data(),
                   let f = d["finishing"] as? [String: Any] {
                    let mux = ((f["mux"] as? [String: Any])?["finalUrl"] as? String) ?? ""
                    let lip = ((f["lipsync"] as? [String: Any])?["outputUrl"] as? String) ?? ""
                    if !(mux.isEmpty && lip.isEmpty) {
                        let s = mux.isEmpty ? lip : mux
                        print("[Push] fetch.server_success url_short=\(s.prefix(64)) path=\(ref.path)")
                    }
                }
                completionHandler(.newData)
            } catch {
                print("[Push] background_fetch_error \(error.localizedDescription) path=\(ref.path)")
                completionHandler(.failed)
            }
        }
    }
}

// MARK: - Delegates
extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
}

extension PushNotificationManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            uploadFCMToken(token)
        }
    }
}
