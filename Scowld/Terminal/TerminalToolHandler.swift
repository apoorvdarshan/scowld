import Foundation
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "Terminal")

// MARK: - Terminal Tool Handler

enum TerminalToolHandler {

    /// Full path to claude CLI (SSH sessions don't load shell profile)
    static let claudePath = "/Users/ApoorvDarshan/.local/bin/claude"

    /// Parsed terminal task from LLM response
    struct TerminalTask: Sendable {
        let task: String
    }

    // MARK: - Task Extraction

    /// Extract [TERMINAL]{"task":"..."}[/TERMINAL] from LLM response
    static func extractTask(from response: String) -> TerminalTask? {
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

            // Try JSON parse — look for "task" or "command" key
            for jsonStr in ["{\(content)}", content] {
                if let jsonData = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    if let task = json["task"] as? String {
                        return TerminalTask(task: task)
                    }
                    // Fallback: accept "command" key too (in case LLM uses old format)
                    if let command = json["command"] as? String {
                        return TerminalTask(task: command)
                    }
                }
            }

            // Fallback: treat as raw task string
            if !content.isEmpty {
                return TerminalTask(task: content)
            }
        }

        return nil
    }

    /// Check if response contains a terminal block
    static func containsTerminalBlock(_ response: String) -> Bool {
        response.contains("[TERMINAL]") && response.contains("[/TERMINAL]")
    }

    // MARK: - Command Building

    /// Build the actual SSH command — uses claude --print with default model (Opus)
    static func buildCommand(for task: String) -> String {
        // Escape single quotes in the task for shell
        let escapedTask = task.replacingOccurrences(of: "'", with: "'\\''")
        // Fresh session each time — --continue was causing hangs loading large previous sessions
        return "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\" && \(claudePath) --print '\(escapedTask)' 2>&1"
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
        task: String,
        result: CommandResult,
        originalMessages: [ChatMessage]
    ) -> [ChatMessage] {
        var messages = originalMessages
        let truncatedOutput = truncateOutput(result.stdout)
        let statusText = result.exitCode == 0 ? "succeeded" : "failed (exit code \(result.exitCode))"

        let summaryRequest = ChatMessage(
            role: .user,
            content: """
            [System: Claude Code was asked to "\(task)" and \(statusText). Here is Claude's output:

            ```
            \(truncatedOutput)
            ```

            Please summarize this result concisely for the user. If it succeeded, tell them what was done. If it failed, explain the error and suggest what to try next. Keep it conversational and brief.]
            """
        )

        messages.append(summaryRequest)
        return messages
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
