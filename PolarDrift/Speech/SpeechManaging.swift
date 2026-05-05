enum SpeechCommand {
    case start
    case skip
}

protocol SpeechManaging: AnyObject {
    var isListening: Bool { get }
    var lastCommand: SpeechCommand { get }
    var commandCount: Int { get }
    func startListening()
    func stopListening()
    func requestPermissions() async -> Bool
}
