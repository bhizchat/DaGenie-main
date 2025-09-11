//  IntroOnboardingView.swift
//  DateGenie
//
//  Three-step intro that explains DateGenie.
//
import SwiftUI
import FirebaseAuth

struct IntroOnboardingView: View {
    @EnvironmentObject var auth: AuthViewModel
    @AppStorage("hasSeenOnboarding") private var hasSeen = false
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            OnboardPage(imageName: "onboard_welcome",
                        title: "Welcome to Date Genie!",
                        subtitle: "Turn your date into a fun adventure",
                        buttonLabel: "Continue") {
                page = 1
            }
            .tag(0)

            OnboardPage(imageName: "onboard_memory",
                        title: "Capture Memories",
                        subtitle: "Snap Photos and take Videos to create a highlight reel",
                        buttonLabel: "Get Started") {
                hasSeen = true
            }
            .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .overlay(alignment: .topLeading) {
            Button(action: {
                if page == 0 {
                    // Exit onboarding – return to auth flow
                    auth.signOut()
                    hasSeen = false
                } else {
                    withAnimation { page -= 1 }
                }
            }) {
                Image(systemName: "arrow.backward.circle")
                    .font(.title2)
                    .padding(16)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct OnboardPage: View {
    let imageName: String
    let title: String
    let subtitle: String
    let buttonLabel: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
            Text(title)
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button(action: action) {
                Text(buttonLabel)
                    .font(.custom("VT323", size: 22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .padding()
    }
}

#if DEBUG
struct IntroOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        IntroOnboardingView()
    }
}
#endif
