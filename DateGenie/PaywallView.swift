//  PaywallView.swift
//  DateGenie
//  A simple subscription paywall.

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sub = SubscriptionManager.shared
    @State private var showManage = false

    var body: some View {

        VStack(spacing: 28) {
            // Observe subscription status
        
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundColor(.pink)
                .padding(.top, 20)

            Text("Unlimited Access")
                .font(.largeTitle.bold())
            Text("Download, share, and keep creating unlimited ad videos.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let product = sub.product {
                Button {
                    Task { await sub.purchase() }
                } label: {
                    Text(ctaTitle(for: product))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(sub.purchaseInProgress)

                Button("Restore Purchases") { Task { await sub.restore() } }
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                ProgressView().task { await sub.loadProduct() }
            }

            Button("Not now") { dismiss() }
                .foregroundColor(.secondary)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Auto‑renewable subscription. Renews weekly unless canceled at least 24 hours before the end of the period. You can cancel anytime in your App Store settings.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    Link("Privacy Policy", destination: URL(string: "https://dategenie-love-unleashed.lovable.app/privacy")!)
                    Link("Terms of Use", destination: URL(string: "https://dategenie-love-unleashed.lovable.app/terms")!)
                    Button("Manage") { showManage = true }
                }
                .font(.footnote)
            }

            Spacer()
        }
        .frame(maxWidth: 500)
        .onChange(of: sub.isSubscribed) { subscribed in
            if subscribed { dismiss() }
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .padding()
    }
}

#Preview {
    PaywallView()
}

private extension PaywallView {
    func ctaTitle(for product: Product) -> String {
        if let unit = product.subscription?.subscriptionPeriod.unit, unit == .week {
            return "Subscribe for \(product.displayPrice) per week"
        }
        return "Subscribe for \(product.displayPrice)"
    }
}
