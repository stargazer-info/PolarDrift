import SwiftUI

struct SessionView: View {
    @Environment(SessionViewModel<SpeechRecognitionManager>.self) private var viewModel
    @Binding var shouldStartSession: Bool

    var body: some View {
        @Bindable var session = viewModel

        ZStack {
            CameraPreviewView(previewLayer: session.previewLayer)
                .ignoresSafeArea()

            if needsDimOverlay {
                Color.astronomyBackground.opacity(0.85)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: needsDimOverlay)
            }

            Group {
                switch session.step {
                case .phaseGuide(let phase):
                    PhaseGuideView(phase: phase, mode: session.currentMode,
                                   step: $session.step,
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
                        mode: session.currentMode,
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
                    SessionCompleteView(mode: session.currentMode,
                                        shouldStartSession: $shouldStartSession)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: stepID)

            if showsCameraControls {
                VStack {
                    Spacer()
                    CameraControlsView(
                        measureExposureSec: $session.measureExposureSec,
                        measureISO: $session.measureISO,
                        calibExposureSec: $session.calibExposureSec,
                        calibISO: $session.calibISO,
                        minContrast: $session.minContrast
                    )
                }
                .ignoresSafeArea(.keyboard)
            }
        }
        // 計測中と Dec 軸キャリブ中はモード選択に戻れないよう戻るボタン+ナビバーを隠す
        .navigationTitle(modeTitle)
        .navigationBarBackButtonHidden(!canReturnToModeSelection)
        .navigationBarHidden(!canReturnToModeSelection)
        .onChange(of: viewModel.speech.commandCount) {
            viewModel.handleVoiceCommand(viewModel.speech.lastCommand)
        }
    }

    private var modeTitle: String {
        viewModel.currentMode == .periodCheck ? "周期確認" : "ドリフト確認"
    }

    private var showsCameraControls: Bool {
        switch viewModel.step {
        case .calibration, .driftMeasure: return true
        default: return false
        }
    }

    private var needsDimOverlay: Bool {
        switch viewModel.step {
        case .calibration, .driftMeasure, .phaseGuide: return false
        default: return true
        }
    }

    private var canReturnToModeSelection: Bool {
        switch viewModel.step {
        case .driftMeasure(.measuring), .calibration(.awaitingDecMove):
            return false
        default:
            return true
        }
    }

    private var stepID: Int {
        switch viewModel.step {
        case .phaseGuide:      return 1
        case .calibration:     return 2
        case .driftMeasure:    return 3
        case .phaseComplete:   return 4
        case .sessionComplete: return 5
        }
    }
}
