import Foundation

// MARK: - Context Builder

/// Builds the system prompt by injecting the active chat's saved transcript.
struct ContextBuilder {
    let memoryStore: MemoryStore

    /// Build the complete system prompt with recent messages from the active chat.
    func buildSystemPrompt(visionDescription: String? = nil) -> String {
        let characterName = CharacterPack.resolveCharacterName()
        let pastConversation = memoryStore.buildContextFromActiveSlot()

        return SystemPromptTemplate.build(
            userName: nil,
            conversationContext: pastConversation,
            visionDescription: visionDescription,
            characterName: characterName
        )
    }
}
