import SwiftUI

struct VoiceStatusBadge: View {
    let isListening: Bool
    var expectedCommand: String? = "「スタート」"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isListening ? "mic.fill" : "mic.slash.fill")
                .foregroundStyle(isListening ? Color.green : Color.gray)
                .symbolEffect(.pulse, isActive: isListening)
            Text(displayText)
                .font(.instructionBody)
                .foregroundStyle(isListening ? .white : .gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.astronomyCard, in: Capsule())
    }

    private var displayText: String {
        if !isListening { return "マイク無効" }
        guard let cmd = expectedCommand else { return "音声待機中" }
        return "\(cmd) と言ってください"
    }
}
