import Foundation

enum AlignmentPhase: String, Codable, CaseIterable {
    case azimuth
    case altitude

    var displayName: String {
        switch self {
        case .azimuth: return "方位角フェーズ"
        case .altitude: return "高度フェーズ"
        }
    }

    var guideMessage: String {
        switch self {
        case .azimuth: return "南中付近の星に望遠鏡を向けてください"
        case .altitude: return "東または西の地平線付近の星に望遠鏡を向けてください"
        }
    }

    var adjustmentAxis: String {
        switch self {
        case .azimuth: return "極軸を東西方向に動かしてみてください"
        case .altitude: return "極軸高度を上下に動かしてみてください"
        }
    }

    var next: AlignmentPhase? {
        switch self {
        case .azimuth: return .altitude
        case .altitude: return nil
        }
    }
}
