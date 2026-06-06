import AVFoundation
import Accelerate

struct GrayImage {
    let data: [UInt8]
    let width: Int
    let height: Int

    init?(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var srcBuffer = vImage_Buffer(data: base, height: vImagePixelCount(h),
                                      width: vImagePixelCount(w), rowBytes: rowBytes)
        var grayData = [UInt8](repeating: 0, count: w * h)
        let result: GrayImage? = grayData.withUnsafeMutableBufferPointer { ptr in
            var dstBuffer = vImage_Buffer(data: ptr.baseAddress!, height: vImagePixelCount(h),
                                          width: vImagePixelCount(w), rowBytes: w)
            let matrix: [Int16] = [29, 150, 77, 0]  // メモリ配置BGRA順の重み: B=29,G=150,R=77,A=0 (BT.601)
            let err = vImageMatrixMultiply_ARGB8888ToPlanar8(&srcBuffer, &dstBuffer,
                                                              matrix, 256, nil, 0,
                                                              vImage_Flags(kvImageNoFlags))
            guard err == kvImageNoError else { return nil }
            return GrayImage(data: Array(ptr), width: w, height: h)
        }
        guard let r = result else { return nil }
        self = r
    }

    private init(data: [UInt8], width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}
