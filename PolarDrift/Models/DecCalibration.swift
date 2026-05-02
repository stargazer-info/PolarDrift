import Foundation
import CoreGraphics

struct DecCalibration: Codable {
    let decAxisVector: CGVector  // Dec軸方向の単位ベクトル（符号不問）

    var raAxisVector: CGVector {
        CGVector(dx: -decAxisVector.dy, dy: decAxisVector.dx)
    }

    // 変位ベクトルをDec軸に投影（符号付き。キャリブレーション時の移動方向が+）
    func decComponent(of displacement: CGVector) -> CGFloat {
        displacement.dx * decAxisVector.dx + displacement.dy * decAxisVector.dy
    }

    // Dec軸・RA軸それぞれの角度（atan2、Canvas描画用）
    func crosshairAngles() -> (decAngle: CGFloat, raAngle: CGFloat) {
        let dec = atan2(decAxisVector.dy, decAxisVector.dx)
        let ra = atan2(raAxisVector.dy, raAxisVector.dx)
        return (dec, ra)
    }

    static func from(origin: CGPoint, moved: CGPoint) -> DecCalibration? {
        let dx = moved.x - origin.x
        let dy = moved.y - origin.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return nil }
        return DecCalibration(decAxisVector: CGVector(dx: dx / length, dy: dy / length))
    }
}

