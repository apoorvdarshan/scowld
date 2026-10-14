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
- There is **no Scowld backend that receives, proxies, or stores user API keys**. Requests go directly from the device to the provider the user configured (OpenAI, Anthropic, Gemini, ElevenLabs, Groq, etc.).
- A local HTTP server runs inside the app only to serve the bundled web (VRM) frontend and to proxy provider calls on-device using the key from Keychain; it is bound to localhost and not exposed off-device.
- Chat history, provider/model choices, and preferences are stored locally on the device.
- The marketing website at [scowld.xyz](https://scowld.xyz) serves marketing, blog, privacy, and terms pages, plus a star-history SVG for the README. That endpoint reads public stargazer data from the GitHub API with a read-only token kept as a Cloudflare Worker secret; the site has no accounts and stores no user data.

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
- Dependabot alerts and security updates, with GitHub Actions pinned to commit SHAs and store tooling hash-locked.
- Secret scanning with push protection.
- Each GitHub Release attaches a Sigstore-signed source archive with a build-provenance attestation (see [store/README.md](store/README.md)).

## Out of scope

- Vulnerabilities in third-party providers (OpenAI, Anthropic, Google, ElevenLabs, etc.) — report those to the provider.
- Issues that require a jailbroken device or physical access to an unlocked device.
- The intentional ability to reveal your **own** stored API key in Settings (this is a deliberate, user-only feature on a personal device).

Thank you for reporting responsibly.
