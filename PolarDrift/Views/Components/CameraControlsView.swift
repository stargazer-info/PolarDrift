import SwiftUI

struct CameraControlsView: View {
    @Binding var iso: Float
    @Binding var shutterDenominator: Int
    @Binding var minContrast: Float
    let onApply: () -> Void

    @State private var isExpanded = false

    private let shutterOptions = [15, 30, 60, 120, 250]

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("ISO \(Int(iso))  1/\(shutterDenominator)s")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.7))
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
                VStack(spacing: 12) {
                    LabeledSlider(label: "ISO", value: $iso,
                                  range: 200...3200, step: 100,
                                  format: { "\(Int($0))" })
                    HStack {
                        Text("シャッタースピード")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        ForEach(shutterOptions, id: \.self) { s in
                            Button("1/\(s)") {
                                shutterDenominator = s
                                onApply()
                            }
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(shutterDenominator == s
                                        ? Color.astronomyAccent.opacity(0.3)
                                        : Color.astronomyCard,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(shutterDenominator == s ? Color.astronomyAccent : .white.opacity(0.7))
                        }
                    }
                    LabeledSlider(label: "コントラスト", value: $minContrast,
                                  range: 0.05...0.6, step: 0.05,
                                  format: { String(format: "%.2f", $0) })
                }
                .padding(16)
                .background(Color.astronomyCard)
                .onChange(of: iso) { _, _ in onApply() }
            }
        }
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
