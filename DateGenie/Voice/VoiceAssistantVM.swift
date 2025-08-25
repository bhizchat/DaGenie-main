import Foundation
import AVFoundation
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit
import SwiftUI
import StoreKit

@MainActor
final class VoiceAssistantVM: ObservableObject {
	enum UIState { case idle, listening, thinking, speaking, choosingStyle }
	// Phase 1: Unified overlay state for confirmation/generating surfaces
	enum AdStyle { case cinematic, animation }
	enum OverlayState {
		case none
		case confirming(summary: String, style: AdStyle)
		case generating(style: AdStyle)
	}
	@Published var uiState: UIState = .idle
	@Published var overlayState: OverlayState = .none
	@Published var allowStreamingText: Bool = true
	@Published var showStylePicker: Bool = false
	@Published var partialTranscript: String = ""
	@Published var assistantStreamingText: String = ""
	@Published var showBanner: Bool = false
	@Published var listenProgress: Double = 0.0 // 0.0..1.0 progress for UI ring
	@Published var attachedImage: UIImage? = nil
	// New: style picker state
	struct StyleOption: Identifiable, Equatable {
		let id = UUID()
		let key: String
		let title: String
		let subtitle: String
		var previewURL: URL? // resolved Firebase download URL
		var posterURL: URL?
	}
	@Published var styleOptions: [StyleOption] = []
	@Published var pendingStyleOptions: [StyleOption]? = nil
	@Published var isResolvingPreviews: Bool = false
	@Published var lastBuiltPromptJSON: [String: Any]? = nil
	// Confirmation state for creation (kept for compatibility; driven by overlayState)
	@Published var isAwaitingConfirmation: Bool = false
	@Published var confirmationSummary: String = ""
	@Published var pendingStyleKey: String? = nil
	@Published var pendingAudioWithSound: Bool = true
	@Published var generatedVideoURL: URL? = nil
	// Generating overlay state
	@Published var isGenerating: Bool = false
	@Published var awaitingRepeat: Bool = false
	@Published var awaitingStylePrompt: Bool = false
	private var stylePromptRetried: Bool = false
	
	// Lightweight chat history for staged follow-ups
	private var chatHistory: [[String: String]] = [] // elements like ["role": "user"|"assistant", "content": text]

	private let assembly = AssemblyRealtime()
	private var sseTask: Task<Void, Never>?
	private var sseIntroFallbackTask: Task<Void, Never>?
	private var sseIntroAudioStarted: Bool = false
	private var sseIntroFallbackActivated: Bool = false
	private var audioPlayer: AVAudioPlayer?
	private let speechSynth = AVSpeechSynthesizer()
	private var speechDelegate: SpeechDelegate?
	private var streamingStarted = false
	private var didLoadFlags = false
	private var sseStartedAt: Date?
	private var sseFirstTokenAt: Date?
	private var lastFirstTokenLatencyMs: Int = -1
	private var minSessionTimer: Timer?
	private var listenStartAt: Date?
	private let maxListenSeconds: TimeInterval = 30.0
	private var generatingStartedAt: Date? = nil
	// Preferred ElevenLabs voice (can be made user-selectable later)
	private let ttsVoiceId: String = "L1aJrPa7pLJEyYlh3Ilq"
	private let firstLaunchKey: String = "dg_first_launch_greeting_v1"

	// Feature flags (can be backed by Remote Config later)
	struct STTFlags {
		var useKeytermsStreaming: Bool = true
		var forceEnglish: Bool = true
		var keytermsAtStartWindowMs: Int = 150
		var enableBriefFormatWindow: Bool = true
		var enableLegacyWordBoost: Bool = true
		var enableVerify: Bool = false
		var verifyABRatio: Double = 0.5
		// Phase 3 flags
		var targetChunkMs: Int = 100 // 80|100|160
		var endpointProfile: String = "balanced" // balanced|conservative|custom
	}
	private var sttFlags = STTFlags()
	private var metricVerifyRequests: Int = 0
	private var metricVerifyCorrections: Int = 0
	private var metricVerifyLatencyMsSum: Int = 0
	private var metricVerifyLatencyCount: Int = 0


	func startListening(withToken token: String) {
		guard uiState == .idle else { return }
		print("[VoiceAssistantVM] startListening")
		// Load server-driven flags once per app session
		Task { [weak self] in await self?.loadFlagsOnce() }
		// Ensure previous audio session/taps are fully torn down to avoid AU render -1
		assembly.stop()
		// NEW: cancel any ongoing SSE stream so we don't compete with recording
		sseTask?.cancel(); sseTask = nil
		// NEW: Stop any ongoing TTS cleanly before opening mic to avoid route contention
		if audioPlayer?.isPlaying == true { audioPlayer?.stop() }
		speechSynth.stopSpeaking(at: .immediate)
		// Deactivate playback session so record can take priority
		try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
		// Proactively stop any ongoing playback/TTS and allow brief settle before recording
		// Give the audio route a brief moment to settle before activating record
		usleep(150_000)
		AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
			Task { @MainActor in
				guard let self else { return }
				if !granted {
					print("[VoiceAssistantVM] mic permission denied")
					self.uiState = .idle
					self.assistantStreamingText = ""
					self.showBanner = true
					self.partialTranscript = "Microphone permission needed. Enable in Settings."
					return
				}
				// Update dynamic word boost from recent context before opening mic
				if self.sttFlags.enableLegacyWordBoost {
					let boost = self.buildContextWordBoost()
					self.assembly.updateWordBoost(boost)
				}
				// Build turn-specific keyterms and set language code
				if self.sttFlags.useKeytermsStreaming {
					let keyterms = self.buildContextKeyterms()
					self.assembly.updateKeyterms(keyterms)
				}
				self.assembly.setLanguageCode(self.sttFlags.forceEnglish ? "en" : nil)
				self.assembly.setBriefFormattingStartWindow(ms: self.sttFlags.enableBriefFormatWindow ? self.sttFlags.keytermsAtStartWindowMs : 0)
				// Apply Phase 3 runtime flags
				self.assembly.applyRuntimeFlags(targetChunkMs: self.sttFlags.targetChunkMs, endpointProfile: self.sttFlags.endpointProfile)
				self.uiState = .listening
				self.partialTranscript = ""
				self.assistantStreamingText = ""
				self.showBanner = true
				self.streamingStarted = false
				self.minSessionTimer?.invalidate(); self.minSessionTimer = nil
				print("[VoiceAssistantVM] opening realtime with token len=\(token.count)")
				self.assembly.start(withToken: token, onBegin: { [weak self] in
					Task { @MainActor in
						self?.streamingStarted = true
						print("[VoiceAssistantVM] session begin")
						// 30s window with smooth progress updates every 50 ms
						self?.listenStartAt = Date()
						self?.listenProgress = 0.0
						self?.minSessionTimer?.invalidate();
						self?.minSessionTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
							Task { @MainActor in
								guard let self else { return }
								guard self.uiState == .listening, let start = self.listenStartAt else { return }
								let elapsed = Date().timeIntervalSince(start)
								self.listenProgress = min(1.0, max(0.0, elapsed / self.maxListenSeconds))
								if elapsed >= self.maxListenSeconds {
									print("[VoiceAssistantVM] auto stop after 30s")
									self.stopListening(sendToLLM: true)
								}
							}
						}
					}
				}, onText: { [weak self] text in
					Task { @MainActor in self?.partialTranscript = text; print("[VM partial] \(text)") }
				}, onFinalText: { [weak self] text in
					Task { @MainActor in
						self?.handleFinalTranscript(text)
						print("[VM final] \(text)")
						// Capture per-turn ASR metrics snapshot and log
						let m = self?.assembly.metricsSnapshotAndReset() ?? [:]
						if !m.isEmpty {
							AnalyticsManager.shared.logEvent("asr_metrics", parameters: m)
						}
					}
				})
			}
		}
	}

	private func buildContextWordBoost() -> [String] {
		// Extract capitalized tokens and domain terms from the last assistant message
		let lastAssistant = chatHistory.reversed().first { $0["role"] == "assistant" }?["content"] ?? ""
		let tokens = lastAssistant.split{ !$0.isLetter && !$0.isNumber && $0 != Character("-") }
		var words: [String] = []
		for t in tokens {
			let s = String(t)
			if s.count >= 3 && s.first?.isUppercase == true { words.append(s) }
		}
		// Generic (non-brand) phrases only
		words.append(contentsOf: ["CTA", "add to cart", "coupon", "promo code", "retailer", "store locator"])
		return Array(Set(words)).prefix(50).map { String($0) }
	}

	private func buildContextKeyterms() -> [String] {
		var terms: [String] = []
		// 1) Generic CTA phrases (no brand seeding)
		let domainPrimary: [String] = [
			"add to cart", "coupon", "promo code", "retailer", "store locator"
		]
		terms.append(contentsOf: domainPrimary)
		// 2) Pull likely entities from the last assistant turn (capitalized words, 3–30 chars)
		let lastAssistant = chatHistory.reversed().first { $0["role"] == "assistant" }?["content"] ?? ""
		let tokens = lastAssistant.split { !$0.isLetter && !$0.isNumber && $0 != Character("-") }
		for t in tokens {
			let s = String(t)
			if s.first?.isUppercase == true && s.count >= 3 && s.count <= 30 { terms.append(s) }
		}
		// 2b) Pull likely entities from the last user turn
		let lastUser = chatHistory.reversed().first { $0["role"] == "user" }?["content"] ?? ""
		let userTokens = lastUser.split { !$0.isLetter && !$0.isNumber && $0 != Character("-") }
		for t in userTokens {
			let s = String(t)
			if s.first?.isUppercase == true && s.count >= 3 && s.count <= 30 { terms.append(s) }
		}
		// 2c) Include capitalized tokens from current partial transcript (if any)
		let partial = partialTranscript
		if !partial.isEmpty {
			let ptoks = partial.split { !$0.isLetter && !$0.isNumber && $0 != Character("-") }
			for t in ptoks {
				let s = String(t)
				if s.first?.isUppercase == true && s.count >= 3 && s.count <= 30 { terms.append(s) }
			}
		}
		// 2d) Lowercase nouns from latest user text and partial (length 4..30)
		func addLowercaseNouns(from text: String) {
			let toks = text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != Character("-") }
			for t in toks {
				let s = String(t)
				if s.count >= 4 && s.count <= 30 { terms.append(s) }
				// simple pluralization variants
				if s.hasSuffix("s"), s.count >= 5 { terms.append(String(s.dropLast())) }
				else if s.count >= 4 { terms.append(s + "s") }
			}
		}
		addLowercaseNouns(from: lastUser)
		addLowercaseNouns(from: partial)
		// 3) Include pending style key if present
		if let key = pendingStyleKey, !key.isEmpty { terms.append(key) }
		// 4) Filters: length 3..50, drop greetings/common fillers
		let stoplist: Set<String> = ["Hello", "Hey", "Hi", "Thanks", "Thank", "You"]
		let filtered = terms.filter { $0.count >= 3 && $0.count <= 50 && !stoplist.contains($0) }
		// 5) Dedup and clamp to ~100
		let unique = Array(Set(filtered)).prefix(100)
		return Array(unique)
	}

	func stopListening(sendToLLM: Bool = true) {
		print("[VoiceAssistantVM] stopListening sendToLLM=\(sendToLLM)")
		minSessionTimer?.invalidate(); minSessionTimer = nil
		listenStartAt = nil
		listenProgress = 0.0
		// Force endpoint to get a final quickly, then stop the stream
		assembly.forceEndpoint()
		// Wait briefly for a pending final; fallback to partial if none arrives
		let fallbackDelay: useconds_t = 200_000 // 200 ms
		usleep(fallbackDelay)
		assembly.stop()
		// Safety: if SSE was speaking, stop it so we always give a reply after stop
		sseTask?.cancel();
		var finalText = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
		if finalText.isEmpty {
			// If we didn't capture a final, try prompting the user politely instead of failing silently
			AnalyticsManager.shared.logEvent("voice_empty_final", parameters: ["reason": "manual_stop_empty"]) 
			// If we are in a style or generating prompt flow, stay silent to avoid confusion
			if awaitingStylePrompt || {
				if case .generating = overlayState { return true } else { return false }
			}() {
				uiState = .idle
				showBanner = false
				return
			}
			uiState = .idle
			showBanner = true
			assistantStreamingText = "I didn’t catch that — please say it again."
			awaitingRepeat = true
			// ElevenLabs voice; mic will reopen when TTS completes
			startIntroSSE(text: assistantStreamingText)
			return
		}
		if sendToLLM {
			print("[VoiceAssistantVM] manual stop textLen=\(finalText.count)")
			startSSE(with: finalText)
			uiState = .thinking
		} else {
			uiState = .idle
			showBanner = false
		}
		streamingStarted = false
	}

	private func handleFinalTranscript(_ text: String) {
		partialTranscript = text
		print("[VoiceAssistantVM] final transcript length=\(text.count)")
		// New: skip follow-ups; immediately generate from first input
		stopListening(sendToLLM: false)
		chatHistory.append(["role": "user", "content": text])
		Task { @MainActor in await self.confirmCreation() }
		// Keep verification telemetry (non-blocking)
		Task { @MainActor in
			await self.verifyIfCritical(streamingText: text)
		}
	}

	private func verifyIfCritical(streamingText: String) async {
		guard sttFlags.enableVerify else { return }
		// Heuristic: verify on numbers/brands OR low confidence OR short/uncertain utterances
		let lower = streamingText.lowercased()
		let hasNumber = lower.range(of: "\\d", options: .regularExpression) != nil
		let suspects = ["cta", "add to cart", "retailer"] // keep generic only
		let hasBrand = suspects.contains(where: { lower.contains($0) })
		// New: low-confidence and short-text triggers
		let eotConf = assembly.getLastEotConfidence()
		let isLowConf = eotConf < 0.8
		let isShort = streamingText.split{ $0 == " " }.count < 6
		let hasRepeatWord = {
			let ws = streamingText.lowercased().split{ !$0.isLetter }
			var seen = Set<String>()
			for w in ws { if seen.contains(String(w)) { return true } else { seen.insert(String(w)) } }
			return false
		}()
		guard hasNumber || hasBrand || isLowConf || isShort || hasRepeatWord else { return }
		// A/B gating
		if sttFlags.verifyABRatio < 1.0 {
			let roll = Double.random(in: 0..<1)
			guard roll < max(0.0, min(1.0, sttFlags.verifyABRatio)) else { return }
		}
		let pcm = assembly.finalAudioDataAndReset()
		guard !pcm.isEmpty else { return }
		print("[VoiceAssistantVM] verify pass initiating bytes=\(pcm.count)")
		do {
			let keyterms = self.buildContextKeyterms()
			let lang = self.sttFlags.forceEnglish ? "en" : nil
			let t0 = Date()
			let fixed = try await verifyTranscriptCallable(audioPcm16k: pcm, draft: streamingText, keyterms: keyterms, languageCode: lang)
			let dt = Int(Date().timeIntervalSince(t0) * 1000)
			self.metricVerifyRequests &+= 1
			self.metricVerifyLatencyMsSum &+= dt
			self.metricVerifyLatencyCount &+= 1
			if let fixed, fixed != streamingText {
				print("[VoiceAssistantVM] verification updated transcript")
				// Update last assistant prompt text if needed, or store for prompt building
				self.partialTranscript = fixed
				self.metricVerifyCorrections &+= 1
			}
			// --- Analytics: stt_verify with entity deltas + latency ---
			let before = streamingText
			let after = (fixed ?? streamingText)
			let numsBefore = extractNumbers(before)
			let numsAfter = extractNumbers(after)
			let emailsBefore = extractEmails(before)
			let emailsAfter = extractEmails(after)
			let brandsBefore = containsAnyKeyterm(before, keyterms: keyterms)
			let brandsAfter = containsAnyKeyterm(after, keyterms: keyterms)
			let applied = (fixed != nil && fixed != streamingText)
			AnalyticsManager.shared.logEvent("stt_verify", parameters: [
				"requested": 1,
				"latency_ms": dt,
				"correction_applied": applied ? 1 : 0,
				"numbers_before": numsBefore.count,
				"numbers_after": numsAfter.count,
				"emails_before": emailsBefore.count,
				"emails_after": emailsAfter.count,
				"brand_before": brandsBefore ? 1 : 0,
				"brand_after": brandsAfter ? 1 : 0,
				"downstream_first_token_ms": self.lastFirstTokenLatencyMs,
				"ab_ratio": self.sttFlags.verifyABRatio,
				"language_code": lang ?? "auto",
				"trigger_reason": hasNumber ? "numbers" : (hasBrand ? "brand" : (isLowConf ? "low_conf" : (isShort ? "short" : (hasRepeatWord ? "repeat" : "other"))))
			])
		} catch {
			print("[VoiceAssistantVM] verify error: \(error.localizedDescription)")
		}
	}

	private func verifyTranscriptCallable(audioPcm16k: Data, draft: String, keyterms: [String], languageCode: String?) async throws -> String? {
		let url = URL(string: "https://us-central1-\(Self.projectId()).cloudfunctions.net/verifyTranscript")!
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		if let token = try? await currentIdToken() { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
		let b64 = audioPcm16k.base64EncodedString()
		var payload: [String: Any] = ["audioPcm16kB64": b64, "draft": draft]
		if !keyterms.isEmpty { payload["keyterms"] = keyterms }
		if let code = languageCode { payload["language_code"] = code }
		let body: [String: Any] = ["data": payload]
		req.httpBody = try JSONSerialization.data(withJSONObject: body)
		let (data, resp) = try await URLSession.shared.data(for: req)
		guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
		let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		return obj?["fixed"] as? String
	}

	func startSSE(with userText: String) {
		sseTask?.cancel()
		assistantStreamingText = ""
		showBanner = true
		sseStartedAt = Date(); sseFirstTokenAt = nil; lastFirstTokenLatencyMs = -1
		// Non-blocking wake phrase: detect and strip “Hey, Genie …” if present,
		// but proceed even if the phrase is missing.
		let processed = stripWakePhraseIfPresent(userText)
		let textToSend = processed.stripped.trimmingCharacters(in: .whitespacesAndNewlines)
		// Require a product image before engaging the Q&A flow
		if attachedImage == nil {
			uiState = .idle
			assistantStreamingText = "I don’t see a product image yet. Please add one by taking a picture or tapping the plus, then type your idea below to begin."
			showBanner = true
			AnalyticsManager.shared.logEvent("image_required_block", parameters: ["phase": "pre_sse"])
			startIntroSSE(text: assistantStreamingText)
			return
		}
		let url = URL(string: "https://us-central1-\(Self.projectId()).cloudfunctions.net/voiceAssistant")!
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.addValue("text/event-stream", forHTTPHeaderField: "Accept")
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		// Record the new user message locally so we can gate style options by turn
		chatHistory.append(["role": "user", "content": textToSend])
		// Prepare history to send to backend
		var historyToSend = chatHistory
		print("[VoiceAssistantVM] startSSE imageAttached=\(attachedImage != nil) textLen=\(textToSend.count)")
		var body: [String: Any] = [
			"history": historyToSend,
			"voice": ttsVoiceId,
			"tts": "eleven"
		]
		if let dataUrl = attachedImageDataURL() { body["imageDataUrl"] = dataUrl }
		req.httpBody = try? JSONSerialization.data(withJSONObject: body)

		sseTask = Task { [weak self] in
			guard let self else { return }
			do {
				let (bytes, _) = try await URLSession.shared.bytes(for: req)
				for try await line in bytes.lines {
					if line.hasPrefix("data: ") {
						let payload = String(line.dropFirst(6))
						guard let data = payload.data(using: .utf8),
						      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
						await self.handleSSE(json)
					}
				}
			} catch {
				print("[VoiceAssistantVM] SSE error: \(error.localizedDescription)")
				// Suppress any fallback while style selection prompt is active or confirmation/generating overlays
				let isOverlayBlocking: Bool = {
					if case .confirming = self.overlayState { return true }
					if case .generating = self.overlayState { return true }
					return false
				}()
				if self.awaitingStylePrompt || isOverlayBlocking {
					await MainActor.run {
						self.uiState = .idle
						self.showBanner = false
						self.assistantStreamingText = ""
					}
					return
				}
				// Otherwise, route fallback via ElevenLabs and enable repeat mode
				await MainActor.run {
					self.uiState = .idle
					self.showBanner = true
					self.assistantStreamingText = "I didn’t catch that — please type your idea again using short, clear phrases."
					self.awaitingRepeat = true
				}
				self.startIntroSSE(text: "I didn’t catch that — please type your idea again using short, clear phrases.")
			}
		}
	}

	// MARK: - Wake phrase utilities
	private func reopenMicForRepeat() async {
		await MainActor.run {
			self.uiState = .idle
		}
		// Fetch token via the same path the UI uses
		let projectId = FirebaseApp.app()?.options.projectID ?? Self.projectId()
		guard let url = URL(string: "https://us-central1-\(projectId).cloudfunctions.net/getAssemblyToken") else { return }
		var req = URLRequest(url: url); req.httpMethod = "GET"
		do {
			let (data, _) = try await URLSession.shared.data(for: req)
			if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let token = obj["token"] as? String {
				await MainActor.run { self.awaitingRepeat = false }
				self.startListening(withToken: token)
			}
		} catch {
			print("[VoiceAssistantVM] reopenMicForRepeat token error: \(error.localizedDescription)")
		}
	}
	private func stripWakePhraseIfPresent(_ text: String) -> (stripped: String, found: Bool) {
		// Accept common variants and punctuation: "hey genie", "hi genie", "genie,"
		let lowered = text.lowercased()
		let variants = ["hey genie", "hi genie", "genie"]
		if let match = variants.first(where: { lowered.contains($0) }) {
			if let range = lowered.range(of: match) {
				let idx = range.upperBound
				let suffix = lowered[idx...]
				// Map back to original string using same index distances
				let utf16Start = lowered.utf16.distance(from: lowered.startIndex, to: idx)
				if let start = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Start, limitedBy: text.utf16.endIndex),
		   let scalarStart = String.Index(start, within: text) {
					let stripped = text[scalarStart...]
					return (String(stripped), true)
				}
			}
		}
		return (text, false)
	}

	// MARK: - Ad job creation + Veo kick-off (Phase 2 MVP)
	func createAdJobAndStart(transcript: String) async {
		guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
		print("[VoiceAssistantVM] createAdJobAndStart")
		do {
			guard let jobId = try await createAdJobCallable(transcript: transcript) else {
				print("[VoiceAssistantVM] createAdJob failed")
				return
			}
			// If user attached an image, upload it under this job and set inputImagePath before starting Veo
			if let _ = attachedImage {
				if let gsPath = try await uploadAttachedImage(jobId: jobId) {
					print("[VoiceAssistantVM] uploaded image gs=\(gsPath)")
					let db = Firestore.firestore()
					try await db.collection("adJobs").document(jobId).setData(["inputImagePath": gsPath], merge: true)
				} else {
					print("[VoiceAssistantVM] image upload skipped or failed")
				}
			}
			print("[VoiceAssistantVM] job=\(jobId) created; starting Veo…")
			_ = try await startVeoForJobCallable(jobId: jobId)
			await observeJob(jobId: jobId)
		} catch {
			print("[VoiceAssistantVM] createAdJobAndStart error: \(error.localizedDescription)")
		}
	}

	private func uploadAttachedImage(jobId: String) async throws -> String? {
		guard let img = attachedImage else { return nil }
		guard let uid = Auth.auth().currentUser?.uid else { return nil }
		let storage = Storage.storage()
		let ref = storage.reference(withPath: "user_uploads/\(uid)/\(jobId)/input.jpg")
		guard let data = img.jpegData(compressionQuality: 0.9) else { return nil }
		let metadata = StorageMetadata(); metadata.contentType = "image/jpeg"
		let _ = try await ref.putDataAsync(data, metadata: metadata)
		// Ensure Firebase creates a download token (used by server fallback)
		_ = try? await ref.downloadURL()
		return "gs://\(storage.reference().bucket)/user_uploads/\(uid)/\(jobId)/input.jpg"
	}

	private func createAdJobCallable(transcript: String) async throws -> String? {
		let url = URL(string: "https://us-central1-\(Self.projectId()).cloudfunctions.net/createAdJob")!
		let payload: [String: Any] = ["data": ["transcript": transcript]]
		let json = try await callCallable(url: url, payload: payload)
		if let result = json["result"] as? [String: Any], let jobId = result["jobId"] as? String { return jobId }
		if let jobId = json["jobId"] as? String { return jobId }
		return nil
	}

	private func startVeoForJobCallable(jobId: String) async throws -> Bool {
		let url = URL(string: "https://us-central1-\(Self.projectId()).cloudfunctions.net/startVeoForJob")!
		let payload: [String: Any] = ["data": ["jobId": jobId]]
		let json = try await callCallable(url: url, payload: payload)
		let status = (json["result"] as? [String: Any])?["status"] as? String ?? json["status"] as? String
		return status == "ready" || status == "pending" || status == "ok"
	}

	private func callCallable(url: URL, payload: [String: Any]) async throws -> [String: Any] {
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		if let token = try await currentIdToken() {
			req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		}
		req.httpBody = try JSONSerialization.data(withJSONObject: payload)
		let (data, resp) = try await URLSession.shared.data(for: req)
		guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			let body = String(data: data, encoding: .utf8) ?? "<no body>"
			throw NSError(domain: "callCallable", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
		}
		let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		return json ?? [:]
	}

	// New: createAdFromConversation callable wrapper
	private func createAdFromConversationCallable(messages: [[String:String]], productImageGsPath: String?) async throws -> (String?, [String: Any]) {
		let url = URL(string: "https://us-central1-\(Self.projectId()).cloudfunctions.net/createAdFromConversation")!
		var inner: [String: Any] = ["messages": messages]
		if let gs = productImageGsPath { inner["assets"] = ["productImageGsPath": gs] }
		let payload: [String: Any] = ["data": inner]
		let json = try await callCallable(url: url, payload: payload)
		let result = (json["result"] as? [String: Any]) ?? json
		let jobId = result["jobId"] as? String
		return (jobId, result)
	}

	private func currentIdToken() async throws -> String? {
		if let user = Auth.auth().currentUser {
			return try await user.getIDToken()
		}
		return nil
	}

	private func observeJob(jobId: String) async {
		let db = Firestore.firestore()
		db.collection("adJobs").document(jobId).addSnapshotListener { [weak self] snap, _ in
			guard let data = snap?.data() else { return }
			let status = data["status"] as? String ?? ""
			print("[VoiceAssistantVM] job status=\(status)")
			if status == "ready" {
				self?.uiState = .idle
				self?.showBanner = false
				self?.isGenerating = false
				self?.transitionOverlay(to: .none)
				if let start = self?.generatingStartedAt {
					let ms = Int(Date().timeIntervalSince(start) * 1000)
					AnalyticsManager.shared.logEvent("generating_ready", parameters: ["latency_ms": ms])
					self?.generatingStartedAt = nil
				}
				// Try common fields for final video URL
				let urlStr = (data["finalVideoUrl"] as? String) ?? (data["videoUrl"] as? String) ?? (data["outputUrl"] as? String)
				if let s = urlStr, let u = URL(string: s) {
					self?.generatedVideoURL = u
				}
			}
			if status == "error" {
				self?.isGenerating = false
				self?.transitionOverlay(to: .none)
				let err = data["error"] as? String ?? "unknown"
				AnalyticsManager.shared.logEvent("generating_error", parameters: ["message": err])
				if err == "image_required" || err == "image_sign_failed" {
					let msg = "I don’t see a product image yet. Please add one by taking a picture or tapping the plus, then try again."
					self?.assistantStreamingText = msg
					self?.showBanner = true
					self?.startIntroSSE(text: msg)
				}
			}
		}
	}

	private func handleSSE(_ json: [String: Any]) async {
		let type = json["type"] as? String
		switch type {
		case "meta":
			let img = (json["image"] as? Bool) ?? false
			let len = (json["lastUserLen"] as? Int) ?? -1
			print("[VoiceAssistantVM] server meta image=\(img) lastUserLen=\(len)")
		case "token":
			// Suppress any streamed text while confirmation/generating overlays are active
			guard allowStreamingText else { break }
			// Style picker removed: no awaitingStylePrompt gating
			if sseFirstTokenAt == nil {
				sseFirstTokenAt = Date()
				if let start = sseStartedAt {
					let ms = Int(Date().timeIntervalSince(start) * 1000)
					lastFirstTokenLatencyMs = ms
					AnalyticsManager.shared.logEvent("sse_first_token", parameters: ["latency_ms": ms])
				}
			}
			let t = (json["text"] as? String) ?? ""
			assistantStreamingText += t
			showBanner = true
			// Style picker removed: ignore style-choice cues
		case "audio":
			let size = (json["bytes"] as? Int) ?? -1
			print("[VoiceAssistantVM] received audio event bytes=\(size)")
			sseIntroAudioStarted = true
			if let b64 = json["base64"] as? String, let data = Data(base64Encoded: b64) {
				await playAudio(data, fallbackText: assistantStreamingText)
			}
			// Style picker removed
		case "tts_fallback":
			let msg = (json["message"] as? String) ?? ""
			let detail = (json["detail"] as? String) ?? ""
			print("[VoiceAssistantVM] tts_fallback msg=\(msg) detail=\(detail)")
			await speakLocally(assistantStreamingText)
		case "done":
			// If we intentionally suppressed streaming text (e.g., during confirmation/generating),
			// do NOT play any fallback or show a banner.
			if !allowStreamingText {
				uiState = .idle
				showBanner = false
				break
			}
			uiState = .idle
			let final = assistantStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
			if final.isEmpty {
				// Suppress any fallback entirely during generating
				if ({ if case .generating = overlayState { return true } else { return false } }()) {
					showBanner = false
					break
				}
				// If we are awaiting a repeat, reopen mic now
				if awaitingRepeat {
					await reopenMicForRepeat()
				} else {
					// Route fallback via ElevenLabs and then reopen mic
					awaitingRepeat = true
					let msg = "I didn’t catch that — please tap the mic and speak into it again one word at a time."
					assistantStreamingText = msg
					showBanner = true
					startIntroSSE(text: msg)
				}
			} else {
				chatHistory.append(["role": "assistant", "content": final])
			}
			showBanner = false
			// Style options removed
		case "style_options":
			break
		case "request_confirmation":
			// Style confirmation removed: ignore
			break
		default:
			break
		}
	}

	// MARK: - Overlay state transitions (Phase 1)
	func transitionOverlay(to newState: OverlayState) {
		let old = overlayState
		overlayState = newState
		print("[VoiceAssistantVM] overlay \(old) -> \(newState)")
		// Keep legacy flags in sync for any existing views
		switch newState {
		case .none:
			isAwaitingConfirmation = false
			isGenerating = false
			allowStreamingText = true
		case .confirming:
			isAwaitingConfirmation = true
			isGenerating = false
			allowStreamingText = false
		case .generating:
			isAwaitingConfirmation = false
			isGenerating = true
			allowStreamingText = false
		}
	}

	// MARK: - Confirmation helpers
	var confirmationSubtitleText: String {
		// Generic subtitle now that style selection is removed
		return "We’ll tailor the visuals and pacing based on what you shared."
	}

	// Style picker removed

	// MARK: - Flag loading (Firestore)
	private func loadFlagsOnce() async {
		if didLoadFlags { return }
		didLoadFlags = true
		await loadFlags()
	}

	private func loadFlags() async {
		let db = Firestore.firestore()
		do {
			let snap = try await db.collection("configs").document("voice_stt").getDocument()
			if let data = snap.data() {
				if let enable = data["enableVerify"] as? Bool { self.sttFlags.enableVerify = enable }
				if let ratio = data["verifyABRatio"] as? Double { self.sttFlags.verifyABRatio = ratio }
				if let tcm = data["targetChunkMs"] as? Int { self.sttFlags.targetChunkMs = tcm }
				if let ep = data["endpointProfile"] as? String { self.sttFlags.endpointProfile = ep }
			}
		} catch {
			print("[VoiceAssistantVM] loadFlags error: \(error.localizedDescription)")
		}
	}

	// MARK: - Entity helpers for analytics
	private func extractNumbers(_ s: String) -> [String] {
		let pattern = "[0-9][0-9,.:-]*"
		guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
		let range = NSRange(s.startIndex..., in: s)
		return re.matches(in: s, options: [], range: range).compactMap {
			Range($0.range, in: s).map { String(s[$0]) }
		}
	}

	private func extractEmails(_ s: String) -> [String] {
		let pattern = "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"
		guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
		let range = NSRange(s.startIndex..., in: s)
		return re.matches(in: s, options: [], range: range).compactMap {
			Range($0.range, in: s).map { String(s[$0]) }
		}
	}

	private func containsAnyKeyterm(_ text: String, keyterms: [String]) -> Bool {
		let lower = text.lowercased()
		return keyterms.contains(where: { lower.contains($0.lowercased()) })
	}

	// MARK: - Text input entry point (use instead of mic when desired)
	func submitText(_ text: String) {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		print("[VoiceAssistantVM] submitText len=\(trimmed.count)")
		// Require a product image; do not proceed without it
		if attachedImage == nil {
			assistantStreamingText = "I don’t see a product image yet. Please add one by taking a picture or tapping the plus, then hit Generate."
			showBanner = true
			return
		}
		// Bypass chat: immediately go to generating and kick off pipeline
		chatHistory.append(["role": "user", "content": trimmed])
		transitionOverlay(to: .generating(style: .cinematic))
		generatingStartedAt = Date()
		Task { @MainActor in await self.confirmCreation() }
	}

	func confirmCreation() async {
		// Hard gate: require subscription if user previously declined and is flagged
		let require = await SubscriptionGate.getRequireForGeneration()
		if !SubscriptionManager.shared.isSubscribed && require {
			await MainActor.run {
				if let top = UIApplication.shared.topMostViewController() {
					let hosting = UIHostingController(rootView: PaywallView())
					hosting.modalPresentationStyle = .pageSheet
					top.present(hosting, animated: true)
				}
			}
			return
		}
		// Hard-require an attached image before generating
		if attachedImage == nil {
			await MainActor.run {
				self.transitionOverlay(to: .none)
				self.uiState = .idle
				self.assistantStreamingText = "I don’t see a product image yet. Please add one by taking a picture or tapping the plus, then hit Confirm again."
				self.showBanner = true
			}
			AnalyticsManager.shared.logEvent("image_required_block", parameters: ["phase": "confirm"])
			startIntroSSE(text: assistantStreamingText)
			return
		}
		let lastUser = chatHistory.reversed().first { $0["role"] == "user" }?["content"] ?? ""
		do {
			// Enter generating state immediately
			await MainActor.run {
				self.generatingStartedAt = Date()
				self.transitionOverlay(to: .generating(style: .cinematic)) // placeholder style enum retained
			}
			// New flow: call createAdFromConversation with history + asset gs path. It will auto-start if image is present.
			// 1) Ensure image is uploaded and resolve gs path
			var gsPath: String? = nil
			if let _ = attachedImage { gsPath = try await uploadAttachedImage(jobId: UUID().uuidString) /* temp id only for path; server stores real job */ }
			// 2) Build messages with only the first user input to enforce one-shot generation
			let messages: [[String: String]] = [["role": "user", "content": lastUser]]
			// 3) Call server
			let (jobId, result) = try await self.createAdFromConversationCallable(messages: messages, productImageGsPath: gsPath)
			if let fmt = result["inferredFormat"] as? String { print("[VoiceAssistantVM] inferredFormat=\(fmt)") }
			guard let jobId else { throw NSError(domain: "VoiceAssistantVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "no jobId"]) }
			// 4) Observe job status
			await observeJob(jobId: jobId)
			await MainActor.run { self.isAwaitingConfirmation = false }
		} catch {
			print("[VoiceAssistantVM] confirmCreation pipeline error: \(error.localizedDescription)")
			// Keep generating screen visible while server may retry; error state will close it
		}
	}

	private func buildFinalPromptForJob(jobId: String, styleKey: String, withSound: Bool) async {
		let url = URL(string: "https://us-central1-\(Self.projectId()).cloudfunctions.net/voiceAssistant")!
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: Any] = [
			"action": "build_final_prompt",
			"history": chatHistory,
			"styleKey": styleKey,
			"audioPreference": withSound ? "with_sound" : "no_sound",
			"jobId": jobId
		]
		req.httpBody = try? JSONSerialization.data(withJSONObject: body)
		do {
			let (data, resp) = try await URLSession.shared.data(for: req)
			if let http = resp as? HTTPURLResponse { print("[VoiceAssistantVM] build_final_prompt status=\(http.statusCode)") }
			if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
				self.lastBuiltPromptJSON = obj
				print("[VoiceAssistantVM] built prompt json=\(obj)")
			}
		} catch {
			print("[VoiceAssistantVM] build_final_prompt error: \(error.localizedDescription)")
		}
	}

	func cancelAndAddDetails() {
		isAwaitingConfirmation = false
		assistantStreamingText = ""
		partialTranscript = ""
		showBanner = true
		assistantStreamingText = "Okay — add any extra details and hit the mic when you're ready."
		transitionOverlay(to: .none)
	}

	private func playAudio(_ data: Data, fallbackText: String) async {
		uiState = .speaking
		do {
			let session = AVAudioSession.sharedInstance()
			// Use plain .playback here; .defaultToSpeaker is only valid with .playAndRecord
			try? session.setCategory(.playback, mode: .default, options: [])
			try? session.setActive(true, options: [])
			print("[VoiceAssistantVM] init AVAudioPlayer bytes=\(data.count)")
			audioPlayer = try AVAudioPlayer(data: data)
			audioPlayer?.prepareToPlay()
			let ok = audioPlayer?.play() ?? false
			print("[VoiceAssistantVM] AVAudioPlayer.play()=\(ok)")
			DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 0)) {
				try? session.setActive(false, options: [.notifyOthersOnDeactivation])
				self.uiState = .idle
				self.showBanner = false
			}
		} catch {
			print("[VoiceAssistantVM] AVAudioPlayer error=\(error.localizedDescription)")
			await speakLocally(fallbackText)
		}
	}

	private func speakLocally(_ text: String) async {
		guard !text.isEmpty else { return }
		uiState = .speaking
		let session = AVAudioSession.sharedInstance()
		// Use .playback without .defaultToSpeaker for TTS
		try? session.setCategory(.playback, mode: .default, options: [])
		try? session.setActive(true)
		// Configure persistent synthesizer and delegate for reliable finish callback
		if speechDelegate == nil {
			speechDelegate = SpeechDelegate(onFinish: { [weak self] in
				guard let self else { return }
				try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
				self.uiState = .idle
				self.showBanner = false
			})
			speechSynth.delegate = speechDelegate
		}
		let utter = AVSpeechUtterance(string: text)
		utter.voice = AVSpeechSynthesisVoice(language: "en-US")
		speechSynth.speak(utter)
	}


	// One-shot generating line via ElevenLabs through existing SSE voice path
	func speakGeneratingEleven() async {
		let line = "Your wish is my command — generating your ad."
		// Reuse SSE path which streams from the server using ElevenLabs
		startIntroSSE(text: line)
	}

	func reset() {
		sseTask?.cancel(); sseTask = nil
		assembly.stop()
		uiState = .idle
		partialTranscript = ""
		assistantStreamingText = ""
		showBanner = false
		streamingStarted = false
		minSessionTimer?.invalidate(); minSessionTimer = nil
	}

	// MARK: - First launch greeting
	func speakIntroOnFirstOpen() {
		guard uiState == .idle else { return }
		var uidStr = Auth.auth().currentUser?.uid ?? "anon"
		let perUserKey = "\(firstLaunchKey)_\(uidStr)"
		let greeted = UserDefaults.standard.bool(forKey: perUserKey)
		let preferredName: String? = {
			if let repo = try? Self.resolveUserRepo(), let n = repo.profile.firstName, !n.trimmingCharacters(in: .whitespaces).isEmpty { return n }
			if let dn = Auth.auth().currentUser?.displayName, let first = dn.split(separator: " ").first { return String(first) }
			return nil
		}()
		let intro: String = {
			if !greeted {
				if let n = preferredName { return "Hello there, \(n), I’m the Genie — your creative AI ad specialist. Tap the plus to attach a product photo, then type what you want to create below and I’ll bring it to life." }
				return "Hello there, I’m the Genie — your creative AI ad specialist. Tap the plus to attach a product photo, then type what you want to create below and I’ll bring it to life."
			} else {
				let n = preferredName ?? "friend"
				let jokes = [
					"Welcome back, \(n)! I was beginning to think you left me in the lamp again.",
					"Ah, there you are, \(n)! I’ve been polishing the lamp and some ideas while you were gone.",
					"Good to see you, \(n). I promise I only granted push notifications while you were away."
				]
				return jokes.randomElement() ?? "Welcome back, \(n)! Ready to make some magic?"
			}
		}()
		print("[VoiceAssistantVM] playing intro via SSE/ElevenLabs greeted=\(greeted)")
		// Use ElevenLabs only for greeting; do not fall back to local TTS.
		startIntroSSE(text: intro)
		UserDefaults.standard.set(true, forKey: perUserKey)
	}

	private static func resolveUserRepo() throws -> UserRepository? {
		// Best-effort global access; in SwiftUI, views inject it but VM may be used elsewhere
		return UserRepository.shared
	}

	private func startIntroSSE(text: String, deadlineMs: Int? = nil) {
		sseTask?.cancel()
		sseIntroFallbackTask?.cancel(); sseIntroFallbackTask = nil
		sseIntroAudioStarted = false
		sseIntroFallbackActivated = false
		assistantStreamingText = ""
		showBanner = true
		let url = URL(string: "https://us-central1-\(Self.projectId()).cloudfunctions.net/voiceAssistant")!
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.addValue("text/event-stream", forHTTPHeaderField: "Accept")
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: Any] = [
			"speakText": text,
			"voice": ttsVoiceId,
			"tts": "eleven"
		]
		req.httpBody = try? JSONSerialization.data(withJSONObject: body)

		// Optional fast-start: if no audio arrives by the deadline, cancel SSE and speak locally
		if let ms = deadlineMs, ms > 0 {
			let deadline = UInt64(ms) * 1_000_000
			sseIntroFallbackTask = Task { [weak self] in
				try? await Task.sleep(nanoseconds: deadline)
				guard let self else { return }
				if !self.sseIntroAudioStarted {
					self.sseTask?.cancel()
					self.sseIntroFallbackActivated = true
					await self.speakLocally(text)
				}
			}
		}

		sseTask = Task { [weak self] in
			guard let self else { return }
			do {
				let (bytes, _) = try await URLSession.shared.bytes(for: req)
				for try await line in bytes.lines {
					if line.hasPrefix("data: ") {
						let payload = String(line.dropFirst(6))
						guard let data = payload.data(using: .utf8),
						      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
						await self.handleSSE(json)
						// When the TTS completes and we're awaiting a repeat, reopen mic
						if let t = json["type"] as? String, t == "done", self.awaitingRepeat {
							await self.reopenMicForRepeat()
						}
					}
				}
			} catch {
				print("[VoiceAssistantVM] Intro SSE error: \(error.localizedDescription)")
				// Retry once for style prompt; no Apple TTS
				if self.awaitingStylePrompt && !self.stylePromptRetried {
					self.stylePromptRetried = true
					self.startIntroSSE(text: text, deadlineMs: deadlineMs)
				}
			}
		}
	}

	// MARK: - Image helpers
	private func attachedImageDataURL() -> String? {
		guard let img = attachedImage else { return nil }
		guard let data = img.jpegData(compressionQuality: 0.85) else { return nil }
		let b64 = data.base64EncodedString()
		return "data:image/jpeg;base64,\(b64)"
	}

	// MARK: - Style previews resolution and confirm
	private func pathCandidates(for key: String, ext: String) -> [String] {
		// Prefer lowercase, but also try uppercase file extensions in case they were uploaded that way
		return ["style_previews/\(key).\(ext)", "style_previews/\(key).\(ext.uppercased())"]
	}
	
	private func downloadURL(for pathCandidates: [String]) async -> URL? {
		let storage = Storage.storage()
		for p in pathCandidates {
			do {
				let url = try await storage.reference(withPath: p).downloadURL()
				return url
			} catch {
				continue
			}
		}
		return nil
	}
	
	private func resolveURLPair(for key: String) async -> (URL?, URL?) {
		async let video = downloadURL(for: pathCandidates(for: key, ext: "mp4"))
		async let poster = downloadURL(for: pathCandidates(for: key, ext: "jpg"))
		return await (video, poster)
	}
	
	private func resolvePreviewURLs() async {
		isResolvingPreviews = true
		var updated: [StyleOption] = []
		for opt in styleOptions {
			let (v, p) = await resolveURLPair(for: opt.key)
			var o = opt
			o.previewURL = v
			o.posterURL = p
			updated.append(o)
		}
		styleOptions = updated
		isResolvingPreviews = false
	}

	private func isReadyForStyleOptionsGate() -> Bool {
		// Updated gating to surface visuals on the third question.
		// Sequence before visuals:
		// 1) Assistant ack + question (1)
		// 2) User answer (1)
		// 3) Assistant ack + CTA question (2)
		// 4) User answer (2)
		// 5) Assistant asks next question (3) → now allow visuals
		let assistantCount = chatHistory.filter { $0["role"] == "assistant" }.count
		let userCount = chatHistory.filter { $0["role"] == "user" }.count
		return assistantCount >= 3 && userCount >= 3
	}
	
	private func isReadyForConfirmation() -> Bool {
		// Must be past the Step 3 turn boundary (assistant>=3, user>=3)
		guard isReadyForStyleOptionsGate() else { return false }
		// Require explicit style choice in the last user answer (Step 3 answer)
		let lastUser = chatHistory.reversed().first { $0["role"] == "user" }?["content"] ?? ""
		let lowered = lastUser.lowercased()
		let hasStyle = lowered.contains("cinematic") || lowered.contains("animation")
		return hasStyle
	}
	
	func confirmStyleSelection(styleKey: String, withSound: Bool) async {
		guard !styleKey.isEmpty else { return }
		let url = URL(string: "https://us-central1-\(Self.projectId()).cloudfunctions.net/voiceAssistant")!
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: Any] = [
			"action": "build_final_prompt",
			"history": chatHistory,
			"styleKey": styleKey,
			"audioPreference": withSound ? "with_sound" : "no_sound"
		]
		req.httpBody = try? JSONSerialization.data(withJSONObject: body)
		do {
			let (data, resp) = try await URLSession.shared.data(for: req)
			if let http = resp as? HTTPURLResponse { print("[VoiceAssistantVM] build_final_prompt status=\(http.statusCode)") }
			let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
			self.lastBuiltPromptJSON = obj
			print("[VoiceAssistantVM] built prompt json=\(obj ?? [:])")
			uiState = .idle
			showBanner = false
		} catch {
			print("[VoiceAssistantVM] build_final_prompt error: \(error.localizedDescription)")
		}
	}

	// Helper to infer projectId
	private static func projectId() -> String {
		if let opts = FirebaseApp.app()?.options, let pid = opts.projectID { return pid }
		return "dategenie" // fallback
	}
}

// MARK: - Speech delegate helper
final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
	private let onFinish: () -> Void
	init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
	func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish() }
	func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onFinish() }
}
