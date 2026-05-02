import Speech
import AVFoundation
import Observation

enum SpeechCommand {
    case start
}

@Observable
final class SpeechRecognitionManager: NSObject, SpeechManaging {
    private(set) var isListening = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var commandContinuation: AsyncStream<SpeechCommand>.Continuation?

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return true
        #endif
    }

    /// 呼び出すたびに前のストリームを終了し新しいストリームを返す
    func makeCommandStream() -> AsyncStream<SpeechCommand> {
        commandContinuation?.finish()
        return AsyncStream { [weak self] continuation in
            self?.commandContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.commandContinuation = nil
            }
        }
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

        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let transcript = result.bestTranscription.formattedString
            if transcript.contains("スタート") || transcript.contains("start") || transcript.contains("START") {
                Task { @MainActor [weak self] in
                    self?.commandContinuation?.yield(.start)
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
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            startListening()
        }
    }
}
