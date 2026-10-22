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
never erases or resets an existing simulator. It starts booting the simulator,
builds the app and tests (`build-for-testing`) meanwhile, then runs them
(`test-without-building`). Build products are reused under
`~/Library/Developer/Xcode/DerivedData/Scowld-simulator-tests`, and each run keeps
its own `TestResults/<timestamp>/` with `Build.xcresult` and `Tests.xcresult` (the
latter printed at the end). Override `IOS_TEST_DERIVED_DATA`, `IOS_TEST_PACKAGES`
or `IOS_TEST_RESULTS` when needed. Extra arguments go to the test step. The run
fails if either test bundle runs zero tests (`scripts/ci/check_xcresult.py`), and
prints the per-bundle counts.

CI uses the GitHub-hosted `xcode-27` runner (Xcode 27.0). Tests run serially on
one simulator. Results, failure screenshots and logs are kept as the
`ios-test-results` artifact for seven days. Superseded pull-request runs are
cancelled; `main` and release runs never are.

A new simulator keeps setting itself up for 10 to 15 minutes after its first boot.
The costliest part comes minutes in: SpringBoard runs a background task in which
PosterBoard prewarms the wallpaper gallery, rendering 368 wallpaper previews (5 to
12 minutes after boot in the runs measured). On the runner (3 CPUs, 7 GB, no GPU)
that takes every CPU and about 2 GB of memory for one to three minutes; UI tests
that ran meanwhile saw accessibility checks of 4 to 30 seconds and failed at
random.

So CI starts from a simulator that has already been through all of that:

- The workflow's **Prepare the iOS test simulator** job runs next to the tests.
  When the Actions cache has no simulator for this runner image, Xcode build,
  simulator runtime build and device type (the cache key,
  `scripts/ci/ios_simulator.py cache-key`), it runs
  `scripts/ci/prepare-ios-simulator.sh`: it creates the simulator, boots it,
  waits for PosterBoard's prewarm to complete and then for the rest of the
  first boot's work to end (the simulator's processes under half a CPU for three
  minutes, at most ten minutes), turns on PosterBoard's keynote mode, shuts the
  simulator down and saves its device folder (about 1 GB) to the cache. Nothing
  is ever installed on it. Otherwise it only looks the key up. The tests never
  wait for this job, its failure never fails the run, and tag runs skip it.
- Keynote mode, PosterBoard's switch for demo devices, is needed because every
  boot, not only the first, has SpringBoard ask PosterBoard to prewarm the
  gallery again, and it renders all 368 previews again two to eight minutes
  after the boot. With keynote mode on it skips the prewarm. It changes only the
  Lock Screen wallpaper gallery, which no test uses.
- The tests job restores that simulator, moves it into CoreSimulator's device
  set, restarts CoreSimulator's service so it is picked up, and checks that it
  is listed, shut down and usable, with the expected runtime and device type.
  The app is built first (1 to 2 minutes on its own, 5 to 15 next to a boot),
  then the simulator boots and the tests start once `simctl bootstatus` says
  the boot is over.
- When there is no cached simulator, or the restored one is unusable, the
  script falls back to a new simulator: it boots while the app builds, and the
  tests wait for PosterBoard to log the end of its prewarm (usually it has ended
  by the time the build finishes), at most until 15 minutes after the boot. The
  script says how long it waited. Local runs always use a new simulator and skip
  the wait; the slowdown was measured on the CI runner.

A runner image update, a new Xcode or runtime, or a different device type changes
the key, so the next run tests on a new simulator and prepares the next cached one
meanwhile. A cache saved by a pull request is only visible to that pull request;
one saved on `main` is visible to every run.

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

Unit tests never create a `WKWebView`: one starts WebKit's GPU, networking and
web content processes in the test host, which on CI took up to 30 seconds to
launch and stalled the main thread under the tests that ran next. The companion
coordinator's navigation and message handling are checked without a web view.
Messages are compared as JSON, never as encoded strings: `JSONSerialization`
writes a dictionary's keys in an order that can differ between two equal
dictionaries.

UI tests launch the app with `--ui-testing` (plus `--ui-testing-reset`,
`--ui-testing-onboarded`, `--ui-testing-seed-chat`), handled by
`ScowldTestEnvironment`, which compiles to `false` in Release builds and is
inert on devices. Under test the app skips the App Store update check, never
starts a live conversation, never reaches the App Store or Scowld's server, and
never requests microphone or speech-recognition permission (so hands-free
listening never starts). `--ui-testing-reset` removes only Scowld's simulator
preferences, saved chats and provider keys before launch.

UI tests flip a switch with a one-second press, not a tap. Since iOS 26 a switch
flips through a press gesture that starts only once the app has seen the finger
down for a moment. A tap lifts about 50 ms after it lands, so when the app is busy
as the tap arrives (on CI it often is, answering the test's own accessibility
queries), the press never starts and the switch ignores the tap. The other
controls the tests use (buttons, tabs, segmented controls, menus, swipe actions)
respond to a tap even when the app handles it late.

Every UI query (`exists`, `isHittable`, a wait's check) takes a snapshot of the
app's whole accessibility tree, which keeps the app busy for a fraction of a second
on CI. Helpers stop querying once they have their answer: `reveal(_:in:)` checks
whether the element is on screen before each swipe and stops as soon as it is.

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
