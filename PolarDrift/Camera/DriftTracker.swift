import Foundation
import CoreGraphics
import Observation
import os

private let driftLogger = Logger(subsystem: "com.polardrift", category: "DriftMeasure")

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
    var elapsedTime: TimeInterval = 0  // 計測開始からの経過秒数

    var previousSlope: Double?
    private(set) var slopeHistory: [(rate: Double, iteration: Int)] = []

    var calibration: DecCalibration?
    var imageSize: CGSize = .zero

    var trackingState: StarTrackingState = .idle
    var sessionOrigin: CGPoint?        // 測定「スタート」瞬間の位置（十字線固定点）

    private(set) var rawFrames: [(elapsed: Double, x: Double, y: Double, decDisp: Double)] = []

    private var recentDisplacements: [(CGVector, Date)] = []
    private var trackingStartTime: Date?
    private var lastLoggedSecond: Int = -1

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
        currentSlope = 0
        slopeStdError = 0
        isDriftSignificant = false
        elapsedTime = 0
        lastLoggedSecond = -1
        rawFrames = []
    }

    @discardableResult
    func stopTracking() -> Double {
        isTracking = false
        previousSlope = currentSlope
        let ratePx = currentSlope * 60 * (imageSize.height > 0 ? imageSize.height : 720)
        slopeHistory.append((rate: ratePx, iteration: slopeHistory.count + 1))
        if slopeHistory.count > 5 { slopeHistory.removeFirst() }
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
        elapsedTime = t
        rawFrames.append((elapsed: t, x: Double(point.x), y: Double(point.y), decDisp: Double(decDisp)))
        regression.add(t: t, y: Double(decDisp))

        currentSlope = regression.slope
        slopeStdError = regression.slopeStdError
        // 統計的有意 かつ 実ピクセル換算で 1 px/分超過の両方を満たす場合のみ有意とする
        let threshold = imageSize.height > 0 ? 1.0 / imageSize.height : 1.0 / 720
        isDriftSignificant = regression.isSignificant && abs(currentSlope * 60) >= threshold

        let sec = Int(elapsedTime)
        if sec > lastLoggedSecond {
            lastLoggedSecond = sec
            let scale  = imageSize.height > 0 ? imageSize.height : 720
            let ratePx = currentSlope * 60 * scale       // 実ピクセル/分
            let sePx   = slopeStdError * 60 * scale
            let tStat  = slopeStdError > 0 ? currentSlope / slopeStdError : 0
            let xPx    = imageSize.width  > 0 ? point.x * imageSize.width  : point.x
            let yPx    = imageSize.height > 0 ? point.y * imageSize.height : point.y
            driftLogger.info(
                "t=\(sec)s n=\(self.regression.n) pos=(\(String(format: "%.1f", xPx)),\(String(format: "%.1f", yPx)))px rate=\(String(format: "%.2f", ratePx))±\(String(format: "%.2f", sePx*2))px/min(actual) t=\(String(format: "%.2f", tStat)) sig=\(self.isDriftSignificant)"
            )
        }
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

    func resetHistory() {
        slopeHistory = []
    }

    var isPhaseComplete: Bool {
        elapsedTime >= 30 || (isDriftSignificant && elapsedTime >= 5)
    }
}
