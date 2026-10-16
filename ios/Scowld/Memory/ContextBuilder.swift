import Foundation

// MARK: - Context Builder

/// Builds the live session instructions by injecting the active chat's saved transcript.
struct ContextBuilder {
    let memoryStore: MemoryStore

    /// The instructions for a live voice session, with recent messages from the active chat.
    func buildSystemPrompt(cameraAvailable: Bool) -> String {
        SystemPromptTemplate.build(
            conversationContext: memoryStore.buildContextFromActiveSlot(),
            characterName: CharacterPack.resolveCharacterName(),
            cameraAvailable: cameraAvailable
        )
    }
}
