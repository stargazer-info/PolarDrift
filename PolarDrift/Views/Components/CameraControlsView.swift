import SwiftUI

struct CameraControlsView: View {
    @Binding var measureExposureSec: Double
    @Binding var measureISO: Float
    @Binding var calibExposureSec: Double
    @Binding var calibISO: Float
    @Binding var minContrast: Float

    @State private var isExpanded = false

    // 計測相は長秒まで許可（星は静止）。キャリブ相はストリーク抑制のため上限を抑える。
    private let measureExposureOptions: [Double] = [1.0/250, 1.0/120, 1.0/60, 1.0/30, 1.0/15, 1.0/8, 1.0/4, 1.0/2, 1.0]
    private let calibExposureOptions: [Double]  = [1.0/120, 1.0/60, 1.0/30, 1.0/15, 1.0/8, 1.0/4]

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("計測 \(Self.label(measureExposureSec)) ISO\(Int(measureISO))  ｜  較正 \(Self.label(calibExposureSec)) ISO\(Int(calibISO))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.astronomyCard)
            }

            if isExpanded {
                VStack(spacing: 16) {
                    exposureSection(title: "計測（長秒で暗い星を写す）",
                                    options: measureExposureOptions,
                                    selection: $measureExposureSec)
                    isoSlider(label: "計測ISO", value: $measureISO)

                    Divider().overlay(Color.white.opacity(0.15))

                    exposureSection(title: "較正（控えめ露光・ブレ防止）",
                                    options: calibExposureOptions,
                                    selection: $calibExposureSec)
                    isoSlider(label: "較正ISO", value: $calibISO)

                    Divider().overlay(Color.white.opacity(0.15))

                    LabeledSlider(label: "コントラスト", value: $minContrast,
                                  range: 0.05...0.6, step: 0.05,
                                  format: { String(format: "%.2f", $0) })
                }
                .padding(16)
                .background(Color.astronomyCard)
            }
        }
    }

    @ViewBuilder
    private func exposureSection(title: String, options: [Double], selection: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { sec in
                        let isSel = abs(sec - selection.wrappedValue) < 1e-6
                        Button(Self.label(sec)) { selection.wrappedValue = sec }
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSel ? Color.astronomyAccent.opacity(0.3) : Color.astronomyBackground,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(isSel ? Color.astronomyAccent : .white.opacity(0.7))
                    }
                }
            }
        }
    }

    private func isoSlider(label: String, value: Binding<Float>) -> some View {
        LabeledSlider(label: label, value: value,
                      range: 200...6400, step: 100,
                      format: { "\(Int($0))" })
    }

    /// 露光秒を "1/30s" / "1s" 形式に整形。
    static func label(_ sec: Double) -> String {
        sec >= 1 ? "\(Int(sec))s" : "1/\(Int((1.0/sec).rounded()))s"
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let format: (Float) -> String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 80, alignment: .leading)
            Slider(value: $value, in: range, step: step)
                .tint(Color.astronomyAccent)
            Text(format(value))
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 48, alignment: .trailing)
        }
    }
}
