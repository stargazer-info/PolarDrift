import Foundation
import CoreGraphics
import Observation

enum StarTrackingState {
    case idle
    case tracking(lastPosition: CGPoint)
    case searching(framesLost: Int)
    case lostAlert
}

@Observable
final class DriftTracker {
    var isTracking = false
    var regression = OnlineRegression()

    var currentSlope: Double = 0       // px/秒（符号付き、Dec軸投影済み）
    var slopeStdError: Double = 0
    var isDriftSignificant: Bool = false

    var previousSlope: Double?

    var calibration: DecCalibration?

    var trackingState: StarTrackingState = .idle
    var sessionOrigin: CGPoint?        // 測定「スタート」瞬間の位置（十字線固定点）

    private var recentDisplacements: [(CGVector, Date)] = []
    private var trackingStartTime: Date?

    var predictedVelocity: CGVector {
        let recent = recentDisplacements.suffix(3)
        guard recent.count >= 2 else { return .zero }
        let sum = recent.reduce(CGVector.zero) { CGVector(dx: $0.dx + $1.0.dx, dy: $0.dy + $1.0.dy) }
        return CGVector(dx: sum.dx / CGFloat(recent.count), dy: sum.dy / CGFloat(recent.count))
    }

    func startTracking(at origin: CGPoint) {
        regression.reset()
        isTracking = true
        trackingStartTime = Date()
        sessionOrigin = origin
        previousSlope = currentSlope.isNaN ? nil : currentSlope
        currentSlope = 0
        slopeStdError = 0
        isDriftSignificant = false
    }

    @discardableResult
    func stopTracking() -> Double {
        isTracking = false
        previousSlope = currentSlope
        return currentSlope
    }

    func addCentroid(_ point: CGPoint, at time: Date) {
        guard isTracking, let startTime = trackingStartTime else { return }
        guard let cal = calibration, let origin = sessionOrigin else { return }

        // 変位ベクトルをDec軸に投影
        let disp = CGVector(dx: point.x - origin.x, dy: point.y - origin.y)
        let decDisp = cal.decComponent(of: disp)

        // 速度予測用に直近変位を記録
        if case .tracking(let last) = trackingState {
            let frameDisp = CGVector(dx: point.x - last.x, dy: point.y - last.y)
            recentDisplacements.append((frameDisp, time))
            if recentDisplacements.count > 5 { recentDisplacements.removeFirst() }
        }
        trackingState = .tracking(lastPosition: point)

        let t = time.timeIntervalSince(startTime)
        regression.add(t: t, y: Double(decDisp))

        currentSlope = regression.slope
        slopeStdError = regression.slopeStdError
        isDriftSignificant = regression.isSignificant
    }

    // 星ロスト時の処理（FrameProcessorがnilを返したフレームごとに呼ぶ）
    func handleFrameLost() {
        switch trackingState {
        case .tracking:
            trackingState = .searching(framesLost: 1)
        case .searching(let n):
            let next = n + 1
            if next >= 90 {  // 3秒 @30fps
                trackingState = .lostAlert
            } else {
                trackingState = .searching(framesLost: next)
            }
        default:
            break
        }
    }

    func resetLost() {
        trackingState = .idle
        recentDisplacements = []
    }

    var isPhaseComplete: Bool {
        !isDriftSignificant && regression.n >= 30
    }
}
