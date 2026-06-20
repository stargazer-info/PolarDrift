import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewUIView {
        PreviewUIView()
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.setLayer(previewLayer)
    }

    // UIView サブクラスで layoutSubviews を使いフレームを常に正確に設定
    final class PreviewUIView: UIView {
        private var currentLayer: AVCaptureVideoPreviewLayer?

        func setLayer(_ layer: AVCaptureVideoPreviewLayer?) {
            if currentLayer !== layer {
                currentLayer?.removeFromSuperlayer()
                if let layer {
                    self.layer.insertSublayer(layer, at: 0)
                }
                currentLayer = layer
            }
            currentLayer?.frame = bounds
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            currentLayer?.frame = bounds
        }
    }
}
