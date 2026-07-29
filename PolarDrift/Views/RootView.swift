import SwiftUI

struct RootView: View {
    @State private var viewModel: SessionViewModel<SpeechRecognitionManager>
    @State private var isSessionActive = false
    @State private var shouldStartNewSession = false

    init() {
        _viewModel = State(initialValue: SessionViewModel(speech: SpeechRecognitionManager()))
    }

    var body: some View {
        NavigationStack {
            ModeSelectionView { mode in
                viewModel.selectMode(mode)
                isSessionActive = true
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $isSessionActive) {
                SessionView(shouldStartSession: $shouldStartNewSession)
            }
        }
        .environment(viewModel)
        .task { await viewModel.setup() }
        .onChange(of: shouldStartNewSession) { _, newValue in
            if newValue {
                isSessionActive = false
                shouldStartNewSession = false
            }
        }
        .onChange(of: isSessionActive) { _, newValue in
            // ナビの戻る／完了ボタン等で pop したときにセッション状態を初期化する
            if !newValue { viewModel.startSession() }
        }
    }
}
