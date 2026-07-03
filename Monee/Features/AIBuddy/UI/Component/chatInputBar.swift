
import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    var placeholder: String = "Ask Buntel anything"
    var onSend: () -> Void
    var onMicTap: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .lineLimit(1...4)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit(sendIfPossible)

            if !canSend {
                Button(action: onMicTap) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dictate message")
            }

            Button(action: sendIfPossible) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }

    private func sendIfPossible() {
        guard canSend else { return }
        onSend()
    }
}

#Preview {
    ChatInputBar(text: .constant(""), onSend: {}, onMicTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}
