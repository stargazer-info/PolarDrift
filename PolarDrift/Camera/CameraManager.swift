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

        // afocal撮影のためフォーカスを無限遠に固定（start前なので起動時のAFハンチングも回避）
        lockFocusInfinity()
    }

    func start() {
        guard let session = captureSession, !session.isRunning else { return }
        session.startRunning()
    }

    func stop() {
        captureSession?.stopRunning()
    }

    /// コリメート(afocal)撮影では接眼レンズが無限遠に像を作るため、
    /// レンズ位置を無限遠(1.0)へ固定しAFのハンチングによる重心ブレを防ぐ。
    /// ピント微調整は望遠鏡のフォーカサー側で行う。
    func lockFocusInfinity() {
        guard let cam = camera else { return }
        guard (try? cam.lockForConfiguration()) != nil else { return }
        #if os(iOS)
        if cam.isLockingFocusWithCustomLensPositionSupported {
            cam.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil)  // 1.0 = 最遠 ≒ 無限遠
        } else if cam.isFocusModeSupported(.locked) {
            cam.focusMode = .locked
        }
        #else
        if cam.isFocusModeSupported(.locked) { cam.focusMode = .locked }
        #endif
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
