import Foundation

// MARK: - Context Builder

/// Builds the system prompt by injecting the active memory slot's log.
struct ContextBuilder {
    let memoryStore: MemoryStore

    /// Build the complete system prompt with memory log from the active slot
    func buildSystemPrompt(visionDescription: String? = nil) -> String {
        let memoryLog = memoryStore.getActiveMemoryLog()
        let characterName = UserDefaults.standard.string(forKey: "character_name") ?? "Stella"

        // Split memory log into lines for the prompt
        let memories = memoryLog.isEmpty ? [] : memoryLog.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return SystemPromptTemplate.build(
            userName: nil,
            memories: memories,
            visionDescription: visionDescription,
            characterName: characterName
        )
    }
}
