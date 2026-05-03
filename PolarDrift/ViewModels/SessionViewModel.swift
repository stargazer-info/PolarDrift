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
// アプリ全体で使用する具体型エイリアス
typealias AppSessionViewModel = SessionViewModel<SpeechRecognitionManager>



@Observable
final class SessionViewModel<Speech: SpeechManaging> {

    // MARK: - 共有状態
    var step: SessionStep = .phaseGuide(.azimuth) {
        didSet { updateListeningState() }
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

    init(speech: Speech) {
        self.speech = speech
    }

    // MARK: - セットアップ

    func setup() async {
        await speech.requestPermissions()
        let layer = await Task { @CameraActor in
            self.cameraManager.setup()
            self.cameraManager.start()
            return self.cameraManager.previewLayer
        }.value
        previewLayer = layer
        startSession()
    }

    func startSession() {
        currentPhase = .azimuth
        calibration = nil
        step = .phaseGuide(.azimuth)   // didSet が startListening() を呼ぶ
    }

    func handleVoiceCommand(_ command: SpeechCommand) {
        switch command {
        case .start:
            handleStart()
        }
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
        switch step {
        case .phaseGuide,
             .calibration(.waitingForVoice),
             .calibration(.complete),
             .driftMeasure(.reintroducing),
             .driftMeasure(.showingResult):
            speech.startListening()
        default:
            speech.stopListening()
        }
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
