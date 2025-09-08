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
