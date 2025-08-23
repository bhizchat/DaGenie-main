//  PaywallView.swift
//  DateGenie
//  A simple subscription paywall.

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sub = SubscriptionManager.shared

    var body: some View {

        VStack(spacing: 28) {
            // Observe subscription status
        
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundColor(.pink)
                .padding(.top, 20)

            Text("Unlimited Plans")
                .font(.largeTitle.bold())
            Text("Generate as many personalised date ideas as you like — no monthly limit.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let product = sub.product {
                Button {
                    Task { await sub.purchase() }
                } label: {
                    Text("Subscribe for \(product.displayPrice) / month")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(sub.purchaseInProgress)
            } else {
                ProgressView().task { await sub.loadProduct() }
            }

            Button("Not now") { dismiss() }
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: 500)
        .onChange(of: sub.isSubscribed) { subscribed in
            if subscribed { dismiss() }
        }
        .padding()
    }
}

#Preview {
    PaywallView()
}
