import SwiftUI

struct PhaseGuideView: View {
    let phase: AlignmentPhase
    @Binding var step: SessionStep
    let isListening: Bool

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    let color = phase == .azimuth ? Color.phaseAzimuth : Color.phaseAltitude
                    Label(phase.displayName,
                          systemImage: phase == .azimuth ? "arrow.left.and.right" : "arrow.up.and.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.2), in: Capsule())
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(phase.guideMessage)
                        .font(.cardTitle)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)

                    Text(phase == .azimuth
                         ? "赤緯 0° 付近の明るい星が最適です"
                         : "高度 20〜30° 付近、赤緯 0° 付近の星が最適です")
                        .font(.instructionBody)
                        .foregroundStyle(.white.opacity(0.6))

                    Text("「スタート」と言って開始します")
                        .font(.instructionBody)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.astronomyCard.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            VoiceStatusBadge(isListening: isListening)
                .padding(.bottom, 48)
        }
    }
}
