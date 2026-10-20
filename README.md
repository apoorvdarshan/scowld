<p align="center">
  <img src="assets/logo.png" alt="Scowld Logo" width="120">
</p>

<h1 align="center">Scowld</h1>

<p align="center">
  An iOS AI voice companion with an animated character you talk to live, hands-free wake mode, bring-your-own-key live voice providers (Google Gemini Live, OpenAI Realtime, xAI Grok Voice) or optional Scowld Premium with no API key, optional vision, and saved conversations.
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6760672848"><img src="https://img.shields.io/badge/App%20Store-Download-black?logo=apple" alt="App Store"></a>
  <a href="https://github.com/apoorvdarshan/scowld/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="License: MIT"></a>
  <a href="https://scowld.xyz"><img src="https://img.shields.io/badge/Website-scowld.xyz-blue" alt="Website"></a>
  <a href="https://www.instagram.com/apoorvcodes/"><img src="https://img.shields.io/badge/Instagram-@apoorvcodes-pink" alt="Instagram"></a>
  <a href="https://www.producthunt.com/products/scowld-2"><img src="https://img.shields.io/badge/Product%20Hunt-Scowld-orange" alt="Product Hunt"></a>
</p>

<p align="center">
  <a href="https://www.bestpractices.dev/projects/15502"><img src="https://www.bestpractices.dev/projects/15502/badge" alt="OpenSSF Best Practices"></a>
  <a href="https://scorecard.dev/viewer/?uri=github.com/apoorvdarshan/scowld"><img src="https://api.scorecard.dev/projects/github.com/apoorvdarshan/scowld/badge" alt="OpenSSF Scorecard"></a>
</p>

<p align="center">
  <img src="assets/avatars.png" alt="Scowld Avatars" width="700">
</p>

## Status

This is the open-source repository for the Scowld iOS app and the marketing website at [scowld.xyz](https://scowld.xyz). Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Features

- **Animated companion** - VRM character rendering through the bundled Amica/Arbius frontend, with idle animations and lip sync driven by the live audio.
- **Live speech-to-speech** - Each conversation runs over one live connection to the provider you pick. The provider hears the microphone directly and answers in its own voice; there is no separate speech-to-text or text-to-speech step.
- **Interrupt anytime** - Start speaking while she talks and she stops to listen (barge-in).
- **Hands-free wake mode** - When enabled, the app uses Apple's on-device speech recognition only to listen for Bella or the saved custom companion name, then starts a live session. Nothing is sent to a provider before the session starts.
- **Home tips** - A top-right info button explains the wake phrases and composer controls. With your own key, until a key is saved, the Chat tab says so and links to Settings; with Scowld Premium and no plan or minutes left, it offers the plans or minute packs.
- **BYOK live voice providers** - Google Gemini Live, OpenAI Realtime, and xAI Grok Voice with your own API key, free and unlimited, each with its own models and built-in voices (see below).
- **Scowld Premium (optional)** - Talk without an API key: Google Gemini Live with Scowld's own key, sold as weekly or yearly plans and minute packs (see [Scowld Premium](#scowld-premium)).
- **Vision** - Optional front-camera context with Gemini, OpenAI, or Scowld Premium. Off by default; frames are sent only while the eye is on.
- **Captions** - Optional captions show what she says while she talks.
- **Past chats** - Each turn's transcript is saved on the device, and the active chat is used as context for the next conversation.
- **Ends by itself** - A live conversation ends after 90 seconds of silence and when you leave the Chat tab or the app goes to the background.
- **Character settings** - Avatar, custom name, and system prompt controls.
- **Reply language** - Defaults to the iPhone language, with supported language overrides.
- **Local key storage** - Provider API keys are stored in iOS Keychain and sent only to their provider; the connection (Scowld Premium or Own API Key) and provider, model, and voice choices are stored in local preferences.
- **Startup onboarding** - Local companion videos and Privacy/Terms acceptance with links to the web policies.
- **About actions** - Update check, rating, share, Product Hunt, an Open Source section (source code, Star on GitHub, and the GitHub bug report and feature request forms), contact, Instagram, X, privacy, and terms.

## Live Voice Providers

| Provider | Models (default first) | Voices | Camera |
|----------|------------------------|--------|--------|
| Google Gemini Live | `gemini-3.8-live`, `gemini-3.8-live-extended-thinking`, `gemini-3.1-flash-live-preview` | 14 built-in female voices, Leda by default | A frame about every 2 seconds while the eye is on |
| OpenAI Realtime | `gpt-realtime-2.1-mini`, `gpt-realtime-2.1` | Marin (default), Shimmer, Coral, Sage | The latest frame with each thing you say |
| xAI Grok Voice | `grok-voice-latest`, `grok-voice-3.0` | Ara (default), Eve | Not supported |

With OpenAI Realtime, what you say is transcribed inside the session (`whisper-1`) so it can be saved to the chat. With your own key, the app connects straight to the provider you pick and no Scowld server is involved. Scowld Premium uses Gemini Live (`gemini-3.8-live`) with the same 14 voices and the camera, through Scowld's server.

## Scowld Premium

Scowld Premium is an optional way to talk without an API key. It uses Google Gemini Live (`gemini-3.8-live`) with Scowld's own key, offers the same 14 female Gemini voices, and works with the camera. Bringing your own key works exactly as before and stays free and unlimited.

| Plan | Price (US) | Minutes |
|------|------------|---------|
| Weekly | $6.99/week | 20 minutes a week |
| Yearly | $99.99/year | 50 minutes a month; new subscribers get a 3-day free trial that includes 10 minutes |

Both plans are auto-renewing subscriptions; other countries get local equivalent prices. Plan minutes reset each week (weekly) or each month of the subscription year (yearly) and don't roll over. Minute packs are one-time consumable purchases that anyone can buy, with or without a plan: 20 minutes for $6.99, 60 minutes for $16.99, and 150 minutes for $34.99. They never expire and are used after a plan's minutes run out. Minutes count the time a Premium conversation is connected.

New installs start in Premium mode, and the plans are shown once after onboarding. People who already saved an API key keep using their key. Users switch in Settings > Live Voice (Scowld Premium / Own API Key), which also shows the minutes left, See Premium Plans, Buy More Minutes, Restore Purchases, and Manage Subscription.

**How it works.** The app opens a WebSocket to `wss://scowld.xyz/api/live` and identifies itself with its anonymous RevenueCat app user ID (the `X-Scowld-User` header). The Worker in `web/` checks that user's purchases with RevenueCat and relays the live conversation to Gemini Live in real time with Scowld's key, metering the connected time:

- `web/src/premium.js` - the rules, with no I/O: plans, trial, monthly minutes, minute packs, and the fixed setup sent to Gemini (model, voices, context limit)
- `web/src/relay.js` - the metering relay between the app and Gemini Live (at most one camera frame every 2 seconds; ends the conversation when the minutes run out)
- `web/src/premium-account.js` - one Durable Object per user: checks purchases with RevenueCat, serves the balance, and relays one conversation at a time
- `web/src/premium-ledger.js` - the usage ledger: minutes used per App Store purchase

The Worker reads two secrets, `GEMINI_API_KEY` and `REVENUECAT_SECRET_KEY`.

**Privacy.** Through Scowld's server go microphone audio (streamed continuously while a conversation is active), camera frames while the camera is on (at most one every 2 seconds), and the companion's instructions (her name, the system prompt, the reply language, and recent messages from the active saved chat). The server does not store audio, camera frames, transcripts, or conversation content. To check purchases it sends the anonymous RevenueCat app user ID to RevenueCat, and it records the minutes used per App Store purchase (keyed by App Store transaction identifiers, not by name, email, or device) so limits survive reinstalling. Cloudflare processes connection data such as the IP address as the host, and Google processes what it receives under Google's terms for the Gemini API. Transcripts are still saved only on the device. With your own key, nothing goes through Scowld's server.

## Repo Structure

```
ios/             - iOS app (open ios/Scowld.xcodeproj in Xcode)
ios/ScowldTests/ - Unit tests
ios/ScowldUITests/ - UI tests
web/             - scowld.xyz: static HTML/CSS/JS pages and a Cloudflare Worker
assets/          - README assets
store/           - App Store listing (source of truth) and release switches
scripts/         - Test and release scripts
APPSTORE.md      - App Store Connect reference copy
```

## Architecture

```
Native iOS (Swift/SwiftUI)
├── HomeView              - Main chat UI, composer, and WKWebView bridge
├── HomeTipsSheet         - In-app guide for wake phrases and composer controls
├── LiveConversation      - Turns, barge-in, camera frames, and idle timeouts
├── LiveSession           - The live WebSocket: message order, queued input, Gemini session resumption
├── LiveWire              - Gemini Live, OpenAI Realtime, xAI Grok Voice, and Scowld Premium protocols
├── LiveAudioEngine       - Microphone with voice processing, playback, lip-sync levels
├── HandsFreeWakeListener - On-device wake word (Apple speech recognition)
├── MemoryStore           - Local CoreData chat history and selected chat context
├── PremiumModel          - Scowld Premium: plans, minute packs, balance, purchases and restore (RevenueCat)
├── PremiumPaywallView    - Premium plans; MinutePacksView sells minute packs
├── SettingsView          - Live Voice connection (Scowld Premium or own key), provider, model, voice and key; language, captions, avatar, and prompt
└── AboutView             - App actions, update check, links, and support

WKWebView (bundled Amica/Arbius frontend)
├── Three.js + three-vrm  - 3D avatar rendering
├── VRMA animations       - Idle, gesture, and lip sync animation support
├── Lip-sync bridge       - Page script that feeds the avatar the levels of her natively played voice
└── Native bridge         - JavaScript to Swift message passing

Website (web/, Cloudflare Workers)
├── public/               - Plain HTML, CSS and JavaScript: landing, blog, privacy, terms
├── src/worker.js         - Serves /api/star-history.svg and routes /api/live and /api/premium/balance; everything else is static
├── src/premium.js        - Scowld Premium rules: plans, trial, minutes, packs, fixed Gemini setup
├── src/relay.js          - Metering relay between the app and Gemini Live
├── src/premium-account.js - Durable Object per Premium user: purchase check, balance, relay
└── src/premium-ledger.js - Durable Object usage ledger: minutes used per App Store purchase
```

## Requirements

- iOS 17.0+
- Xcode 26+ (CI uses Xcode 27)
- Node.js 22+ for the website tools (the site itself has no build step)
- Scowld Premium needs two Worker secrets, `GEMINI_API_KEY` and `REVENUECAT_SECRET_KEY` (see [Website Environment Variables](#website-environment-variables)). Own-key conversations need none.
- With their own key, users bring a Google Gemini, OpenAI, or xAI API key inside the iOS app.

## Monetization

Scowld is free with your own API key: no subscription, no limits from Scowld, and nothing goes through a Scowld server. [Scowld Premium](#scowld-premium) is an optional paid way to talk without a key (weekly or yearly auto-renewing subscriptions and consumable minute packs). About > Support Scowld also offers optional one-time tips (consumable in-app purchases from $0.99 to $19.99) that unlock nothing. Premium plans, minute packs, and tips are App Store purchases managed with RevenueCat.

With their own key, users are responsible for provider accounts, API keys, provider billing, rate limits, and acceptable use policies for the live voice provider they configure (Google, OpenAI, or xAI).

## Setup

### iOS App

1. Open the Xcode project.
   ```bash
   open ios/Scowld.xcodeproj
   ```
2. Select the Scowld scheme and your device.
3. Build and run from Xcode.
4. After launch, choose a connection in Settings > Live Voice: Scowld Premium (test purchases with a sandbox account), or Own API Key with a provider and its API key.

### Website

The pages in `web/public/` are plain HTML, CSS and JavaScript, edited directly. There is no framework and nothing to compile. Serve them in the local Workers runtime:

```bash
cd web
npm install
npm run dev   # http://localhost:8787
```

Deploy with the configured Wrangler account:

```bash
npm run deploy
```

The deployment targets the `scowld-web` Worker. To serve `scowld.xyz`, first add the domain as a Cloudflare zone and update its registrar nameservers, then add `scowld.xyz` and `www.scowld.xyz` as Worker custom domains.

### Tests

```bash
bash scripts/test-ios.sh
```

Runs the unit (`ScowldTests`) and UI (`ScowldUITests`) tests on a fresh iPhone simulator. GitHub Actions runs them on every pull request that touches the app. Tests never use the network, microphone, camera, real provider keys, the App Store, or Scowld's server. See [docs/ios-testing.md](docs/ios-testing.md).

```bash
cd web && npm ci && npm run lint && npm test && npm run build && npm run smoke
```

Checks the website: ESLint and html-validate, the Vitest suite (including [fast-check](https://fast-check.dev) fuzz properties for the star-history SVG renderer, and the Scowld Premium rules and metering relay in `tests/premium.test.js`), a site check (`npm run build`) for page metadata, internal links, JSON-LD and the sitemap, and a smoke test that serves the site in the local Workers runtime and requests every sitemap page. The **Website** workflow runs the same steps on pull requests that touch `web/`.

### Security checks

Every pull request also runs [CodeQL](.github/workflows/codeql.yml) (JavaScript, Python and GitHub Actions; [the Swift app](.github/workflows/codeql-swift.yml) weekly and for each release tag) and [dependency review](.github/workflows/dependency-review.yml). [OpenSSF Scorecard](.github/workflows/scorecard.yml) runs on `main` and weekly, Dependabot keeps pinned dependencies current, and releases attach a Sigstore-signed source archive. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

### Releases

Pushing a `v<version>` tag equal to `MARKETING_VERSION` runs the **iOS Release** workflow: the tests, then only the App Store steps switched on with repository variables (upload, listing, What's New, screenshots, product page header and search results images, App Review submission), then the GitHub Release with a Sigstore-signed source archive. A manual **Run workflow** only validates the signed build with App Store Connect. Every switch is off by default; see [store/README.md](store/README.md). Xcode Cloud was removed for Scowld on 2026-10-14 and must not be re-created.

### Website Environment Variables

Scowld Premium (`/api/live` and `/api/premium/balance`) needs two Worker secrets: `GEMINI_API_KEY` (Scowld's Gemini key, which stays on the server) and `REVENUECAT_SECRET_KEY` (to check purchases). Without them, Premium answers that it is unavailable; the pages and own-key conversations are unaffected. The star-history SVG (`/api/star-history.svg`) reads public stargazer data with a `GITHUB_TOKEN` Worker secret; without it, the endpoint serves a fallback card. Set secrets with `npx wrangler secret put <NAME>`.

See [web/.env.example](web/.env.example) for defaults.

## Privacy Model

- Provider API keys are entered by the user, stored in iOS Keychain, and sent only to that provider.
- The connection (Scowld Premium or Own API Key) and provider, model, and voice choices are stored locally in app preferences.
- Chat history (each turn's transcript) and selected chat context are stored locally on device, with either connection.
- With your own key, while a live conversation is active, microphone audio is streamed continuously to the selected provider, together with the selected chat context. The provider answers in its own voice and produces the transcripts. No Scowld server is in between.
- With Scowld Premium, the same audio, context, and camera frames (at most one every 2 seconds) go through Scowld's server (scowld.xyz, on Cloudflare Workers) to Google Gemini Live, relayed in real time with Scowld's key. The server stores no audio, camera frames, transcripts, or conversation content; it sends the anonymous RevenueCat app user ID to RevenueCat to check purchases and records minutes used per App Store purchase (keyed by App Store transaction identifiers, not by name, email, or device).
- Hands-free wake detection uses Apple's on-device speech recognition only to listen for the companion's name while the app is open and idle; nothing is sent to a provider before the live session starts.
- Camera access is optional and off by default. Frames go to the selected provider (or, with Scowld Premium, through Scowld's server to Gemini Live) only while the eye is on (not supported with xAI), and Scowld doesn't record or store camera data.
- Providers process what they receive under their own terms and privacy policies; with Scowld Premium, Google processes it under Google's terms for the Gemini API, and Cloudflare processes connection data such as the IP address as the host.
- Scowld does not use Apple's TrueDepth API or ARKit face tracking and does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or other face data.
- Privacy Policy and Terms are published on the web. Startup onboarding links to the web policies and records acceptance.

## Website Links

- Website: https://scowld.xyz
- Blog: https://scowld.xyz/blog
- Privacy: https://scowld.xyz/privacy
- Terms: https://scowld.xyz/terms
- Instagram: https://www.instagram.com/apoorvcodes/
- Product Hunt: https://www.producthunt.com/products/scowld-2
- Ko-fi: https://ko-fi.com/apoorvdarshan

## Credits

- Character/avatar frontend: Amica / Arbius AI (MIT)
- Developer: Apoorv Darshan, ad13dtu@gmail.com

## Star History

<a href="https://github.com/apoorvdarshan/scowld/stargazers">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://scowld.xyz/api/star-history.svg?theme=dark&amp;v=3" />
    <source media="(prefers-color-scheme: light)" srcset="https://scowld.xyz/api/star-history.svg?theme=light&amp;v=3" />
    <img alt="Scowld GitHub star history" src="https://scowld.xyz/api/star-history.svg?theme=light&amp;v=3" />
  </picture>
</a>

## License

Scowld is released under the [MIT License](LICENSE). The bundled character/avatar frontend (Amica / Arbius AI) is also MIT licensed.
