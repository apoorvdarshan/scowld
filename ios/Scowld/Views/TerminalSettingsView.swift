import SwiftUI

// MARK: - Terminal Settings View

struct TerminalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isEnabled: Bool = false
    @State private var showPassword: Bool = false
    @State private var testStatus: TestStatus = .idle
    @State private var hasChanges: Bool = false

    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        List {
            // MARK: - Enable Toggle
            Section {
                Toggle("Enable Terminal Access", isOn: $isEnabled)
                    .tint(.amicaBlue)
                    .onChange(of: isEnabled) { hasChanges = true }
            } footer: {
                Text("When enabled, your AI companion can execute terminal commands on your Mac via SSH.")
            }

            // MARK: - Connection Settings
            Section {
                TextField("Host (IP or hostname)", text: $host)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textContentType(.URL)
                    .onChange(of: host) { hasChanges = true }

                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                    .onChange(of: port) { hasChanges = true }

                TextField("Username", text: $username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textContentType(.username)
                    .onChange(of: username) { hasChanges = true }

                HStack {
                    if showPassword {
                        TextField("Password", text: $password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                    }
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: password) { hasChanges = true }
            } header: {
                Label("SSH Connection", systemImage: "terminal")
            } footer: {
                Text("Credentials are stored securely in iOS Keychain. Enable Remote Login on your Mac in System Settings > General > Sharing.")
            }

            // MARK: - Test Connection
            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")

                        Spacer()

                        switch testStatus {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                                .controlSize(.small)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(host.isEmpty || username.isEmpty || password.isEmpty)

                if case .failed(let error) = testStatus {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if case .success = testStatus {
                    Text("Connected successfully!")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // MARK: - Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How it works")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("When enabled, you can ask your AI to run commands on your Mac. For example:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\"Check git status of my project\"")
                        Text("\"Build my project\"")
                        Text("\"Run Claude to make a weather website\"")
                        Text("\"List files in my home directory\"")
                    }
                    .font(.caption)
                    .foregroundStyle(.amicaBlue)
                    .italic()
                }
            } header: {
                Label("Usage", systemImage: "questionmark.circle")
            }

            // MARK: - Safety
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Destructive commands are blocked", systemImage: "shield.checkered")
                        .font(.subheadline)
                    Text("Commands like rm -rf /, format disk, and fork bombs are automatically prevented.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Safety", systemImage: "lock.shield")
            }
        }
        .navigationTitle("Terminal (SSH)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveSettings()
                    dismiss()
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                        .foregroundStyle(hasChanges ? .amicaBlue : .secondary)
                }
                .disabled(!hasChanges)
            }
        }
        .onAppear { loadSettings() }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let config = SSHConfig.load()
        host = config.host
        port = String(config.port)
        username = config.username
        password = config.password
        isEnabled = config.isEnabled

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hasChanges = false
        }
    }

    private func saveSettings() {
        let config = SSHConfig(
            host: host,
            port: Int(port) ?? 22,
            username: username,
            password: password,
            isEnabled: isEnabled
        )
        config.save()
        hasChanges = false

        // Reconnect if enabled and configured
        if isEnabled && config.isConfigured {
            Task {
                await SSHManager.shared.connect()
            }
        } else {
            Task {
                await SSHManager.shared.disconnect()
            }
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        testStatus = .testing

        Task {
            // Save current settings temporarily for test
            let config = SSHConfig(
                host: host,
                port: Int(port) ?? 22,
                username: username,
                password: password,
                isEnabled: true
            )
            config.save()

            await SSHManager.shared.disconnect()
            await SSHManager.shared.connect()

            if SSHManager.shared.isConnected {
                // Run a quick test command
                do {
                    let result = try await SSHManager.shared.execute(command: "echo 'Scowld connected'")
                    if result.stdout.contains("Scowld connected") {
                        testStatus = .success
                    } else {
                        testStatus = .failed("Connected but command failed")
                    }
                } catch {
                    testStatus = .failed(error.localizedDescription)
                }
            } else if case .error(let msg) = SSHManager.shared.connectionState {
                testStatus = .failed(msg)
            } else {
                testStatus = .failed("Could not connect")
            }
        }
    }
}
