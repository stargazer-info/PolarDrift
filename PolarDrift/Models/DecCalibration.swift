import Foundation
import CoreGraphics

// Dec/RA軸の分解はすべてピクセル座標で行う。
// 重心は x を幅・y を高さで割った異方性のある正規化座標で得られるため、
// そのまま 90°回転・射影すると天球上の直交と一致せずRA成分がDecへ混入する。
// 呼び出し側で重心を px（x*width, y*height）に変換してから本構造体へ渡すこと。
// px 空間は等方なので RA⊥Dec が成立し、射影結果はそのまま px 単位になる。
struct DecCalibration: Codable {
    let decAxisVector: CGVector  // px空間でのDec軸方向の単位ベクトル（符号はキャリブレーション移動方向が+）

    // RA軸は px空間でDec軸に直交（90°回転）。等方空間なので天球上の直交と一致する。
    var raAxisVector: CGVector {
        CGVector(dx: -decAxisVector.dy, dy: decAxisVector.dx)
    }

    // px変位ベクトルをDec軸に投影（符号付き、戻り値 px。キャリブレーション移動方向が+）
    func decComponent(of pixelDisplacement: CGVector) -> CGFloat {
        pixelDisplacement.dx * decAxisVector.dx + pixelDisplacement.dy * decAxisVector.dy
    }

    // px変位ベクトルをRA軸に投影（診断用、px）
    func raComponent(of pixelDisplacement: CGVector) -> CGFloat {
        let ra = raAxisVector
        return pixelDisplacement.dx * ra.dx + pixelDisplacement.dy * ra.dy
    }

    // Dec軸・RA軸それぞれの角度（atan2、Canvas描画用）。
    // 軸はpx空間 = 等方ビュー空間と同方向なので画面上で正しく直交描画される。
    func crosshairAngles() -> (decAngle: CGFloat, raAngle: CGFloat) {
        let dec = atan2(decAxisVector.dy, decAxisVector.dx)
        let ra = atan2(raAxisVector.dy, raAxisVector.dx)
        return (dec, ra)
    }

    // px の2点（原点・移動後）からDec軸を決定。from(points:) が縮退した場合のフォールバック。
    static func from(origin: CGPoint, moved: CGPoint) -> DecCalibration? {
        let dx = moved.x - origin.x
        let dy = moved.y - origin.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return nil }
        return DecCalibration(decAxisVector: CGVector(dx: dx / length, dy: dy / length))
    }

    // px の移動軌跡全点から主軸（全最小二乗 / PCA）でDec軸を決定。
    // 重心ノイズを平均化し角度誤差（θ）を最小化する。
    static func from(points: [CGPoint]) -> DecCalibration? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }

        let n = Double(points.count)
        let meanX = points.reduce(0.0) { $0 + Double($1.x) } / n
        let meanY = points.reduce(0.0) { $0 + Double($1.y) } / n

        // 2×2 共分散行列
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            let dx = Double(p.x) - meanX
            let dy = Double(p.y) - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }

        // 分散が縮退（ほぼ点）の場合は2点フォールバック
        guard sxx + syy > 0 else { return from(origin: first, moved: last) }

        // 主軸の向き: θ = 0.5 * atan2(2·Sxy, Sxx − Syy)
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        var dirX = cos(theta)
        var dirY = sin(theta)

        // 符号を先頭→末尾の正味変位方向に揃える
        let netX = Double(last.x) - Double(first.x)
        let netY = Double(last.y) - Double(first.y)
        if dirX * netX + dirY * netY < 0 {
            dirX = -dirX
            dirY = -dirY
        }

        let len = sqrt(dirX * dirX + dirY * dirY)
        guard len > 0 else { return from(origin: first, moved: last) }
        return DecCalibration(decAxisVector: CGVector(dx: dirX / len, dy: dirY / len))
    }
}
