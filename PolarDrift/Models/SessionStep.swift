import CoreGraphics

// MARK: - CalibrationStep

enum CalibrationStep: Equatable {
    case waitingForVoice
    case detectingCentroid
    case awaitingDecMove(origin: CGPoint)
    case complete(DecCalibration)

    // DecCalibration は Equatable でないため手書き。
    // .complete 同士は内容によらず同一扱い（再キャリブレーション時のアニメーション抑制のため）
    static func == (lhs: CalibrationStep, rhs: CalibrationStep) -> Bool {
        switch (lhs, rhs) {
        case (.waitingForVoice, .waitingForVoice):             return true
        case (.detectingCentroid, .detectingCentroid):         return true
        case (.awaitingDecMove(let a), .awaitingDecMove(let b)): return a == b
        case (.complete, .complete):                           return true
        default:                                               return false
        }
    }
}

// MARK: - DriftMeasureStep

enum DriftMeasureStep {
    case reintroducing(iteration: Int)
    case measuring(iteration: Int)
    case showingResult(DriftFeedback, iteration: Int)
}

// MARK: - SessionStep

enum SessionStep {
    case phaseGuide(AlignmentPhase)
    case calibration(CalibrationStep)
    case driftMeasure(DriftMeasureStep)
    case phaseComplete(AlignmentPhase)
    case sessionComplete
}

extension SessionStep {
    var shouldListen: Bool {
        switch self {
        case .phaseGuide,
             .calibration(.waitingForVoice),
             .calibration(.complete),
             .driftMeasure(.reintroducing),
             .driftMeasure(.showingResult):
            return true
        default:
            return false
        }
    }
}
