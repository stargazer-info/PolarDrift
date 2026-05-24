import CoreGraphics

// MARK: - CalibrationStep

enum CalibrationStep: Equatable {
    case waitingForVoice
    case detectingCentroid
    case awaitingDecMove(origin: CGPoint)
}

// MARK: - DriftMeasureStep

enum DriftMeasureStep {
    case reintroducing(iteration: Int)
    case measuring(iteration: Int)
    case showingResult(iteration: Int)
}

// MARK: - SessionStep

enum SessionStep {
    case phaseGuide(AlignmentPhase)
    case calibration(CalibrationStep)
    case driftMeasure(DriftMeasureStep)
    case phaseComplete(AlignmentPhase)
    case sessionComplete
}

// MARK: - CustomStringConvertible

extension CalibrationStep: CustomStringConvertible {
    var description: String {
        switch self {
        case .waitingForVoice:          return "waitingForVoice"
        case .detectingCentroid:        return "detectingCentroid"
        case .awaitingDecMove(let o):   return "awaitingDecMove(origin: \(o))"
        }
    }
}

extension DriftMeasureStep: CustomStringConvertible {
    var description: String {
        switch self {
        case .reintroducing(let n): return "reintroducing(iter: \(n))"
        case .measuring(let n):     return "measuring(iter: \(n))"
        case .showingResult(let n): return "showingResult(iter: \(n))"
        }
    }
}

extension SessionStep: CustomStringConvertible {
    var description: String {
        switch self {
        case .phaseGuide(let p):    return "phaseGuide(\(p))"
        case .calibration(let s):   return "calibration.\(s)"
        case .driftMeasure(let s):  return "driftMeasure.\(s)"
        case .phaseComplete(let p): return "phaseComplete(\(p))"
        case .sessionComplete:      return "sessionComplete"
        }
    }
}

// MARK: - shouldListen

extension SessionStep {
    var shouldListen: Bool {
        switch self {
        case .phaseGuide,
             .calibration(.waitingForVoice),
             .driftMeasure(.reintroducing),
             .driftMeasure(.showingResult):
            return true
        default:
            return false
        }
    }
}
