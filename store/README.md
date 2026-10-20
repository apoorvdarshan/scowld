# Store release automation

GitHub Actions builds, signs and uploads Scowld's iOS releases, keeps the App
Store listing in this repository, and creates the GitHub Release. Every App
Store Connect call goes through the pinned App Store Connect CLI (see
[App Store Connect CLI](#app-store-connect-cli-asc)).

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
       IOS_CREATE_VERSION ─► create the tag's App Store version if it is missing (refused,
            without writing, next to an unfinished version or when the tag is not newer)
       any listing/What's New/screenshot/creative asset/review switch ─► read-only preflight:
            the version exists in a state that allows the enabled steps, with every repository
            locale; What's New differs from the live version; screenshots and creative assets
            that can no longer change already match; no in-app product would have to ship with
            it (fails before any upload)
       IOS_UPLOAD_BUILD ─► next build number from App Store Connect (read-only)
                        ─► archive Release ─► verify bundle id/version/build in every .app/.appex
                        ─► cloud-signed export + upload (xcodebuild)
                        ─► wait until THIS build is VALID (read-only; poll 30 s, up to 120 min
                           from upload start)
       IOS_UPLOAD_LISTING / IOS_UPLOAD_WHATS_NEW / IOS_UPLOAD_SCREENSHOTS ─► version listing
       IOS_UPLOAD_CREATIVE_ASSETS ─► header / search results images: upload and review new
                                     ones on their own, place approved ones on every locale
       IOS_SUBMIT_REVIEW ─► no pending in-app products ─► select this run's build, read it back
                         ─► set release type ─► recheck build + selection
                         ─► submit the draft, which holds this version and nothing else
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

### App Store Connect CLI (`asc`)

Every App Store Connect call goes through the
[App Store Connect CLI](https://github.com/rorkai/App-Store-Connect-CLI) (`asc`,
MIT) instead of hand-written API code.
[`scripts/store/asc_cli.py`](../scripts/store/asc_cli.py) is the only place
that runs it:

- It is pinned to one release (`ASC_VERSION`, today 5.15.0) and installed by
  `asc_cli.py install`, which refuses a binary whose SHA-256 differs from the
  pinned value for that platform (`linux_amd64` and `macOS_arm64`). Every job
  that uses it runs `asc_cli.py check`, and every script re-checks the checksum
  of the `asc` on `PATH` before handing it credentials; no environment variable
  can point the scripts at another executable.
- Credentials come only from the `APP_STORE_CONNECT_*` secrets, through asc's
  own environment variables; the keychain and asc config files are bypassed,
  and `ASC_STRICT_AUTH` rejects credentials mixed from several sources.
- Telemetry (`ASC_TELEMETRY_DISABLED`, `DO_NOT_TRACK`) and the skills update
  check are off.
- Checks that must never write run asc read-only (`ASC_READ_ONLY`): the
  preflight, build numbering, the build wait, the listing export, and the whole
  `prepare` job on validation runs. asc refuses a write in that mode before
  sending it (exit 6).
- On failure the error keeps asc's exit code and drops the key and issuer IDs.
  The build wait retries only asc's server-side exit codes (HTTP 5xx, 408, 429)
  and asc calls that time out; auth, usage and not-found errors stop at once.
- The pinned App Store Connect app is `6760672848`: every run first checks that
  it carries the bundle id `com.apoorvdarshan.Scowld`, and the scripts refuse
  any other bundle id.

The binary itself is still exported and uploaded by `xcodebuild`. To move to a
newer asc, change `ASC_VERSION` and both `ASC_SHA256` values from that
release's `asc_<version>_checksums.txt`, then run the store tests; Dependabot
cannot update the pin.

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
| `IOS_UPLOAD_SCREENSHOTS` | The screenshots listed in each locale's `screenshots.json`; a display type whose images are unchanged is left alone |
| `IOS_UPLOAD_CREATIVE_ASSETS` | Product page header and search results images from `store/creative/ios` (see [Creative assets](#creative-assets)). A new image is uploaded to the Asset Library and sent to App Review in a submission of its own; once Apple approves it, a later run places it on every locale's version, or swaps it in for the image placed there. Never changes anything while the version is in a review submission. Off until images are committed |
| `IOS_SUBMIT_REVIEW` | Select this run's processed build and submit the version for App Review. Requires `IOS_UPLOAD_BUILD` |
| `IOS_PUBLIC_RELEASE` | Release automatically after approval. Off = you release it by hand. Requires `IOS_SUBMIT_REVIEW` |
| `IOS_BUILD_POLL_SECONDS` | Poll interval while App Store Connect processes the build, default 30 (10–600) |
| `IOS_BUILD_WAIT_MINUTES` | Total wait counted from upload start (upload + processing), default 120 (10–300) |

Copy names from [`gates.env.example`](gates.env.example). Scowld needs no shared
`STORE_*` switch: the pipeline never creates, changes or submits in-app products
(see [In-app purchases](#in-app-purchases)).

Listing, What's New, screenshots, creative assets and review submission act on
the App Store version named by the tag. With `IOS_CREATE_VERSION` on, the tag run creates a
missing version itself, right before the preflight. Otherwise **create the X.Y.Z
App Store version in App Store Connect first** (App Store tab → **+ Version**,
left in Prepare for Submission) whenever any of those switches is on. Either way
the version needs every language in `store/metadata/ios/`; the pipeline never
adds one. The read-only preflight stops the run before anything is built or
uploaded otherwise. A version created by a run whose later steps fail stays in
Prepare for Submission, and the next run for the same tag reuses it. A
build-only release (`IOS_UPLOAD_BUILD` alone) needs no App Store version.

Prepare checks only the store files the enabled switches use: an invalid or
missing screenshot, creative image, listing or What's New file never blocks a
release that does not upload it. The **Store automation (offline)** workflow still validates all
of them on every pull request and main push that touches them.

Waiting for the build is its own job, so when a later store step fails (for
example App Store Connect changed in between), **Re-run failed jobs** reuses the
processed build instead of waiting again; the store step re-verifies it before
selecting it. Reruns are idempotent once the version is in review too: in Ready
for Review (it already sits in a draft review submission, for example after a
failed submit) the listing and What's New can still change but screenshots and
creative assets cannot; in Waiting for Review (already submitted) nothing can. A step that can no
longer change only confirms App Store Connect already matches the repository, and
fails, before anything is written, if a change would be needed; submission then
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

A draft review submission is submitted only while it holds this version and
nothing else: it is checked when the run picks it up and read again right
before it is submitted, so an item added by hand (or by another tool) stops the
run instead of riding along. Drafts holding creative images belong to those
images' own review and are never used for the version.

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
live ones: [`store/metadata/screenshots/ios/iphone-6.9/`](metadata/screenshots/ios/iphone-6.9) (iPhone 6.9", 1260×2736,
`APP_IPHONE_67`) and [`store/metadata/screenshots/ios/ipad-13/`](metadata/screenshots/ios/ipad-13)
(iPad 13", 2064×2752, `APP_IPAD_PRO_3GEN_129`). Sizes, opacity and the 10-image
limit are checked before any upload; with the screenshot switch on and no
`screenshots.json`, the run fails with that message.

`APPSTORE.md` is reference copy; the pipeline reads only `store/metadata/ios/`.
After editing the listing directly in App Store Connect, re-export it. The
export needs the `APP_STORE_CONNECT_*` credentials in the environment and the
pinned asc on `PATH`, and runs asc read-only:

```bash
python3 scripts/store/asc_cli.py install --dest ~/.local/asc-bin   # once
PATH="$HOME/.local/asc-bin:$PATH" python3 scripts/store/asc_export_listing.py   # newest live version; --version 2.0.1 for another
```

## Creative assets

`IOS_UPLOAD_CREATIVE_ASSETS` keeps the App Store product page header and search
results images in the repository:

```
store/creative/ios/
  header/           # one product page header image: 3840×1646 PNG
  search-results/   # one search results image: 3:2, 1920×1280 to 3840×2560, PNG or JPEG
```

No image is committed yet, so the switch stays off; with it on and no image in
either folder, the run fails before anything reaches App Store Connect. Each
folder takes at most one image, and a slot without one is left alone. Apple's
current sizes are listed by `asc asset-library specs`; Apple's rules for these
images: no prices, website addresses, other platforms or Apple badges, and no
transparency.

An image is matched in the Asset Library by file name and size, so give a
changed image a new file name. Apple reviews each new image on its own (Scowld
already has an approved version), and a later run places it on every repository
locale's version once it is approved, or swaps it in for the image placed there;
a rejected image stops the run with Apple's reason. A retry finishes the image
review submission an earlier attempt left behind instead of starting another.
While the version is in a review submission (Ready for Review or Waiting for
Review) nothing is uploaded, sent to App Review or placed: the run only confirms
that every image is already placed or still in review.

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
| [`scripts/store/asc_cli.py`](../scripts/store/asc_cli.py) | Installs the pinned, checksum-verified `asc` and runs it (credentials, read-only mode, telemetry off, redacted errors) |
| [`scripts/store/asc_release.py`](../scripts/store/asc_release.py) | Version creation (`--create-version`), listing, What's New, screenshots, creative assets, build selection, review submission (`--dry-run` = local checks only, `--preflight` = read-only App Store Connect checks); every call through `asc` |
| [`scripts/store/asc_export_listing.py`](../scripts/store/asc_export_listing.py) | Export of the live listing into `store/metadata/ios/` (asc read-only) |
| [`scripts/store/test_ios_release.py`](../scripts/store/test_ios_release.py) | Offline tests against a fake App Store Connect behind `asc`: disabled/invalid switches, tag mismatch, validation mode, export compliance (missing, unknown, `YES` without a code, archived `Info.plist`), version creation (missing, existing, unfinished or newer version, other app), build wait timeout/failure/ambiguity/mismatch/old build/missing upload time, selection read-back, preflight, listing, plain-text What's New, screenshots (manifest order, processing), creative assets, submission and the draft's items, reruns in review, the asc runner (credentials, read-only, redaction, pinned checksum), the listing export, printed switches, release notes, log redaction |
| [`scripts/store/print_gates.py`](../scripts/store/print_gates.py) | Prints the switches in the run log; an invalid value shows as `INVALID` |
| [`scripts/store/redact_logs.py`](../scripts/store/redact_logs.py) | Removes the App Store Connect key and issuer IDs from failed-build logs before they become an artifact |
| [`scripts/release_notes.py`](../scripts/release_notes.py) | GitHub Release notes from the matching `RELEASE_NOTES.md` section (else GitHub's generated notes; two sections for one tag fail the release) |

The jobs that call App Store Connect run the store scripts on Python 3.13
(`actions/setup-python`) and install the pinned asc first: `prepare`,
`wait-for-build` and `app-store-connect` in the release workflow. The scripts
need only the standard library, so there is no Python dependency to install.
The other Python steps run on the runner's own `python3`:
`ios_release.py export-compliance`, `redact_logs.py` (and the step that writes
the `.p8` key) in the `build` job, and `print_gates.py` and `release_notes.py`
in `github-release`. Steps that talk to App Store Connect run unbuffered
(`python3 -u`), so the build wait's progress shows in the live log.

The **Store automation (offline)** workflow installs and checks the pinned asc
the same way (so a pin that no longer downloads or matches its checksum fails
on the pull request), runs the offline tests, and validates the whole committed
listing, screenshots and release notes on every pull request and main push that
touches these files. It never calls App Store Connect.

Environment flags read by `asc_release.py` (set by `ios-release.yml` from the
resolved switches): `UPLOAD_LISTING`, `UPLOAD_WHATS_NEW`, `UPLOAD_SCREENSHOTS`,
`UPLOAD_CREATIVE_ASSETS`, `SUBMIT_IOS_REVIEW`, `PUBLIC_RELEASE`, and
`CREATE_IOS_VERSION` (read only with `--create-version`). `ASC_READ_ONLY` makes
every asc call read-only.

## How to release

1. Bump `MARKETING_VERSION` (and, if you like, `CURRENT_PROJECT_VERSION`; the
   pipeline uses the higher of it and the last App Store Connect build + 1).
2. Update `store/metadata/ios/<locale>/whats_new.txt` (plain text), and add one
   `## vX.Y.Z` section to `RELEASE_NOTES.md` for the GitHub Release (optional).
3. Run **iOS Release → Run workflow** with `marketing_version` = the new version
   to validate signing (nothing is uploaded).
4. If any listing, What's New, screenshot, creative asset or review switch will
   be on, the X.Y.Z App Store version must exist. With `IOS_CREATE_VERSION` on, the tag run
   creates it; otherwise create it in App Store Connect first (App Store tab →
   **+ Version**; leave it in Prepare for Submission).
5. Turn on only the switches you want, then push the tag `vX.Y.Z`. Leave
   `IOS_SUBMIT_REVIEW` and `IOS_PUBLIC_RELEASE` off until you intend that release.

## Local dry-run

```bash
python3 -m unittest scripts/store/test_ios_release.py
UPLOAD_LISTING=true UPLOAD_WHATS_NEW=true UPLOAD_SCREENSHOTS=true \
  python3 scripts/store/asc_release.py --dry-run
GITHUB_EVENT_NAME=push GITHUB_REF_NAME=v2.0.1 python3 scripts/store/ios_release.py gates
python3 scripts/release_notes.py v2.0.1
```
