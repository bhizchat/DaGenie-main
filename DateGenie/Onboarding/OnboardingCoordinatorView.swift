import SwiftUI

struct OnboardingCoordinatorView: View {
    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        ZStack {
            Color(red: 245/255, green: 170/255, blue: 82/255).ignoresSafeArea()
            Group {
                switch vm.step {
                case .name:
                    NameEntryView(vm: vm)
                case .upload:
                    LogoUploadView(vm: vm)
                }
            }
        }
    }
}

private struct NameEntryView: View {
    @ObservedObject var vm: OnboardingViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 32)
            Image("Logo_DG")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .background(Color.white)
                .cornerRadius(16)
            Text("Welcome to DaGenie")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Business Name")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                TextField("", text: $vm.businessName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($isFocused)
                    .padding(14)
                    .background(vm.isBusinessNameValid ? Color.white : Color.gray.opacity(0.35))
                    .cornerRadius(10)
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 24)

            Button(action: { UIApplication.hideKeyboard(); vm.advanceFromName() }) {
                Text("CONTINUE")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(vm.isBusinessNameValid ? Color.white : Color.gray.opacity(0.6))
                    .cornerRadius(12)
            }
            .disabled(!vm.isBusinessNameValid)
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isFocused = true } }
    }
}

private struct LogoUploadView: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var showPicker = false
    @State private var picked: UIImage? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 32)
            Text("BRING YOUR BRAND TO LIFE")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Upload your logo to create more personalized videos for your business.")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(0.9)

            Spacer()

            Button(action: { showPicker = true }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 180, height: 180)
                    if let img = vm.logoImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(22)
                    } else {
                        VStack(spacing: 10) {
                            Image("upload_icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .foregroundColor(.black)
                            Text("UPLOAD")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPicker, onDismiss: {
                if let picked = picked { vm.setLogoImage(picked) }
            }) {
                ImagePicker(image: $picked, sourceType: .photoLibrary)
            }

            // Business slogan input
            VStack(alignment: .leading, spacing: 8) {
                Text("Business Slogan")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                TextField("", text: $vm.businessSlogan)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .padding(14)
                    .background(vm.businessSlogan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.35) : Color.white)
                    .cornerRadius(10)
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: { vm.completeOnboarding() }) {
                Text("GET STARTED")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(vm.canGetStarted ? Color.white : Color.gray.opacity(0.6))
                    .cornerRadius(12)
            }
            .disabled(!vm.canGetStarted)
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)
        }
    }
}


