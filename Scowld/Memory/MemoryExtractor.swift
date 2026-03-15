import Foundation

// MARK: - Memory Extractor

/// After each AI response, the LLM reviews the conversation and updates
/// the memory log for the active slot — distilling key facts to remember.
@Observable
final class MemoryExtractor {
    var isExtracting = false

    /// Update the active slot's memory log based on recent conversation
    func updateMemoryLog(
        userMessage: String,
        aiResponse: String,
        currentLog: String,
        using provider: (any LLMProvider)?,
        store: MemoryStore
    ) async {
        guard let provider else { return }
        guard !isExtracting else { return }
        isExtracting = true
        defer { isExtracting = false }

        let prompt = """
        You are a memory system. Your job is to maintain a concise memory log about the user.

        CURRENT MEMORY LOG:
        \(currentLog.isEmpty ? "(empty — first conversation)" : currentLog)

        LATEST EXCHANGE:
        User: \(userMessage)
        Assistant: \(aiResponse)

        Update the memory log by:
        - Adding any NEW facts about the user (name, preferences, interests, what they're working on, etc.)
        - Keeping existing facts that are still relevant
        - Removing outdated facts if contradicted
        - Keep it concise — bullet points, max 20 lines
        - Only include facts about the USER, not about the conversation itself

        Return ONLY the updated memory log, nothing else. No explanations.
        If there's nothing new worth remembering, return the current log unchanged.
        """

        do {
            let updatedLog = try await provider.generate(
                messages: [ChatMessage(role: .user, content: prompt)],
                systemPrompt: "You are a memory system. Return only the updated memory log as bullet points. No other text."
            )

            let cleaned = updatedLog.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                store.updateMemoryLog(cleaned)
            }
        } catch {
            print("Memory log update failed: \(error.localizedDescription)")
        }
    }
}
