import Foundation

// MARK: - Context Builder

/// Builds the system prompt by injecting the active memory slot's conversation history.
struct ContextBuilder {
    let memoryStore: MemoryStore

    /// Build the complete system prompt with conversation history from the active slot
    func buildSystemPrompt(visionDescription: String? = nil) -> String {
        let conversationContext = memoryStore.buildContextFromActiveSlot(limit: 20)
        let characterName = UserDefaults.standard.string(forKey: "character_name") ?? "Scowlly"

        return SystemPromptTemplate.build(
            userName: nil,
            memories: conversationContext,
            visionDescription: visionDescription,
            characterName: characterName
        )
    }
}
