import AVFoundation
import UIKit

// MARK: - Camera Manager

/// Manages front camera capture for vision analysis.
/// Camera frames are NEVER sent to any API — only text descriptions.
@Observable
final class CameraManager: NSObject {
    // MARK: - Published State
    var isActive = false
    var latestFrame: UIImage?
    var permissionGranted = false
    var error: String?

    // MARK: - Private
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.scowld.camera")
    private let videoOutput = AVCaptureVideoDataOutput()

    // Thread-safe frame counter using atomic operations
    private let frameCounter = FrameCounter()
    private let captureInterval: Int32 = 30 // Capture every 30th frame (~1/sec at 30fps)

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permissionGranted = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
            return granted
        default:
            permissionGranted = false
            return false
        }
    }

    // MARK: - Session Management

    func startCapture() {
        guard permissionGranted else { return }
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            Task { @MainActor in
                self?.isActive = false
            }
        }
    }

    /// Capture a single frame for vision API requests
    func captureSnapshot() -> UIImage? {
        return latestFrame
    }

    // MARK: - Private

    private func configureSession() {
        guard !captureSession.isRunning else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        // Front camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input)
        else {
            Task { @MainActor in self.error = "Failed to access front camera" }
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(input)

        // Video output
        let outputQueue = DispatchQueue(label: "com.scowld.camera.output")
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(videoOutput) else {
            Task { @MainActor in self.error = "Failed to configure camera output" }
            captureSession.commitConfiguration()
            return
        }

        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
            connection.isVideoMirrored = true
        }

        captureSession.commitConfiguration()
        captureSession.startRunning()

        Task { @MainActor in
            self.isActive = true
        }
    }
}

// MARK: - Thread-safe Frame Counter

/// Simple thread-safe counter using os_unfair_lock
private final class FrameCounter: @unchecked Sendable {
    private var _value: Int32 = 0
    private var lock = os_unfair_lock()

    func increment() -> Int32 {
        os_unfair_lock_lock(&lock)
        _value += 1
        let val = _value
        os_unfair_lock_unlock(&lock)
        return val
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let count = frameCounter.increment()
        guard count % captureInterval == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)

        Task { @MainActor in
            self.latestFrame = image
        }
    }
}
