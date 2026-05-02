import Foundation

// 符号付き線形回帰（O(1)/サンプル）
// y = a + b*t の b（傾き）がドリフト速度
struct OnlineRegression {
    private(set) var n: Int = 0
    private var sumT: Double = 0
    private var sumT2: Double = 0
    private var sumY: Double = 0
    private var sumY2: Double = 0
    private var sumTY: Double = 0

    mutating func add(t: Double, y: Double) {
        n += 1
        sumT  += t
        sumT2 += t * t
        sumY  += y
        sumY2 += y * y
        sumTY += t * y
    }

    mutating func reset() {
        n = 0; sumT = 0; sumT2 = 0; sumY = 0; sumY2 = 0; sumTY = 0
    }

    // 傾き b（ドリフト速度、符号付き）
    var slope: Double {
        guard n >= 2 else { return 0 }
        let denom = Double(n) * sumT2 - sumT * sumT
        guard denom != 0 else { return 0 }
        return (Double(n) * sumTY - sumT * sumY) / denom
    }

    // 残差の分散 σ²
    private var residualVariance: Double {
        guard n >= 3 else { return Double.infinity }
        let b = slope
        let a = (sumY - b * sumT) / Double(n)
        let ssr = sumY2 - 2 * a * sumY - 2 * b * sumTY + Double(n) * a * a + 2 * a * b * sumT + b * b * sumT2
        return max(ssr / Double(n - 2), 0)
    }

    // 傾きの標準誤差 SE(b)
    var slopeStdError: Double {
        guard n >= 3 else { return Double.infinity }
        let sxx = sumT2 - sumT * sumT / Double(n)
        guard sxx > 0 else { return Double.infinity }
        return sqrt(residualVariance / sxx)
    }

    // |t統計量| > 2.0（95%信頼区間、df大）のときドリフト有意
    // 最低10サンプル必要
    var isSignificant: Bool {
        guard n >= 10 else { return false }
        let se = slopeStdError
        guard se > 0 && se.isFinite else { return false }
        return abs(slope / se) > 2.0
    }
}
