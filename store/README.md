# Store release automation

GitHub Actions builds, signs and uploads Scowld's iOS releases, keeps the App
Store listing in this repository, and creates the GitHub Release.

**Nothing reaches the App Store unless its switch is on.** Every switch is off
until it is set as a repository Variable. A `v*` tag runs
[`ios-release.yml`](../.github/workflows/ios-release.yml); a manual **Run
workflow** only validates.

**Xcode Cloud was removed on 2026-10-14.** Scowld's Xcode Cloud "Default"
workflow (which `v*` tags also started) and its Xcode Cloud product were deleted
in App Store Connect after this pipeline validated. Xcode Cloud triggers live in
App Store Connect, not in this repository, so no switch here could stop them.
Never re-create an Xcode Cloud workflow for this app, or two pipelines would
build and upload the same tag.

## iOS release flow (`v*` tag)

```
vX.Y.Z tag ─► iOS unit + UI tests ─► offline release-script tests
           ─► resolve switches (the tag must equal MARKETING_VERSION exactly)
           ─► check only the store files the enabled switches use, and this tag's
              RELEASE_NOTES.md section (at most one)
  └─ IOS_RELEASE_AUTOMATION off ─► GitHub Release only
  └─ on:
       IOS_UPLOAD_SCREENSHOTS ─► stage RGB copies of the screenshots (no alpha, well-formed file)
       IOS_UPLOAD_CREATIVE_ASSETS ─► check the header / search results images
                                     (size, format, no alpha, well-formed file)
       IOS_CREATE_VERSION ─► create the tag's App Store version if it is missing (refused,
            without writing, next to an unfinished version or when the tag is not newer)
       any listing/What's New/screenshot/creative/review switch ─► read-only preflight: the
            version exists in a state that allows the enabled steps, with every repository
            locale; What's New differs from the live version; screenshots that can no longer
            change already match; no in-app product would have to ship with it; the version's
            draft is usable (IOS_SUBMIT_REVIEW); the images' Asset Library state allows the
            creative step (IOS_UPLOAD_CREATIVE_ASSETS) (fails before any upload)
       IOS_UPLOAD_BUILD ─► next build number from App Store Connect
                        ─► archive Release ─► verify bundle id/version/build in every .app/.appex
                        ─► cloud-signed export + upload
                        ─► wait until THIS build is VALID (poll 30 s, up to 120 min from upload start)
       IOS_SUBMIT_REVIEW ─► pick and check the version's draft review submission
                            (read-only, before any write) and reserve it
       IOS_UPLOAD_LISTING / IOS_UPLOAD_WHATS_NEW / IOS_UPLOAD_SCREENSHOTS ─► version listing
       IOS_UPLOAD_CREATIVE_ASSETS ─► new images: Asset Library upload, then App Review
                                     in a submission of their own
                                  ─► approved images: placed on the version (en-US)
       IOS_SUBMIT_REVIEW ─► no pending in-app products ─► select this run's build, read it back
                         ─► set release type ─► recheck build + selection ─► submit for review
  └─ GitHub Release (only if every enabled step succeeded)
       ─► tagged source archive + Sigstore bundle + SHA-256, build-provenance attestation
```

Each GitHub Release carries `scowld-X.Y.Z-source.tar.gz` (`git archive` of the
tag), its keyless Sigstore bundle (`.sigstore.json`) and checksum (`.sha256`),
plus a GitHub build-provenance attestation. Verify a download with:

```bash
cosign verify-blob scowld-X.Y.Z-source.tar.gz \
  --bundle scowld-X.Y.Z-source.tar.gz.sigstore.json \
  --certificate-identity-regexp '^https://github.com/apoorvdarshan/scowld/\.github/workflows/ios-release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
gh attestation verify scowld-X.Y.Z-source.tar.gz --repo apoorvdarshan/scowld
```

A manual **Run workflow** (`workflow_dispatch`) is a validation run: it archives,
signs, exports and validates the IPA with App Store Connect (`altool
--validate-app`), and never uploads, edits the listing, submits or creates a
GitHub Release. Apple refuses versions it has already approved, so fill in the
optional **marketing_version** input with the next version (for example `2.0.2`
while 2.0.1 is live); the build is validated as that version without changing
the project.

Submission stops instead of continuing when the build times out, fails
processing, is expired, is ambiguous, belongs to another app or version, was
uploaded before this run, or is not the build selected on the version. An older
build is never substituted. The wait covers build processing only — not App
Review or the public release.

## Switches

Repository **Variables** (Settings → Secrets and variables → Actions →
Variables). Missing means off. Any value other than
`true/false/yes/no/on/off/1/0` fails the run, even when the master switch is off.

| Variable | When `true` |
|----------|-------------|
| `IOS_RELEASE_AUTOMATION` | Master switch. When off, every iOS store operation below is skipped; the tag still runs the tests and creates the GitHub Release |
| `IOS_CREATE_VERSION` | Create the tag's App Store version (Prepare for Submission) when App Store Connect does not have it, before the preflight. An existing version is left alone. Refuses, before anything is built and without writing, when another version is still on its way to the store (anything but Ready for Distribution, replaced or removed), the tag is not newer than every existing version, or the bundle id resolves to another app. Tag runs only |
| `IOS_UPLOAD_BUILD` | Build, sign and upload the binary to App Store Connect, then wait until this build is processed |
| `IOS_UPLOAD_LISTING` | App name, subtitle and privacy policy URL (app info), and description, keywords, promotional text, marketing and support URLs (version) — only fields that differ from App Store Connect are sent |
| `IOS_UPLOAD_WHATS_NEW` | What's New, as plain text: Markdown (`**bold**`, backticks, `[links](…)`, `#` headings) is refused because the App Store shows it literally. Refused if it is identical to the live version's text |
| `IOS_UPLOAD_SCREENSHOTS` | The screenshots listed in each locale's `screenshots.json` (6.9" iPhone, 13" iPad, iPhone Duo and Apple Watch sets), uploaded as RGB copies; a display type whose images are unchanged is left alone (see [Listing source of truth](#listing-source-of-truth)) |
| `IOS_UPLOAD_CREATIVE_ASSETS` | Product page header and search results images from `store/creative/ios/`, checked (size, format, no alpha) before the build. A new image is uploaded to the Asset Library once and sent to App Review in a submission of its own; an approved image is placed on the version's en-US page while the version can be edited (see [Header and search results images](#header-and-search-results-images-ios)). No image is committed yet, so leave it off. Off: never read |
| `IOS_SUBMIT_REVIEW` | Select this run's processed build and submit the version for App Review. Requires `IOS_UPLOAD_BUILD` |
| `IOS_PUBLIC_RELEASE` | Release automatically after approval. Off = you release it by hand. Requires `IOS_SUBMIT_REVIEW` |
| `IOS_BUILD_POLL_SECONDS` | Poll interval while App Store Connect processes the build, default 30 (10–600) |
| `IOS_BUILD_WAIT_MINUTES` | Total wait counted from upload start (upload + processing), default 120 (10–300) |

Copy names from [`gates.env.example`](gates.env.example). Scowld needs no shared
`STORE_*` switch: the pipeline never creates, changes or submits in-app products
(see [In-app purchases](#in-app-purchases)).

Listing, What's New, screenshots, creative assets and review submission act on
the App Store version named by the tag. With `IOS_CREATE_VERSION` on, the tag run
creates a missing version itself, right before the preflight. Otherwise **create
the X.Y.Z App Store version in App Store Connect first** (App Store tab → **+
Version**, left in Prepare for Submission) whenever any of those switches is on. Either way
the version needs every language in `store/metadata/ios/`; the pipeline never
adds one. The read-only preflight stops the run before anything is built or
uploaded otherwise. A version created by a run whose later steps fail stays in
Prepare for Submission, and the next run for the same tag reuses it. A
build-only release (`IOS_UPLOAD_BUILD` alone) needs no App Store version.

Prepare checks only the store files the enabled switches use: an invalid or
missing screenshot, creative image, listing or What's New file never blocks a
release that does not upload it. The **Store automation (offline)** workflow
still validates all of them on every pull request and main push that touches
them.

Waiting for the build is its own job, so when a later store step fails (for
example App Store Connect changed in between), **Re-run failed jobs** reuses the
processed build instead of waiting again; the store step re-verifies it before
selecting it. Header and search results images already in the Asset Library are
never uploaded again, an image already placed is left alone, and an interrupted
image review is finished in the draft it left (see
[Header and search results images](#header-and-search-results-images-ios)).
Reruns are idempotent once the version is in review too: in Ready for Review (it
already sits in a draft review submission, for example after a failed submit)
the listing and What's New can still change but screenshots and creative
placements cannot; in Waiting for Review (already submitted) nothing can. A step
that can no longer change only confirms App Store Connect already matches the
repository, and fails, before anything is written, if a change would be needed; submission then
only confirms review holds this run's build. Tag runs share one concurrency group
with `queue: max`, so releases run one at a time and no waiting release run is
ever cancelled by a newer one; manual validation runs have their own group and
never block a release.

When the build job fails, its logs are kept as the `ios-release-logs-<run>-<attempt>`
artifact (7 days). Artifacts are not masked like the job log, so first
[`redact_logs.py`](../scripts/store/redact_logs.py) replaces the App Store Connect
key ID and issuer ID with `<ASC_KEY_ID>` / `<ASC_ISSUER_ID>` in every file,
binary or text, UTF-8 or UTF-16. A file it cannot rewrite is dropped, and if even
that fails, no artifact is uploaded.

### In-app purchases

Scowld sells optional Scowld Premium subscriptions (weekly and yearly, the yearly
plan with a free trial), consumable minute packs, and optional one-time tips. All
of them are App Store in-app purchases managed with RevenueCat; Premium minutes
are enforced by the Worker in [`web/`](../web) (see the main README). Using your
own API key needs no purchase.

The pipeline does not submit in-app products. If App Store Connect holds a
product that would have to go to review with a version (`READY_TO_SUBMIT`,
`DEVELOPER_REJECTED`, `READY_FOR_REVIEW`), `IOS_SUBMIT_REVIEW` stops before
anything is uploaded or changed (in the preflight, and again before the listing
step). Submit those products in App Store Connect, or add a product catalog and
the Fud AI product-submission step, then rerun.

## Export compliance

The app declares its export compliance answer in its build settings
(`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in Debug and Release, so
every build's `Info.plist` carries `ITSAppUsesNonExemptEncryption = false`).
Without it, App Store Connect asks about each build by hand, and review
submission fails with `usesNonExemptEncryption` missing.

`NO` is right because Scowld only uses exempt encryption: HTTPS and the live
voice WebSockets (Gemini Live, OpenAI Realtime, xAI Grok Voice, and Scowld
Premium's relay at `wss://scowld.xyz/api/live`) through Apple's networking, the
Keychain for provider keys, and Apple's system crypto (RevenueCat's hashing and
signature checks, the companion page's WebCrypto SHA-256 digests). If the app ever adds its own
encryption, set it to `YES` and add
`INFOPLIST_KEY_ITSEncryptionExportComplianceCode` with the code App Store
Connect issues for the app's encryption documentation.

The prebuilt Amica page (`ios/Scowld/Resources/amica.bundle`) used to ship a
JavaScript copy of Node's `crypto` module (AES, DES, Diffie-Hellman, ECDH, RSA,
PBKDF2) in one chunk, `fec483df-29d484622c428254.js`. Only Amica's `/share` page
loaded it, and only to hash a file before publishing an avatar to Amica's online
store. So that the `NO` answer leaves no doubt, the chunk was removed and the
app's web view cancels every navigation to `/share` (when the chunk fails to
load, the page's router falls back to a full navigation, which the web view
blocks). The only effect: you cannot publish avatars to Amica's online store from
the app. `CompanionExportComplianceTests` fail if any encryption code returns to
the bundle, the block is lost, or the app stops declaring `NO`.

Release and validation runs check the answer twice: `ios_release.py gates` reads
each configuration (Debug and Release) of the app target before anything is
built, and `ios_release.py export-compliance` reads the archived app's
`Info.plist` right after the archive. A configuration without the key, an
unknown value, different answers per configuration, or `YES` without the code
fails the run; values on the test targets do not count.

## Listing source of truth

`store/metadata/ios/<locale>/` holds the live App Store listing, exported from
App Store Connect with [`asc_export_listing.py`](../scripts/store/asc_export_listing.py)
(read-only). Only `en-US` exists today.

| File | App Store Connect field | Limit |
|------|-------------------------|-------|
| `name.txt` | App name (app info) | 30 |
| `subtitle.txt` | Subtitle (app info) | 30 |
| `privacy_url.txt` | Privacy policy URL (app info) | URL |
| `description.txt` | Description | 4000 |
| `keywords.txt` | Keywords | 100 |
| `promotional_text.txt` | Promotional text | 170 |
| `marketing_url.txt` / `support_url.txt` | Marketing / support URL | URL |
| `whats_new.txt` | What's New — update it for every release; plain text, no Markdown | 4000 |
| `screenshots.json` | Screenshot sets: display type → ordered image paths | 10 per set |

An empty or missing text file leaves that field unchanged. `screenshots.json`
points at App Store-ready images already in the repository — today exactly the
live ones: [`store/metadata/screenshots/ios/iphone-6.9/`](metadata/screenshots/ios/iphone-6.9) (iPhone 6.9", 1320×2868,
`APP_IPHONE_67`) and [`store/metadata/screenshots/ios/ipad-13/`](metadata/screenshots/ios/ipad-13)
(iPad 13", 2064×2752, `APP_IPAD_PRO_3GEN_129`). Sizes and the 10-image limit are
checked before any upload; with the screenshot switch on and no
`screenshots.json`, the run fails with that message.

Screenshots are uploaded from RGB copies in a temporary folder, never from the
committed files, which are only read. App Store Connect refuses a PNG that
stores an alpha channel, even when every pixel is opaque. A PNG that already is
RGB without alpha (every committed screenshot today) is its own RGB copy: it is
copied byte for byte, so it still matches the checksum of the set App Store
Connect holds and an unchanged set is never uploaded again. Any other PNG has its
transparent pixels laid over black once and keeps its colour profile (ICC
profile, sRGB, gamma and chromaticity chunks); sizes never change. That takes
Pillow from the store tooling; without it the file is copied as it is, so one
that stores alpha stops the run. Right before upload, every copy must be a PNG
that stores no alpha (neither PNG colour type 4 or 6 nor a `tRNS` chunk) and is
well formed (complete chunks with matching CRCs, image data of the size its
header gives, a final `IEND`), or a readable JPEG, or the run stops before
anything is sent. The dry run stages the copies the same way.

iPhone Duo screenshots go in an `APP_IPHONE_DUO` set: one set takes both screens,
outer 1398×2034 and inner 2007×2853 (or landscape). `APP_IPHONE_DUO` is not in
Apple's OpenAPI spec yet, but App Store Connect accepts it. Apple Watch
screenshots are listed under `"watch"`, for example from
`store/metadata/screenshots/ios/watch/`; each frame's size picks its set: 416×496
`APP_WATCH_SERIES_10`, 422×514 or 410×502 `APP_WATCH_ULTRA`, 396×484
`APP_WATCH_SERIES_7`, 368×448 `APP_WATCH_SERIES_4`, 312×390 `APP_WATCH_SERIES_3`;
any other size fails before upload. The Watch sets go after the others. Like every
set, a Watch set is replaced only when its files differ, and only compared while
the version is in a review submission. Sets the manifest does not list (such as an
`APP_WATCH_ULTRA` set uploaded by hand) are left alone; remove them in App Store
Connect if they should go. Neither set exists for Scowld yet; adding the images
and listing them in `screenshots.json` is all it takes.

`APPSTORE.md` is reference copy; the pipeline reads only `store/metadata/ios/`.
After editing the listing directly in App Store Connect, re-export it:

```bash
python3 scripts/store/asc_export_listing.py   # newest live version; --version 2.0.1 for another
```

## Header and search results images (iOS)

With `IOS_UPLOAD_CREATIVE_ASSETS` on, the images in `store/creative/ios/` go to
the App Store product page: `header/` takes one PNG of exactly 3840×1646, and
`search-results/` one PNG or JPEG in 3:2, from 1920×1280 to 3840×2560. Neither
may store alpha. `prepare` checks sizes, formats, alpha and that each file is a
complete, well-formed image before anything is built, then (read-only) each
image's Asset Library state the way the store step plans it, so an image the
version cannot take now fails before the build. A slot without an image is left
alone (other files in the folders, such as their README, do not count); with
neither image the run fails. No image is committed for Scowld yet, so leave the
switch off until one is.

They live in the app's Asset Library and are reviewed on their own, apart from
the version:

1. An image is uploaded once, matched by file name and size. A reservation an
   interrupted upload left in `AWAITING_UPLOAD` (like a failed or archived image)
   does not count, and the image is uploaded again. To change an image, commit
   it under a new file name. An image App Review rejected stops the run until it
   is replaced.
2. A new image goes to App Review in a review submission of its own, never the
   version's draft. A draft an earlier attempt left holding only some of the
   images is finished first, else an empty draft, else a new one is created, so
   re-runs never pile up drafts. The run submits it only when it holds exactly
   these images.
3. Once Apple approves an image, the run places it on the version's en-US
   localization (`POST /v1/appAssetLibraryPlacements`, placement group
   `DEFAULT_PROFILE`), only while the version can be edited (Prepare for
   Submission or rejected). An image already placed there is left alone; another
   image in the same slot is replaced in the same request. Approval takes a while,
   so a new image is usually placed by the next release's run.

While the version is in a review submission (`READY_FOR_REVIEW` or
`WAITING_FOR_REVIEW`), nothing is uploaded, reviewed or placed: an image that
still needs uploading or review fails the run, and an approved image waits for
a later run.

With `IOS_SUBMIT_REVIEW` on, the run picks the version's draft review submission
before anything is written: the draft that already holds the version, else the
one draft holding no app version (more than one is ambiguous and stops the run),
never one holding header or search results images. The draft may hold nothing
but this version. That draft is reserved for the version, so image reviews never
take it. A `READY_FOR_REVIEW` version that no such draft holds stops the run in
`prepare`, before the build, and the store step checks it again before its first
write.

## Secrets

| Secret | Used for |
|--------|----------|
| `APP_STORE_CONNECT_API_KEY_ID` | Admin-role App Store Connect API key: build numbers, cloud-managed distribution signing, upload, build readiness, listing, creative assets, review |
| `APP_STORE_CONNECT_ISSUER_ID` | API key issuer |
| `APP_STORE_CONNECT_API_KEY_P8` | API private key (`.p8` body) |
| `IOS_DEV_SIGNING_P12_BASE64` | CI Apple Development identity (base64 `.p12`; certificate "Apple Development: Created via API", ID `NVNGDQGCKK`, expires 2027-10-14) that signs the archive. App Store signing happens at export with Apple's cloud-managed distribution certificate |
| `IOS_DEV_SIGNING_P12_PASSWORD` | Password for that `.p12` |

### CI certificate rotation

The same CI identity signs the archives of Fud AI, Verceltics, Abysm, iitjee,
Quit All, Scowld and Sesslet: Apple allows one API-created development
certificate per API key. Its private key exists only in those repositories'
`IOS_DEV_SIGNING_*` secrets. Before it expires (2027-10-14) or after it is
revoked: revoke it (App Store Connect API, `DELETE /v1/certificates/<id>`),
create a new one (`certificateType: DEVELOPMENT`), and replace both
`IOS_DEV_SIGNING_*` secrets in every one of those repositories.

## Scripts

| Script | Role |
|--------|------|
| [`scripts/store/ios_release.py`](../scripts/store/ios_release.py) | Switches (`gates`), tag/version check, export compliance (before the build and in the archived app), build number, wait for this run's build |
| [`scripts/store/asc_release.py`](../scripts/store/asc_release.py) | Version creation (`--create-version`), listing, What's New, 6.9" iPhone / 13" iPad / iPhone Duo / Apple Watch screenshots (uploaded as RGB copies), header and search results images, build selection, review submission (`--dry-run` = local checks only, `--preflight` = read-only App Store Connect checks) |
| [`scripts/store/asc_export_listing.py`](../scripts/store/asc_export_listing.py) | Read-only export of the live listing into `store/metadata/ios/` |
| [`scripts/store/test_ios_release.py`](../scripts/store/test_ios_release.py) | Offline tests: disabled/invalid switches, tag mismatch, validation mode, export compliance (missing, unknown, `YES` without a code, archived `Info.plist`), version creation (missing, existing, unfinished or newer version, other app), build wait timeout/failure/ambiguity/mismatch/old build/missing upload time, selection read-back, token refresh, ES256 token signing (needs the store tooling), preflight, listing, plain-text What's New, screenshots, the screenshot alpha guard and RGB copies (needs the store tooling), Apple Watch sets, header and search results images (upload, review, placement, drafts), submission, reruns in review, printed switches, release notes, log redaction |
| [`scripts/store/print_gates.py`](../scripts/store/print_gates.py) | Prints the switches in the run log; an invalid value shows as `INVALID` |
| [`scripts/store/redact_logs.py`](../scripts/store/redact_logs.py) | Removes the App Store Connect key and issuer IDs from failed-build logs before they become an artifact |
| [`scripts/release_notes.py`](../scripts/release_notes.py) | GitHub Release notes from the matching `RELEASE_NOTES.md` section (else GitHub's generated notes; two sections for one tag fail the release) |

The jobs that install the store tooling run on Python 3.13
(`actions/setup-python`): `prepare`, `wait-for-build` and `app-store-connect`
in the release workflow, and the **Store automation (offline)** workflow. They
install [`requirements-store.txt`](../requirements-store.txt) (PyJWT and
Pillow, hash-pinned, `--require-hashes`); `prepare` installs it before its local
file check, which stages the RGB screenshot copies. The lock targets that Python
only: regenerate it from `requirements-store.in` with the `uv` command in it. Dependabot proposes
updates weekly and also writes the lock without `--universal` markers. The other
Python steps need only the standard library and run on the runner's own
`python3`: `ios_release.py export-compliance`, `redact_logs.py` (and the step
that writes the `.p8` key) in the `build` job, and `print_gates.py` and
`release_notes.py` in `github-release`.
Steps that talk to App Store Connect run unbuffered (`python3 -u`), so the build
wait's progress shows in the live log.

The **Store automation (offline)** workflow installs `requirements-store.txt`
the same way, runs the offline tests (including signing a throwaway App Store
Connect token with that PyJWT and flattening screenshots with that Pillow, tests
that fail there instead of skipping) and validates the whole committed listing,
screenshots, header and search results images and release notes on every pull
request and main push that touches these files. A Dependabot update to the
store tooling is therefore proven before it can reach a release.

Environment flags read by `asc_release.py` (set by `ios-release.yml` from the
resolved switches): `UPLOAD_LISTING`, `UPLOAD_WHATS_NEW`, `UPLOAD_SCREENSHOTS`,
`UPLOAD_CREATIVE_ASSETS`, `SUBMIT_IOS_REVIEW`, `PUBLIC_RELEASE`, and
`CREATE_IOS_VERSION` (read only with `--create-version`).

## How to release

1. Bump `MARKETING_VERSION` (and, if you like, `CURRENT_PROJECT_VERSION`; the
   pipeline uses the higher of it and the last App Store Connect build + 1).
2. Update `store/metadata/ios/<locale>/whats_new.txt` (plain text), and add one
   `## vX.Y.Z` section to `RELEASE_NOTES.md` for the GitHub Release (optional).
3. Run **iOS Release → Run workflow** with `marketing_version` = the new version
   to validate signing (nothing is uploaded).
4. If any listing, What's New, screenshot, creative asset or review switch will
   be on, the X.Y.Z App Store version must exist. With `IOS_CREATE_VERSION` on,
   the tag run creates it; otherwise create it in App Store Connect first (App
   Store tab → **+ Version**; leave it in Prepare for Submission).
5. Turn on only the switches you want, then push the tag `vX.Y.Z`. Leave
   `IOS_SUBMIT_REVIEW` and `IOS_PUBLIC_RELEASE` off until you intend that release.

## Local dry-run

```bash
python3 -m unittest scripts/store/test_ios_release.py
UPLOAD_LISTING=true UPLOAD_WHATS_NEW=true UPLOAD_SCREENSHOTS=true \
  python3 scripts/store/asc_release.py --dry-run
UPLOAD_CREATIVE_ASSETS=true python3 scripts/store/asc_release.py --dry-run   # once an image is committed
GITHUB_EVENT_NAME=push GITHUB_REF_NAME=v2.0.1 python3 scripts/store/ios_release.py gates
python3 scripts/release_notes.py v2.0.1
```
