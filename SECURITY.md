# Security Policy

Thanks for helping keep Scowld and its users safe.

## Supported versions

Security fixes are made against the latest released version of the iOS app and the `main` branch.

| Version | Supported |
| ------- | --------- |
| 2.x     | ✅        |
| < 2.0   | ❌        |

## Security model

Scowld is a **bring-your-own-key (BYOK)** app. Understanding the model helps when assessing a report:

- Provider API keys are entered by the user and stored in the **iOS Keychain** on the device.
- There is **no Scowld backend that receives, proxies, or stores user API keys**. With the user's own key, each live conversation is a WebSocket connection made natively from the device straight to the provider the user selected (Google Gemini Live, OpenAI Realtime, or xAI Grok Voice), and each key is sent only to its own provider.
- **Scowld Premium** conversations instead go through Scowld's relay on the website's Cloudflare Worker (`web/src/premium-account.js`), which adds Scowld's own Gemini key server-side; that key never reaches the app. The app identifies itself only with its anonymous RevenueCat app user ID; the relay checks purchases with a read-only RevenueCat key, fixes the model and context limit so a client can't run up costs, records minutes used per App Store purchase, and stores no audio, camera frames or transcripts.
- A local HTTP server runs inside the app only to serve the bundled web (VRM) frontend; it is bound to localhost, not exposed off-device, and makes no provider calls. (Scowld 2.0.1 and earlier also use it to proxy text-to-speech requests on-device with the key from Keychain.)
- Hands-free wake detection uses Apple's on-device speech recognition and listens only for the companion's name; nothing is sent to a provider before a live conversation starts.
- Chat history (each turn's transcript), provider/model/voice choices, and preferences are stored locally on the device.
- The marketing website at [scowld.xyz](https://scowld.xyz) serves marketing, blog, privacy, and terms pages, a star-history SVG for the README, and the Scowld Premium relay (`/api/live`, `/api/premium/balance`). The star-history endpoint reads public stargazer data from the GitHub API with a read-only token. Worker secrets (`GITHUB_TOKEN`, `GEMINI_API_KEY`, `REVENUECAT_SECRET_KEY`) live only in Cloudflare. The site has no accounts; the only stored data is Premium minute usage keyed by App Store purchase.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report privately using either:

1. **GitHub private vulnerability reporting** — open a private advisory at
   [github.com/apoorvdarshan/scowld/security/advisories/new](https://github.com/apoorvdarshan/scowld/security/advisories/new) (preferred), or
2. **Email** — [ad13dtu@gmail.com](mailto:ad13dtu@gmail.com) with subject `SECURITY - Scowld`.

Please include:

- A description of the issue and its impact.
- Steps to reproduce or a proof of concept.
- Affected version / commit and device + iOS version.
- Any suggested remediation.

### What to expect

- Acknowledgement within **3 business days**.
- A fix or mitigation plan for confirmed, in-scope issues, and a coordinated disclosure once a fix is available.
- Credit for the report if you would like it.
- Fixed vulnerabilities are published as GitHub security advisories and named in the release notes of the version that fixes them.

## How the project is checked

- CodeQL static analysis on every pull request and weekly, dependency review on pull requests, and OpenSSF Scorecard on `main`.
- Dependabot alerts and security updates, with GitHub Actions pinned to commit SHAs (the release workflows pin [store-release](https://github.com/apoorvdarshan/store-release), whose store tooling is hash-locked).
- Secret scanning with push protection.
- Each GitHub Release attaches a Sigstore-signed source archive with a build-provenance attestation; for releases after v2.1.0 it is signed by store-release's `ios-source-archive.yml` called from this repository (verification commands in [store/README.md](store/README.md#verifying-a-release)).

## Out of scope

- Vulnerabilities in third-party providers (Google, OpenAI, xAI, etc.) — report those to the provider.
- Issues that require a jailbroken device or physical access to an unlocked device.
- The intentional ability to reveal your **own** stored API key in Settings (this is a deliberate, user-only feature on a personal device).

Thank you for reporting responsibly.
