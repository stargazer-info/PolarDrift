import SwiftUI

extension Color {
    static let astronomyBackground = Color(red: 0.04, green: 0.04, blue: 0.08)
    static let astronomyCard       = Color(red: 0.08, green: 0.09, blue: 0.14)
    static let astronomyAccent     = Color(red: 0.4,  green: 0.7,  blue: 1.0)
    static let decAxisColor        = Color(red: 0.3,  green: 0.6,  blue: 1.0)  // Dec軸（青）
    static let raAxisColor         = Color(red: 1.0,  green: 0.9,  blue: 0.2)  // RA軸（黄）
    static let driftPositive       = Color(red: 0.3,  green: 0.6,  blue: 1.0)  // ドリフト+
    static let driftNegative       = Color(red: 1.0,  green: 0.55, blue: 0.2)  // ドリフト-
    static let starMarkerIdle      = Color(red: 0.3,  green: 0.85, blue: 0.5)  // 待機中（緑）
    static let starMarkerTracking  = Color(red: 1.0,  green: 0.7,  blue: 0.1)  // 追跡中（橙）
    static let phaseAzimuth        = Color(red: 0.6,  green: 0.4,  blue: 0.9)
    static let phaseAltitude       = Color(red: 0.3,  green: 0.7,  blue: 0.85)
}
