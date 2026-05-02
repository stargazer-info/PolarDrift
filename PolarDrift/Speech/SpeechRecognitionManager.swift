import Speech
import AVFoundation
import Observation

@Observable
final class SpeechRecognitionManager: NSObject {
    var isListening = false
    var onStartCommand: (() -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }

        #if os(iOS)
        let mic = await AVAudioApplication.requestRecordPermission()
        return mic
        #else
        return true
        #endif
    }

    func startListening() {
        guard !isListening else { return }
        guard speechRecognizer?.isAvailable == true else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Validate format before installing tap
        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("Invalid audio format: sampleRate=\(format.sampleRate), channelCount=\(format.channelCount)")
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let transcript = result.bestTranscription.formattedString
            if transcript.contains("スタート") || transcript.contains("start") || transcript.contains("START") {
                Task { @MainActor [weak self] in
                    self?.onStartCommand?()
                    // コマンド検出後にリセット（連続検出を防ぐ）
                    self?.restartRecognition()
                }
            }
        }

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    private func restartRecognition() {
        stopListening()
        // 短い遅延後に再開（同じ発話の重複検出を防ぐ）
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            startListening()
        }
    }
}
