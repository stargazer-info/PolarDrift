protocol SpeechManaging: AnyObject {
    var isListening: Bool { get }
    func startListening()
    func stopListening()
    func makeCommandStream() -> AsyncStream<SpeechCommand>
    func requestPermissions() async -> Bool
}
