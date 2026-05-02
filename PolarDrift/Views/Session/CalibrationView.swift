import SwiftUI

struct CalibrationView<Speech: SpeechManaging>: View {
    let vm: CalibrationViewModel
    @Binding var step: SessionStep
    @Binding var calibration: DecCalibration?
    let speech: Speech

    var body: some View {
        @Bindable var vm = vm

        ZStack {
            StarOverlayView(
                detectedCentroid: vm.detectedCentroid,
                sessionOrigin: nil,
                calibration: calibration,
                driftHistory: [],
                isTracking: false,
                showCrosshair: isDecAxisKnown,
                crosshairFollowsStar: true
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                instructionCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                if !isDetecting {
                    VoiceStatusBadge(isListening: speech.isListening)
                        .padding(.bottom, 48)
                } else {
                    Spacer().frame(height: 48)
                }
            }
        }
        .task {
            for await command in speech.makeCommandStream() {
                if case .start = command {
                    vm.handleVoiceCommand(
                        step: $step,
                        calibration: $calibration,
                        speech: speech
                    )
                }
            }
        }
    }

    private var isDetecting: Bool {
        guard case .calibration(.detectingCentroid) = step else { return false }
        return true
    }

    private var isDecAxisKnown: Bool {
        guard case .calibration(.complete) = step else { return false }
        return true
    }

    @ViewBuilder
    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch step {
            case .calibration(.waitingForVoice):
                VStack(alignment: .leading, spacing: 8) {
                    if vm.detectionFailed {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("星を検出できませんでした")
                                .font(.cardTitle).foregroundStyle(.orange)
                        }
                    }
                    Text("目標の星を導入したら")
                        .font(.cardTitle).foregroundStyle(.white)
                    Text("「スタート」と言ってください")
                        .font(.phaseTitle).foregroundStyle(Color.astronomyAccent)
                }

            case .calibration(.detectingCentroid):
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("星を検出しています…")
                        .font(.cardTitle).foregroundStyle(.white)
                }

            case .calibration(.awaitingDecMove):
                Text("赤緯（Dec）方向に")
                    .font(.cardTitle).foregroundStyle(.white)
                Text("望遠鏡を少し動かしてください")
                    .font(.phaseTitle).foregroundStyle(.yellow)
                Text("どちらの方向でも構いません")
                    .font(.instructionBody).foregroundStyle(.white.opacity(0.6))

            case .calibration(.complete):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("赤緯軸を確認しました")
                        .font(.cardTitle).foregroundStyle(.white)
                }
                Text("準備完了。「スタート」と言ってドリフト測定を開始してください")
                    .font(.instructionBody).foregroundStyle(.white.opacity(0.8))

            default:
                EmptyView()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.astronomyCard.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
    }
}
