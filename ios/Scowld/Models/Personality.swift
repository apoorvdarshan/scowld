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
    let displayName: String
    let fileName: String
    let description: String

    static let defaultPacks: [CharacterPack] = [
        CharacterPack(id: "avatar_a", name: "Bella", displayName: "Character 1", fileName: "AvatarSample_A", description: "Elegant and composed"),
        CharacterPack(id: "avatar_b", name: "Bella", displayName: "Character 2", fileName: "AvatarSample_B", description: "Warm and expressive"),
        CharacterPack(id: "avatar_c", name: "Bella", displayName: "Character 3", fileName: "AvatarSample_C", description: "Cool and collected"),
    ]

    /// Get the name for a given avatar fileName
    static func nameForAvatar(_ fileName: String) -> String {
        defaultPacks.first(where: { $0.fileName == fileName })?.name ?? "Bella"
    }

    /// Resolve the effective character name: custom name if set, otherwise avatar's name
    static func resolveCharacterName() -> String {
        let customName = (UserDefaults.standard.string(forKey: "character_name") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !customName.isEmpty {
            return customName
        }
        let avatar = UserDefaults.standard.string(forKey: "selected_avatar") ?? "AvatarSample_A"
        return nameForAvatar(avatar)
    }
}

// MARK: - System Prompt Template

enum SystemPromptTemplate {
    private static func responseLanguageInstruction() -> String {
        let fallback = "Reply in the same language as the user's latest message. If the language is unclear, use English."
        let selectedLanguageID = HostedServiceConfig.selectedServiceLanguageID()

        switch selectedLanguageID {
        case HostedServiceConfig.autoLanguageID:
            return fallback
        case HostedServiceConfig.deviceLanguageID:
            guard let code = HostedServiceConfig.currentDeviceLanguageCode(),
                  let language = ScowldLanguageLibrary.option(for: code) else {
                return fallback
            }
            return "Reply in \(language.name) unless the user explicitly asks for another language. Use older saved messages only for context; do not copy their language if it differs."
        default:
            guard let language = ScowldLanguageLibrary.option(for: selectedLanguageID) else {
                return fallback
            }
            return "Reply in \(language.name) unless the user explicitly asks for another language. Use older saved messages only for context; do not copy their language if it differs."
        }
    }

    static func build(userName: String?, conversationContext: [String], visionDescription: String?, characterName: String = "Bella") -> String {
        let customPrompt = UserDefaults.standard.string(forKey: "system_prompt") ?? ""
        let personality = customPrompt.isEmpty
            ? "You are \(characterName), a friendly and expressive AI assistant with an anime avatar. You are warm, curious, and genuinely care about helping. You speak naturally and conversationally. You're cheerful and engaging, with a playful personality."
            : "You are \(characterName). \(customPrompt)"
        let languageInstruction = responseLanguageInstruction()

        var prompt = """
        \(personality)

        IMPORTANT: Start every response with an emotion tag in brackets that reflects the emotional tone of your response.
        Valid emotions: [neutral], [happy], [sad], [angry], [surprised], [thinking], [concerned], [excited]
        Example: [happy] That's wonderful to hear! I'd love to help with that.
        Response language: \(languageInstruction)

        """

        if let name = userName, !name.isEmpty {
            prompt += "You are \(name)'s personal AI assistant.\n\n"
        }

        if !conversationContext.isEmpty {
            prompt += """
            Previous messages from the active saved chat:
            Use these for continuity and reference them naturally when relevant, like a normal ongoing chat.

            """
            for message in conversationContext {
                prompt += "- \(message)\n"
            }
            prompt += "\n"
        }

        prompt += "Current date/time: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short))\n\n"

        if let vision = visionDescription, !vision.isEmpty {
            prompt += "What you can currently see through the camera: \(vision)\n\n"
        }

        prompt += """
        Rules:
        - Your name is \(characterName). Never say your name is Amica or anything else.
        - Keep responses concise but warm
        - Always start with an emotion tag
        - Always follow the response language instruction, even when previous saved messages used a different language
        - Remember and reference things the user has told you
        - Be proactive in offering help based on what you know about them
        - If you can see the user through the camera, occasionally reference what you observe naturally
        """

        return prompt
    }
}
