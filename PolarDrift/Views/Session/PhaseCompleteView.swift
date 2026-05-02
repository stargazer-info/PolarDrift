import SwiftUI

struct PhaseCompleteView: View {
    let phase: AlignmentPhase

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(phase == .azimuth ? Color.phaseAzimuth : Color.phaseAltitude)

            VStack(spacing: 12) {
                Text("\(phase.displayName)完了！")
                    .font(.phaseTitle)
                    .foregroundStyle(.white)
                if let next = phase.next {
                    Text("次は\(next.displayName)です")
                        .font(.cardTitle)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(next.guideMessage)
                        .font(.instructionBody)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            Spacer()
        }
    }
}
