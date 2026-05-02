import SwiftUI

struct VoiceStatusBadge: View {
    let isListening: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isListening ? "mic.fill" : "mic.slash.fill")
                .foregroundStyle(isListening ? Color.green : Color.gray)
                .symbolEffect(.pulse, isActive: isListening)
            Text(isListening ? "「スタート」と言ってください" : "マイク無効")
                .font(.instructionBody)
                .foregroundStyle(isListening ? .white : .gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.astronomyCard, in: Capsule())
    }
}
