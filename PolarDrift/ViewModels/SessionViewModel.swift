import Foundation
import AVFoundation
import SwiftUI
import Observation
import os

private let logger = Logger(subsystem: "com.polardrift", category: "SessionStep")

/// キャリブ露光の上限（秒）。星を動かすキャリブ相でストリークを抑えるため計測相より短く制限する。
private let calibExposureCap: Double = 1.0 / 4

// MARK: - SessionViewModel

@Observable
final class SessionViewModel<Speech: SpeechManaging> {

    // MARK: - 共有状態
    var step: SessionStep = .phaseGuide(.azimuth) {
        didSet {
            logger.info("step: \(oldValue) → \(self.step)")
            handleStepTransition(from: oldValue, to: step)
            updateListeningState()
        }
    }
    var currentPhase: AlignmentPhase = .azimuth
    var calibration: DecCalibration?
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - インフラ
    let cameraManager = CameraManager()
    let speech: Speech

    // 露光は相ごとに分離する。計測相は星が静止するため長秒露光・低ISOでSNRを稼ぎ、
    // キャリブ相は星を速く動かすため控えめ露光（ブレ回避）＋高ISO（明るさ）にする。
    var measureExposureSec: Double = 1.0 / 30 { didSet { applyCurrentExposure() } }
    var measureISO: Float = 800 { didSet { applyCurrentExposure() } }
    var calibExposureSec: Double = 1.0 / 30 { didSet { applyCurrentExposure() } }
    var calibISO: Float = 1600 { didSet { applyCurrentExposure() } }
    var minContrast: Float = 0.25 {
        didSet {
            calibrationVM.frameProcessor.minContrast  = minContrast
            driftMeasureVM.frameProcessor.minContrast = minContrast
        }
    }

    // 周期確認モード（デバッグ専用）。UI露出は #if DEBUG だが、プロパティ自体は全ビルドに置く。
    var diagnosticMode: Bool = false {
        didSet { driftMeasureVM.driftTracker.diagnosticMode = diagnosticMode }
    }
    var diagnosticDurationMin: Int = 20 {
        didSet { driftMeasureVM.driftTracker.diagnosticDuration = TimeInterval(diagnosticDurationMin * 60) }
    }

    // MARK: - 子VM
    let calibrationVM  = CalibrationViewModel()
    let driftMeasureVM = DriftMeasureViewModel()
    let recorder       = SessionRecorder()

    init(speech: Speech) {
        self.speech = speech
    }

    // MARK: - セットアップ

    func setup() async {
        await speech.requestPermissions()
        let (sec, iso) = exposureSettings(for: step)   // 起動時の初期相に応じた露出
        let layer = await Task { @CameraActor in
            self.cameraManager.setup()   // フォーカス無限遠固定・WBロックも内部で実施
            self.cameraManager.setExposure(seconds: sec, iso: iso)  // start前にカスタム露出を適用（didSet未発火対策）
            self.cameraManager.start()
            return self.cameraManager.previewLayer
        }.value
        previewLayer = layer
        startSession()
    }

    // MARK: - 露出（相ごと）

    /// 現在（または指定）の相に応じた露光秒・ISOを返す。キャリブ露光は上限でクランプする。
    func exposureSettings(for step: SessionStep) -> (seconds: Double, iso: Float) {
        switch step {
        case .driftMeasure:
            return (measureExposureSec, measureISO)
        default:   // calibration / phaseGuide など計測以外はキャリブ設定（控えめ露光＋高ISO）
            return (min(calibExposureSec, calibExposureCap), calibISO)
        }
    }

    /// 設定変更時、現在の相に該当する露出を即時再適用する。
    private func applyCurrentExposure() {
        let (sec, iso) = exposureSettings(for: step)
        Task { @CameraActor in self.cameraManager.setExposure(seconds: sec, iso: iso) }
    }

    func startSession() {
        currentPhase = .azimuth
        calibration = nil
        recorder.startSession()
        step = .phaseGuide(.azimuth)   // didSet が startListening() を呼ぶ
    }

    private func handleStepTransition(from old: SessionStep, to new: SessionStep) {
        switch new {
        case .driftMeasure(.reintroducing(1)):
            // キャリブレーション完了直後 → キャリブレーション情報を記録
            if case .calibration = old {
                recorder.recordCalibration(calibration, phase: currentPhase)
            }

        case .driftMeasure(.showingResult(let iter)):
            recorder.recordRawFrames(iteration: iter, tracker: driftMeasureVM.driftTracker)
            recorder.recordMeasurement(
                iteration: iter,
                tracker: driftMeasureVM.driftTracker
            )

        case .sessionComplete:
            recorder.saveSession()

        default:
            break
        }
    }

    func handleVoiceCommand(_ command: SpeechCommand) {
        switch command {
        case .start:
            handleStart()
        case .skip:
            handleSkip()
        }
    }

    private func handleSkip() {
        guard case .driftMeasure(.showingResult(let iter)) = step else { return }
        recorder.recordMeasurement(
            iteration: iter,
            tracker: driftMeasureVM.driftTracker
        )
        @Bindable var this = self
        driftMeasureVM.forceCompletePhase(
            step: $this.step,
            calibration: $this.calibration,
            currentPhase: $this.currentPhase
        )
    }

    private func handleStart() {
        @Bindable var this = self
        switch step {
        case .phaseGuide:
            step = .calibration(.detectingCentroid)
        case .calibration:
            calibrationVM.handleVoiceCommand(step: $this.step, calibration: $this.calibration)
        case .driftMeasure:
            driftMeasureVM.handleVoiceCommand(step: $this.step,
                                              calibration: $this.calibration,
                                              currentPhase: $this.currentPhase)
        default:
            break
        }
    }

    private func updateListeningState() {
        step.shouldListen ? speech.startListening() : speech.stopListening()
    }

    // MARK: - ストリーム開始（SessionView の onAppear から呼ばれる）

    func startCalibrationStream() {
        @Bindable var this = self
        let (sec, iso) = exposureSettings(for: .calibration(.detectingCentroid))
        Task { @CameraActor in
            self.cameraManager.setExposure(seconds: sec, iso: iso)   // キャリブ露光（控えめ＋高ISO）
            let stream = self.cameraManager.makeGrayImageStream()
            await MainActor.run {
                self.calibrationVM.startStream(
                    stream,
                    step: $this.step,
                    calibration: $this.calibration
                )
            }
        }
    }

    func startDriftStream() {
        @Bindable var this = self
        // 周期確認モード設定をストリーム開始前に明示適用（didSet未発火・トグル順序対策）
        driftMeasureVM.driftTracker.diagnosticMode = diagnosticMode
        driftMeasureVM.driftTracker.diagnosticDuration = TimeInterval(diagnosticDurationMin * 60)
        let (sec, iso) = exposureSettings(for: .driftMeasure(.reintroducing(iteration: 1)))
        Task { @CameraActor in
            self.cameraManager.setExposure(seconds: sec, iso: iso)   // 計測露光（長秒・低ISO）
            let stream = self.cameraManager.makeGrayImageStream()
            await MainActor.run {
                self.driftMeasureVM.startStream(
                    stream,
                    step: $this.step,
                    calibration: $this.calibration,
                    currentPhase: $this.currentPhase
                )
            }
        }
    }
}
