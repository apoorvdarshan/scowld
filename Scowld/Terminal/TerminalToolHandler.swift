import Foundation
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "Terminal")

// MARK: - Terminal Tool Handler

enum TerminalToolHandler {

    /// Parsed terminal command from LLM response
    struct TerminalCommand: Sendable {
        let command: String
        let workingDirectory: String?
    }

    // MARK: - Command Extraction

    /// Extract [TERMINAL]{"command":"..."}[/TERMINAL] from LLM response
    static func extractCommand(from response: String) -> TerminalCommand? {
        // Try standard format first
        let patterns = [
            #"\[TERMINAL\]\s*\{(.*?)\}\s*\[/TERMINAL\]"#,
            #"\[TERMINAL\]\s*(.*?)\s*\[/TERMINAL\]"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
                  let contentRange = Range(match.range(at: 1), in: response) else {
                continue
            }

            let content = String(response[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Try JSON parse
            if let jsonData = "{\(content)}".data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let command = json["command"] as? String {
                return TerminalCommand(
                    command: command,
                    workingDirectory: json["cwd"] as? String
                )
            }

            // Already valid JSON with braces
            if let jsonData = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let command = json["command"] as? String {
                return TerminalCommand(
                    command: command,
                    workingDirectory: json["cwd"] as? String
                )
            }

            // Fallback: treat as raw command string
            if !content.isEmpty {
                return TerminalCommand(command: content, workingDirectory: nil)
            }
        }

        return nil
    }

    /// Check if response contains a terminal command block
    static func containsTerminalBlock(_ response: String) -> Bool {
        response.contains("[TERMINAL]") && response.contains("[/TERMINAL]")
    }

    // MARK: - Safety Check

    /// Blocklist of dangerous commands
    private static let blockedPatterns: [String] = [
        #"rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?/"#,       // rm -rf /
        #"rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?~"#,        // rm -rf ~
        #"mkfs\b"#,                                    // format filesystem
        #"dd\s+if="#,                                   // dd disk destroyer
        #":\(\)\s*\{\s*:\|:\s*&\s*\}\s*;"#,           // fork bomb
        #"\|\s*sh\b"#,                                 // pipe to shell
        #"\|\s*bash\b"#,                               // pipe to bash
        #"curl\s.*\|\s*(sh|bash)"#,                    // curl | sh
        #"wget\s.*\|\s*(sh|bash)"#,                    // wget | sh
        #"chmod\s+777\s+/"#,                           // chmod 777 /
        #"shutdown"#,                                   // system shutdown
        #"reboot"#,                                     // system reboot
        #"init\s+[06]"#,                               // init shutdown/reboot
        #">\s*/dev/sd"#,                               // write to disk device
        #"mv\s+/\s"#,                                  // mv / somewhere
    ]

    static func isCommandSafe(_ command: String) -> Bool {
        for pattern in blockedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil {
                logger.warning("[Terminal] Blocked unsafe command: \(command)")
                return false
            }
        }
        return true
    }

    // MARK: - Output Processing

    /// Truncate output to fit within LLM context limits
    static func truncateOutput(_ output: String, maxChars: Int = 4000) -> String {
        guard output.count > maxChars else { return output }
        let half = maxChars / 2
        let prefix = String(output.prefix(half))
        let suffix = String(output.suffix(half))
        return "\(prefix)\n\n... [output truncated, \(output.count - maxChars) chars omitted] ...\n\n\(suffix)"
    }

    /// Build messages for LLM to summarize command output
    static func buildSummaryMessages(
        command: String,
        result: CommandResult,
        originalMessages: [ChatMessage]
    ) -> [ChatMessage] {
        var messages = originalMessages
        let truncatedOutput = truncateOutput(result.stdout)
        let statusText = result.exitCode == 0 ? "succeeded" : "failed (exit code \(result.exitCode))"

        let summaryRequest = ChatMessage(
            role: .user,
            content: """
            [System: The terminal command `\(command)` \(statusText). Here is the output:

            ```
            \(truncatedOutput)
            ```

            Please summarize this result concisely for the user. If it succeeded, tell them what happened. If it failed, explain the error and suggest fixes. Keep it conversational.]
            """
        )

        messages.append(summaryRequest)
        return messages
    }

    /// Check if command is a Claude CLI invocation (needs longer timeout)
    static func isClaudeCommand(_ command: String) -> Bool {
        let patterns = [
            #"\bclaude\b"#,
            #"\bclaude\s+--print\b"#,
            #"\bclaude\s+-p\b"#,
        ]
        return patterns.contains { pattern in
            (try? NSRegularExpression(pattern: pattern))?.firstMatch(
                in: command, range: NSRange(command.startIndex..., in: command)
            ) != nil
        }
    }

    /// Wrap a Claude CLI command for non-interactive execution
    static func wrapClaudeCommand(_ command: String) -> String {
        // If user just said "claude <task>", wrap with --print for non-interactive mode
        if command.hasPrefix("claude ") && !command.contains("--print") && !command.contains("-p ") {
            let task = String(command.dropFirst(7))
            return "claude --print \(task) 2>&1"
        }
        return "\(command) 2>&1"
    }

    /// Extract the text portion (before/after terminal block) from LLM response
    static func extractTextPortion(from response: String) -> String {
        let pattern = #"\[TERMINAL\].*?\[/TERMINAL\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return response
        }
        return regex.stringByReplacingMatches(
            in: response,
            range: NSRange(response.startIndex..., in: response),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
