import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            SessionView()
                .tabItem {
                    Label("セッション", systemImage: "scope")
                }

            GuideView()
                .tabItem {
                    Label("ガイド", systemImage: "book.fill")
                }
        }
        .tint(Color.astronomyAccent)
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }
}
