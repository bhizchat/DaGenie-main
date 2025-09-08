import AVFoundation
import UIKit

final class CameraController: NSObject {
    enum CameraPosition { case front, back }

    private var session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private(set) var isConfigured = false
    private(set) var currentPosition: CameraPosition = .back
    var onRecordingFinished: ((URL?) -> Void)?

    // MARK: Permissions
    private func ensureAuthorization(completion: @escaping (Bool) -> Void) {
        // Photos do not require microphone permission. Only require video to proceed.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func configure(completion: @escaping (Bool) -> Void) {
        ensureAuthorization { granted in
            guard granted else { completion(false); return }
            self.sessionQueue.async {
                let ok = self.configureSession()
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    private func configureSession() -> Bool {
        guard !isConfigured else { return true }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Video input
        let position: AVCaptureDevice.Position = currentPosition == .back ? .back : .front
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(videoInput)
        videoDeviceInput = videoInput

        // Audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        // Photo output
        guard session.canAddOutput(photoOutput) else { session.commitConfiguration(); return false }
        session.addOutput(photoOutput)
        photoOutput.isHighResolutionCaptureEnabled = true
        // Prioritize quality for stills
        if #available(iOS 13.0, *) { photoOutput.maxPhotoQualityPrioritization = .quality }

        // Movie output (Phase 1; Phase 2 will switch to AVAssetWriter for filtered video)
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            movieOutput.movieFragmentInterval = .invalid
        }

        // Connection defaults
        if let conn = movieOutput.connection(with: .video) {
            if conn.isVideoStabilizationSupported { conn.preferredVideoStabilizationMode = .cinematic }
            conn.videoOrientation = .portrait
            conn.isVideoMirrored = (position == .front)
        }
        if let conn = photoOutput.connection(with: .video) {
            conn.videoOrientation = .portrait
            conn.isVideoMirrored = (position == .front)
        }

        // Device configuration (FPS, low light)
        do {
            try videoDevice.lockForConfiguration()
            if videoDevice.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 }) {
                videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            }
            if videoDevice.isLowLightBoostSupported { videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = true }
            // iOS 17+: must disable automatic adjustment before toggling HDR
            if #available(iOS 17.0, *) {
                if videoDevice.automaticallyAdjustsVideoHDREnabled { videoDevice.automaticallyAdjustsVideoHDREnabled = false }
            }
            if videoDevice.isVideoHDREnabled { videoDevice.isVideoHDREnabled = false }
            videoDevice.unlockForConfiguration()
        } catch { }

        session.commitConfiguration()
        isConfigured = true
        return true
    }

    func startRunning() {
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stopRunning() {
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    /// Fully tear down the AVCapture session and release camera resources.
    func teardownSession(completion: (() -> Void)? = nil) {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.session.commitConfiguration()
            self.videoDeviceInput = nil
            self.isConfigured = false
            DispatchQueue.main.async { completion?() }
        }
    }

    func toggleCamera(completion: ((Bool) -> Void)? = nil) {
        sessionQueue.async {
            self.session.beginConfiguration()
            if let currentInput = self.videoDeviceInput { self.session.removeInput(currentInput) }
            self.currentPosition = self.currentPosition == .back ? .front : .back
            let position: AVCaptureDevice.Position = self.currentPosition == .back ? .back : .front
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { completion?(false) }
                return
            }
            self.session.addInput(input)
            self.videoDeviceInput = input
            if let conn = self.movieOutput.connection(with: .video) {
                conn.videoOrientation = .portrait
                conn.isVideoMirrored = (position == .front)
            }
            if let conn = self.photoOutput.connection(with: .video) {
                conn.videoOrientation = .portrait
                conn.isVideoMirrored = (position == .front)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async { completion?(true) }
        }
    }

    // MARK: Photo
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode, delegate: AVCapturePhotoCaptureDelegate) {
        print("[CameraController] capturePhoto called; isConfigured=\(isConfigured)")
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashMode) { settings.flashMode = flashMode }
        settings.isHighResolutionPhotoEnabled = true
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    // MARK: Video (Phase 1 - MovieFileOutput)
    func startRecording(to url: URL, completion: ((Bool) -> Void)? = nil) {
        sessionQueue.async {
            guard !self.movieOutput.isRecording else { DispatchQueue.main.async { completion?(false) }; return }
            if let connection = self.movieOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = (self.currentPosition == .front)
            }
            print("[CameraController] startRecording to=\(url.lastPathComponent)")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { completion?(true) }
        }
    }

    func stopRecording() { sessionQueue.async { if self.movieOutput.isRecording { self.movieOutput.stopRecording() } } }

    // Expose session for preview layer
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.videoOrientation = .portrait
        return layer
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.onRecordingFinished?(error == nil ? outputFileURL : nil) }
    }
}


