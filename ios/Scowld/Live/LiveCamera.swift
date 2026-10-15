@preconcurrency import AVFoundation
import CoreImage
import os

nonisolated private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "LiveCamera")

/// The front camera for live conversations. It keeps only the latest frame, as a
/// small JPEG, for the provider to look at; nothing is recorded or saved.
///
/// Capture is native: the companion web page's hidden video went stale because
/// WebKit stops updating video it doesn't show.
nonisolated final class LiveCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Frames are encoded at most this often (seconds); the provider gets them less often.
    static let encodeInterval: TimeInterval = 0.5
    static let maximumSide: CGFloat = 512

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.scowld.live.camera")
    private let output = AVCaptureVideoDataOutput()
    private let context = CIContext()
    private let lock = NSLock()
    private var latest: Data?
    private var lastEncodedAt: TimeInterval = 0
    private var isConfigured = false

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static var isDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// The most recent frame as JPEG, or nil if the camera isn't running yet.
    func latestJPEG() -> Data? {
        lock.withLock { latest }
    }

    func start() {
        queue.async { [self] in
            guard Self.isAuthorized else { return }
            if !isConfigured {
                configure()
            }
            if isConfigured, !session.isRunning {
                session.startRunning()
                logger.info("[Camera] Started")
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
                logger.info("[Camera] Stopped")
            }
            lock.withLock { latest = nil }
        }
    }

    private func configure() {
        // The live conversation owns the audio session; the camera must not change it.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            logger.error("[Camera] The front camera isn't available")
            return
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            logger.error("[Camera] Can't add the video output")
            return
        }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            // Portrait and mirrored, as the user sees themselves.
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        isConfigured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastEncodedAt >= Self.encodeInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastEncodedAt = now

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(1, Self.maximumSide / max(image.extent.width, image.extent.height))
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = context.jpegRepresentation(
                of: image,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.65]
              ) else { return }
        lock.withLock { latest = jpeg }
    }
}
