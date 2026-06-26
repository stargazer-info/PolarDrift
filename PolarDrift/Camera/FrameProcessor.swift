import CoreGraphics

struct FrameProcessor {
    var minContrast: Float = 0.15
    var minBlobPixels: Int = 1
    var maxBlobPixels: Int = 800  // 長秒露光の星像肥大・キャリブ時の軽微なストリークを吸収

    func detectInitialCentroid(in gray: GrayImage) -> CGPoint? {
        let w = CGFloat(gray.width)
        let h = CGFloat(gray.height)
        return findCentroid(in: gray, roi: CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.8, height: h * 0.8))
    }

    func trackCentroid(in gray: GrayImage,
                       lastPosition: CGPoint,
                       predictedVelocity: CGVector,
                       searchRadius: CGFloat) -> CGPoint? {
        let w = CGFloat(gray.width)
        let h = CGFloat(gray.height)
        let predicted = CGPoint(
            x: lastPosition.x + predictedVelocity.dx,
            y: lastPosition.y + predictedVelocity.dy
        )
        let r = searchRadius
        let roi = CGRect(x: predicted.x - r, y: predicted.y - r, width: r * 2, height: r * 2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return findCentroid(in: gray, roi: roi)
    }

    // MARK: - Private

    private func findCentroid(in gray: GrayImage, roi: CGRect) -> CGPoint? {
        let (data, w, h) = (gray.data, gray.width, gray.height)

        let x0 = max(0, Int(roi.minX))
        let y0 = max(0, Int(roi.minY))
        let x1 = min(w, Int(roi.maxX))
        let y1 = min(h, Int(roi.maxY))
        guard x1 > x0 && y1 > y0 else { return nil }

        var hist = [Int](repeating: 0, count: 256)
        var peak: UInt8 = 0
        for y in y0..<y1 { for x in x0..<x1 {
            let v = data[y * w + x]
            hist[Int(v)] &+= 1
            if v > peak { peak = v }
        }}
        // ROI内の星像占有に対しロバストな背景推定（平均は狭ROI+長秒露光時に高騰する）
        let target = max(1, ((x1 - x0) * (y1 - y0)) / 4)
        var cum = 0
        var background: Float = 0
        for i in 0..<256 {
            cum += hist[i]
            if cum >= target { background = Float(i); break }
        }
        guard (Float(peak) - background) / 255.0 >= minContrast else { return nil }

        let thresh = UInt8(background + 0.3 * (Float(peak) - background))
        var sumWt = 0.0, sumWX = 0.0, sumWY = 0.0, blobCount = 0
        for y in y0..<y1 { for x in x0..<x1 {
            let v = data[y * w + x]; guard v >= thresh else { continue }
            let wt = Double(v); sumWt += wt; sumWX += wt * Double(x); sumWY += wt * Double(y)
            blobCount += 1
        }}
        guard sumWt > 0, blobCount >= minBlobPixels, blobCount <= maxBlobPixels else { return nil }
        return CGPoint(x: sumWX / sumWt, y: sumWY / sumWt)
    }
}
