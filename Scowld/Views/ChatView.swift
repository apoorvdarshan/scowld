import SwiftUI

// MARK: - Chat View

/// Displays conversation messages as chat bubbles.
/// Appears at the bottom of the home screen below the character.
struct ChatView: View {
    let messages: [ChatMessage]
    @Binding var inputText: String
    var onSend: () -> Void
    var isGenerating: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isGenerating {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("typing")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        if let lastMessage = messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isGenerating) {
                    if isGenerating {
                        withAnimation {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            // Text input bar
            HStack(spacing: 12) {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray6))
                    )
                    .onSubmit {
                        if !inputText.isEmpty { onSend() }
                    }

                Button {
                    if !inputText.isEmpty { onSend() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.isEmpty ? .gray : .orange)
                }
                .disabled(inputText.isEmpty || isGenerating)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(isUser ? Color.orange : Color(.systemGray5))
                    )
                    .foregroundStyle(isUser ? .white : .primary)

                if let emotion = message.emotion, !isUser {
                    Text(emotion.emoji)
                        .font(.caption2)
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.orange.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .offset(y: animationPhase == index ? -4 : 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemGray5))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                    animationPhase = 2
                }
            }
        }
    }
}
