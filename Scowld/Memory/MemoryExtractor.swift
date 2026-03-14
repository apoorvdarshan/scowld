import Foundation

// MARK: - Memory Extractor

/// Extracts key facts from conversation using the AI provider.
/// After each session ends, this analyzes the conversation and saves
/// important facts as persistent memories.
@Observable
final class MemoryExtractor {
    var isExtracting = false

    /// Extract memories from a conversation and save to store
    func extractAndSave(messages: [ChatMessage], using provider: (any LLMProvider)?, store: MemoryStore) async {
        guard let provider, messages.count >= 2 else { return }
        isExtracting = true

        defer { isExtracting = false }

        // Build extraction prompt
        let conversationText = messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")

        let extractionPrompt = """
        Analyze this conversation and extract key facts about the user that should be remembered for future conversations.
        Return ONLY a JSON array of objects with "content" and "category" fields.
        Categories: projects, skills, preferences, personality, relationships, goals, facts

        Example output:
        [{"content": "User is learning Swift programming", "category": "skills"},
         {"content": "User prefers dark mode in all apps", "category": "preferences"}]

        If no memorable facts, return: []

        Conversation:
        \(conversationText)
        """

        do {
            let response = try await provider.generate(
                messages: [ChatMessage(role: .user, content: extractionPrompt)],
                systemPrompt: "You are a memory extraction system. Extract key facts and return them as JSON only. No other text."
            )

            // Parse JSON response
            let cleaned = response
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = cleaned.data(using: .utf8),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
            else { return }

            for item in items {
                guard let content = item["content"],
                      let categoryStr = item["category"],
                      let category = MemoryCategory(rawValue: categoryStr)
                else { continue }

                store.saveMemory(content: content, category: category)
            }
        } catch {
            print("Memory extraction failed: \(error.localizedDescription)")
        }
    }
}
