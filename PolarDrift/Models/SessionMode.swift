enum SessionMode {
    case driftCheck   // ドリフト確認モード（azimuth → altitude の2フェーズ）
    case periodCheck  // 周期確認モード（1回のキャリブ + 長時間連続計測）

    // CSVファイル名に埋め込むモード識別子
    var fileSlug: String {
        switch self {
        case .driftCheck:  return "drift"
        case .periodCheck: return "period"
        }
    }
}
