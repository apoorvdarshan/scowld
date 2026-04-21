import Foundation

// MARK: - SSH Configuration

struct SSHConfig: Sendable {
    var host: String
    var port: Int
    var username: String
    var password: String
    var isEnabled: Bool

    static let keychainHost = "com.scowld.ssh.host"
    static let keychainPort = "com.scowld.ssh.port"
    static let keychainUsername = "com.scowld.ssh.username"
    static let keychainPassword = "com.scowld.ssh.password"
    static let enabledKey = "terminal_ssh_enabled"

    static func load() -> SSHConfig {
        let defaults = UserDefaults.standard
        return SSHConfig(
            host: KeychainManager.load(key: keychainHost) ?? "",
            port: Int(KeychainManager.load(key: keychainPort) ?? "22") ?? 22,
            username: KeychainManager.load(key: keychainUsername) ?? "",
            password: KeychainManager.load(key: keychainPassword) ?? "",
            isEnabled: defaults.bool(forKey: enabledKey)
        )
    }

    func save() {
        KeychainManager.save(key: SSHConfig.keychainHost, value: host)
        KeychainManager.save(key: SSHConfig.keychainPort, value: String(port))
        KeychainManager.save(key: SSHConfig.keychainUsername, value: username)
        KeychainManager.save(key: SSHConfig.keychainPassword, value: password)
        UserDefaults.standard.set(isEnabled, forKey: SSHConfig.enabledKey)
    }

    var isConfigured: Bool {
        !host.isEmpty && !username.isEmpty && !password.isEmpty
    }
}
