import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isGenerating: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                assistantAvatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                if message.role == .assistant && !message.content.isEmpty {
                    timestampView
                }
            }

            if message.role == .user {
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
            }

            if message.role == .user {
                userAvatar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var bubbleContent: some View {
        if message.content.isEmpty && isGenerating {
            TypingIndicator()
        } else {
            Text(message.content)
                .font(.body)
                .foregroundColor(message.role == .user ? .white : .primary)
                .textSelection(.enabled)
        }
    }

    private var bubbleBackground: Color {
        message.role == .user ? .blue : Color(.systemGray6)
    }

    private var assistantAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 32, height: 32)
            .overlay(
                Text("J")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    private var userAvatar: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            )
    }

    private var timestampView: some View {
        Text(message.timestamp, style: .time)
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotCount = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotCount == index ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: dotCount
                    )
            }
        }
        .onAppear {
            withAnimation {
                dotCount = 1
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        MessageBubble(
            message: Message(role: .user, content: "Hello, how are you?"),
            isGenerating: false
        )

        MessageBubble(
            message: Message(role: .assistant, content: "I'm doing well, thank you for asking! How can I help you today?"),
            isGenerating: false
        )

        MessageBubble(
            message: Message(role: .assistant, content: ""),
            isGenerating: true
        )
    }
}
