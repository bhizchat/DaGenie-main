import Foundation
import AVFoundation

final class AssemblyRealtime: NSObject {
	private let sampleRate: Double = 16_000
	private let numChannels: AVAudioChannelCount = 1

	private let audioEngine = AVAudioEngine()
	private var inputFormat: AVAudioFormat?
	private var converter: AVAudioConverter?
	private var outputFormat: AVAudioFormat?

	private var webSocket: URLSessionWebSocketTask?
	private var urlSession: URLSession?
	private var connectionOpen = false
	private var receiving = false
	private var pingTimer: Timer?
	private var connectionStartAt: Date?

	// Buffer early audio (~1.0s) while the socket establishes to avoid losing first words
	private var prebuffer = Data()
	private let prebufferQueue = DispatchQueue(label: "AssemblyRealtime.prebuffer")
	private var prebufferSeconds: Double = 1.0
	private var prebufferLimitBytes: Int { Int(sampleRate * 2 * prebufferSeconds) } // 16kHz * 2 bytes * seconds

	// Adaptive chunking for network sends
	private var targetChunkMs: Int = 100 // configurable A/B: 80|100|160
	private var pendingChunk = Data()
	private var pendingChunkMs: Int = 0
	private let flushCapWhileGatedMs: Int = 800 // avoid >1000ms input duration while SoS gate is active

	// Accumulated PCM for the current turn (16k PCM s16le)
	private var currentTurnPcm = Data()

	// SoS gating (speech onset) for prebuffer flush
	private var sosDetected: Bool = false
	private var gateFlushUntilSoS: Bool = false
	private var beginOpenedAt: Date?
	private let sosTimeoutMs: Int = 2500
	private let sosAmplitudeThreshold: Int = 800 // avg |int16| amplitude

	// Low-confidence end-of-turn guard
	private var pendingFinalizeWorkItem: DispatchWorkItem?
	private let finalizeDelayMs: Int = 700
	private let finalizeTailMs: Int = 300
	private let lowConfidenceThreshold: Double = 0.6

	// Endpointing profile (configurable)
	private var endOfTurnConfThreshold: Double = 0.85
	private var minEotSilenceConfidentMs: Int = 300
	private var maxEotSilenceMs: Int = 3000

	// Domain vocabulary to bias transcription toward
	private let wordBoost: [String] = [
		"Genie", "Veo", "Coca-Cola", "Coca Cola", "Coke",
		"call to action", "retailer", "add to cart", "grocery delivery",
		"campus", "ad", "creative"
	]

	// Optional language code to force routing (e.g., "en")
	private var languageCode: String? = nil
	// Pending keyterms to apply on session start and updates
	private var pendingKeyterms: [String] = []
	// Brief formatting window at session start (ms) so keyterms influence early decoding
	private var briefFormattingStartMs: Int = 150

	// Telemetry counters (lightweight)
	private var metric_forceEndpoints: Int = 0
	private var metric_delayedFinalizes: Int = 0
	private var metric_tailSumMs: Int = 0
	private var metric_tailCount: Int = 0
	private static var movingBeginAvgMs: Double = 0
	private static var movingBeginCount: Int = 0

	private var onTextHandler: ((String) -> Void)?
	private var onFinalTextHandler: ((String) -> Void)?
	private var onSessionBegin: (() -> Void)?

	// --- Per-turn metrics ---
	private var beginAt: Date?
	private var firstInterimAt: Date?
	private var endOfTurnAt: Date?
	private var finalAt: Date?
	private var lastTailAppliedMs: Int = 0
	private var lastEotManual: Bool = false
	private var lastEotConfidence: Double = 1.0

	// Internal state guards to prevent double-start/double-tap crashes
	private var tapInstalled = false
	private var engineStarted = false

	func start(withToken token: String,
	           onBegin: (() -> Void)? = nil,
	           onText: @escaping (String) -> Void,
	           onFinalText: @escaping (String) -> Void) {
		// Ensure any previous session is fully torn down before starting again
		if webSocket != nil || connectionOpen || tapInstalled || engineStarted {
			stop()
		}
		onTextHandler = onText
		onFinalTextHandler = onFinalText
		onSessionBegin = onBegin
		setupAudioSession()
		setupConversion()
		// Start capturing immediately; prebuffer until ASR signals Begin
		startTapping()
		openSocket(token: token)
	}

	func stop() {
		if connectionOpen { sendJSON(["terminate_session": true]) }
		connectionOpen = false
		receiving = false
		pingTimer?.invalidate(); pingTimer = nil
		webSocket?.cancel(with: .goingAway, reason: nil)
		webSocket = nil
		urlSession?.invalidateAndCancel()
		teardownAudio()
	}

	private func setupAudioSession() {
		let session = AVAudioSession.sharedInstance()
		try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
		try? session.setPreferredSampleRate(sampleRate)
		try? session.setPreferredIOBufferDuration(0.08) // try ~80ms buffers (A/B configurable)
		try? session.setActive(true, options: [])
	}

	private func setupConversion() {
		let input = audioEngine.inputNode
		inputFormat = input.inputFormat(forBus: 0)
		outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: numChannels, interleaved: false)
		if let inFmt = inputFormat, let outFmt = outputFormat { converter = AVAudioConverter(from: inFmt, to: outFmt) }
		// Re-enable Apple voice processing (AEC/NR/AGC) for robust near-field defaults
		try? audioEngine.inputNode.setVoiceProcessingEnabled(true)
	}

	private func teardownAudio() {
		if tapInstalled {
			audioEngine.inputNode.removeTap(onBus: 0)
			tapInstalled = false
		}
		audioEngine.stop()
		engineStarted = false
		prebuffer.removeAll()
		try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
	}

	private func startTapping() {
		guard let outFmt = outputFormat else { return }
		let input = audioEngine.inputNode
		let bus: AVAudioNodeBus = 0
		// Remove any existing tap before installing a new one
		if tapInstalled {
			input.removeTap(onBus: bus)
			tapInstalled = false
		}
		let desiredFrames = AVAudioFrameCount(((self.inputFormat?.sampleRate ?? self.sampleRate) * 0.05).rounded()) // capture ~50ms; we will aggregate to ~100ms
		input.installTap(onBus: bus, bufferSize: desiredFrames, format: inputFormat) { [weak self] buffer, _ in
			guard let self else { return }
			// Convert the input buffer to 16k mono int16
			guard let converter = self.converter else { return }
			let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(outFmt.sampleRate / 20))! // ~50ms
			var error: NSError?
			let inputBlock: AVAudioConverterInputBlock = { _, outStatus in outStatus.pointee = .haveData; return buffer }
			converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
			if error != nil { return }
			guard let ch0 = pcmBuffer.int16ChannelData?.pointee else { return }
			let frameLen = Int(pcmBuffer.frameLength)
			let byteCount = frameLen * MemoryLayout<Int16>.size
			let data = Data(bytes: ch0, count: byteCount)
			// Simple SoS detection using avg |int16|
			var sumAbs: Int = 0
			// Use magnitude to avoid overflow trap on Int16.min when calling abs()
			for i in 0..<frameLen {
				sumAbs &+= Int(ch0[i].magnitude)
			}
			let avgAbs = frameLen > 0 ? sumAbs / frameLen : 0
			if !sosDetected && avgAbs > sosAmplitudeThreshold { sosDetected = true }
			let ms = max(1, Int((Double(frameLen) / outFmt.sampleRate) * 1000.0))
			// If socket not ready yet, prebuffer instead of dropping the first words
			if !connectionOpen {
				self.appendToPrebuffer(data)
			} else {
				// Gate prebuffer flush until SoS or timeout
				if gateFlushUntilSoS {
					if sosDetected || (beginOpenedAt != nil && Int(Date().timeIntervalSince(beginOpenedAt!) * 1000) > sosTimeoutMs) {
						flushPrebufferIfNeeded(); gateFlushUntilSoS = false
					}
				}
				// Aggregate to ~targetChunkMs before sending; while gated keep chunks small and capped
				pendingChunk.append(data)
				currentTurnPcm.append(data)
				pendingChunkMs += ms
				if pendingChunkMs >= targetChunkMs && (!gateFlushUntilSoS || pendingChunkMs >= flushCapWhileGatedMs) {
					let toSend = pendingChunk; pendingChunk.removeAll(keepingCapacity: true); pendingChunkMs = 0
					webSocket?.send(.data(toSend)) { err in if let err = err { print("[AssemblyRealtime] send error: \(err.localizedDescription)") } }
				}
			}
		}
		tapInstalled = true
		if !audioEngine.isRunning {
			try? audioEngine.start()
			engineStarted = true
		}
	}

	private func appendToPrebuffer(_ data: Data) {
		guard !data.isEmpty else { return }
		prebufferQueue.sync {
			if prebuffer.count + data.count > prebufferLimitBytes {
				let overflow = prebuffer.count + data.count - prebufferLimitBytes
				if overflow >= prebuffer.count {
					prebuffer.removeAll()
				} else {
					prebuffer.removeFirst(overflow)
				}
			}
			prebuffer.append(data)
		}
	}

	private func flushPrebufferIfNeeded() {
		// Atomically swap out the prebuffer to avoid any copy-on-write surprises
		let bufferSnapshot: Data = prebufferQueue.sync {
			let snap = prebuffer
			prebuffer = Data()
			return snap
		}
		let total = bufferSnapshot.count
		guard total > 0 else { return }
		let bytesPerChunk = Int(sampleRate / 20) * MemoryLayout<Int16>.size // ~50ms at 16kHz
		var offset = 0
		while offset < total {
			let safeEnd = min(offset + bytesPerChunk, total)
			guard safeEnd > offset else { break }
			let range = offset..<safeEnd
			let chunk = bufferSnapshot.subdata(in: range)
			if !chunk.isEmpty {
				webSocket?.send(.data(chunk)) { err in if let err = err { print("[AssemblyRealtime] prebuffer send error: \(err.localizedDescription)") } }
			}
			offset = safeEnd
		}
	}

	private func openSocket(token: String) {
		let url = URL(string: "wss://streaming.assemblyai.com/v3/ws?sample_rate=16000&encoding=pcm_s16le&token=\(token)")!
		var req = URLRequest(url: url)
		urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
		webSocket = urlSession!.webSocketTask(with: req)
		webSocket!.resume()
		connectionStartAt = Date()
		beginOpenedAt = Date(); sosDetected = false; gateFlushUntilSoS = true
		receiveLoop()
	}

	private func receiveLoop() {
		guard let ws = webSocket else { return }
		receiving = true
		ws.receive { [weak self] result in
			guard let self else { return }
			switch result {
			case .failure(let err):
				print("[AssemblyRealtime] receive error: \(err.localizedDescription)")
				self.receiving = false
			case .success(let msg):
				switch msg {
				case .string(let text):
					print("[AssemblyRealtime] <= \(text)")
					self.handleMessage(text)
				case .data(let data):
					if let text = String(data: data, encoding: .utf8) { print("[AssemblyRealtime] <= \(text)"); self.handleMessage(text) }
				@unknown default: break
				}
				if self.receiving { self.receiveLoop() }
			}
		}
	}

	private func handleMessage(_ text: String) {
		guard let data = text.data(using: .utf8),
		      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
		let type = (json["type"] as? String) ?? ""
		if type == "Begin" {
			connectionOpen = true
			startPing();
			// Cancel any pending finalize from a previous turn to avoid cross-turn flush
			cancelPendingFinalize()
			// Reset per-turn metrics
			beginAt = Date(); firstInterimAt = nil; endOfTurnAt = nil; finalAt = nil; lastTailAppliedMs = 0; lastEotManual = false
			onSessionBegin?()
			if let t0 = connectionStartAt { print("[AssemblyRealtime] time_to_begin_ms=\(Int(Date().timeIntervalSince(t0)*1000))") }
			// Update moving average and adapt prebuffer next session
			if let t0 = connectionStartAt {
				let ms = Double(Int(Date().timeIntervalSince(t0)*1000))
				let n = Double(Self.movingBeginCount)
				Self.movingBeginAvgMs = (Self.movingBeginAvgMs * n + ms) / max(1, n + 1)
				Self.movingBeginCount += 1
				let avg = Self.movingBeginAvgMs
				// Adjust for next session (0.6s .. 1.2s)
				if avg > 900 { prebufferSeconds = 1.2 } else if avg < 600 { prebufferSeconds = 0.6 } else { prebufferSeconds = 1.0 }
			}
			// Flush any buffered audio captured while waiting for Begin
			flushPrebufferIfNeeded()
			// Send initial configuration: unformatted interim for latency
			sendInitialConfig()
			return
		}
		if type == "Termination" {
			print("[ASR termination] \(json)")
			return
		}
		if type == "Turn" {
			let transcript = (json["transcript"] as? String) ?? ""
			let endOfTurn = (json["end_of_turn"] as? Bool) ?? false
			let confidence = (json["end_of_turn_confidence"] as? Double) ?? 1.0
			if !transcript.isEmpty {
				print("[ASR turn] \(transcript) eot=\(endOfTurn) conf=\(String(format: "%.2f", confidence))")
				// Any new incoming text cancels a pending finalize
				cancelPendingFinalize()
				// Metrics: first interim latency
				if firstInterimAt == nil { firstInterimAt = Date() }
				if endOfTurn {
					// Turn formatting ON for the final pass
					updateFormatting(isOn: true)
					endOfTurnAt = Date(); lastEotConfidence = confidence
					if confidence < lowConfidenceThreshold {
						// Delay longer on low confidence
						onTextHandler?(transcript)
						scheduleFinalize(afterMs: finalizeDelayMs, transcript: transcript, countAsTail: true)
					} else {
						// Apply a short tail even on high confidence
						onTextHandler?(transcript)
						scheduleFinalize(afterMs: finalizeTailMs, transcript: transcript, countAsTail: true)
					}
				} else {
					onTextHandler?(transcript)
				}
			}
		}
	}

	private func sendJSON(_ obj: [String: Any]) {
		guard let ws = webSocket, let data = try? JSONSerialization.data(withJSONObject: obj), let str = String(data: data, encoding: .utf8) else { return }
		ws.send(.string(str)) { err in if let err = err { print("[AssemblyRealtime] send error: \(err.localizedDescription)") } }
	}

	// Public control messages
	func forceEndpoint() {
		metric_forceEndpoints += 1
		sendJSON(["type": "ForceEndpoint"])
		lastEotManual = true
	}

	private func sendInitialConfig() {
		var cfg: [String: Any] = [
			"type": "UpdateConfiguration",
			"format_text": false,
			"punctuate": false,
			"end_of_turn_confidence_threshold": endOfTurnConfThreshold,
			"min_end_of_turn_silence_when_confident_ms": minEotSilenceConfidentMs,
			"max_end_of_turn_silence_ms": maxEotSilenceMs
		]
		if let code = languageCode, !code.isEmpty { cfg["language_code"] = code }
		if !pendingKeyterms.isEmpty { cfg["keyterms"] = pendingKeyterms }
		print("[AssemblyRealtime] sending initial ASR config")
		sendJSON(cfg)
		// Briefly enable formatting so keyterms apply to early decoding, then turn off
		if briefFormattingStartMs > 0 {
			print("[AssemblyRealtime] brief formatting ON for \(briefFormattingStartMs)ms")
			updateFormatting(isOn: true)
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(briefFormattingStartMs)) { [weak self] in
				self?.updateFormatting(isOn: false)
				print("[AssemblyRealtime] brief formatting OFF")
			}
		}
	}

	private func updateFormatting(isOn: Bool) {
		let cfg: [String: Any] = [
			"type": "UpdateConfiguration",
			"format_text": isOn,
			"punctuate": isOn
		]
		sendJSON(cfg)
	}

	// Public: allow VM to change chunk size / endpoint profile at runtime (flags)
	func applyRuntimeFlags(targetChunkMs: Int?, endpointProfile: String?) {
		if let t = targetChunkMs { setTargetChunkMs(t) }
		if let p = endpointProfile { setEndpointProfile(p) }
	}

	// Public: configure chunk size A/B
	func setTargetChunkMs(_ ms: Int) {
		let allowed = [80, 100, 160]
		targetChunkMs = allowed.contains(ms) ? ms : 100
		print("[AssemblyRealtime] set targetChunkMs=\(targetChunkMs)")
	}

	// Public: endpointing profile switcher
	func setEndpointProfile(_ profile: String) {
		switch profile.lowercased() {
		case "conservative":
			endOfTurnConfThreshold = 0.92
			minEotSilenceConfidentMs = 450
			maxEotSilenceMs = 3500
		case "custom":
			// Leave as-is for custom tuning
			break
		default: // balanced
			endOfTurnConfThreshold = 0.85
			minEotSilenceConfidentMs = 300
			maxEotSilenceMs = 3000
		}
		print("[AssemblyRealtime] endpoint profile=\(profile) thr=\(endOfTurnConfThreshold) min=\(minEotSilenceConfidentMs) max=\(maxEotSilenceMs)")
		if connectionOpen { sendInitialConfig() }
	}

	// Public: allow callers (e.g., VM) to toggle formatting briefly at turn start/end
	func setFormattingEnabled(_ on: Bool) {
		updateFormatting(isOn: on)
		print("[AssemblyRealtime] formatting \(on ? "ON" : "OFF")")
	}

	// Public: configure brief formatting window duration at session start
	func setBriefFormattingStartWindow(ms: Int) {
		briefFormattingStartMs = max(0, ms)
	}

	func updateWordBoost(_ words: [String]) {
		guard !words.isEmpty else { return }
		let unique = Array(Set(words)).prefix(50)
		let cfg: [String: Any] = [
			"type": "UpdateConfiguration",
			"word_boost": Array(unique),
			"boost_param": "high"
		]
		sendJSON(cfg)
	}

	// New: Streaming keyterms prompting (Universal-Streaming)
	func updateKeyterms(_ terms: [String]) {
		guard !terms.isEmpty else { return }
		let unique = Array(Set(terms)).prefix(100)
		pendingKeyterms = Array(unique)
		print("[AssemblyRealtime] set keyterms count=\(pendingKeyterms.count) sample=\(pendingKeyterms.prefix(3))")
		if connectionOpen {
			let cfg: [String: Any] = [
				"type": "UpdateConfiguration",
				"keyterms": pendingKeyterms
			]
			sendJSON(cfg)
		}
	}

	// New: Set or clear a fixed language code for the session
	func setLanguageCode(_ code: String?) {
		languageCode = code
		var cfg: [String: Any] = ["type": "UpdateConfiguration"]
		if let c = code, !c.isEmpty { cfg["language_code"] = c }
		print("[AssemblyRealtime] set language_code=\(code ?? "<nil>")")
		sendJSON(cfg)
	}

	private func scheduleFinalize(afterMs: Int, transcript: String, countAsTail: Bool = false) {
		cancelPendingFinalize()
		let work = DispatchWorkItem { [weak self] in
			if countAsTail { self?.metric_delayedFinalizes += 1; self?.metric_tailSumMs += afterMs; self?.metric_tailCount += 1 }
			self?.lastTailAppliedMs = afterMs
			// Provide final PCM for optional verification
			let pcm = self?.finalAudioDataAndReset() ?? Data()
			// Call final text handler first (existing flow); VM may call back into us for PCM
			self?.onFinalTextHandler?(transcript)
			self?.finalAt = Date()
			// Turn formatting back off for next turn
			self?.updateFormatting(isOn: false)
		}
		pendingFinalizeWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(afterMs), execute: work)
	}

	func finalAudioDataAndReset() -> Data {
		let d = currentTurnPcm
		currentTurnPcm.removeAll(keepingCapacity: false)
		return d
	}

	private func cancelPendingFinalize() {
		pendingFinalizeWorkItem?.cancel(); pendingFinalizeWorkItem = nil
	}

	private func startPing() {
		pingTimer?.invalidate()
		pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
			guard let self, let ws = self.webSocket else { return }
			ws.sendPing { err in if let err = err { print("[AssemblyRealtime] ping error: \(err.localizedDescription)") } }
		}
	}
}

extension AssemblyRealtime: URLSessionWebSocketDelegate {
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
		print("[AssemblyRealtime] socket opened")
	}
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
		let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "<none>"
		print("[AssemblyRealtime] socket closed code=\(closeCode.rawValue) reason=\(reasonStr)")
		pingTimer?.invalidate(); pingTimer = nil
		connectionOpen = false
	}
}

// MARK: - Metrics snapshot (exposed to VM)
extension AssemblyRealtime {
	func metricsSnapshotAndReset() -> [String: Int] {
		var out: [String: Int] = [:]
		if let b = beginAt, let i = firstInterimAt { out["interim_latency_ms"] = Int(i.timeIntervalSince(b) * 1000) }
		if let e = endOfTurnAt, let f = finalAt { out["end_to_final_ms"] = Int(f.timeIntervalSince(e) * 1000) }
		out["tail_applied_ms"] = lastTailAppliedMs
		out["eot_manual"] = lastEotManual ? 1 : 0
		out["eot_confidence_pct"] = Int(max(0, min(1, lastEotConfidence)) * 100)
		beginAt = nil; firstInterimAt = nil; endOfTurnAt = nil; finalAt = nil; lastTailAppliedMs = 0; lastEotManual = false
		return out
	}
	func getLastEotConfidence() -> Double { return lastEotConfidence }
}
