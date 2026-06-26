import SwiftUI

struct ModeSelectionView: View {
    let onSelect: (SessionMode) -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("極軸合わせモードを選択")
                    .font(.phaseTitle)
                    .foregroundStyle(.white)
                Text("セッション中は変更できません")
                    .font(.instructionBody)
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(spacing: 16) {
                modeButton(
                    title: "ドリフト確認",
                    subtitle: "方位角・高度の2フェーズで極軸誤差を確認",
                    icon: "arrow.left.and.right",
                    color: Color.phaseAzimuth,
                    mode: .driftCheck
                )
                modeButton(
                    title: "周期確認",
                    subtitle: "1回の長時間連続計測で赤道儀の周期誤差を確認",
                    icon: "clock.arrow.circlepath",
                    color: .orange,
                    mode: .periodCheck
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func modeButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        mode: SessionMode
    ) -> some View {
        Button {
            onSelect(mode)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.cardTitle)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.instructionBody)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.astronomyCard.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
