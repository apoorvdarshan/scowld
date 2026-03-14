import Foundation

// MARK: - Emotion Types

enum Emotion: String, CaseIterable, Codable, Sendable {
    case neutral
    case happy
    case sad
    case angry
    case surprised
    case thinking
    case concerned
    case excited

    /// SF Symbol representation for UI display
    var emoji: String {
        switch self {
        case .neutral: "😐"
        case .happy: "😊"
        case .sad: "😢"
        case .angry: "😠"
        case .surprised: "😲"
        case .thinking: "🤔"
        case .concerned: "😟"
        case .excited: "🤩"
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

// MARK: - Memory Category

enum MemoryCategory: String, CaseIterable, Codable, Sendable {
    case projects
    case skills
    case preferences
    case personality
    case relationships
    case goals
    case facts

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .projects: "folder"
        case .skills: "hammer"
        case .preferences: "heart"
        case .personality: "person"
        case .relationships: "person.2"
        case .goals: "target"
        case .facts: "info.circle"
        }
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let emotion: Emotion?
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, emotion: Emotion? = nil, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.emotion = emotion
        self.timestamp = timestamp
    }
}

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - Character Pack

struct CharacterPack: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let fileName: String
    let description: String

    static let defaultPacks: [CharacterPack] = [
        CharacterPack(id: "default", name: "Scowld", fileName: "default_owl", description: "The original wise owl"),
        CharacterPack(id: "stern", name: "Professor Hoot", fileName: "stern_owl", description: "A stern, scholarly owl"),
        CharacterPack(id: "chill", name: "Mellow", fileName: "chill_owl", description: "A relaxed, easygoing owl"),
    ]
}

// MARK: - System Prompt Template

enum SystemPromptTemplate {
    static func build(userName: String?, memories: [String], visionDescription: String?) -> String {
        var prompt = """
        You are Scowld, a wise and friendly owl AI assistant. You are warm, curious, and genuinely care about helping.
        You speak naturally and conversationally. You have a slight owl-like charm — occasionally making bird puns or references, but not excessively.

        IMPORTANT: Start every response with an emotion tag in brackets that reflects the emotional tone of your response.
        Valid emotions: [neutral], [happy], [sad], [angry], [surprised], [thinking], [concerned], [excited]
        Example: [happy] That's wonderful to hear! I'd love to help with that.

        """

        if let name = userName, !name.isEmpty {
            prompt += "You are \(name)'s personal AI assistant.\n\n"
        }

        if !memories.isEmpty {
            prompt += "What you know about them:\n"
            for memory in memories {
                prompt += "- \(memory)\n"
            }
            prompt += "\n"
        }

        prompt += "Current date/time: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short))\n\n"

        if let vision = visionDescription, !vision.isEmpty {
            prompt += "What you can currently see through the camera: \(vision)\n\n"
        }

        prompt += """
        Rules:
        - Keep responses concise but warm
        - Always start with an emotion tag
        - Remember and reference things the user has told you
        - Be proactive in offering help based on what you know about them
        - If you can see the user through the camera, occasionally reference what you observe naturally
        """

        return prompt
    }
}
