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
                if case .driftMeasure(.showingResult) = step, !vm.slopeHistory.isEmpty {
                    historyCard
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
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
        case .driftMeasure(.showingResult(let n)): return n
        default: return nil
        }
    }

    private var driftDisplay: some View {
        VStack(spacing: 4) {
            if tracker.isTracking && tracker.regression.n >= 5 {
                let rate = tracker.currentSlope * 60
                let se   = tracker.slopeStdError * 60
                Text(String(format: "%.1f ± %.1f px/分 (3σ)", rate, se * 3))
                    .font(.driftRate)
                    .foregroundStyle(driftColor(rate))
                    .contentTransition(.numericText())
                Text(String(format: "RA %.1f px/分（診断）", tracker.raSlope * 60))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                Text("サンプル数: \(tracker.regression.n)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text(stabilityStatus)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tracker.isStable ? .green : .white.opacity(0.6))
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

    private var stabilityStatus: String {
        #if DEBUG
        if tracker.diagnosticMode {
            let e = Int(tracker.elapsedTime)
            let capMin = Int((tracker.diagnosticDuration / 60).rounded())
            return String(format: "周期確認モード 経過 %d:%02d ／ 上限 %d分", e / 60, e % 60, capMin)
        }
        #endif
        let remaining = tracker.minMeasureDuration - tracker.elapsedTime
        if remaining > 0 {
            return String(format: "安定化待ち 残り%.0f秒", remaining)
        }
        return tracker.isStable ? "安定 ✓" : "傾き安定化中…"
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 12) {
            switch step {
            case .driftMeasure(.reintroducing):
                instructionText("星を中央に導入してください")
                VoiceStatusBadge(isListening: isListening,
                                 expectedCommand: "「スタート」")

            case .driftMeasure(.measuring):
                instructionText("望遠鏡を動かさないでください")
                #if DEBUG
                if tracker.diagnosticMode {
                    Button("計測停止") {
                        vm.stopMeasurementManually(
                            step: $step,
                            calibration: $calibration,
                            currentPhase: $currentPhase
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                #endif
                VoiceStatusBadge(isListening: isListening,
                                 expectedCommand: nil)

            case .driftMeasure(.showingResult):
                VoiceStatusBadge(isListening: isListening,
                                 expectedCommand: "「スタート」または「スキップ」")

            default:
                VoiceStatusBadge(isListening: isListening)
            }
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

    private var historyCard: some View {
        VStack(spacing: 2) {
            ForEach(vm.slopeHistory.suffix(3).reversed(), id: \.iteration) { entry in
                HStack {
                    Text("測定\(entry.iteration)")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(String(format: "%.1f ± %.1f px/分", entry.rate, entry.sePxPerMin * 3))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(abs(entry.rate) < 1.0 ? .green : .white.opacity(0.8))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.astronomyCard.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
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
