import SwiftUI

struct SessionCompleteView: View {
    let mode: SessionMode
    @Binding var shouldStartSession: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: mode == .periodCheck ? "waveform.path.ecg" : "star.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(Color.astronomyAccent)
                .symbolEffect(.bounce)

            VStack(spacing: 12) {
                Text(mode == .periodCheck ? "周期確認 完了！" : "極軸合わせ完了！")
                    .font(.phaseTitle)
                    .foregroundStyle(.white)
                Text(mode == .periodCheck
                     ? "長時間ドリフトログを保存しました"
                     : "方位角・高度の両フェーズが完了しました")
                    .font(.cardTitle)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("新しいセッションを開始") {
                shouldStartSession = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.astronomyAccent)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 32)
    }
}
