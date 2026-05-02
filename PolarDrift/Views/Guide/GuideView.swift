import SwiftUI

struct GuideView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    guideSection(
                        title: "ドリフト法とは",
                        icon: "scope",
                        content: """
                        ドリフト法は赤道儀の極軸を精密に合わせる方法です。
                        星の赤緯方向のずれ（ドリフト）を計測し、方位角と高度を調整します。
                        本アプリはiPhoneのカメラで星を自動追跡し、ドリフトを定量的に計測します。
                        """
                    )

                    guideSection(
                        title: "Step 1: 方位角フェーズ",
                        icon: "arrow.left.and.right",
                        content: """
                        南中付近（子午線上）の赤緯 0° 付近の星を使います。
                        ドリフトを計測し、極軸の方位角を東西方向に調整します。
                        「スタート」と言って測定を開始し、結果に従って調整してください。
                        """
                    )

                    guideSection(
                        title: "Step 2: 高度フェーズ",
                        icon: "arrow.up.and.down",
                        content: """
                        東または西の地平線付近（高度 20〜30°）の赤緯 0° 付近の星を使います。
                        ドリフトを計測し、極軸の高度（仰角）を上下に調整します。
                        """
                    )

                    guideSection(
                        title: "キャリブレーションについて",
                        icon: "viewfinder",
                        content: """
                        各フェーズの開始時に赤緯軸の方向をキャリブレーションします。
                        星を中央に導入後「スタート」と言い、赤緯方向に少し動かすだけです。
                        アプリが自動的に赤緯軸の方向を特定し、十字線を表示します。
                        """
                    )

                    guideSection(
                        title: "ドリフト判定について",
                        icon: "chart.line.uptrend.xyaxis",
                        content: """
                        アプリは線形回帰を使ってドリフト速度（px/分）を計算します。
                        残差から動的にしきい値を設定するため、シーイング条件に自動適応します。
                        ± 2σ の範囲内でドリフトが有意でなくなったときに「完了」と判定します。
                        """
                    )
                }
                .padding(16)
            }
            .background(Color.astronomyBackground)
            .navigationTitle("ガイド")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.astronomyBackground, for: .navigationBar)
        }
    }

    private func guideSection(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.astronomyAccent)
                    .frame(width: 24)
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(.white)
            }
            Text(content)
                .font(.instructionBody)
                .foregroundStyle(.white.opacity(0.75))
                .lineSpacing(4)
        }
        .padding(16)
        .background(Color.astronomyCard, in: RoundedRectangle(cornerRadius: 14))
    }
}
