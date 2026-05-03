import SwiftUI
import AVFoundation

struct StarOverlayView: View {
    let detectedCentroid: CGPoint?
    let sessionOrigin: CGPoint?          // 「スタート」瞬間の固定基準点（測定中）
    let calibration: DecCalibration?
    let driftHistory: [CGPoint]
    let isTracking: Bool
    let showCrosshair: Bool              // false=非表示、true=表示（十字線）
    let crosshairFollowsStar: Bool       // true=星追随（キャリブ後）、false=固定（測定中）
    let previewLayer: AVCaptureVideoPreviewLayer?

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // 1. 十字線
                if showCrosshair, let cal = calibration {
                    let center: CGPoint
                    if crosshairFollowsStar {
                        center = denormalized(detectedCentroid ?? .init(x: 0.5, y: 0.5), size)
                    } else {
                        center = denormalized(sessionOrigin ?? .init(x: 0.5, y: 0.5), size)
                    }
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

    private func denormalized(_ pt: CGPoint, _ size: CGSize) -> CGPoint {
        if let layer = previewLayer {
            return layer.layerPointConverted(fromCaptureDevicePoint: pt)
        }
        return CGPoint(x: pt.x * size.width, y: pt.y * size.height)
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
