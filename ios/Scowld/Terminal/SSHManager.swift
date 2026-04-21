import Foundation
import Citadel
import NIOCore
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "SSH")

// MARK: - SSH Manager

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int
}

enum SSHError: Error, LocalizedError {
    case notConnected
    case notConfigured
    case notEnabled
    case commandTimeout
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "SSH not connected"
        case .notConfigured: "SSH not configured"
        case .notEnabled: "Terminal access is disabled"
        case .commandTimeout: "Command timed out"
        case .connectionFailed(let msg): "Connection failed: \(msg)"
        }
    }
}

enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

@Observable
final class SSHManager {
    static let shared = SSHManager()

    var connectionState: ConnectionState = .disconnected

    private var client: SSHClient?

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    func connect() async {
        let config = SSHConfig.load()
        guard config.isConfigured else {
            connectionState = .error("SSH not configured")
            return
        }

        connectionState = .connecting
        logger.info("[SSH] Connecting to \(config.host):\(config.port)")

        do {
            let host = config.host
            let port = config.port
            let username = config.username
            let password = config.password

            let newClient = try await Task.detached {
                try await SSHClient.connect(
                    host: host,
                    port: port,
                    authenticationMethod: .passwordBased(username: username, password: password),
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never
                )
            }.value

            self.client = newClient
            connectionState = .connected
            logger.info("[SSH] Connected successfully")
        } catch {
            connectionState = .error(error.localizedDescription)
            logger.error("[SSH] Connection failed: \(error.localizedDescription)")
        }
    }

    func disconnect() async {
        if let client = self.client {
            try? await Task.detached {
                try await client.close()
            }.value
        }
        self.client = nil
        connectionState = .disconnected
        logger.info("[SSH] Disconnected")
    }

    func execute(command: String, timeout: TimeInterval = 30) async throws -> CommandResult {
        guard let client = self.client else {
            // Try to reconnect once
            await connect()
            guard let client = self.client else {
                throw SSHError.notConnected
            }
            return try await executeOnClient(client, command: command, timeout: timeout)
        }
        return try await executeOnClient(client, command: command, timeout: timeout)
    }

    private func executeOnClient(_ client: SSHClient, command: String, timeout: TimeInterval) async throws -> CommandResult {
        logger.info("[SSH] Executing: \(command)")

        // Wrap command to capture both stdout and stderr, and exit code
        let wrappedCommand = "bash -c '\(command.replacingOccurrences(of: "'", with: "'\\''"))' 2>&1; echo \"__EXIT_CODE:$?\""

        let result: CommandResult = try await Task.detached {
            let buffer = try await client.executeCommand(wrappedCommand)
            let rawOutput = String(buffer: buffer)

            // Parse exit code from output
            var lines = rawOutput.components(separatedBy: "\n")
            var exitCode = 0
            if let lastLine = lines.last(where: { $0.hasPrefix("__EXIT_CODE:") }) {
                exitCode = Int(lastLine.replacingOccurrences(of: "__EXIT_CODE:", with: "")) ?? 0
                lines.removeAll { $0.hasPrefix("__EXIT_CODE:") }
            }
            let output = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            return CommandResult(stdout: output, stderr: "", exitCode: exitCode)
        }.value

        logger.info("[SSH] Command finished with exit code \(result.exitCode), output length: \(result.stdout.count)")
        return result
    }

    /// Execute a long-running command like `claude` with extended timeout
    func executeLongRunning(command: String) async throws -> CommandResult {
        try await execute(command: command, timeout: 300) // 5 minute timeout for claude CLI
    }
}
