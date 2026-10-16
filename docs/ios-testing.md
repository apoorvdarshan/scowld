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
  delete, de-duplication, per-chat memory log, context for the next
  conversation), the system prompt (spoken persona without emotion tags, custom
  prompt, reply language, saved chat, camera note),
  provider/model/voice/language preferences and their defaults (a removed
  provider falls back to Gemini), the one-time cleanup of removed providers'
  keys and settings, the provider catalog (models, voices, camera support,
  Keychain keys that match earlier versions), each provider's live protocol
  (Gemini Live, OpenAI Realtime and xAI Grok Voice: connection request, session
  setup, audio, text and image input, server events) and the Scowld Premium wire
  (`LiveWireTests`: Gemini Live through Scowld's relay, and its notices), the
  live session (setup before input, message order, only the latest seconds of
  speech wait for the connection, Gemini's resumption handle, a dropped
  connection reported once, closing, truncate), live conversations over a
  scripted socket and fake audio (nothing connects without a key, microphone
  problems, replies with lip sync and captions saved after the user's words,
  barge-in on OpenAI and Gemini, camera frames per provider and none while the
  camera is off or with xAI, provider failures, idle and connection timeouts,
  audio interruptions; with Scowld Premium, `LiveConversationTests` cover
  connecting through `wss://scowld.xyz/api/live` with the `X-Scowld-User`
  header, no connection without an account ID, and the out-of-minutes and
  unavailable notices), Scowld Premium in the app (`PremiumTests`, against a
  fake store: balance decoding, prices, store purchases including cancelled,
  pending and failed ones, restore, which connection new users start with while
  key holders keep their key, and the plan and minute pack catalog matching
  Scowld's server), the Keychain wrapper, the App Store update check, the
  loopback server that serves the bundled companion (no speech proxy remains),
  the native side of the companion bridge (the page's old chat and speech
  requests are ignored and never reach the network; no camera frame while the
  camera is off), and export compliance (the app declares no non-exempt
  encryption, the bundled companion ships no encryption code, and its removed
  `/share` page is never opened).
- **UI tests** (`ios/ScowldUITests`): first-launch onboarding (policy acceptance
  gates the app; shown once), the four tabs, the companion screen's composer
  (live button only, with no text field; camera off until turned on; hands-free
  toggle remembered), new users being offered Scowld Premium (the hint, and the
  mic opens the plans) and switching to their own key, the missing-key hint that
  opens Settings and goes away once a key is saved, the Premium settings and the
  minute packs screen, home tips, the character name changing the wake phrase,
  saving a live provider, model, voice and key (with no separate speech-to-text
  or text-to-speech settings), the note that Grok Voice can't see the camera,
  the captions preference, creating/renaming/switching/deleting chats and
  reading a saved transcript, and the About screen.
- UI tests never reach the App Store or Scowld's server, so no prices load in
  them and nothing can be bought; the plans screen is checked without prices.
- The Worker's Premium logic has its own Vitest tests in
  [`web/tests/premium.test.js`](../web/tests/premium.test.js) (plans, trial,
  monthly minutes, packs, per-purchase usage, the fixed setup, and the metering
  relay); see the README's website checks.

## Test mode (Debug simulator builds only)

Live conversations in unit tests run over a scripted socket (`FakeLiveSocket`)
with audio that needs no hardware (`FakeLiveAudio`), and any HTTP is answered
in-process by a `URLProtocol` stub, so no provider key, network, microphone or
speaker is used. The unit-test host app stays idle on a black screen.

UI tests launch the app with `--ui-testing` (plus `--ui-testing-reset`,
`--ui-testing-onboarded`, `--ui-testing-seed-chat`), handled by
`ScowldTestEnvironment`, which compiles to `false` in Release builds and is
inert on devices. Under test the app skips the App Store update check, never
starts a live conversation, never reaches the App Store or Scowld's server, and
never requests microphone or speech-recognition permission (so hands-free
listening never starts). `--ui-testing-reset` removes only Scowld's simulator
preferences, saved chats and provider keys before launch.

UI tests leave out the bundled 3D companion (a WebGL page in a web view) and show
a black placeholder behind the same native composer. CI simulators have no GPU,
so they render it in software: with it loaded, every UI query took 10–60 seconds
and an app relaunch timed out. Its native bridge is covered by unit tests
instead.

For screenshots, a Debug simulator build also accepts `--preview-tab
chat|chats|settings|about|paywall|minutes`, which opens that tab (or the Premium
plans or minute packs screen) at launch with the companion loaded and without
prompting for microphone or speech-recognition permission.

Not covered: the companion page's own rendering and JavaScript, real provider
accounts, real App Store purchases and Scowld's live server, live connections
and replies, microphone, speaker and camera hardware, and on-device speech
recognition; check those on a device.

Signed Release builds come from the iOS Release workflow (see
[`store/README.md`](../store/README.md)); these Debug simulator tests do not
replace that validation.
