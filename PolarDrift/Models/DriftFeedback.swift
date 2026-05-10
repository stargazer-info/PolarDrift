import Foundation

enum DriftFeedback {
    case sameDirection    // 同じ方向へ動かして下さい（改善中）
    case reverseDirection // 逆方向へ動かして下さい（悪化 or 行き過ぎ）
    case complete         // このフェーズ完了

    var message: String {
        switch self {
        case .sameDirection:    return "同じ方向へ動かして下さい"
        case .reverseDirection: return "逆方向へ動かして下さい"
        case .complete:         return "このフェーズ完了！"
        }
    }

    var recordLabel: String {
        switch self {
        case .sameDirection:    return "sameDirection"
        case .reverseDirection: return "reverseDirection"
        case .complete:         return "complete"
        }
    }

    // 符号付き slope 比較でフィードバックを生成
    // current, previous: DriftTracker.currentSlope の値
    static func evaluate(current: Double, previous: Double, isSignificant: Bool) -> DriftFeedback {
        guard isSignificant else { return .complete }
        let sameSide = current * previous > 0   // 符号が同じ
        if sameSide && abs(current) < abs(previous) {
            return .sameDirection
        }
        return .reverseDirection
    }
}

