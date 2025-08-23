//  WelcomeCardView.swift
//  DateGenie
//
//  Shows the first onboarding screen with the genie image.
//
//  Created by AI.

import SwiftUI

/// Reusable welcome card for onboarding. Host it inside a `TabView` / `PageTabViewStyle` flow.
struct WelcomeCardView: View {
    /// Callback to move to the next onboarding page.
    var onContinue: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            // Genie image
            Image("welcome_genie")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .padding(.horizontal, 32)

            // Title
            Text("Welcome to DateGenie!")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            // Subtitle
            Text("A little magic helps you plan unforgettable date nights.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer(minLength: 0)

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.custom("VT323", size: 22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

#if DEBUG
struct WelcomeCardView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeCardView()
    }
}
#endif
