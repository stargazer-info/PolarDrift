import SwiftUI

struct SessionView: View {
    @Environment(AppSessionViewModel.self) var session
    @Environment(SpeechRecognitionManager.self) var speech

    var body: some View {
        @Bindable var session = session

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
                    PhaseGuideView(
                        phase: phase,
                        onStart: {
                            @Bindable var s = session
                            session.step = .calibration(.waitingForVoice)
                            session.calibrationVM.handleVoiceCommand(
                                step: $s.step,
                                calibration: $s.calibration,
                                speech: speech
                            )
                        }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                            removal: .move(edge: .leading)))

                case .calibration:
                    CalibrationView(
                        vm: session.calibrationVM,
                        step: $session.step,
                        calibration: $session.calibration,
                        speech: speech
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
                        speech: speech
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
        .task { await session.setup() }
    }

    private var needsDimOverlay: Bool {
        switch session.step {
        case .calibration, .driftMeasure: return false
        default: return true
        }
    }

    private var stepID: Int {
        switch session.step {
        case .phaseGuide:      return 0
        case .calibration:     return 1
        case .driftMeasure:    return 2
        case .phaseComplete:   return 3
        case .sessionComplete: return 4
        }
    }
}
