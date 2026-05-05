import Speech
import AVFoundation
import Observation

@Observable
final class SpeechRecognitionManager: NSObject, SpeechManaging {
    private(set) var isListening = false
    private(set) var lastCommand: SpeechCommand = .start
    private(set) var commandCount: Int = 0

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
        return await AVAudioApplication.requestRecordPermission()
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

        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let transcript = result.bestTranscription.formattedString
            if transcript.contains("スタート") || transcript.contains("start") || transcript.contains("START") {
                Task { @MainActor [weak self] in
                    self?.lastCommand = .start
                    self?.commandCount += 1
                    self?.restartRecognition()
                }
            }
            if transcript.contains("スキップ") || transcript.contains("skip") || transcript.contains("SKIP") {
                Task { @MainActor [weak self] in
                    self?.lastCommand = .skip
                    self?.commandCount += 1
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
