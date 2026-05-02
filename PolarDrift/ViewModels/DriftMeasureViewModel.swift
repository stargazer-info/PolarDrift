import SwiftUI
import Observation

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
        currentPhase: Binding<AlignmentPhase>,
        startListening: () -> Void
    ) {
        guard case .driftMeasure(let driftStep) = step.wrappedValue else { return }
        switch driftStep {
        case .reintroducing(let iter):
            guard let origin = detectedCentroid else { return }
            fixCrosshairAndStartMeasuring(at: origin, iteration: iter, step: step)

        case .showingResult(_, let iter):
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
            detectedCentroid = frameProcessor.detectInitialCentroid(in: gray)

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
        let slope = driftTracker.stopTracking()
        let isSignificant = driftTracker.isDriftSignificant

        let feedback: DriftFeedback
        if let prev = driftTracker.previousSlope {
            feedback = DriftFeedback.evaluate(current: slope, previous: prev, isSignificant: isSignificant)
        } else {
            feedback = isSignificant ? .sameDirection : .complete
        }

        let iter: Int
        if case .driftMeasure(.measuring(let n)) = step.wrappedValue { iter = n } else { iter = 1 }
        step.wrappedValue = .driftMeasure(.showingResult(feedback, iteration: iter))

        if feedback == .complete { advancePhase(step: step, calibration: calibration, currentPhase: currentPhase) }
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
        driftTracker.previousSlope = nil
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
