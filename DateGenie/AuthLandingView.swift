import SwiftUI

/// First unauthenticated screen with logo, slogan, and navigation to Sign Up / Log In
struct AuthLandingView: View {
    @State private var goSignUp = false
    @State private var goSignIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 12)
                    Image("genie_logo")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(maxWidth: 520)
                        .padding(.horizontal, 24)

                    Text("Upload. Imagine. Animate.")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.accentPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    Spacer(minLength: 12)

                    // Create Account
                    Button(action: { goSignUp = true }) {
                        Text("Create an Account")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.accentPrimary)
                            .cornerRadius(16)
                            .padding(.horizontal, 20)
                    }

                    // Log in
                    Button(action: { goSignIn = true }) {
                        Text("Log in")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.black)
                            .cornerRadius(16)
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.vertical, 24)
            }
            .background(Color.white)
            .ignoresSafeArea()
            .navigationDestination(isPresented: $goSignUp) { SignUpView() }
            .navigationDestination(isPresented: $goSignIn) { SignInView() }
        }
    }
}

#if DEBUG
struct AuthLandingView_Previews: PreviewProvider {
    static var previews: some View {
        AuthLandingView()
            .environmentObject(AuthViewModel())
    }
}
#endif


