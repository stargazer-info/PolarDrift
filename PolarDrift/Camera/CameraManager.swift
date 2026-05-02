import AVFoundation

@CameraActor
final class CameraManager: NSObject {
    nonisolated(unsafe) private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    private var captureSession: AVCaptureSession?
    private var camera: AVCaptureDevice?
    private var frameContinuation: AsyncStream<GrayImage>.Continuation?

    func setup() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720

        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam) else { return }

        camera = cam
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame", qos: .userInitiated))
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer

        captureSession = session
    }

    func start() {
        guard let session = captureSession, !session.isRunning else { return }
        session.startRunning()
    }

    func stop() {
        captureSession?.stopRunning()
    }

    func lockFocus() {
        guard let cam = camera else { return }
        try? cam.lockForConfiguration()
        if cam.isFocusModeSupported(.locked) { cam.focusMode = .locked }
        cam.unlockForConfiguration()
    }

    func setExposure(denominator: Int, iso: Float) {
        guard let cam = camera else { return }
        try? cam.lockForConfiguration()
        #if os(iOS)
        if cam.isExposureModeSupported(.custom) {
            let duration = CMTimeMake(value: 1, timescale: CMTimeScale(denominator))
            let clampedISO = min(max(iso, cam.activeFormat.minISO), cam.activeFormat.maxISO)
            cam.setExposureModeCustom(duration: duration, iso: clampedISO)
        }
        #endif
        cam.unlockForConfiguration()
    }

    /// 呼び出すたびに前のストリームを終了し新しいストリームを返す
    func makeGrayImageStream() -> AsyncStream<GrayImage> {
        frameContinuation?.finish()
        return AsyncStream { [weak self] continuation in
            self?.frameContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @CameraActor in self?.frameContinuation = nil }
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let gray = GrayImage(pixelBuffer: pixelBuffer) else { return }
        Task { @CameraActor in self.frameContinuation?.yield(gray) }
    }
}
