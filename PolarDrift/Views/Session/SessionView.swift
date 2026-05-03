import SwiftUI

struct SessionView: View {
    @State private var speech: SpeechRecognitionManager
    @State private var sessionVM: AppSessionViewModel

    init() {
        let s = SpeechRecognitionManager()
        _speech    = State(initialValue: s)
        _sessionVM = State(initialValue: AppSessionViewModel(speech: s))
    }

    var body: some View {
        @Bindable var session = sessionVM

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
                                   isListening: speech.isListening)
                        .transition(.asymmetric(insertion: .move(edge: .trailing),
                                                removal: .move(edge: .leading)))

                case .calibration:
                    CalibrationView(
                        vm: session.calibrationVM,
                        step: $session.step,
                        calibration: $session.calibration,
                        isListening: speech.isListening
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
                        isListening: speech.isListening
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                            removal: .move(edge: .leading)))
                    .onAppear { session.startDriftStream() }
                    .onDisappear { session.driftMeasureVM.stopStream() }

                case .phaseComplete(let phase):
                    PhaseCompleteView(phase: phase)
                        .transition(.opacity)

                case .sessionComplete:
                    SessionCompleteView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: stepID)
        }
        .environment(sessionVM)
        .task { await sessionVM.setup() }
        .onChange(of: speech.commandCount) {
            sessionVM.handleVoiceCommand(speech.lastCommand)
        }
    }

    private var needsDimOverlay: Bool {
        switch sessionVM.step {
        case .calibration, .driftMeasure: return false
        default: return true
        }
    }

    private var stepID: Int {
        switch sessionVM.step {
        case .phaseGuide:      return 0
        case .calibration:     return 1
        case .driftMeasure:    return 2
        case .phaseComplete:   return 3
        case .sessionComplete: return 4
        }
    }
}
