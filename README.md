# Scowld

An open-source AI companion app for iOS with a 3D anime avatar, hands-free voice chat, vision, and persistent memory.

## Features

- **3D Anime Avatar** — VRM character rendered via Three.js with lip sync, idle animations, and expressions
- **Hands-Free Voice Chat** — Always-on speech recognition with auto-send on silence, live captions for both user and AI
- **Vision** — Front camera feeds to the AI so it can see what you see (no preview shown, privacy-first)
- **Multi-Provider LLM** — Gemini, OpenAI, Claude, Ollama, OpenRouter, xAI, Together AI
- **Text-to-Speech** — ElevenLabs, OpenAI TTS, or native iOS
- **Persistent Memory** — AI extracts and remembers key details across conversations using memory slots
- **On-Device Speech** — Apple Speech framework, no cloud STT needed

## Architecture

```
Native iOS (Swift/SwiftUI)
├── VoiceManager        — Always-on speech recognition + silence detection
├── MemoryStore         — CoreData persistence for chat history + memory logs
├── MemoryExtractor     — LLM-powered memory extraction from conversations
├── LLM Providers       — Gemini, OpenAI, Claude, Ollama, OpenRouter, xAI, Together
└── HomeView            — Main UI with WKWebView bridge

WKWebView (Amica Frontend)
├── Three.js + three-vrm — 3D avatar rendering
├── VRMA Animations      — Idle, gesture, and lip sync
├── AudioContext          — TTS audio playback
└── Native Bridge         — JS <-> Swift message passing
```

## Requirements

- iOS 17.0+
- Xcode 16+
- An API key for at least one LLM provider

## Setup

1. Clone the repo
   ```bash
   git clone https://github.com/apoorvdarshan/scowld.git
   cd scowld
   ```

2. Open in Xcode
   ```bash
   open Scowld.xcodeproj
   ```

3. Build and run on your iPhone

4. In Settings, select your AI provider and enter your API key (stored in iOS Keychain)

## How It Works

### Voice Mode
Tap the waveform icon to enable hands-free mode. Speak naturally — the app auto-sends after 0.8s of silence. While the AI responds, the mic pauses and resumes automatically after TTS finishes. Live captions show what you're saying and what the AI says.

### Vision
The front camera is enabled by default (hidden, no preview). The AI can see through your camera when you send messages. Toggle with the eye icon in the bottom bar.

### Memory
The AI automatically extracts important details from conversations and stores them in memory slots. These persist across sessions and are injected into the system prompt for context-aware responses.

## Tech Stack

- **Swift / SwiftUI** — Native iOS app
- **WKWebView** — Hosts Amica's Three.js frontend for 3D avatar
- **CoreData** — Chat history and memory persistence
- **Apple Speech** — On-device speech recognition
- **AVAudioEngine** — Audio session management for simultaneous TTS and STT

## License

MIT License — see [LICENSE](LICENSE)

## Contact

**Apoorv Darshan** — ad13dtu@gmail.com
