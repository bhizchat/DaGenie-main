import SwiftUI
import FirebaseAuth
import FirebaseStorage
import PhotosUI
import UIKit

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var userRepo: UserRepository
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var pendingUsername: String = ""

    var body: some View {
        VStack(spacing: 24) {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(Color(red: 246/255, green: 182/255, blue: 86/255))
                    .frame(height: 220)
                    .overlay(
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color(white: 0.9)).frame(width: 180, height: 180)
                                // Profile image or placeholder
                                if let urlStr = userRepo.profile.photoURL, let url = URL(string: urlStr) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                                .onAppear { print("ProfileView AsyncImage – loading url=", urlStr) }
                                        case .success(let img):
                                            img.resizable().scaledToFill()
                                                .onAppear { print("ProfileView AsyncImage – success url=", urlStr) }
                                        case .failure:
                                            Image(systemName: "circle")
                                                .resizable().scaledToFit()
                                                .foregroundColor(.black.opacity(0.7))
                                                .onAppear { print("ProfileView AsyncImage – failure url=", urlStr) }
                                        @unknown default:
                                            Image(systemName: "circle")
                                                .resizable().scaledToFit()
                                                .foregroundColor(.black.opacity(0.7))
                                                .onAppear { print("ProfileView AsyncImage – unknown url=", urlStr) }
                                        }
                                    }
                                    .frame(width: 168, height: 168)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 140, height: 140)
                                        .foregroundColor(.black.opacity(0.7))
                                        .onAppear { print("ProfileView – photoURL = nil") }
                                }
                                // Plus button overlay (asset-backed if available)
                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    if UIImage(named: "icon_profile_plus") != nil {
                                        Image("icon_profile_plus")
                                            .resizable()
                                            .frame(width: 34, height: 34)
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .resizable()
                                            .frame(width: 34, height: 34)
                                            .foregroundColor(.black)
                                            .background(Circle().fill(Color.white))
                                    }
                                }
                                .offset(x: 76, y: 76)
                            }
                            // Show first + last name if available; fall back to display name or email prefix
                            Group {
                                let first = (userRepo.profile.firstName ?? "").trimmingCharacters(in: .whitespaces)
                                let last = (userRepo.profile.lastName ?? "").trimmingCharacters(in: .whitespaces)
                                let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                                if !combined.isEmpty {
                                    Text(combined)
                                } else if let dn = userRepo.profile.displayName, !dn.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text(dn)
                                } else if let email = authVM.user?.email {
                                    Text(String(email.split(separator: "@").first ?? "User"))
                                } else {
                                    Text("User")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 24)
                            .padding(.bottom, 4)
                            // Right-aligned 3-dot menu on the yellow header
                            HStack {
                                Spacer()
                                Menu {
                                    Button("Change username") { promptChangeUsername() }
                                    Button("Remove Profile Picture", role: .destructive) { removeProfilePicture() }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.title2)
                                        .foregroundColor(.black)
                                        .padding(.trailing, 16)
                                        .offset(y: -5)
                                }
                            }
                        }
                    )
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(12)
                }
            }

            VStack(spacing: 16) {
                Button(role: .destructive) {
                    Task { await authVM.deleteAccount(); dismiss() }
                } label: {
                    Text("Delete Account")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button {
                    authVM.signOut(); dismiss()
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 246/255, green: 182/255, blue: 86/255))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 24)

            // Community CTA
            VStack(spacing: 12) {
                Text("Join the Community 👇")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: 0x131563))

                Button {
                    openDiscordInvite()
                } label: {
                    HStack(spacing: 12) {
                        Image("discord")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Text("DISCORD")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(hex: 0x131563))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 246/255, green: 182/255, blue: 86/255))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .task { await userRepo.loadProfile() }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    // Load raw data then decode to UIImage for JPEG conversion
                    guard let rawData = try await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: rawData) else {
                        print("ProfileView picker – failed to load Data/UIImage")
                        return
                    }
                    guard let data = image.jpegData(compressionQuality: 0.9) else {
                        print("ProfileView picker – jpegData returned nil")
                        return
                    }
                    guard let uid = Auth.auth().currentUser?.uid else { return }
                    let ref = Storage.storage().reference().child("userProfile/\(uid)/avatar.jpg")
                    let meta = StorageMetadata(); meta.contentType = "image/jpeg"
                    print("ProfileView upload – starting \(data.count) bytes to \(ref.fullPath)")
                    ref.putData(data, metadata: meta) { _, error in
                        if let error = error {
                            print("ProfileView upload – error:", error.localizedDescription)
                            return
                        }
                        ref.downloadURL { url, err in
                            if let err = err {
                                print("ProfileView downloadURL – error:", err.localizedDescription)
                                return
                            }
                            guard let urlStr = url?.absoluteString else { print("ProfileView downloadURL – nil url"); return }
                            print("ProfileView upload – success url=", urlStr)
                            Task { @MainActor in
                                // Optimistically update local model then persist to Firestore
                                await userRepo.updatePhotoURL(urlStr)
                                await userRepo.loadProfile()
                            }
                        }
                    }
                } catch {
                    print("ProfileView picker – exception:", error.localizedDescription)
                }
            }
        }
        .alert("Change username", isPresented: Binding(get: { showingRename }, set: { _ in })) {
            // Placeholder: we'll drive showingRename via promptChangeUsername()
        } message: { EmptyView() }
    }
}
private var showingRename: Bool { false }

extension ProfileView {
    private func openDiscordInvite() {
        guard let url = URL(string: "https://discord.gg/mt5JusrCkz") else { return }
        UIApplication.shared.open(url)
    }

    private func promptChangeUsername() {
        // Simple inline prompt using UIKit alert for brevity
        guard let root = UIApplication.shared.topMostViewController() else { return }
        let alert = UIAlertController(title: "Change username", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "username"
            tf.text = userRepo.profile.username ?? authVM.user?.email?.split(separator: "@").first.map(String.init)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            let value = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                Task { await userRepo.updateUsername(value) }
            }
        }))
        root.present(alert, animated: true)
    }

    private func removeProfilePicture() {
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            // Clear Firestore field and cached model
            await userRepo.updatePhotoURL(nil)
            // Try to delete from Storage (ignore errors to avoid blocking UI)
            let ref = Storage.storage().reference().child("userProfile/\(uid)/avatar.jpg")
            ref.delete { error in
                if let e = error { print("removeProfilePicture – storage delete error:", e.localizedDescription) }
            }
        }
    }
}
