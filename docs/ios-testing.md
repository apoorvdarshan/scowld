# iOS testing

The **iOS tests** GitHub Actions workflow builds the Debug app and runs both
`ScowldTests` (unit) and `ScowldUITests` (UI) on an iPhone simulator. It runs for
pull requests and pushes to `main` that touch the app, its tests, the project or
the workflow, on demand, and before every tag release. It never archives,
uploads or submits an app.

## Run locally

On a Mac with Xcode 26 or newer and an iOS 17+ Simulator runtime:

```sh
bash scripts/test-ios.sh
```

The script creates its own simulator ("Scowld CI") and deletes it afterwards; it
never erases or resets an existing simulator. Build products are reused under
`~/Library/Developer/Xcode/DerivedData/Scowld-simulator-tests`, and each run keeps
its own `TestResults/<timestamp>/Tests.xcresult` (printed at the end). Override
`IOS_TEST_DERIVED_DATA`, `IOS_TEST_PACKAGES` or `IOS_TEST_RESULTS` when needed.
The run fails if either test bundle runs zero tests
(`scripts/ci/check_xcresult.py`), and prints the per-bundle counts.

CI uses the GitHub-hosted `xcode-27` runner (Xcode 27.0). Tests run serially on
one simulator. Results, failure screenshots and logs are kept as the
`ios-test-results` artifact for seven days. Superseded pull-request runs are
cancelled; `main` and release runs never are.

## Coverage

- **Unit tests** (`ios/ScowldTests`): emotion-tag parsing and character state,
  lip-sync smoothing, saved chats (Core Data, in memory: create, rename, switch,
  delete, de-duplication, per-chat memory log, context for the next reply), the
  system prompt (persona, custom prompt, reply language, context, vision),
  provider/model/voice/language preferences and their defaults, the provider
  catalogs, every chat provider's request and response handling (Gemini, OpenAI,
  Claude, OpenAI-compatible, Ollama — including vision and error mapping),
  cloud speech-to-text requests and parsing (OpenAI, Groq, Deepgram, AssemblyAI,
  Google), WAV encoding and resampling, the Keychain wrapper, the App Store
  update check, the ElevenLabs request builder, the loopback server that
  serves the bundled companion and proxies text-to-speech, and the native side
  of the companion bridge (a chat message from the page is answered by the
  selected provider and saved; no key or an inactive tab never reaches the
  network; speech without an ElevenLabs key fails without a request), and
  export compliance (the app declares no non-exempt encryption, the bundled
  companion ships no encryption code, and its removed `/share` page is never
  opened).
- **UI tests** (`ios/ScowldUITests`): first-launch onboarding (policy acceptance
  gates the app; shown once), the four tabs, the companion screen's composer
  (send enabled only for text, hands-free toggle remembered), home tips, the
  character name changing the wake phrase, saving a provider, model and key,
  the captions preference, creating/renaming/switching/deleting chats and
  reading a saved transcript, and the About screen.
- There is no paywall or purchase flow to test: Scowld 2.0 removed them.

## Test mode (Debug simulator builds only)

All HTTP in unit tests is answered in-process by a `URLProtocol` stub, so no
provider key or network is used. The unit-test host app stays idle on a black
screen.

UI tests launch the app with `--ui-testing` (plus `--ui-testing-reset`,
`--ui-testing-onboarded`, `--ui-testing-seed-chat`), handled by
`ScowldTestEnvironment`, which compiles to `false` in Release builds and is inert
on devices. Under test the app skips the App Store update check and never
requests microphone or speech-recognition permission (so hands-free listening
never starts). `--ui-testing-reset` removes only Scowld's simulator preferences,
saved chats and provider keys before launch.

UI tests leave out the bundled 3D companion (a WebGL page in a web view) and show
a black placeholder behind the same native composer. CI simulators have no GPU,
so they render it in software: with it loaded, every UI query took 10–60 seconds
and an app relaunch timed out. Its native bridge is covered by unit tests
instead.

Not covered: the companion page's own rendering and JavaScript, real provider
accounts and replies, microphone and camera hardware, and on-device speech
recognition; check those on a device.

Signed Release builds come from the iOS Release workflow (see
[`store/README.md`](../store/README.md)); these Debug simulator tests do not
replace that validation.
