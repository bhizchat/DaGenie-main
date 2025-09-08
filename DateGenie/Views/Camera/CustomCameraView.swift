import SwiftUI
import AVFoundation
import FirebaseCore



struct CustomCameraView: View {
	// Removed onComplete; view uses voice assistant only

    // Profile UI removed for this phase
	@StateObject private var voiceVM = VoiceAssistantVM()
	@State private var isHoldingMic: Bool = false
	@State private var showImagePicker: Bool = false
	@State private var pickedImage: UIImage? = nil
    @State private var composerText: String = ""
    var presentEditorOnSend: Bool = true
    var initialImage: UIImage? = nil
    var intro: AdIntroContent = .commercial
    private var archetype: Archetype { intro.archetype }

	var body: some View {
		ZStack {
			Color.white.ignoresSafeArea()

			// Header content
			ScrollView {
				AdHeaderView(intro: intro)
					.padding(.horizontal, 24)
					.frame(maxWidth: .infinity)
			}

            VStack {
                HStack {
                    Button(action: { UIApplication.shared.topMostViewController()?.dismiss(animated: true) }) {
                        Image("back_arrow")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                Spacer()
            }

            VStack {
                ZStack {
                    // Mic UI removed for text-only mode
                }
                .offset(y: 300)
            }
		}
		// Voice intro disabled for now – we'll revisit later
		.onAppear {
			/* voiceVM.speakIntroOnFirstOpen() */
			if let img = initialImage, voiceVM.attachedImage == nil {
				voiceVM.clearAttachmentPaths()
				voiceVM.attachedImage = img
				Task { await voiceVM.uploadAttachmentIfNeeded() }
			}
		}
		.onChange(of: pickedImage) { newValue in
			if let img = newValue {
				voiceVM.clearAttachmentPaths()
				voiceVM.attachedImage = img
				Task { await voiceVM.uploadAttachmentIfNeeded() }
			}
		}
		.onChange(of: voiceVM.attachedImage) { newVal in
			// Clear any lingering "image required" banner once an image is attached
			if newVal != nil {
				voiceVM.assistantStreamingText = ""
				voiceVM.showBanner = false
			}
		}
		.onChange(of: voiceVM.uiState) { _ in }
		// Streaming banner removed in this phase
		.overlay(alignment: .top) { EmptyView() }
		// Style picker removed
		.sheet(isPresented: $showImagePicker, onDismiss: {
			if let img = pickedImage {
				voiceVM.clearAttachmentPaths()
				voiceVM.attachedImage = img
				Task { await voiceVM.uploadAttachmentIfNeeded() }
			}
		}) {
			ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
		}
		// Present immediate preview when a final video URL arrives
		.onChange(of: voiceVM.generatedVideoURL) { url in
			guard let url else { return }
			// Notify any editor to insert the finished clip
			NotificationCenter.default.post(name: .AdGenComplete, object: nil, userInfo: ["url": url])
		}
		// Visual style picker removed
		.safeAreaInset(edge: .bottom) {
			CreativeInputBar(
				text: $composerText,
				attachments: Binding(get: {
					if let img = voiceVM.attachedImage { return [ImageAttachment(image: img)] }
					return []
				}, set: { arr in
					voiceVM.attachedImage = arr.first?.image
				}),
				onAddTapped: { presentPicker() },
				onSend: {
					let text = composerText
					composerText = ""
                    voiceVM.currentArchetype = archetype
					voiceVM.submitText(text)
					UIImpactFeedbackGenerator(style: .light).impactOccurred()
					UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
					// Present editor immediately in generating mode with placeholder (or keep current editor)
					if presentEditorOnSend {
						let placeholderURL = URL(fileURLWithPath: "/dev/null")
						let host = UIHostingController(rootView: CapcutEditorView(url: placeholderURL, initialGenerating: true))
						host.modalPresentationStyle = .overFullScreen
						UIApplication.shared.topMostViewController()?.present(host, animated: true) {
							NotificationCenter.default.post(name: .AdGenBegin, object: nil)
						}
					} else {
						NotificationCenter.default.post(name: .AdGenBegin, object: nil)
					}
				},
				isUploading: voiceVM.isUploadingAttachment
			)
			.ignoresSafeArea(edges: .bottom)
		}
        .contentShape(Rectangle())
        .onTapGesture { UIApplication.hideKeyboard() }
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

// Style selection popup removed

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
private extension CustomCameraView {}

// MARK: - Subviews
private struct AdHeaderView: View {
    let intro: AdIntroContent
    var body: some View {
        VStack(spacing: 0) {
            if let name = intro.imageName, UIImage(named: name) != nil {
                Image(name)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
                    .padding(.top, 12)
            } else {
                Image(systemName: "wand.and.stars")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .padding(.top, 12)
            }

            if let t = intro.title {
                Text(t)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            if let d = intro.description {
                Text(d)
                    .font(.callout)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 8)
            }

            if let ex = intro.example {
                Text(ex)
                    .font(.footnote)
                    .italic()
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
    }
}
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