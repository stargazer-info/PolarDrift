import SwiftUI
import AVFoundation

struct DriftMeasureView: View {
    let vm: DriftMeasureViewModel
    @Binding var step: SessionStep
    @Binding var currentPhase: AlignmentPhase
    @Binding var calibration: DecCalibration?
    let isListening: Bool
    let previewLayer: AVCaptureVideoPreviewLayer?

    private var tracker: DriftTracker { vm.driftTracker }

    var body: some View {
        ZStack {
            StarOverlayView(
                detectedCentroid: vm.detectedCentroid,
                sessionOrigin: tracker.sessionOrigin,
                calibration: calibration,
                driftHistory: [],
                isTracking: tracker.isTracking,
                showCrosshair: showDriftCrosshair,
                crosshairFollowsStar: crosshairFollowsStar,
                previewLayer: previewLayer
            )
            .ignoresSafeArea()

            VStack {
                phaseHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer()
                if case .lostAlert = tracker.trackingState {
                    lostAlertCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                driftDisplay
                    .padding(.horizontal, 16)
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 48)
            }
        }
    }

    private var isMeasuring: Bool {
        guard case .driftMeasure(.measuring) = step else { return false }
        return true
    }

    private var showDriftCrosshair: Bool {
        switch step {
        case .driftMeasure: return true
        default: return false
        }
    }

    private var crosshairFollowsStar: Bool {
        guard case .driftMeasure(.reintroducing) = step else { return false }
        return true
    }

    // MARK: - Sub-views

    private var phaseHeader: some View {
        HStack {
            let color = currentPhase == .azimuth ? Color.phaseAzimuth : Color.phaseAltitude
            Text(currentPhase.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(color.opacity(0.2), in: Capsule())
            Spacer()
            if let n = iterationNumber {
                Text("測定 \(n) 回目")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.astronomyBackground.opacity(0.6))
    }

    private var iterationNumber: Int? {
        switch step {
        case .driftMeasure(.reintroducing(let n)): return n
        case .driftMeasure(.measuring(let n)): return n
        case .driftMeasure(.showingResult(_, let n)): return n
        default: return nil
        }
    }

    private var driftDisplay: some View {
        VStack(spacing: 4) {
            if tracker.isTracking && tracker.regression.n >= 5 {
                let rate = tracker.currentSlope * 60
                let se   = tracker.slopeStdError * 60
                Text(String(format: "%.1f ± %.1f px/分", rate, se * 2))
                    .font(.driftRate)
                    .foregroundStyle(driftColor(rate))
                    .contentTransition(.numericText())
                Text("サンプル数: \(tracker.regression.n)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else if tracker.isTracking {
                Text("計測中…")
                    .font(.cardTitle)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
    }

    private func driftColor(_ rate: Double) -> Color {
        abs(rate) < 1 ? .green : (rate > 0 ? .driftPositive : .driftNegative)
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 12) {
            switch step {
            case .driftMeasure(.reintroducing(let n)):
                instructionText(n == 1
                    ? "星を中央に導入して「スタート」と言ってください"
                    : "調整後、星を中央に導入して「スタート」と言ってください")

            case .driftMeasure(.measuring):
                instructionText("望遠鏡を動かさないでください")

            case .driftMeasure(.showingResult(let feedback, _)):
                resultCard(feedback)

            default:
                EmptyView()
            }
            VoiceStatusBadge(isListening: isListening)
        }
    }

    private func instructionText(_ text: String) -> some View {
        Text(text)
            .font(.cardTitle)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.astronomyCard.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
    }

    private func resultCard(_ feedback: DriftFeedback) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: feedback == .complete ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(feedback == .complete ? .green : Color.astronomyAccent)
                Text(feedback == .complete ? "このフェーズ完了！" : currentPhase.adjustmentAxis)
                    .font(.cardTitle).foregroundStyle(.white)
            }
            if feedback != .complete {
                Text(feedback.message)
                    .font(.phaseTitle)
                    .foregroundStyle(feedback == .sameDirection ? Color.driftPositive : Color.driftNegative)
                Text("「スタート」と言って再測定します")
                    .font(.instructionBody).foregroundStyle(.white.opacity(0.6))

                if !tracker.slopeHistory.isEmpty {
                    Divider().background(.white.opacity(0.2))
                    VStack(spacing: 4) {
                        ForEach(tracker.slopeHistory.reversed(), id: \.iteration) { entry in
                            HStack {
                                Text("測定\(entry.iteration)")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text(String(format: "%.1f px/分", entry.rate))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(abs(entry.rate) < 60 ? .green : .white.opacity(0.8))
                            }
                        }
                    }
                }

                Text("「スキップ」と言うと次のフェーズへ進みます")
                    .font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.astronomyCard.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
    }

    private var lostAlertCard: some View {
        VStack(spacing: 12) {
            Text("星が見つかりません")
                .font(.cardTitle).foregroundStyle(.orange)
            HStack(spacing: 12) {
                Button("測定を続ける") {
                    vm.handleLostStarContinue(
                        step: $step,
                        calibration: $calibration,
                        currentPhase: $currentPhase
                    )
                }
                .buttonStyle(.bordered).tint(.orange)
                Button("やり直す") {
                    vm.handleLostStarRestart(step: $step)
                }
                .buttonStyle(.bordered).tint(.gray)
            }
        }
        .padding(16)
        .background(Color.astronomyCard.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
    }
}
