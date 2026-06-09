# Contributing to Scowld

Thanks for your interest in contributing! Scowld is an open-source iOS AI companion with an animated VRM character, hands-free wake mode, and bring-your-own-key (BYOK) AI / speech providers.

This guide covers how to report issues, propose changes, and get the project running locally.

## Ways to contribute

- **Report a bug** or **request a feature** via [GitHub Issues](https://github.com/apoorvdarshan/scowld/issues).
- **Improve docs** (README, this file, in-app copy).
- **Submit code** via a pull request.
- **Report a security vulnerability** — please follow [SECURITY.md](SECURITY.md), not a public issue.

## Repo structure

```
ios/             - iOS app (open ios/Scowld.xcodeproj in Xcode)
web/             - Next.js marketing website
assets/          - README assets
APPSTORE.md      - App Store Connect copy
```

## Getting set up

### Requirements

- iOS 17.0+ target
- Xcode 16 or newer
- Node.js (only for the website)

### iOS app

```bash
open ios/Scowld.xcodeproj
```

1. Select the **Scowld** scheme and your device or simulator.
2. Build and run.
3. Add your provider API keys in **Settings** after launch (they are stored in the iOS Keychain).

### Website

```bash
cd web
npm install
npm run dev   # http://localhost:3000
```

## Pull request guidelines

1. **Open an issue first** for anything non-trivial so the approach can be discussed.
2. **Branch** off `main` and keep each PR focused on one change.
3. **Match the existing style** — SwiftUI conventions, naming, and structure already used in the codebase. Read nearby code before adding new patterns.
4. **Build before you push.** Make sure the app compiles and runs on a device/simulator.
5. **Describe your change** clearly and link the related issue (e.g. `Closes #123`).

## Coding guidelines

- **Never hardcode or commit API keys, tokens, or secrets.** Keys belong in the iOS Keychain at runtime, entered by the user — never in source or git history.
- Keep the **BYOK model intact**: requests go directly from the device to the user's chosen provider. Do not introduce a server that receives or stores user keys.
- Prefer the existing helpers and components (settings rows, providers, `KeychainManager`, etc.) over new one-off patterns.
- If you change legal text, keep the **website Privacy/Terms** and the **in-app onboarding copy** in sync.
- Keep user-facing copy concise and consistent with the existing tone.

## Reporting bugs

Good bug reports include:

- What you expected vs. what happened.
- Steps to reproduce.
- Device model and iOS version, and the app version (Settings/About → version).
- Screenshots or screen recordings when relevant.

## Code of conduct

Be respectful and constructive. Harassment or abuse of any kind is not welcome. Maintainers may remove comments, commits, or contributions that violate this spirit.

## Questions

Open a [discussion or issue](https://github.com/apoorvdarshan/scowld/issues), or reach the developer at [ad13dtu@gmail.com](mailto:ad13dtu@gmail.com).
