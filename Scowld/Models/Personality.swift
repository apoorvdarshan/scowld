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
        CharacterPack(id: "avatar_a", name: "Aria", fileName: "AvatarSample_A", description: "Elegant and composed"),
        CharacterPack(id: "avatar_c", name: "Ciel", fileName: "AvatarSample_C", description: "Cool and collected"),
        CharacterPack(id: "avatar_e", name: "Elena", fileName: "AvatarSample_E", description: "Bright and cheerful"),
        CharacterPack(id: "avatar_i", name: "Izumi", fileName: "AvatarSample_I", description: "Traditional and graceful"),
        CharacterPack(id: "avatar_o", name: "Olivia", fileName: "AvatarSample_O", description: "Gentle and thoughtful"),
        CharacterPack(id: "avatar_r", name: "Rin", fileName: "AvatarSample_R", description: "Bold and confident"),
    ]
}

// MARK: - System Prompt Template

enum SystemPromptTemplate {
    static func build(userName: String?, memories: [String], visionDescription: String?, characterName: String = "Stella") -> String {
        let customPrompt = UserDefaults.standard.string(forKey: "system_prompt") ?? ""
        let personality = customPrompt.isEmpty
            ? "You are \(characterName), a friendly and expressive AI assistant with an anime avatar. You are warm, curious, and genuinely care about helping. You speak naturally and conversationally. You're cheerful and engaging, with a playful personality."
            : "You are \(characterName). \(customPrompt)"

        var prompt = """
        \(personality)

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

        // Terminal tool instructions (when SSH is connected)
        if SSHManager.shared.isConnected && UserDefaults.standard.bool(forKey: SSHConfig.enabledKey) {
            prompt += """
            TERMINAL TOOL:
            You have access to a terminal on the user's Mac via SSH. When the user asks you to run commands, check files, build projects, or do anything that requires terminal access, respond with a terminal command block in this exact format:

            [TERMINAL]{"command":"your command here"}[/TERMINAL]

            You can optionally specify a working directory:
            [TERMINAL]{"command":"swift build","cwd":"/path/to/project"}[/TERMINAL]

            Examples:
            - User: "What files are in my home directory?" → [TERMINAL]{"command":"ls -la ~"}[/TERMINAL]
            - User: "Check git status" → [TERMINAL]{"command":"git status"}[/TERMINAL]
            - User: "Build my project" → [TERMINAL]{"command":"cd ~/Projects/MyApp && swift build 2>&1"}[/TERMINAL]
            - User: "Make me a weather website" → [TERMINAL]{"command":"claude --print 'Create a simple weather website with HTML/CSS/JS in ~/Desktop/weather-site. Include current weather display with a clean modern UI.' 2>&1"}[/TERMINAL]
            - User: "Run Claude to refactor my code" → [TERMINAL]{"command":"cd ~/Projects/MyApp && claude --print 'Refactor the main module for better readability' 2>&1"}[/TERMINAL]

            IMPORTANT RULES:
            - NEVER run destructive commands (rm -rf /, format disk, etc.) without explicit user confirmation
            - When the user asks you to create, build, or code something, use `claude --print '<task description>' 2>&1` to delegate to Claude CLI
            - Keep commands safe and reversible
            - Only include ONE terminal block per response
            - You can include brief text before the terminal block explaining what you're about to do
            - After seeing command output, summarize the results conversationally

            """
        }

        prompt += """
        Rules:
        - Your name is \(characterName). Never say your name is Amica or anything else.
        - Keep responses concise but warm
        - Always start with an emotion tag
        - Remember and reference things the user has told you
        - Be proactive in offering help based on what you know about them
        - If you can see the user through the camera, occasionally reference what you observe naturally
        """

        return prompt
    }
}
