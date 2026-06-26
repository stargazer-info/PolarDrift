import SwiftUI
import Observation

@Observable
final class CalibrationViewModel {

    // MARK: - 所有する状態
    var detectionFailed: Bool = false
    var detectedCentroid: CGPoint?
    var frameProcessor = FrameProcessor()
    private(set) var imageSize: CGSize? = nil

    private var calibrationOrigin: CGPoint?
    private var calibLastPos: CGPoint?
    private var calibPrevPos: CGPoint?          // 1つ前の位置（予測速度の算出用）
    private var calPath: [CGPoint] = []          // Dec軸決定用の移動軌跡（px、主軸フィット用）
    private let decMoveThreshold: CGFloat = 0.10  // 移動量しきい値（画像幅に対する割合）
    private var detectionTimeoutTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?

    // MARK: - フレームストリーム開始・停止

    func startStream(
        _ stream: AsyncStream<GrayImage>,
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>
    ) {
        streamTask?.cancel()
        streamTask = Task {
            // 遷移アニメーション完了後に検出開始（「星を検出しています…」を確実に表示）
            try? await Task.sleep(for: .milliseconds(400))
            // PhaseGuideViewから直接.detectingCentroidに遷移した場合、タイムアウトを自動開始
            if case .calibration(.detectingCentroid) = step.wrappedValue {
                startDetectionTimeout(step: step)
            }
            for await gray in stream {
                processFrame(gray, step: step, calibration: calibration)
            }
        }
    }

    func stopStream() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - 音声コマンド処理

    func handleVoiceCommand(
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>
    ) {
        guard case .calibration(let calStep) = step.wrappedValue else { return }
        switch calStep {
        case .waitingForVoice:
            detectionFailed = false
            step.wrappedValue = .calibration(.detectingCentroid)
            startDetectionTimeout(step: step)

        case .detectingCentroid:
            cancelDetectionTimeout()
            detectedCentroid = nil
            detectionFailed = false
            step.wrappedValue = .calibration(.detectingCentroid)
            startDetectionTimeout(step: step)

        default:
            break
        }
    }

    // MARK: - フレーム処理（@MainActor 継承により await 不要）

    private func processFrame(
        _ gray: GrayImage,
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>
    ) {
        imageSize = CGSize(width: gray.width, height: gray.height)
        switch step.wrappedValue {
        case .calibration(.detectingCentroid):
            handleCalibrationDetection(gray, step: step, calibration: calibration)

        case .calibration(.awaitingDecMove(let origin)):
            handleDecAxisDetection(gray, origin: origin, step: step, calibration: calibration)

        default:
            break
        }
    }

    private func handleCalibrationDetection(
        _ gray: GrayImage,
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>
    ) {
        let centroid = frameProcessor.detectInitialCentroid(in: gray)
        detectedCentroid = centroid
        guard let centroid else { return }
        cancelDetectionTimeout()
        calibrationOrigin = centroid
        calibLastPos = centroid
        calibPrevPos = nil
        calPath = [centroid]
        step.wrappedValue = .calibration(.awaitingDecMove(origin: centroid))
    }

    private func handleDecAxisDetection(
        _ gray: GrayImage,
        origin: CGPoint,
        step: Binding<SessionStep>,
        calibration: Binding<DecCalibration?>
    ) {
        guard let last = calibLastPos else { return }
        // 直近2点から予測速度（px/フレーム）を求め、低fpsでフレーム間移動が大きくても追跡ROIに収める
        var predicted = CGVector.zero
        if let prev = calibPrevPos {
            predicted = CGVector(dx: last.x - prev.x, dy: last.y - prev.y)
        }
        guard let pos = frameProcessor.trackCentroid(
            in: gray, lastPosition: last,
            predictedVelocity: predicted, searchRadius: 80
        ) else { return }
        detectedCentroid = pos
        calibPrevPos = last
        calibLastPos = pos

        calPath.append(pos)

        // 移動量判定（しきい値は画像幅に対する割合を px に換算）
        let disp = CGVector(dx: pos.x - origin.x, dy: pos.y - origin.y)
        let dist = sqrt(disp.dx * disp.dx + disp.dy * disp.dy)
        let threshPx = CGFloat(gray.width) * decMoveThreshold
        guard dist >= threshPx else { return }
        // 移動軌跡の全点から主軸フィットでDec軸を確定（ノイズ平均化で角度誤差を最小化）
        guard let cal = DecCalibration.from(points: calPath)
            ?? DecCalibration.from(origin: origin, moved: pos) else { return }
        calibration.wrappedValue = cal
        step.wrappedValue = .driftMeasure(.reintroducing(iteration: 1))
    }

    // MARK: - 検出タイムアウト

    private func startDetectionTimeout(step: Binding<SessionStep>) {
        detectionTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if case .calibration(.detectingCentroid) = step.wrappedValue {
                detectedCentroid = nil
                detectionFailed = true
                step.wrappedValue = .calibration(.waitingForVoice)
            }
        }
    }

    private func cancelDetectionTimeout() {
        detectionTimeoutTask?.cancel()
        detectionTimeoutTask = nil
    }
}
