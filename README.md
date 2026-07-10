<p align="center">
  <img src="assets/logo.png" alt="Scowld Logo" width="120">
</p>

<h1 align="center">Scowld</h1>

<p align="center">
  An iOS AI voice companion with an animated character, hands-free wake mode, bring-your-own-key AI providers, speech-to-text, ElevenLabs text-to-speech, vision, and saved conversations.
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6760672848"><img src="https://img.shields.io/badge/App%20Store-Download-black?logo=apple" alt="App Store"></a>
  <a href="https://github.com/apoorvdarshan/scowld/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="License: MIT"></a>
  <a href="https://scowld.xyz"><img src="https://img.shields.io/badge/Website-scowld.xyz-blue" alt="Website"></a>
  <a href="https://www.instagram.com/scowld_/"><img src="https://img.shields.io/badge/Instagram-@scowld__-pink" alt="Instagram"></a>
  <a href="https://www.producthunt.com/products/scowld"><img src="https://img.shields.io/badge/Product%20Hunt-Scowld-orange" alt="Product Hunt"></a>
</p>

<p align="center">
  <img src="assets/avatars.png" alt="Scowld Avatars" width="700">
</p>

## Status

This is the open-source repository for the Scowld iOS app and the marketing website at [scowld.xyz](https://scowld.xyz). Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Features

- **Animated companion** - VRM character rendering through the bundled Amica/Arbius frontend, with lip sync, idle animations, and expressions.
- **Voice and text chat** - Send typed messages or voice input from the iOS composer.
- **Hands-free wake mode** - When enabled, the app listens on device for Bella or the saved custom companion name to start voice recording.
- **Home tips** - A top-right info button explains the wake phrases and composer controls.
- **BYOK AI providers** - Gemini, OpenAI, Claude, Ollama, Groq, OpenRouter, xAI, Together AI, Hugging Face, Venice AI, and Moonshot AI.
- **BYOK speech-to-text** - Native iOS speech, OpenAI Whisper, Groq Whisper, Deepgram, AssemblyAI, Google Cloud STT, browser Whisper, or text-only mode.
- **BYOK text-to-speech** - ElevenLabs (Celine, Claire, bundled voice presets, custom voice IDs, model selection, and bundled local voice previews) and OpenAI voices.
- **Vision** - Optional front-camera context can be sent to the AI when enabled.
- **Past chats** - Conversations are saved locally and can be selected as context for future replies.
- **Character settings** - Avatar, custom name, and system prompt controls.
- **Multilingual speech settings** - Defaults to the iPhone language, with supported language overrides.
- **Local key storage** - Provider API keys are stored in iOS Keychain; provider/model choices are stored in local preferences.
- **Startup onboarding** - Local companion videos and Privacy/Terms acceptance with links to the web policies.
- **About actions** - Update check, rating, Star on GitHub, share, Product Hunt, report an issue or request a feature via GitHub Issues, contact, Instagram, X, privacy, and terms.

## Repo Structure

```
ios/             - iOS app (open ios/Scowld.xcodeproj in Xcode)
web/             - Next.js marketing website
assets/          - README assets
APPSTORE.md      - App Store Connect copy
```

## Architecture

```
Native iOS (Swift/SwiftUI)
├── HomeView             - Main chat UI and WKWebView bridge
├── HomeTipsSheet        - In-app guide for wake phrases and composer controls
├── CloudSTTProvider     - Native/cloud speech-to-text providers
├── AI providers         - BYOK Gemini, OpenAI, Claude, Ollama, and OpenAI-compatible clients
├── MemoryStore          - Local CoreData chat history and selected chat context
├── SettingsView         - BYOK AI/STT/TTS, voice, language, avatar, and prompt settings
└── AboutView            - App actions, update check, links, and support

WKWebView (bundled Amica/Arbius frontend)
├── Three.js + three-vrm - 3D avatar rendering
├── VRMA animations      - Idle, gesture, and lip sync animation support
├── AudioContext         - TTS audio playback
└── Native bridge        - JavaScript to Swift message passing

Cloudflare Workers / Next.js website
└── Marketing, blog, privacy, and terms pages
```

## Requirements

- iOS 17.0+
- Xcode 16+
- Node.js 20.9+ for the website
- No Cloudflare environment variables are required for app AI, speech, or billing services.
- Users bring their own provider API keys inside the iOS app.

## Monetization

Scowld 2.0 removes subscriptions, Billing, StoreKit purchases, paywalls, voice credits, and extra credit packs.

Users are responsible for provider accounts, API keys, provider billing, rate limits, and acceptable use policies for the AI, speech-to-text, and text-to-speech providers they configure.

## Setup

### iOS App

1. Open the Xcode project.
   ```bash
   open ios/Scowld.xcodeproj
   ```
2. Select the Scowld scheme and your device.
3. Build and run from Xcode.
4. Add provider API keys in Settings after launch.

### Website

```bash
cd web
npm install
npm run dev
```

Next.js runs at `http://localhost:3000`.

Build and preview in the Cloudflare Workers runtime:

```bash
npm run preview
```

Deploy with the configured Wrangler account:

```bash
npm run deploy
```

The deployment targets the `scowld-web` Worker. To serve `scowld.xyz`, first add the domain as a Cloudflare zone and update its registrar nameservers, then add `scowld.xyz` and `www.scowld.xyz` as Worker custom domains.

### Website Environment Variables

The website does not require hosted AI, speech, or billing environment variables.

See [web/.env.example](web/.env.example) for defaults.

## Privacy Model

- Provider API keys are entered by the user and stored in iOS Keychain.
- Provider/model choices are stored locally in app preferences.
- Chat history and selected chat context are stored locally on device.
- Voice audio, prompt text, optional image context, and generated speech text are sent directly to the providers configured by the user.
- Hands-free wake detection is processed on device while the app is open and idle; it is not sent to external providers before command recording starts.
- Camera access is optional and used only when visual context is sent.
- Scowld does not use Apple's TrueDepth API or ARKit face tracking and does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or other face data.
- Privacy Policy and Terms are published on the web. Startup onboarding links to the web policies and records acceptance.

## Website Links

- Website: https://scowld.xyz
- Blog: https://scowld.xyz/blog
- Privacy: https://scowld.xyz/privacy
- Terms: https://scowld.xyz/terms
- Instagram: https://www.instagram.com/scowld_/
- Product Hunt: https://www.producthunt.com/products/scowld
- Ko-fi: https://ko-fi.com/apoorvdarshan

## Credits

- Character/avatar frontend: Amica / Arbius AI (MIT)
- Developer: Apoorv Darshan, ad13dtu@gmail.com

## License

Scowld is released under the [MIT License](LICENSE). The bundled character/avatar frontend (Amica / Arbius AI) is also MIT licensed.
