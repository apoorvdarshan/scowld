# Contributing to Scowld

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork the repo
2. Clone your fork
   ```bash
   git clone https://github.com/YOUR_USERNAME/scowld.git
   ```
3. Create a branch
   ```bash
   git checkout -b feature/your-feature-name
   ```
4. Make your changes
5. Test on a real iPhone (simulator won't work for camera/mic features)
6. Push and open a PR

## Project Structure

```
Scowld/
├── AI/                 # LLM providers (Gemini, OpenAI, Claude, Ollama, etc.)
├── Core/               # VoiceManager, SpeechManager, KeychainManager
├── Memory/             # MemoryStore, MemoryExtractor, ContextBuilder
├── Models/             # APIConfig, Personality
├── Views/              # HomeView, SettingsView, MemoryView, ChatView
├── Resources/
│   └── amica.bundle/   # Amica web frontend (Three.js + VRM avatar)
└── ScowldApp.swift     # App entry point
```

## Guidelines

- **No API keys in code** — Use iOS Keychain via `KeychainManager`
- **Test on device** — Camera, mic, and TTS require a real iPhone
- **Keep it simple** — Don't over-engineer. Minimal changes for the task at hand
- **Swift conventions** — Use SwiftUI, `@Observable`, async/await where appropriate

## Areas for Contribution

- New LLM provider integrations
- Better TTS-done detection (current approach uses JS audio event debouncing)
- Local notifications / reminders system
- New VRM character models
- Improved memory extraction prompts
- UI/UX improvements

## Reporting Issues

Open an issue on GitHub with:
- What you expected
- What happened
- Screenshots if applicable
- Device model and iOS version

## Contact

**Apoorv Darshan** — ad13dtu@gmail.com
