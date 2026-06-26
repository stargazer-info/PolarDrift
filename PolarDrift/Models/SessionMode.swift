enum SessionMode {
    case driftCheck   // ドリフト確認モード（azimuth → altitude の2フェーズ）
    case periodCheck  // 周期確認モード（1回のキャリブ + 長時間連続計測）
}
