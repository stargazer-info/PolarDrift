import SwiftUI

struct SessionCompleteView: View {
    @Environment(AppSessionViewModel.self) var vm

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "star.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(Color.astronomyAccent)
                .symbolEffect(.bounce)

            VStack(spacing: 12) {
                Text("極軸合わせ完了！")
                    .font(.phaseTitle)
                    .foregroundStyle(.white)
                Text("方位角・高度の両フェーズが完了しました")
                    .font(.cardTitle)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("新しいセッションを開始") {
                vm.startSession()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.astronomyAccent)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 32)
    }
}
