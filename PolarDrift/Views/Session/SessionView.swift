import SwiftUI

struct SessionView: View {
    @State private var viewModel: SessionViewModel<SpeechRecognitionManager>
    @State private var shouldStartNewSession = false

    init() {
        let s = SpeechRecognitionManager()
        _viewModel = State(initialValue: SessionViewModel(speech: s))
    }

    var body: some View {
        @Bindable var session = viewModel

        ZStack {
            #if os(iOS)
            CameraPreviewView(previewLayer: session.previewLayer)
                .ignoresSafeArea()
            #endif

            if needsDimOverlay {
                Color.astronomyBackground.opacity(0.85)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: needsDimOverlay)
            }

            Group {
                switch session.step {
                case .phaseGuide(let phase):
                    PhaseGuideView(phase: phase, step: $session.step,
                                   isListening: viewModel.speech.isListening)
                        .transition(.asymmetric(insertion: .move(edge: .trailing),
                                                removal: .move(edge: .leading)))

                case .calibration:
                    CalibrationView(
                        vm: session.calibrationVM,
                        step: $session.step,
                        calibration: $session.calibration,
                        isListening: viewModel.speech.isListening,
                        previewLayer: viewModel.previewLayer
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                            removal: .move(edge: .leading)))
                    .onAppear { session.startCalibrationStream() }
                    .onDisappear { session.calibrationVM.stopStream() }

                case .driftMeasure:
                    DriftMeasureView(
                        vm: session.driftMeasureVM,
                        step: $session.step,
                        currentPhase: $session.currentPhase,
                        calibration: $session.calibration,
                        isListening: viewModel.speech.isListening,
                        previewLayer: viewModel.previewLayer
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                            removal: .move(edge: .leading)))
                    .onAppear { session.startDriftStream() }
                    .onDisappear { session.driftMeasureVM.stopStream() }

                case .phaseComplete(let phase):
                    PhaseCompleteView(phase: phase)
                        .transition(.opacity)

                case .sessionComplete:
                    SessionCompleteView(shouldStartSession: $shouldStartNewSession)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: stepID)
        }
        .environment(viewModel)
        .task { await viewModel.setup() }
        .onChange(of: viewModel.speech.commandCount) {
            viewModel.handleVoiceCommand(viewModel.speech.lastCommand)
        }
        .onChange(of: shouldStartNewSession) { _, newValue in
            if newValue {
                viewModel.startSession()
                shouldStartNewSession = false
            }
        }
    }

    private var needsDimOverlay: Bool {
        switch viewModel.step {
        case .calibration, .driftMeasure: return false
        default: return true
        }
    }

    private var stepID: Int {
        switch viewModel.step {
        case .phaseGuide:      return 0
        case .calibration:     return 1
        case .driftMeasure:    return 2
        case .phaseComplete:   return 3
        case .sessionComplete: return 4
        }
    }
}
