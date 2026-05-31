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
    var raRegression = OnlineRegression()  // RA方向ドリフト（診断用）

    var currentSlope: Double = 0       // px/秒（符号付き、Dec軸投影済み）
    var slopeStdError: Double = 0
    var raSlope: Double = 0            // px/秒（RA方向、診断用）
    var isDriftSignificant: Bool = false
    var elapsedTime: TimeInterval = 0  // 計測開始からの経過秒数

    private(set) var slopeHistory: [(rate: Double, sePxPerMin: Double, iteration: Int)] = []

    var calibration: DecCalibration?
    var imageSize: CGSize = .zero

    var trackingState: StarTrackingState = .idle
    var sessionOrigin: CGPoint?        // 測定「スタート」瞬間の位置（十字線固定点）

    private(set) var rawFrames: [(elapsed: Double, x: Double, y: Double, decDisp: Double, raDisp: Double)] = []

    private var recentDisplacements: [(CGVector, Date)] = []
    private var trackingStartTime: Date?
    private var lastLoggedSecond: Int = -1

    // 傾き安定化（収束）判定用の履歴と定数
    private(set) var slopeSamples: [(t: Double, ratePxPerMin: Double)] = []
    let minMeasureDuration: TimeInterval = 90   // 最小計測時間（秒）
    let stabilityWindow: TimeInterval = 60      // 傾きの安定性を見る直近窓（秒）
    let stabilitySlopeTol: Double = 1.0         // 直近窓内の傾きばらつき許容（px/分）
    let maxMeasureDuration: TimeInterval = 300  // 安全上限（秒、ウォーム周期1周を跨げる）

    var predictedVelocity: CGVector {
        let recent = recentDisplacements.suffix(3)
        guard recent.count >= 2 else { return .zero }
        let sum = recent.reduce(CGVector.zero) { CGVector(dx: $0.dx + $1.0.dx, dy: $0.dy + $1.0.dy) }
        return CGVector(dx: sum.dx / CGFloat(recent.count), dy: sum.dy / CGFloat(recent.count))
    }

    func startTracking(at origin: CGPoint) {
        regression.reset()
        raRegression.reset()
        isTracking = true
        trackingStartTime = Date()
        sessionOrigin = origin
        currentSlope = 0
        slopeStdError = 0
        raSlope = 0
        isDriftSignificant = false
        elapsedTime = 0
        lastLoggedSecond = -1
        rawFrames = []
        slopeSamples = []
    }

    @discardableResult
    func stopTracking(iteration: Int) -> Double {
        isTracking = false
        let ratePx = currentSlope * 60       // currentSlope は px/秒
        let sePx = slopeStdError * 60
        slopeHistory.append((rate: ratePx, sePxPerMin: sePx, iteration: iteration))
        return currentSlope
    }

    func addCentroid(_ point: CGPoint, at time: Date) {
        guard isTracking, let startTime = trackingStartTime else { return }
        guard let cal = calibration, let origin = sessionOrigin else { return }

        // 重心(正規化)を px に変換し、px変位を Dec軸・RA軸に投影
        let w = imageSize.width  > 0 ? imageSize.width  : 1280
        let h = imageSize.height > 0 ? imageSize.height : 720
        let dispPx = CGVector(dx: (point.x - origin.x) * w, dy: (point.y - origin.y) * h)
        let decDisp = cal.decComponent(of: dispPx)
        let raDisp = cal.raComponent(of: dispPx)

        // 速度予測用に直近変位を記録
        if case .tracking(let last) = trackingState {
            let frameDisp = CGVector(dx: point.x - last.x, dy: point.y - last.y)
            recentDisplacements.append((frameDisp, time))
            if recentDisplacements.count > 5 { recentDisplacements.removeFirst() }
        }
        trackingState = .tracking(lastPosition: point)

        let t = time.timeIntervalSince(startTime)
        elapsedTime = t
        rawFrames.append((elapsed: t, x: Double(point.x), y: Double(point.y), decDisp: Double(decDisp), raDisp: Double(raDisp)))
        regression.add(t: t, y: Double(decDisp))
        raRegression.add(t: t, y: Double(raDisp))

        currentSlope = regression.slope
        slopeStdError = regression.slopeStdError
        raSlope = raRegression.slope
        // 統計的有意 かつ 1 px/分超過の両方を満たす場合のみ有意とする（currentSlope は px/秒）
        isDriftSignificant = regression.isSignificant && abs(currentSlope * 60) >= 1.0

        let sec = Int(elapsedTime)
        if sec > lastLoggedSecond {
            lastLoggedSecond = sec
            // 傾き安定化判定用にスナップショットを記録
            slopeSamples.append((t: elapsedTime, ratePxPerMin: currentSlope * 60))
            let ratePx = currentSlope * 60               // 実ピクセル/分
            let sePx   = slopeStdError * 60
            let raPx   = raSlope * 60                     // RA方向ドリフト（px/分、診断用）
            let tStat  = slopeStdError > 0 ? currentSlope / slopeStdError : 0
            let xPx    = point.x * w
            let yPx    = point.y * h
            driftLogger.info(
                "t=\(sec)s n=\(self.regression.n) pos=(\(String(format: "%.1f", xPx)),\(String(format: "%.1f", yPx)))px rate=\(String(format: "%.2f", ratePx))±\(String(format: "%.2f", sePx*3))px/min(3σ) RA=\(String(format: "%.2f", raPx))px/min t=\(String(format: "%.2f", tStat)) sig=\(self.isDriftSignificant) precise=\(self.isPrecise)"
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

    // 3σ ≤ 1 px/分 を満たすかどうか（slopeStdError は px/秒）
    var isPrecise: Bool {
        guard regression.n >= 10 else { return false }
        let threeSigmaPxPerMin = slopeStdError * 60 * 3
        return threeSigmaPxPerMin.isFinite && threeSigmaPxPerMin <= 1.0
    }

    // 直近 stabilityWindow 秒で傾き推定が stabilitySlopeTol 以内に収束しているか
    var isStable: Bool {
        guard elapsedTime >= stabilityWindow else { return false }
        let recent = slopeSamples.filter { $0.t >= elapsedTime - stabilityWindow }
        guard recent.count >= 2 else { return false }
        let rates = recent.map { $0.ratePxPerMin }
        guard let lo = rates.min(), let hi = rates.max() else { return false }
        return (hi - lo) <= stabilitySlopeTol
    }

    var isPhaseComplete: Bool {
        if elapsedTime >= maxMeasureDuration { return true }   // 安全上限
        // 統計精度(isPrecise)に加え傾きの収束(isStable)を必須化し、早期終了による系統誤差混入を防ぐ
        return elapsedTime >= minMeasureDuration && isPrecise && isStable
    }
}
