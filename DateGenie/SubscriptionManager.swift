//  SubscriptionManager.swift
//  DateGenie
//
//  Handles StoreKit2 subscription purchase & status.
//  After a verified purchase, notifies backend via callable function
//  to mark the user as subscribed.

import Foundation
import StoreKit
import FirebaseAuth
@preconcurrency import FirebaseFunctions

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published var product: Product?
    @Published var isSubscribed: Bool = false
    @Published var purchaseInProgress = false
    // True while we are validating the receipt with the backend – UI should disable actions.
    @Published var backendSyncInProgress = false
    @Published var error: Error?

    private let productID = "com.bhizchat.dategenie.unlimited_weekly" // Weekly plan
    private let functions = Functions.functions(region: "us-central1")

    private init() {
        Task { await self.refreshEntitlements() }
        // Live updates for renewals/cancellations
        Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update, transaction.productID == productID {
                    await self.handle(transaction: transaction)
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Product
    func loadProduct() async {
        do {
            let storeProducts = try await Product.products(for: [productID])
            self.product = storeProducts.first
        } catch {
            self.error = error
        }
    }

    // MARK: - Purchase
    func purchase() async {
        // If user already has an active subscription, avoid triggering another purchase flow which
        // causes the “You’re currently subscribed” system alert.
        guard !isSubscribed else {
            return
        }
        guard let product = product else { return }
        purchaseInProgress = true
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try self.checkVerified(verification)
                await self.handle(transaction: transaction)
                await transaction.finish()
            case .userCancelled, .pending: break
            default: break
            }
        } catch {
            self.error = error
        }
        purchaseInProgress = false
    }

    // MARK: - Entitlements
    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID {
                await self.handle(transaction: transaction)
                return
            }
        }
        self.isSubscribed = false
    }

    private func handle(transaction: Transaction) async {
        // Compare expiry
        if let expiry = transaction.expirationDate, expiry > Date() {
            self.isSubscribed = true
            backendSyncInProgress = true
            await sendReceiptToBackend()
            backendSyncInProgress = false
        } else {
            self.isSubscribed = false
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }

    // MARK: - Backend
    private func sendReceiptToBackend() async {
        guard let user = Auth.auth().currentUser else {
            print("[Subscription] No signed-in user – skipping receipt validation")
            return
        }
        // Try to obtain receipt
        var receiptDataStr: String?
        if let url = Bundle.main.appStoreReceiptURL,
           let data = try? Data(contentsOf: url) {
            receiptDataStr = data.base64EncodedString()
        }
        // If missing, attempt to refresh the receipt
        if receiptDataStr == nil {
            print("[Subscription] Receipt not found – requesting App Store sync…")
            do { try await AppStore.sync() } catch {}
            if let url = Bundle.main.appStoreReceiptURL,
               let data = try? Data(contentsOf: url) {
                receiptDataStr = data.base64EncodedString()
            }
        }
        guard let encoded = receiptDataStr else {
            print("[Subscription] Still no receipt after sync – cannot validate")
            return
        }
        print("[Subscription] Sending receipt to backend (uid: \(user.uid.prefix(6)))")
        let callable = functions.httpsCallable("validateReceipt")
        do {
            _ = try await callable.call(["receiptData": encoded])
            print("[Subscription] Backend validation call completed ✅")
        } catch {
            print("[Subscription] Backend validation failed: \(error)")
        }
    }

    // MARK: - Restore
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            await sendReceiptToBackend()
        } catch {
            self.error = error
        }
    }

    // MARK: - Legacy backend call (kept for fallback)
    private func notifyBackend(expiry: Date) async {
        guard let _ = Auth.auth().currentUser else { return }
        let callable = functions.httpsCallable("activateSubscription")
        do {
            _ = try await callable.call(["expiryMillis": Int(expiry.timeIntervalSince1970 * 1000)])
        } catch {
            print("Failed to notify backend: \(error)")
        }
    }
}
