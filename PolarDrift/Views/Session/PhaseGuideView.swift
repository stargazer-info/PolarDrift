import SwiftUI

struct PhaseGuideView: View {
    let phase: AlignmentPhase
    let mode: SessionMode
    @Binding var step: SessionStep
    let isListening: Bool

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    if mode == .periodCheck {
                        Text("計測したい星に望遠鏡を向けてください")
                            .font(.cardTitle)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                        Text("明るい星（2〜4等級）が最適です")
                            .font(.instructionBody)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("最大 20 分間の連続計測を行います")
                            .font(.instructionBody)
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Text(phase.guideMessage)
                            .font(.cardTitle)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                        Text(phase == .azimuth
                             ? "赤緯 0° 付近の明るい星が最適です"
                             : "高度 20〜30° 付近、赤緯 0° 付近の星が最適です")
                            .font(.instructionBody)
                            .foregroundStyle(.white.opacity(0.6))
                    }
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
