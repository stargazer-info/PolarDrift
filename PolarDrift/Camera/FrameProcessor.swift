import CoreGraphics

struct FrameProcessor {
    var minContrast: Float = 0.25
    var minBlobPixels: Int = 1
    var maxBlobPixels: Int = 400  // 長秒露光の星像肥大・キャリブ時の軽微なストリークを吸収

    func detectInitialCentroid(in gray: GrayImage) -> CGPoint? {
        findCentroid(in: gray, roi: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
    }

    func trackCentroid(in gray: GrayImage,
                       lastPosition: CGPoint,
                       predictedVelocity: CGVector,
                       searchRadius: CGFloat) -> CGPoint? {
        let w = CGFloat(gray.width)
        let h = CGFloat(gray.height)
        let predicted = CGPoint(
            x: lastPosition.x + predictedVelocity.dx / w,
            y: lastPosition.y + predictedVelocity.dy / h
        )
        let rX = searchRadius / w
        let rY = searchRadius / h
        let roi = CGRect(x: predicted.x - rX, y: predicted.y - rY, width: rX * 2, height: rY * 2)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return findCentroid(in: gray, roi: roi)
    }

    // MARK: - Private

    private func findCentroid(in gray: GrayImage, roi: CGRect) -> CGPoint? {
        let (data, w, h) = (gray.data, gray.width, gray.height)

        let x0 = max(0, Int(roi.minX * CGFloat(w)))
        let y0 = max(0, Int(roi.minY * CGFloat(h)))
        let x1 = min(w, Int(roi.maxX * CGFloat(w)))
        let y1 = min(h, Int(roi.maxY * CGFloat(h)))
        guard x1 > x0 && y1 > y0 else { return nil }

        var sum = 0; var peak: UInt8 = 0
        let count = (x1 - x0) * (y1 - y0)
        for y in y0..<y1 { for x in x0..<x1 {
            let v = data[y * w + x]; sum += Int(v); if v > peak { peak = v }
        }}
        let background = Float(sum) / Float(count)
        guard (Float(peak) - background) / 255.0 >= minContrast else { return nil }

        let thresh = UInt8(background + 0.3 * (Float(peak) - background))
        var sumWt = 0.0, sumWX = 0.0, sumWY = 0.0, blobCount = 0
        for y in y0..<y1 { for x in x0..<x1 {
            let v = data[y * w + x]; guard v >= thresh else { continue }
            let wt = Double(v); sumWt += wt; sumWX += wt * Double(x); sumWY += wt * Double(y)
            blobCount += 1
        }}
        guard sumWt > 0, blobCount >= minBlobPixels, blobCount <= maxBlobPixels else { return nil }
        return CGPoint(x: sumWX / sumWt / Double(w), y: sumWY / sumWt / Double(h))
    }
}
