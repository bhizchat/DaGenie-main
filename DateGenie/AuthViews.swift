//
//  AuthViews.swift
//  DateGenie
//
//  Simple Sign-In and Sign-Up screens approximating the provided mock using built-in system fonts.
//

import SwiftUI

private struct BrandHeader: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("genie_logo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 160, height: 160)
            // Slogan shown on landing; secondary screens keep logo only
        }
        .padding(.bottom, 24)
    }
}

struct SignInView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BrandHeader()
                    .padding(.top, 8)
                auth.appleButton()
                Text("or with Email")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                Group {
                    TextField("", text: $email, prompt: Text("Email").foregroundColor(Color.gray))
                        .foregroundColor(.black)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                    SecureField("", text: $password, prompt: Text("Password").foregroundColor(Color.gray))
                        .foregroundColor(.black)
                        .textContentType(.password)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color.stroke))

                Button(action: { Task { await auth.signIn(email: email, password: password) } }) {
                    Text("Log in")
                        .font(.system(size: 17, weight: .semibold, design: .default).width(.condensed))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.accentPrimary)
                        .cornerRadius(6)
                }
                .disabled(email.isEmpty || password.isEmpty)

                Button {
                    showSignUp = true
                } label: {
                    Text("No account yet? ") + Text("Create Account").bold()
                }
                .font(.system(size: 15, weight: .regular, design: .default).width(.condensed))
                .padding(.top, 8)
            }
            .padding()
        }
        // Avoid attaching global tap gestures that can interfere with SignInWithAppleButton taps
        .background(Color.white)
        .ignoresSafeArea()
        .sheet(isPresented: $showSignUp) { SignUpView() }
        .alert("Error", isPresented: Binding(get: { auth.authError != nil }, set: { _ in auth.authError = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(auth.authError?.localizedDescription ?? "")
        }
    }
}

struct SignUpView: View {
    @State private var isSubmitting = false
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var artistName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @FocusState private var focusedField: SignUpField?
    @State private var keyboardHeight: CGFloat = 0

    private enum SignUpField: Hashable { case artistName, email, password, confirm }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        BrandHeader()
                            .padding(.top, 8)
                        // Apple sign in option at top
                        auth.appleButton()
                        Text("or with Email")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        credentialFields

                        submitButton
                    }
                    .padding()
                }
                .padding(.bottom, keyboardHeight)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { field in
                    if let f = field { withAnimation { proxy.scrollTo(f, anchor: .center) } }
                }
            }
            // Do not attach hideKeyboardOnTap here; it can swallow taps intended for the Apple button
            .navigationTitle("")
            .background(Color.white)
            .ignoresSafeArea()
            
            .alert("Error", isPresented: Binding(get: { auth.authError != nil }, set: { _ in auth.authError = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(auth.authError?.localizedDescription ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                if let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    let height = max(0, UIScreen.main.bounds.height - end.origin.y)
                    keyboardHeight = height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
        }
    }

    private var canSubmit: Bool {
        let n = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !email.isEmpty && password.count >= 6 && password == confirm && !n.isEmpty && n.count <= 40
    }

    private func createAccount() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            await auth.signUp(email: email, password: password, artistName: artistName.trimmingCharacters(in: .whitespacesAndNewlines))
            isSubmitting = false
            if auth.authError == nil { dismiss() }
        }
    }

// MARK: - Helpers
    @ViewBuilder
    private var credentialFields: some View {
        Group {
            TextField("", text: $artistName, prompt: Text("Artist Name").foregroundColor(Color.gray))
                .foregroundColor(.black)
                .textContentType(.username)
                .id(SignUpField.artistName)
                .focused($focusedField, equals: .artistName)
            TextField("", text: $email, prompt: Text("Email").foregroundColor(Color.gray))
                        .foregroundColor(.black)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .id(SignUpField.email)
                .focused($focusedField, equals: .email)
            SecureField("", text: $password, prompt: Text("Password").foregroundColor(Color.gray))
                        .foregroundColor(.black)
                .textContentType(.newPassword)
                .id(SignUpField.password)
                .focused($focusedField, equals: .password)
            SecureField("", text: $confirm, prompt: Text("Confirm Password").foregroundColor(Color.gray))
                .foregroundColor(.black)
                .textContentType(.newPassword)
                .id(SignUpField.confirm)
                .focused($focusedField, equals: .confirm)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.stroke))
    }

    private var submitButton: some View {
        Button(action: createAccount) {
            if isSubmitting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                Text("Create Account")
                    .font(.system(size: 17, weight: .semibold, design: .default).width(.condensed))
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.accentPrimary)
        .cornerRadius(6)
        .disabled(!canSubmit || isSubmitting)
    }

    private var closeButton: some View {
        Button("Close") { dismiss() }
    }
}

#Preview {
    SignInView().environmentObject(AuthViewModel())
}
