import Foundation

// MARK: - Context Builder

/// Builds the system prompt by combining personality, memories, and vision context.
/// Injects the most relevant memories into every AI request.
struct ContextBuilder {
    let memoryStore: MemoryStore
    var userName: String? {
        // Try to find user's name from memories
        let facts = memoryStore.fetchMemories(category: .facts)
        return facts.first(where: { $0.content.lowercased().contains("name is") })?.content
            .components(separatedBy: "name is")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first
    }

    /// Build the complete system prompt with memories and vision context
    func buildSystemPrompt(visionDescription: String? = nil) -> String {
        let relevantMemories = memoryStore.fetchRelevantMemories(limit: 5)
        let memoryStrings = relevantMemories.map { "[\($0.category.displayName)] \($0.content)" }

        return SystemPromptTemplate.build(
            userName: userName,
            memories: memoryStrings,
            visionDescription: visionDescription
        )
    }

    /// Build a condensed context summary for memory extraction
    func buildSessionSummary(messages: [ChatMessage]) -> String {
        let userMessages = messages.filter { $0.role == .user }
        let topics = userMessages.map { $0.content }.joined(separator: "; ")
        return "Topics discussed: \(topics)"
    }
}
