import SwiftUI

struct PhaseGuideView: View {
    let phase: AlignmentPhase
    @Binding var step: SessionStep
    let isListening: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: phase == .azimuth ? "arrow.left.and.right" : "arrow.up.and.down")
                    .font(.system(size: 64))
                    .foregroundStyle(phase == .azimuth ? Color.phaseAzimuth : Color.phaseAltitude)

                Text(phase.displayName)
                    .font(.phaseTitle)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 12) {
                Text(phase.guideMessage)
                    .font(.cardTitle)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if phase == .azimuth {
                    Text("赤緯 0° 付近の明るい星が最適です")
                        .font(.instructionBody)
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("高度 20〜30° 付近、赤緯 0° 付近の星が最適です")
                        .font(.instructionBody)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(24)
            .background(Color.astronomyCard, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()

            VoiceStatusBadge(isListening: isListening)
                .padding(.bottom, 48)
        }
    }
}
