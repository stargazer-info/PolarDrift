import Foundation
import AVFoundation
import SwiftUI
import Observation

// MARK: - Step enums

enum CalibrationStep: Equatable {
    case waitingForVoice
    case detectingCentroid
    case awaitingDecMove(origin: CGPoint)
    case complete(DecCalibration)

    static func == (lhs: CalibrationStep, rhs: CalibrationStep) -> Bool {
        switch (lhs, rhs) {
        case (.waitingForVoice, .waitingForVoice):   return true
        case (.detectingCentroid, .detectingCentroid): return true
        case (.awaitingDecMove(let a), .awaitingDecMove(let b)): return a == b
        case (.complete, .complete): return true
        default: return false
        }
    }
}

enum DriftMeasureStep {
    case reintroducing(iteration: Int)
    case measuring(iteration: Int)
    case showingResult(DriftFeedback, iteration: Int)
}

enum SessionStep {
    case phaseGuide(AlignmentPhase)
    case calibration(CalibrationStep)
    case driftMeasure(DriftMeasureStep)
    case phaseComplete(AlignmentPhase)
    case sessionComplete
}

// MARK: - SessionViewModel

@Observable
final class SessionViewModel {

    // MARK: - 共有状態
    var step: SessionStep = .phaseGuide(.azimuth)
    var currentPhase: AlignmentPhase = .azimuth
    var calibration: DecCalibration?
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - インフラ
    let cameraManager = CameraManager()
    let speechRecognition = SpeechRecognitionManager()

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

    // MARK: - セットアップ

    func setup() async {
        await speechRecognition.requestPermissions()
        let layer = await Task { @CameraActor in
            self.cameraManager.setup()
            self.cameraManager.start()
            return self.cameraManager.previewLayer
        }.value
        previewLayer = layer
        speechRecognition.onStartCommand = { [weak self] in self?.handleVoiceCommand() }
        startSession()
    }

    func startSession() {
        currentPhase = .azimuth
        calibration = nil
        step = .phaseGuide(.azimuth)
        speechRecognition.startListening()
    }

    // MARK: - 音声コマンドルーティング

    func handleVoiceCommand() {
        @Bindable var this = self

        switch step {
        case .phaseGuide:
            // .waitingForVoice を経由せず直接 calibrationVM に処理させる
            step = .calibration(.waitingForVoice)
            fallthrough

        case .calibration:
            calibrationVM.handleVoiceCommand(
                step: $this.step,
                calibration: $this.calibration,
                startListening: { [weak self] in self?.speechRecognition.startListening() },
                stopListening:  { [weak self] in self?.speechRecognition.stopListening() }
            )

        case .driftMeasure:
            driftMeasureVM.handleVoiceCommand(
                step: $this.step,
                calibration: $this.calibration,
                currentPhase: $this.currentPhase,
                startListening: { [weak self] in self?.speechRecognition.startListening() }
            )

        default:
            break
        }
    }

    // MARK: - ストリーム開始（SessionView の onAppear から呼ばれる）

    func startCalibrationStream() {
        @Bindable var this = self
        Task { @CameraActor in
            let stream = self.cameraManager.makeGrayImageStream()
            await MainActor.run {
                self.calibrationVM.startStream(stream, step: $this.step, calibration: $this.calibration)
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
