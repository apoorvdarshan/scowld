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
        CharacterPack(id: "avatar_b", name: "Bella", fileName: "AvatarSample_B", description: "Warm and expressive"),
        CharacterPack(id: "avatar_c", name: "Ciel", fileName: "AvatarSample_C", description: "Cool and collected"),
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
            You have access to Claude Code CLI on the user's Mac via SSH. When the user asks you to do anything that requires their computer — coding, building, checking files, git operations, creating projects, or ANY task — you delegate it to Claude Code by responding with a terminal command block.

            FORMAT (use this exact format):
            [TERMINAL]{"task":"describe what to do in detail"}[/TERMINAL]

            You ONLY provide the task description. The system automatically runs `claude --print '<your task>'` on the Mac. Claude Code handles everything — file creation, builds, git, installations, etc.

            Examples:
            - User: "What files are in my home directory?" → [TERMINAL]{"task":"List all files and folders in the home directory with details"}[/TERMINAL]
            - User: "Check git status of Scowld" → [TERMINAL]{"task":"Check the git status of the Scowld project in ~/Scowld"}[/TERMINAL]
            - User: "Build my project" → [TERMINAL]{"task":"Build the Xcode project in ~/Scowld using xcodebuild"}[/TERMINAL]
            - User: "Make me a weather website" → [TERMINAL]{"task":"Create a beautiful weather website with HTML/CSS/JS. Include current weather display with a clean modern UI, responsive design, and use a free weather API. After creating it, open the index.html in the browser."}[/TERMINAL]
            - User: "Refactor the networking code" → [TERMINAL]{"task":"Refactor the networking/API code in ~/Scowld for better readability and error handling"}[/TERMINAL]
            - User: "Install python" → [TERMINAL]{"task":"Install Python using Homebrew if not already installed"}[/TERMINAL]

            RULES:
            - ALWAYS use the [TERMINAL] block for ANY task that involves the user's computer
            - Describe the task clearly and in detail — Claude Code will figure out the commands and create folders as needed
            - NEVER specify a directory like ~/Desktop — let Claude Code decide where to put things
            - Only include ONE terminal block per response
            - You can include a brief sentence before the block explaining what you're about to do
            - After seeing the result, summarize it conversationally
            - For web projects, include "open the index.html in the browser after creating it"
            - Claude Code keeps session context with --continue, so follow-up tasks remember previous work

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
