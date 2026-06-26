import Foundation
import CoreGraphics

final class SessionRecorder {

    // MARK: - ヘッダー

    private static let header =
        "session_id,session_start,phase," +
        "cal_dec_axis_x,cal_dec_axis_y," +
        "iteration,duration_sec,sample_count," +
        "drift_rate_px_per_min,drift_rate_se_2sigma," +
        "ra_drift_rate_px_per_min," +
        "t_statistic,is_significant"

    private static let rawHeader =
        "session_id,phase,iteration,elapsed_sec," +
        "x_px,y_px,dec_disp_px,ra_disp_px,image_width,image_height"

    // MARK: - 状態

    private var sessionId = ""
    private var sessionStart = ""
    private var currentPhase = ""
    private var calDecAxisX = 0.0
    private var calDecAxisY = 0.0
    private var summaryURL: URL?
    private var rawURL: URL?

    // MARK: - API

    func startSession() {
        sessionId = UUID().uuidString
        let iso = ISO8601DateFormatter()
        sessionStart = iso.string(from: Date())
        currentPhase = ""
        calDecAxisX = 0; calDecAxisY = 0

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        let ts = f.string(from: Date())
        summaryURL = docs.appendingPathComponent("polardrift_\(ts).csv")
        rawURL     = docs.appendingPathComponent("polardrift_raw_\(ts).csv")

        // ヘッダー行を即時書き込み（ファイルを作成）
        append(Self.header + "\n", to: summaryURL)
        append(Self.rawHeader + "\n", to: rawURL)
        if let url = summaryURL {
            print("[SessionRecorder] ファイル作成: \(url.path)")
        }
    }

    func recordCalibration(_ cal: DecCalibration?, phase: AlignmentPhase) {
        currentPhase = phase.rawValue
        calDecAxisX = Double(cal?.decAxisVector.dx ?? 0)
        calDecAxisY = Double(cal?.decAxisVector.dy ?? 0)
    }

    func recordMeasurement(iteration: Int, tracker: DriftTracker) {
        let slope = tracker.currentSlope   // px/秒
        let se    = tracker.slopeStdError
        let raSlope = tracker.raSlope
        let line = [
            sessionId, sessionStart, currentPhase,
            String(calDecAxisX), String(calDecAxisY),
            String(iteration), String(format: "%.3f", tracker.elapsedTime),
            String(tracker.regression.n),
            String(format: "%.4f", slope * 60),
            String(format: "%.4f", se * 60 * 2.0),
            String(format: "%.4f", raSlope * 60),
            String(format: "%.4f", se > 0 ? slope / se : 0.0),
            String(tracker.isDriftSignificant)
        ].joined(separator: ",")
        append(line + "\n", to: summaryURL)
    }

    func recordRawFrames(iteration: Int, tracker: DriftTracker, imageSize: CGSize) {
        let wStr = String(format: "%.0f", imageSize.width)
        let hStr = String(format: "%.0f", imageSize.height)
        let iterStr = String(iteration)
        let lines: [String] = tracker.rawFrames.map { frame in
            let xPx     = String(format: "%.3f", frame.x)        // 既に px
            let yPx     = String(format: "%.3f", frame.y)        // 既に px
            let decPx   = String(format: "%.3f", frame.decDisp)
            let raPx    = String(format: "%.3f", frame.raDisp)
            let elapsed = String(format: "%.6f", frame.elapsed)
            let fields: [String] = [
                sessionId, currentPhase, iterStr,
                elapsed, xPx, yPx, decPx, raPx, wStr, hStr
            ]
            return fields.joined(separator: ",")
        }
        if !lines.isEmpty { append(lines.joined(separator: "\n") + "\n", to: rawURL) }
    }

    // saveSession は後方互換のために残すが実質不要
    func saveSession() {}

    // MARK: - ファイル追記

    private func append(_ text: String, to url: URL?) {
        guard let url, let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }
}
