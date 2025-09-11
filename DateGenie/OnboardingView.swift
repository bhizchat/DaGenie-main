//  OnboardingView.swift
//  DateGenie
//  Hosts the onboarding flow. Currently single page but scalable.
//  Created by AI.

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var page = 0

    var body: some View {
        // Single-page onboarding
        WelcomeCardView {
            hasSeenOnboarding = true
        }
    }
}

// Minimal placeholder for second page so the project compiles.
private struct PointsTutorialCardView: View {
    var onDone: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("points_tutorial")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .padding(.horizontal, 32)
            Text("Snap Photos and take Videos to create a highlight reel")
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
            Button("Start Dating", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .padding(.bottom, 32)
        }
        .padding()
    }
}

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
#endif
