import SwiftUI
import Observation
import os

private let driftLogger = Logger(subsystem: "com.polardrift", category: "DriftMeasure")

@Observable
final class DriftMeasureViewModel {

    // MARK: - 所有する状態
    let driftTracker = DriftTracker()
    var detectedCentroid: CGPoint?
    var frameProcessor = FrameProcessor()

    private var streamTask: Task<Void, Never>?

    // MARK: - フレームストリーム開始・停止

    func startStream(
        _ stream: AsyncStream<GrayImage>,
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>,
        currentPhase: Binding<AlignmentPhase>
    ) {
        driftTracker.calibration = calibration.wrappedValue
        streamTask?.cancel()
        streamTask = Task {
            for await gray in stream {
                processFrame(gray, step: step, calibration: calibration, currentPhase: currentPhase)
            }
        }
    }

    func stopStream() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - 音声コマンド処理

    func handleVoiceCommand(
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>,
        currentPhase: Binding<AlignmentPhase>
    ) {
        guard case .driftMeasure(let driftStep) = step.wrappedValue else { return }
        switch driftStep {
        case .reintroducing(let iter):
            guard let origin = detectedCentroid else { return }
            fixCrosshairAndStartMeasuring(at: origin, iteration: iter, step: step)

        case .showingResult(let iter):
            step.wrappedValue = .driftMeasure(.reintroducing(iteration: iter + 1))

        default:
            break
        }
    }

    // MARK: - ロスト星の処理

    func handleLostStarContinue(
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>,
        currentPhase: Binding<AlignmentPhase>
    ) {
        if driftTracker.regression.n >= 30 {
            finishMeasurement(step: step, calibration: calibration, currentPhase: currentPhase)
        } else {
            driftTracker.resetLost()
            if case .driftMeasure(.measuring(let n)) = step.wrappedValue {
                step.wrappedValue = .driftMeasure(.reintroducing(iteration: n))
            }
        }
    }

    func handleLostStarRestart(step: Binding<SessionStep>) {
        driftTracker.resetLost()
        if case .driftMeasure(.measuring(let n)) = step.wrappedValue {
            step.wrappedValue = .driftMeasure(.reintroducing(iteration: n))
        }
    }

    // MARK: - フレーム処理

    private func processFrame(
        _ gray: GrayImage,
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>,
        currentPhase: Binding<AlignmentPhase>
    ) {
        switch step.wrappedValue {
        case .driftMeasure(.reintroducing):
            if let last = detectedCentroid {
                detectedCentroid = frameProcessor.trackCentroid(
                    in: gray, lastPosition: last,
                    predictedVelocity: .zero, searchRadius: 60
                ) ?? frameProcessor.detectInitialCentroid(in: gray)
            } else {
                detectedCentroid = frameProcessor.detectInitialCentroid(in: gray)
            }

        case .driftMeasure(.measuring):
            handleDriftMeasurement(gray, step: step, calibration: calibration, currentPhase: currentPhase)

        default:
            break
        }
    }

    private func handleDriftMeasurement(
        _ gray: GrayImage,
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>,
        currentPhase: Binding<AlignmentPhase>
    ) {
        if driftTracker.imageSize == .zero {
            driftTracker.imageSize = CGSize(width: gray.width, height: gray.height)
        }
        guard let last = detectedCentroid ?? driftTracker.sessionOrigin else { return }
        if let pos = frameProcessor.trackCentroid(
            in: gray, lastPosition: last,
            predictedVelocity: driftTracker.predictedVelocity,
            searchRadius: 10
        ) {
            detectedCentroid = pos
            driftTracker.addCentroid(pos, at: Date())
            if driftTracker.isPhaseComplete {
                finishMeasurement(step: step, calibration: calibration, currentPhase: currentPhase)
            }
        } else {
            driftTracker.handleFrameLost()
        }
    }

    private func finishMeasurement(
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>,
        currentPhase: Binding<AlignmentPhase>
    ) {
        let elapsed = driftTracker.elapsedTime

        let iter: Int
        if case .driftMeasure(.measuring(let n)) = step.wrappedValue { iter = n } else { iter = 1 }

        let slope = driftTracker.stopTracking(iteration: iter)
        let isSignificant = driftTracker.isDriftSignificant
        let n = driftTracker.regression.n
        let se = driftTracker.slopeStdError
        let tStat = se > 0 ? slope / se : 0
        let raRate = driftTracker.raSlope * 60
        driftLogger.info(
            "測定完了: t=\(String(format: "%.1f", elapsed))s n=\(n) rate=\(String(format: "%.2f", slope*60))px/min(actual) RA=\(String(format: "%.2f", raRate))px/min t統計量=\(String(format: "%.2f", tStat)) 有意=\(isSignificant)"
        )

        step.wrappedValue = .driftMeasure(.showingResult(iteration: iter))
    }

    func forceCompletePhase(
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>,
        currentPhase: Binding<AlignmentPhase>
    ) {
        advancePhase(step: step, calibration: calibration, currentPhase: currentPhase)
    }

    private func advancePhase(
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>,
        currentPhase: Binding<AlignmentPhase>
    ) {
        guard let next = currentPhase.wrappedValue.next else {
            step.wrappedValue = .sessionComplete
            return
        }
        step.wrappedValue = .phaseComplete(currentPhase.wrappedValue)
        currentPhase.wrappedValue = next
        calibration.wrappedValue = nil
        driftTracker.calibration = nil
        driftTracker.resetHistory()
        Task {
            try? await Task.sleep(for: .seconds(3))
            step.wrappedValue = .phaseGuide(next)
        }
    }

    private func fixCrosshairAndStartMeasuring(
        at origin: CGPoint,
        iteration: Int,
        step: Binding<SessionStep>
    ) {
        driftTracker.startTracking(at: origin)
        step.wrappedValue = .driftMeasure(.measuring(iteration: iteration))
    }
}
