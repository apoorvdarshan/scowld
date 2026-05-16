<p align="center">
  <img src="assets/logo.png" alt="Scowld Logo" width="120">
</p>

<h1 align="center">Scowld</h1>

<p align="center">
  A paid iOS AI voice companion with an animated character, hosted Gemini AI, Deepgram speech-to-text, ElevenLabs text-to-speech, vision, and saved conversations.
</p>

<p align="center">
  <a href="https://scowld.xyz"><img src="https://img.shields.io/badge/Website-scowld.xyz-blue" alt="Website"></a>
  <a href="https://www.instagram.com/scowld_/"><img src="https://img.shields.io/badge/Instagram-@scowld__-pink" alt="Instagram"></a>
  <a href="https://www.linkedin.com/company/scowld"><img src="https://img.shields.io/badge/LinkedIn-Scowld-blue" alt="LinkedIn"></a>
  <a href="https://www.producthunt.com/products/scowld"><img src="https://img.shields.io/badge/Product%20Hunt-Scowld-orange" alt="Product Hunt"></a>
</p>

<p align="center">
  <img src="assets/avatars.png" alt="Scowld Avatars" width="700">
</p>

## Status

This is a private Scowld repository for the iOS app, the hosted backend routes, and the marketing website at [scowld.xyz](https://scowld.xyz).

## Features

- **Animated companion** - VRM character rendering through the bundled Amica/Arbius frontend, with lip sync, idle animations, and expressions.
- **Voice and text chat** - Send typed messages or voice input from the iOS composer.
- **Hosted speech-to-text** - Deepgram Nova-3 routed through the Vercel backend.
- **Hosted Gemini AI** - Gemini 3 Flash starts the response path with hosted fallback models.
- **ElevenLabs text-to-speech** - Managed TTS with selectable voice IDs and bundled local voice previews.
- **Vision** - Optional front-camera context can be sent to the AI when enabled.
- **Past chats** - Conversations are saved locally and can be selected as context for future replies.
- **Character settings** - Avatar, custom name, and system prompt controls.
- **Multilingual speech settings** - Defaults to the iPhone language, with supported language overrides.
- **Billing and credits** - RevenueCat-backed StoreKit subscriptions, extra credit packs, and Apple subscription management.
- **About actions** - Update check, rating prompt, share, contact, Product Hunt, Ko-fi, LinkedIn, Instagram, privacy, and terms.

## Repo Structure

```
ios/             - iOS app (open ios/Scowld.xcodeproj in Xcode)
web/             - Next.js website and hosted backend routes
assets/          - README assets
APPSTORE.md      - App Store Connect copy
```

## Architecture

```
Native iOS (Swift/SwiftUI)
├── HomeView             - Main chat UI and WKWebView bridge
├── BillingStore         - RevenueCat, StoreKit products, subscriptions, and voice credits
├── CloudSTTProvider     - Hosted Deepgram speech-to-text
├── HostedGeminiProvider - Hosted Gemini chat requests
├── MemoryStore          - Local CoreData chat history and selected chat context
├── SettingsView         - Voice, language, avatar, prompt, and managed service settings
└── AboutView            - App actions, update check, links, and support

WKWebView (bundled Amica/Arbius frontend)
├── Three.js + three-vrm - 3D avatar rendering
├── VRMA animations      - Idle, gesture, and lip sync animation support
├── AudioContext         - TTS audio playback
└── Native bridge        - JavaScript to Swift message passing

Vercel / Next.js backend
├── /api/chat            - Gemini model fallback route
├── /api/stt/deepgram    - Deepgram speech-to-text proxy
├── /api/tts/elevenlabs  - ElevenLabs text-to-speech proxy
└── /api/billing/config  - Public RevenueCat billing configuration and product metadata
```

## Requirements

- iOS 17.0+
- Xcode 16+
- Node.js for the website/backend
- Vercel environment variables for Gemini, ElevenLabs, Deepgram, and RevenueCat billing config
- App Store Connect and RevenueCat products matching the StoreKit product IDs below

## Monetization

Voice usage is modeled as one simple unit:

**1 voice credit = 1 full voice turn**

| Subscription | Price | Included credits |
| --- | ---: | ---: |
| Weekly | $9.99/week | 40 credits/week |
| Monthly | $34.99/month | 180 credits/month, refilled as 45/week |
| Yearly | $299.99/year | 2,340 credits/year, refilled as 45/week |

| Extra credit pack | Price |
| ---: | ---: |
| 10 credits | $3.99 |
| 50 credits | $14.99 |
| 100 credits | $27.99 |
| 200 credits | $49.99 |
| 500 credits | $119.99 |

Extra credits are used after subscription credits. They do not bypass safety limits such as one active reply at a time, capped audio input length, capped TTS reply length, or reply-rate limits.

StoreKit product IDs:

- `scowld.sub.weekly`
- `scowld.sub.monthly`
- `scowld.sub.yearly`
- `scowld.credits.10`
- `scowld.credits.50`
- `scowld.credits.100`
- `scowld.credits.200`
- `scowld.credits.500`

## Setup

### iOS App

1. Open the Xcode project.
   ```bash
   open ios/Scowld.xcodeproj
   ```
2. Select the Scowld scheme and your device.
3. Build and run from Xcode.
4. Use Xcode StoreKit testing or App Store sandbox for purchase flow testing.

### Website and Hosted Routes

```bash
cd web
npm install
npm run dev
```

Next.js runs at `http://localhost:3000`.

### Hosted Environment Variables

The iOS app does not embed provider API keys. Add these environment variables to the Vercel deployment for `web/`:

```bash
GEMINI_API_KEY
GEMINI_MODEL_FALLBACKS
ELEVENLABS_API_KEY
ELEVENLABS_DEFAULT_VOICE_ID
ELEVENLABS_MODEL
DEEPGRAM_API_KEY
DEEPGRAM_MODEL
REVENUECAT_IOS_API_KEY
REVENUECAT_ENTITLEMENT_ID
REVENUECAT_OFFERING_ID
APP_STORE_APP_ID
```

`REVENUECAT_IOS_API_KEY` is the public RevenueCat SDK key returned by `/api/billing/config`. Provider API keys remain server-side only.

See [web/.env.example](web/.env.example) for defaults.

## Privacy Model

- No user provider API keys are shown in the app.
- Gemini, Deepgram, and ElevenLabs keys live in hosted backend environment variables.
- Chat history and selected chat context are stored locally on device.
- Voice audio, prompt text, optional image context, and generated speech text are routed through the hosted backend only to provide app features.
- Camera access is optional and used only when visual context is sent.

## Website Links

- Website: https://scowld.xyz
- Privacy: https://scowld.xyz/privacy
- Terms: https://scowld.xyz/terms
- LinkedIn: https://www.linkedin.com/company/scowld
- Instagram: https://www.instagram.com/scowld_/
- Product Hunt: https://www.producthunt.com/products/scowld
- Ko-fi: https://ko-fi.com/apoorvdarshan

## Credits

- Character/avatar frontend: Amica / Arbius AI (MIT)
- Developer: Apoorv Darshan, ad13dtu@gmail.com
