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

        guard let cam = makeCamera(),
              let input = try? AVCaptureDeviceInput(device: cam) else { return }

        camera = cam
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame", qos: .userInitiated))
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }

        // 手ブレ補正は画像をワープ/シフトしてドリフトを相殺・汚染するため明示的に無効化
        #if os(iOS)
        if let conn = output.connection(with: .video), conn.isVideoStabilizationSupported {
            conn.preferredVideoStabilizationMode = .off
        }
        #endif

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer

        captureSession = session
    }

    /// バックワイドカメラを生成し、計測用のデバイス設定を一括適用して返す。
    /// - 無限遠フォーカス固定（接眼レンズは無限遠に像を作るため。AFハンチング防止）
    /// - ホワイトバランスを中立ゲインで固定（AWBのゲイン変動による輝度ちらつき防止）
    /// ピント微調整は望遠鏡のフォーカサー側で行う。露出は setExposure で別途適用。
    private func makeCamera() -> AVCaptureDevice? {
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return nil
        }
        guard (try? cam.lockForConfiguration()) != nil else { return cam }
        defer { cam.unlockForConfiguration() }

        #if os(iOS)
        if cam.isLockingFocusWithCustomLensPositionSupported {
            cam.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil)  // 1.0 = 最遠 ≒ 無限遠
        } else if cam.isFocusModeSupported(.locked) {
            cam.focusMode = .locked
        }
        if cam.isWhiteBalanceModeSupported(.locked) {
            // 昼光色温度(約5200K)相当で固定。AWBのように時間変動しない一方、
            // 中立ゲイン(1,1,1)のようなセンサー素の緑かぶりも避け自然な色味にする。
            let tnt = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: 5200, tint: 0)
            var gains = cam.deviceWhiteBalanceGains(for: tnt)
            let maxG = cam.maxWhiteBalanceGain
            gains.redGain   = min(max(1.0, gains.redGain),   maxG)
            gains.greenGain = min(max(1.0, gains.greenGain), maxG)
            gains.blueGain  = min(max(1.0, gains.blueGain),  maxG)
            cam.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        }
        #else
        if cam.isFocusModeSupported(.locked) { cam.focusMode = .locked }
        #endif

        return cam
    }

    func start() {
        guard let session = captureSession, !session.isRunning else { return }
        session.startRunning()
    }

    func stop() {
        captureSession?.stopRunning()
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
