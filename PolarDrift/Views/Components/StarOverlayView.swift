import SwiftUI
import AVFoundation

struct StarOverlayView: View {
    let detectedCentroid: CGPoint?
    let sessionOrigin: CGPoint?          // 「スタート」瞬間の固定基準点（測定中、px）
    let calibration: DecCalibration?
    let driftHistory: [CGPoint]
    let isTracking: Bool
    let showCrosshair: Bool              // false=非表示、true=表示（十字線）
    let crosshairFollowsStar: Bool       // true=星追随（キャリブ後）、false=固定（測定中）
    let previewLayer: AVCaptureVideoPreviewLayer?
    let imageSize: CGSize?               // px → AVF normalized 変換源

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // 1. 十字線
                if showCrosshair, let cal = calibration, let imgSize = imageSize {
                    let centerPx: CGPoint
                    if crosshairFollowsStar {
                        centerPx = detectedCentroid ?? CGPoint(x: imgSize.width * 0.5, y: imgSize.height * 0.5)
                    } else {
                        centerPx = sessionOrigin ?? CGPoint(x: imgSize.width * 0.5, y: imgSize.height * 0.5)
                    }
                    let center = denormalized(centerPx, size)
                    let angles = cal.crosshairAngles()
                    drawLine(ctx: ctx, center: center, angle: angles.decAngle,
                             color: .decAxisColor, size: size)
                    drawLine(ctx: ctx, center: center, angle: angles.raAngle,
                             color: .raAxisColor, size: size)
                }

                // 2. ドリフト軌跡
                if driftHistory.count >= 2 {
                    let points = driftHistory.map { denormalized($0, size) }
                    var path = Path()
                    path.move(to: points[0])
                    for pt in points.dropFirst() { path.addLine(to: pt) }
                    ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
                }

                // 3. 重心マーカー
                if let centroid = detectedCentroid {
                    let pt = denormalized(centroid, size)
                    let color: Color = isTracking ? .starMarkerTracking : .starMarkerIdle
                    let r: CGFloat = 10
                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r*2, height: r*2))
                    ctx.stroke(circle, with: .color(color), lineWidth: 2)

                    // 中心の小さい点
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4))
                    ctx.fill(dot, with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // px CGPoint → ビュー CGPoint（px → AVF normalized → layer point）
    private func denormalized(_ ptPx: CGPoint, _ size: CGSize) -> CGPoint {
        guard let imgSize = imageSize, imgSize.width > 0, imgSize.height > 0 else {
            return ptPx
        }
        let norm = CGPoint(x: ptPx.x / imgSize.width, y: ptPx.y / imgSize.height)
        if let layer = previewLayer {
            return layer.layerPointConverted(fromCaptureDevicePoint: norm)
        }
        return CGPoint(x: norm.x * size.width, y: norm.y * size.height)
    }

    private func drawLine(ctx: GraphicsContext, center: CGPoint,
                          angle: CGFloat, color: Color, size: CGSize) {
        let len = max(size.width, size.height) * 1.5
        let dx = cos(angle) * len
        let dy = sin(angle) * len
        var path = Path()
        path.move(to: CGPoint(x: center.x - dx, y: center.y - dy))
        path.addLine(to: CGPoint(x: center.x + dx, y: center.y + dy))
        ctx.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1.0)
    }
}
