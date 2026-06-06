import Foundation
import AVFoundation
import SwiftUI
import Observation
import os

private let logger = Logger(subsystem: "com.polardrift", category: "SessionStep")

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

    var cameraISO: Float = 800 {
        didSet { Task { @CameraActor in await self.cameraManager.setExposure(denominator: self.cameraShutterDenominator, iso: self.cameraISO) } }
    }
    var cameraShutterDenominator: Int = 30 {
        didSet { Task { @CameraActor in await self.cameraManager.setExposure(denominator: self.cameraShutterDenominator, iso: self.cameraISO) } }
    }
    var minContrast: Float = 0.25 {
        didSet {
            calibrationVM.frameProcessor.minContrast  = minContrast
            driftMeasureVM.frameProcessor.minContrast = minContrast
        }
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
        let layer = await Task { @CameraActor in
            self.cameraManager.setup()   // フォーカス無限遠固定も内部で実施
            self.cameraManager.start()
            return self.cameraManager.previewLayer
        }.value
        previewLayer = layer
        startSession()
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
        Task { @CameraActor in
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
        Task { @CameraActor in
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
