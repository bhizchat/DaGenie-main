//
//  AuthViewModel.swift
//  DateGenie
//
//  Handles Firebase authentication state and actions.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthViewModel: NSObject, ObservableObject {
    // Published Firebase user (nil when signed out)
    @Published var user: User?
    @Published var authError: Error?

    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    override init() {
        super.init()
        // initial user (if token persisted)
        user = Auth.auth().currentUser
        // observe auth state changes
        authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
    }

    deinit {
        if let h = authStateListenerHandle {
            Auth.auth().removeStateDidChangeListener(h)
        }
    }

    // MARK: - Email / Password
    func signIn(email: String, password: String) async {
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            authError = error
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String) async {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let user = result.user
            let display = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            let change = user.createProfileChangeRequest()
            change.displayName = display.isEmpty ? nil : display
            try? await change.commitChanges()
            // Persist to Firestore
            let db = FirebaseFirestore.Firestore.firestore()
            try? await db.collection("users").document(user.uid).setData([
                "firstName": firstName,
                "lastName": lastName,
                "displayName": display
            ], merge: true)
        } catch {
            authError = error
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
    
    func deleteAccount() async {
        guard let user = Auth.auth().currentUser else { return }
        do {
            try await user.delete()
        } catch {
            // If re-auth required, sign out instead and surface error
            await MainActor.run { self.authError = error }
        }
    }

    // MARK: - Apple Sign-In
    func appleButton() -> some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = self.randomNonce()
            self.currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authResults):
                guard let credential = authResults.credential as? ASAuthorizationAppleIDCredential else { return }
                Task { await self.firebaseSignIn(with: credential) }
            case .failure(let error):
                self.authError = error
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 48)
        .cornerRadius(6)
    }

    private func firebaseSignIn(with credential: ASAuthorizationAppleIDCredential) async {
        guard let nonce = currentNonce,
              let tokenData = credential.identityToken,
              let tokenString = String(data: tokenData, encoding: .utf8) else {
            self.authError = NSError(domain: "apple", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple identity token"])
            return
        }
        let authCredential = OAuthProvider.appleCredential(withIDToken: tokenString, rawNonce: nonce, fullName: credential.fullName)
        do {
            _ = try await Auth.auth().signIn(with: authCredential)
        } catch {
            self.authError = error
        }
    }

    // MARK: - Nonce helpers
    private func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess { fatalError("Unable to generate nonce. SecRandomCopyBytes failed.") }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
