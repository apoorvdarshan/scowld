# Contributing to Scowld

Thanks for your interest in contributing! Scowld is an open-source iOS AI companion with an animated VRM character, hands-free wake mode, and bring-your-own-key (BYOK) live voice providers (Google Gemini Live, OpenAI Realtime, xAI Grok Voice).

This guide covers how to report issues, propose changes, and get the project running locally.

## Ways to contribute

- **Report a bug** or **request a feature** via [GitHub Issues](https://github.com/apoorvdarshan/scowld/issues).
- **Improve docs** (README, this file, in-app copy).
- **Submit code** via a pull request.
- **Report a security vulnerability** — please follow [SECURITY.md](SECURITY.md), not a public issue.

## Repo structure

```
ios/             - iOS app (open ios/Scowld.xcodeproj in Xcode)
ios/ScowldTests/ - Unit tests
ios/ScowldUITests/ - UI tests
web/             - scowld.xyz: static HTML/CSS/JS pages and a Cloudflare Worker
assets/          - README assets
store/           - App Store listing and release switches (see store/README.md)
scripts/         - Test and release scripts
APPSTORE.md      - App Store Connect reference copy
```

## Getting set up

### Requirements

- iOS 17.0+ target
- Xcode 26 or newer
- Node.js (only for the website)

### iOS app

```bash
open ios/Scowld.xcodeproj
```

1. Select the **Scowld** scheme and your device or simulator.
2. Build and run.
3. After launch, choose a provider in **Settings > Live Voice** and add its API key (stored in the iOS Keychain).

### Tests

```bash
bash scripts/test-ios.sh
```

This runs the unit and UI tests on a simulator the script creates and deletes (or use **Product → Test** on the **Scowld** scheme in Xcode). The same tests run in GitHub Actions on every pull request that touches the app. They never use the network, microphone, camera, or real provider keys: unit tests stub HTTP and run live conversations over a scripted socket with fake audio, and UI tests launch a Debug-only test mode (`ScowldTestEnvironment`). Details: [docs/ios-testing.md](docs/ios-testing.md).

### Website

The pages in `web/public/` are plain HTML, CSS and JavaScript, edited directly; there is no framework or build step. When you add a page, add it to `web/public/sitemap.xml`.

```bash
cd web
npm install
npm run dev   # serves the site in the local Workers runtime at http://localhost:8787
```

Before opening a website pull request:

```bash
npm run lint    # ESLint and html-validate, no warnings
npm test        # Vitest, including fast-check fuzz properties
npm run build   # checks page metadata, internal links, JSON-LD and the sitemap
npm run smoke   # serves the site in the local Workers runtime and requests every sitemap page
```

The **Website** workflow runs the same steps on pull requests that touch `web/`.

## Pull request guidelines

1. **Open an issue first** for anything non-trivial so the approach can be discussed.
2. **Branch** off `main` and keep each PR focused on one change.
3. **Match the existing style** — SwiftUI conventions, naming, and structure already used in the codebase. Read nearby code before adding new patterns.
4. **Build and test before you push.** Make sure the app compiles and `bash scripts/test-ios.sh` passes (and the website checks above, for `web/` changes).
5. **Describe your change** clearly and link the related issue (e.g. `Closes #123`).

## Testing policy

- **New functionality must come with automated tests** that exercise it: XCTest unit or UI tests in `ios/ScowldTests` / `ios/ScowldUITests` for the app, and Vitest tests in `web/tests` for the website.
- **Bug fixes need a regression test** that fails without the fix, unless that is impractical; say why in the pull request.
- Code that parses data from outside the app or site (provider responses, GitHub API data, bridge messages) should get property-based (fuzz) tests where practical, as `web/tests/star-history-fuzz.test.js` does.
- Pull requests are merged only when their checks pass: CodeQL and dependency review on every pull request, the iOS tests for app changes, and the Website workflow for `web/` changes.

## Releases (maintainers)

Releases are built, signed, and uploaded by GitHub Actions from a `v<version>` tag that matches `MARKETING_VERSION`. Versions follow `MAJOR.MINOR[.PATCH]`, each release gets human-readable notes from `RELEASE_NOTES.md` (or GitHub's generated notes), and the GitHub Release attaches a Sigstore-signed source archive. Each App Store step has its own repository-variable switch, all off by default; a manual run of **iOS Release** only validates. The App Store listing lives in `store/metadata/ios/`. See [store/README.md](store/README.md). Xcode Cloud was removed for Scowld on 2026-10-14; do not re-create it.

## Coding guidelines

- **Never hardcode or commit API keys, tokens, or secrets.** Keys belong in the iOS Keychain at runtime, entered by the user — never in source or git history.
- Keep the **BYOK model intact**: with the user's own key, requests go directly from the device to the chosen provider. Do not introduce a server that receives or stores user keys. Scowld Premium is the only server path (`web/src/`); it uses Scowld's own key and must keep enforcing the model, context limit and minutes on the server.
- Prefer the existing helpers and components (settings rows, providers, `KeychainManager`, etc.) over new one-off patterns.
- If you change legal text, update the **website Privacy/Terms** pages — startup onboarding links to them.
- Keep user-facing copy concise and consistent with the existing tone.

## Reporting bugs

Good bug reports include:

- What you expected vs. what happened.
- Steps to reproduce.
- Device model and iOS version, and the app version (Settings/About → version).
- Screenshots or screen recordings when relevant.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be respectful and constructive; report unacceptable behavior to [ad13dtu@gmail.com](mailto:ad13dtu@gmail.com).

## Questions

Open a [discussion or issue](https://github.com/apoorvdarshan/scowld/issues), or reach the developer at [ad13dtu@gmail.com](mailto:ad13dtu@gmail.com).
