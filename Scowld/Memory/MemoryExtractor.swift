import Foundation

// MARK: - Memory Extractor (Legacy — no longer used)

/// Previously extracted facts from conversations using the AI provider.
/// Now replaced by slot-based memory where full chat history is preserved.
@Observable
final class MemoryExtractor {
    var isExtracting = false
}
