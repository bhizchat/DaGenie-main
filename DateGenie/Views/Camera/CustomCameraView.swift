import SwiftUI
import AVFoundation
import FirebaseCore



struct CustomCameraView: View {
	// Removed onComplete; view uses voice assistant only

    @State private var showProfile: Bool = false
    @EnvironmentObject private var userRepo: UserRepository
	@StateObject private var voiceVM = VoiceAssistantVM()
	@State private var isHoldingMic: Bool = false
	@State private var showImagePicker: Bool = false
	@State private var pickedImage: UIImage? = nil
	@State private var showStylePicker: Bool = false
	@State private var includeSound: Bool = true
	@State private var selectedStyleKey: String? = nil

	var body: some View {
		ZStack {
			Color.white.ignoresSafeArea()

			VStack(spacing: 24) {
				Image("Logo_DG")
					.resizable()
					.scaledToFit()
					.frame(width: 120, height: 120)
					.padding(.top, 28)
				if let img = voiceVM.attachedImage {
					ZStack(alignment: .topTrailing) {
						Image(uiImage: img)
							.resizable()
							.scaledToFit()
							.frame(maxWidth: 300, maxHeight: 320)
							.cornerRadius(12)
						Button(action: { withAnimation { voiceVM.attachedImage = nil } }) {
							Image(systemName: "xmark.circle.fill")
								.font(.system(size: 20, weight: .semibold))
								.foregroundColor(.black.opacity(0.75))
						}
						.offset(x: 10, y: -10)
					}
				}
			}
			.offset(y: -50)

            VStack {
                HStack {
                    Button(action: { showProfile = true }) {
                        ZStack {
                            Circle().stroke(Color.white, lineWidth: 2).frame(width: 36, height: 36)
                            if let urlStr = userRepo.profile.photoURL, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        Image(systemName: "person.circle")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
                                            .foregroundColor(.white)
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    case .failure:
                                        Image(systemName: "person.circle")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
                                            .foregroundColor(.white)
                                    @unknown default:
                                        Image(systemName: "person.circle")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(6)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                Spacer()
            }

            VStack {
                ZStack {
					// Mic: tap to start / tap to stop
					MicrophoneButton(
						isActive: voiceVM.uiState == .listening,
						onTap: {
							if voiceVM.uiState == .listening {
								UIImpactFeedbackGenerator(style: .medium).impactOccurred()
								voiceVM.stopListening(sendToLLM: true)
                            } else {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
								Task {
									let token = await fetchAssemblyToken()
									if let token = token {
										voiceVM.startListening(withToken: token)
                                        } else {
										print("[VoiceUI] token fetch returned nil")
									}
								}
							}
						}
					)
					.environmentObject(voiceVM)

					GeometryReader { geo in
						VStack(spacing: 6) {
							// Left camera icon: opens custom camera
							HStack(spacing: 180) {
								Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); openCamera() }) {
									Image("icon_camera_solid").resizable().scaledToFit().frame(width: 28, height: 28)
								}
								// Right plus icon: open photo picker
							Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); presentPicker() }) {
								Image("plus_icon").resizable().scaledToFit().frame(width: 28, height: 28)
							}
							}
						}
						.position(x: geo.size.width / 2, y: geo.size.height / 2)
					}
				}
				.offset(y: 300)
			}
		}
		.onAppear { voiceVM.speakIntroOnFirstOpen() }
		.onChange(of: pickedImage) { newValue in
			if let img = newValue { voiceVM.attachedImage = img }
		}
		.onChange(of: voiceVM.uiState) { _ in }
		.overlay(alignment: .top) {
			if voiceVM.showBanner || !voiceVM.assistantStreamingText.isEmpty {
				ZStack(alignment: .topTrailing) {
					Text(voiceVM.assistantStreamingText.isEmpty ? voiceVM.partialTranscript : voiceVM.assistantStreamingText)
						.font(.system(size: 18, weight: .semibold))
						.foregroundColor(.white)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.background(RoundedRectangle(cornerRadius: 30).fill(Color.black.opacity(0.5)))
					Button(action: {
						voiceVM.assistantStreamingText = ""
						voiceVM.partialTranscript = ""
						voiceVM.showBanner = false
					}) {
						Image(systemName: "xmark.circle.fill")
							.font(.system(size: 18, weight: .bold))
							.foregroundColor(.black.opacity(0.75))
					}
					.offset(x: 8, y: -8)
				}
				.padding(.top, 60)
				.padding(.horizontal, 24)
			}
		}
		// Style selection popup (full-screen) driven by VM.showStylePicker
		.fullScreenCover(isPresented: Binding(get: { voiceVM.showStylePicker }, set: { newVal in
			if !newVal { voiceVM.showStylePicker = false }
		})) {
			StyleSelectionPopup()
				.environmentObject(voiceVM)
		}
		.sheet(isPresented: $showProfile) {
			ProfileView().environmentObject(AuthViewModel()).environmentObject(userRepo)
		}
		.sheet(isPresented: $showImagePicker, onDismiss: {
			if let img = pickedImage { voiceVM.attachedImage = img }
		}) {
			ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
		}
		// New confirmation popup driven by overlayState
		.alert("Ready to create your ad?", isPresented: Binding(get: {
			if case .confirming = voiceVM.overlayState { return true }
			return false
		}, set: { newVal in
			if !newVal { voiceVM.transitionOverlay(to: .none) }
		})) {
			Button("Cancel", role: .cancel) { voiceVM.cancelAndAddDetails() }
			Button("Confirm") { Task { await voiceVM.confirmCreation() } }
		} message: {
			Text(voiceVM.confirmationSummary.isEmpty ? voiceVM.confirmationSubtitleText : voiceVM.confirmationSummary)
		}
		// Full-screen generating overlay driven by overlayState
		.fullScreenCover(isPresented: Binding(get: {
			if case .generating = voiceVM.overlayState { return true } else { return false }
		}, set: { newVal in
			if !newVal { voiceVM.transitionOverlay(to: .none) }
		})) {
			GeneratingView()
				.environmentObject(voiceVM)
		}
		// Present immediate preview when a final video URL arrives
		.onChange(of: voiceVM.generatedVideoURL) { url in
			guard let url else { return }
			let preview = UIHostingController(rootView: ReelPreviewView(url: url))
			preview.modalPresentationStyle = .overFullScreen
			preview.isModalInPresentation = true
			preview.view.backgroundColor = .black
			UIApplication.shared.topMostViewController()?.present(preview, animated: true)
		}
		// Visual style picker disabled
	}

	private func fetchAssemblyToken() async -> String? {
		let projectId = FirebaseApp.app()?.options.projectID ?? "dategenie"
		let primary = URL(string: "https://us-central1-\(projectId).cloudfunctions.net/getAssemblyToken")!
		let fallback = URL(string: "https://getassemblytoken-6vlzx6cvqa-uc.a.run.app")!
		for url in [primary, fallback] {
			var req = URLRequest(url: url)
			req.httpMethod = "GET"
			print("[VoiceUI] fetching token from \(url.absoluteString)")
			do {
				let (data, resp) = try await URLSession.shared.data(for: req)
				if let http = resp as? HTTPURLResponse { print("[VoiceUI] token resp status=\(http.statusCode)") }
				if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
					if let token = obj["token"] as? String { return token }
					print("[VoiceUI] token resp body=\(obj)")
            } else {
					if let s = String(data: data, encoding: .utf8) { print("[VoiceUI] token raw body=\(s)") }
				}
			} catch {
				print("[VoiceUI] token fetch error: \(error.localizedDescription)")
			}
		}
		return nil
	}

	private func presentPicker() {
		showImagePicker = true
	}

	private func openCamera() {
		// Use system camera picker to avoid missing environment objects in custom hosted view
		pickedImage = nil
		if UIImagePickerController.isSourceTypeAvailable(.camera) {
			let picker = UIHostingController(rootView: ImagePicker(image: Binding(get: { pickedImage }, set: { pickedImage = $0 }), sourceType: .camera))
			if let top = UIApplication.shared.topMostViewController() {
				top.present(picker, animated: true)
            }
        } else {
			showImagePicker = true
		}
	}
}

// MARK: - Generating Overlay
struct GeneratingView: View {
    @EnvironmentObject var voiceVM: VoiceAssistantVM
    @State private var spokenOnce: Bool = false

    var body: some View {
        ZStack {
            // Solid white generating screen as requested
            Color.white.ignoresSafeArea()
            VStack(spacing: 18) {
                GIFView(dataAssetName: "kettle_thinking")
                    .frame(width: 200, height: 200)
                Text("Your wish is my command — generating your ad")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .onAppear {
            if !spokenOnce {
                spokenOnce = true
                Task { await voiceVM.speakGeneratingEleven() }
            }
        }
    }
}

// MARK: - Style Selection Popup
struct StyleSelectionPopup: View {
    @EnvironmentObject var voiceVM: VoiceAssistantVM
    @State private var selected: VoiceAssistantVM.AdStyle? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    // Header lamp for brand continuity
                    Image("Logo_DG").resizable().scaledToFit().frame(width: 90, height: 90)

                    // Card: Cinematic
                    selectionCard(imageName: "Cinematic_ad", title: "Cinematic ad", isSelected: selected == .cinematic)
                        .onTapGesture { selected = .cinematic }

                    // Card: Creative animation
                    selectionCard(imageName: "Creative_animation", title: "Creative animation", isSelected: selected == .animation)
                        .onTapGesture { selected = .animation }

                    Button(action: {
                        guard let style = selected else { return }
                        voiceVM.applyStyleSelection(style: style)
                    }) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background((selected == nil) ? Color.gray.opacity(0.4) : Color.black)
                            .cornerRadius(12)
                    }
                    .disabled(selected == nil)
                    .padding(.top, 8)
                }
                .padding(20)
                .background(Color.white)
                .cornerRadius(16)
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func selectionCard(imageName: String, title: String, isSelected: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(12)
                Circle()
                    .fill(isSelected ? Color.green : Color.white)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .padding(8)
            }
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// Simple GIF renderer using WKWebView backed by a Data asset
import WebKit
struct GIFView: UIViewRepresentable {
    let dataAssetName: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard let data = NSDataAsset(name: dataAssetName)?.data else { return }
        uiView.load(data, mimeType: "image/gif", characterEncodingName: "utf-8", baseURL: URL(string: "about:blank")!)
    }
}

// MARK: - Overlay builder extracted to avoid deep nesting confusing the parser
private extension CustomCameraView {
    // Overlay presented when the user is choosing a video style
    // Extracted into its own computed property to avoid deeply nested code in the main body
	@ViewBuilder
    var stylePickerOverlay: some View {
		if voiceVM.uiState == .choosingStyle {
			VStack(alignment: .leading, spacing: 12) {
				Text("Choose your video style")
					.font(.system(size: 20, weight: .bold))
					.foregroundColor(.black)
					.padding(.horizontal, 16)
				Toggle(isOn: $includeSound) { Text("Include dialogue & sound effects") }
					.padding(.horizontal, 16)
				ScrollView(.vertical, showsIndicators: true) {
					VStack(spacing: 20) {
						ForEach(voiceVM.styleOptions) { opt in
							VStack(alignment: .leading, spacing: 8) {
								AsyncImage(url: opt.posterURL) { phase in
									switch phase {
									case .empty: Color.gray.opacity(0.2)
									case .success(let img): img.resizable().scaledToFill()
									case .failure: Color.gray.opacity(0.2)
									@unknown default: Color.gray.opacity(0.2)
									}
								}
								.frame(height: 180)
								.clipped()
								.cornerRadius(12)
								.overlay(
									RoundedRectangle(cornerRadius: 12)
										.stroke(selectedStyleKey == opt.key ? Color.blue : Color.clear, lineWidth: 3)
								)
								Text(opt.title)
									.font(.system(size: 18, weight: .semibold))
									.foregroundColor(.black)
								Text(opt.subtitle)
									.font(.system(size: 14))
									.foregroundColor(.black)
							}
							.onTapGesture { selectedStyleKey = opt.key }
						}
					}
					.padding(.horizontal, 16)
				}
			}
			.padding(.bottom, 16)
		}
	}
}

// MARK: - Subviews
struct MicrophoneButton: View {
	let isActive: Bool
	let onTap: () -> Void
	@State private var pressed = false
	@EnvironmentObject var voiceVM: VoiceAssistantVM

	var body: some View {
		Button(action: {
			onTap()
		}) {
			ZStack {
				// Base ring
				Circle()
					.stroke(Color.black, lineWidth: 6)
					.background(Circle().fill(Color.white))
				// Progress sweep when recording
				if isActive {
					Circle()
						.trim(from: 0, to: voiceVM.listenProgress)
						.stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
						.rotationEffect(.degrees(-90))
						.animation(.linear(duration: 0.05), value: voiceVM.listenProgress)
				}
				if isActive {
					Rectangle()
						.fill(Color.black)
						.frame(width: 26, height: 26)
						.cornerRadius(4)
        } else {
					Image("mic_asset")
						.renderingMode(.original)
						.resizable()
						.scaledToFit()
						.frame(width: 32, height: 32)
				}
			}
			.scaleEffect(pressed ? 1.1 : 1.0)
		}
		.buttonStyle(.plain)
		.frame(width: 82, height: 82)
		.contentShape(Circle())
		.simultaneousGesture(
			DragGesture(minimumDistance: 0)
				.onChanged { _ in if !pressed { withAnimation(.easeInOut(duration: 0.12)) { pressed = true } } }
				.onEnded { _ in withAnimation(.easeInOut(duration: 0.12)) { pressed = false } }
		)
    }
}

struct ShutterButton: View {
    let isRecording: Bool
    let progress: Double
    let onTap: () -> Void
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void

        @State private var isPressed = false
        @State private var holdTimer: Timer? = nil

        var body: some View {
            ZStack {
				Circle().stroke(Color.black, lineWidth: 6)
                if isRecording {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: progress)
                }
				Circle().fill(Color.black.opacity(0.12))
            }
            .frame(width: 82, height: 82)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            holdTimer?.invalidate()
                        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                            onHoldStart()
                        }
                        }
                    }
                    .onEnded { _ in
                        if let t = holdTimer, t.isValid {
                            t.invalidate()
                            onTap()
                    } else {
                        onHoldEnd()
                    }
                    isPressed = false
                }
        )
    }
}