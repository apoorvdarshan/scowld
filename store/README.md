# Store releases

Scowld's App Store releases run on
[apoorvdarshan/store-release](https://github.com/apoorvdarshan/store-release), a
shared set of reusable workflows and Python tooling. Scowld's own release scripts
(`scripts/store/` at `5283a48`) moved there unchanged as its `scowld` flow, so a
release does exactly what this repository's pipeline did. Two thin caller workflows
pin store-release by commit SHA, with the version in a `# vX.Y.Z` comment (v0.3.0
today):

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| [`ios-release.yml`](../.github/workflows/ios-release.yml) | `vX.Y[.Z]` tag | release run; the tag must equal `MARKETING_VERSION` exactly |
| | **Run workflow** | validation only: archive, cloud-signed export and App Store Connect validation of the IPA (`altool --validate-app`), plus a read-only store plan. Never uploads, edits the listing, submits or creates a GitHub Release |
| [`store-checks.yml`](../.github/workflows/store-checks.yml) | pull requests and `main` pushes that touch store files, **Run workflow** | checks the listing, What's New, screenshots, header and search results images and release notes, [`store-release.toml`](store-release.toml) and the callers against the pinned version, with every switch on. Never uploads |

**Nothing reaches the App Store unless its switch is on**, and merging never
releases: only a tag push does. The callers are rendered by store-release
(`run.py callers render`); Store checks fails when one is edited by hand or pins
anything but a store-release release. Dependabot moves both pins to a new
store-release release in one PR of its own, seven days after it is published.

How the pipeline behaves is documented in store-release (v0.3.0):
[Scowld's flow](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/flows.md#scowld-iosflow--scowld),
[switches](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/switches.md),
[secrets](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/secrets.md),
[jobs and checks](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/workflows.md),
[store plan](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/plan.md),
[re-runs](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/rerun.md),
[verifying downloads](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/verification.md),
[the config file](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/config.md)
and [how a new release reaches this repository](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/release-process.md#how-apps-receive-a-release).
This file keeps only Scowld's own facts.

**Xcode Cloud was removed on 2026-10-14.** Scowld's Xcode Cloud "Default" workflow
(which `v*` tags also started) and its Xcode Cloud product were deleted in App Store
Connect after the GitHub pipeline validated. Xcode Cloud triggers live in App Store
Connect, not in this repository, so no switch here could stop them. Never re-create
an Xcode Cloud workflow for this app, or two pipelines would build and upload the
same tag.

## What this repository keeps

- [`store-release.toml`](store-release.toml): the `scowld` flow, where the store files
  are, and Scowld's fixed identities: bundle id `com.apoorvdarshan.Scowld`, App Store
  Connect app `6760672848`, team `23RV7FYH36`, the Xcode to build with, and the GitHub
  Release title `Scowld X.Y.Z` (always Latest) with its signed source archive.
- The switches (repository variables) and credentials (repository secrets) below.
- The listing and What's New in [`metadata/ios/<locale>/`](metadata/ios), the
  screenshots under [`metadata/screenshots/ios/`](metadata/screenshots/ios), the
  header and search results images in [`creative/ios/`](creative/ios), and
  [`RELEASE_NOTES.md`](../RELEASE_NOTES.md) (GitHub Release bodies).
- The gate a tag run must pass: [`ios-tests.yml`](../.github/workflows/ios-tests.yml)
  (iOS unit and UI tests), which runs next to `prepare`; nothing is built unless it
  passes.

## Current switches

Repository **Variables** (Settings → Secrets and variables → Actions → Variables),
as of 2026-10-21. Missing means off; any value other than
`true/false/yes/no/on/off/1/0` fails the run, even when the master switch is off.

| Variable | Value |
|----------|-------|
| `IOS_RELEASE_AUTOMATION` | `true` |
| `IOS_CREATE_VERSION` | `true` |
| `IOS_UPLOAD_BUILD` | `true` |
| `IOS_UPLOAD_LISTING`, `IOS_UPLOAD_WHATS_NEW`, `IOS_UPLOAD_SCREENSHOTS` | `true` |
| `IOS_SUBMIT_REVIEW`, `IOS_PUBLIC_RELEASE` | `false` |
| `IOS_UPLOAD_CREATIVE_ASSETS` | not set (off; no header or search results image is committed yet, so leave it off) |
| `IOS_BUILD_POLL_SECONDS`, `IOS_BUILD_WAIT_MINUTES` | not set (30 s, 120 min from upload start) |

Scowld needs no shared `STORE_*` switch: the pipeline never creates, changes or
submits in-app products (see [In-app purchases](#in-app-purchases)).

With these values a `vX.Y.Z` tag runs the iOS tests, creates App Store version X.Y.Z
when App Store Connect does not have it yet, builds, signs and uploads the binary,
waits until App Store Connect has processed this build, and updates the version's
listing, What's New and screenshots from `store/metadata/ios/`. It does not submit for
review. Then it creates the GitHub Release `Scowld X.Y.Z` with the signed source
archive. Each **Run workflow** prints this plan for the switches as they are at that
moment (the `store-plan` job's summary). Leave `IOS_SUBMIT_REVIEW` and
`IOS_PUBLIC_RELEASE` off until you intend that release; `IOS_PUBLIC_RELEASE` needs
`IOS_SUBMIT_REVIEW`, which needs `IOS_UPLOAD_BUILD`.

Listing, What's New, screenshots, header and search results images and review
submission act on the App Store version named by the tag. With `IOS_CREATE_VERSION`
on, the tag run creates a missing version itself, right before the read-only
preflight (refused, without writing, next to an unfinished version or when the tag is
not newer than every existing version). The version needs every language in
`store/metadata/ios/`; the pipeline never adds one. A build-only release
(`IOS_UPLOAD_BUILD` alone) needs no App Store version.

### In-app purchases

Scowld sells optional Scowld Premium subscriptions (weekly and yearly, the yearly
plan with a free trial), consumable minute packs, and optional one-time tips. All of
them are App Store in-app purchases managed with RevenueCat; Premium minutes are
enforced by the Worker in [`web/`](../web) (see the main README). Using your own API
key needs no purchase.

The pipeline does not submit in-app products. If App Store Connect holds a product
that would have to go to review with a version (`READY_TO_SUBMIT`,
`DEVELOPER_REJECTED`, `READY_FOR_REVIEW`), `IOS_SUBMIT_REVIEW` stops before anything
is uploaded or changed. Submit those products in App Store Connect, then rerun.

## Export compliance

The app declares its export compliance answer in its build settings
(`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in Debug and Release, so every
build's `Info.plist` carries `ITSAppUsesNonExemptEncryption = false`). Without it,
App Store Connect asks about each build by hand, and review submission fails with
`usesNonExemptEncryption` missing.

`NO` is right because Scowld only uses exempt encryption: HTTPS and the live voice
WebSockets (Gemini Live, OpenAI Realtime, xAI Grok Voice, and Scowld Premium's relay
at `wss://scowld.xyz/api/live`) through Apple's networking, the Keychain for provider
keys, and Apple's system crypto (RevenueCat's hashing and signature checks, the
companion page's WebCrypto SHA-256 digests). If the app ever adds its own encryption,
set it to `YES` and add `INFOPLIST_KEY_ITSEncryptionExportComplianceCode` with the
code App Store Connect issues for the app's encryption documentation.

The prebuilt Amica page (`ios/Scowld/Resources/amica.bundle`) used to ship a
JavaScript copy of Node's `crypto` module (AES, DES, Diffie-Hellman, ECDH, RSA,
PBKDF2) in one chunk, `fec483df-29d484622c428254.js`. Only Amica's `/share` page
loaded it, and only to hash a file before publishing an avatar to Amica's online
store. So that the `NO` answer leaves no doubt, the chunk was removed and the app's
web view cancels every navigation to `/share`. The only effect: you cannot publish
avatars to Amica's online store from the app. `CompanionExportComplianceTests` fail
if any encryption code returns to the bundle, the block is lost, or the app stops
declaring `NO`.

Release and validation runs check the answer twice: `prepare` reads each
configuration (Debug and Release) of the app target before anything is built, and the
build job reads the archived app's `Info.plist` right after the archive. A
configuration without the key, an unknown value, different answers per
configuration, or `YES` without the code fails the run; values on the test targets do
not count.

## Listing source of truth

`store/metadata/ios/<locale>/` holds the live App Store listing. Only `en-US` exists
today.

| File | App Store Connect field | Limit |
|------|-------------------------|-------|
| `name.txt` | App name (app info) | 30 |
| `subtitle.txt` | Subtitle (app info) | 30 |
| `privacy_url.txt` | Privacy policy URL (app info) | URL |
| `description.txt` | Description | 4000 |
| `keywords.txt` | Keywords | 100 |
| `promotional_text.txt` | Promotional text | 170 |
| `marketing_url.txt` / `support_url.txt` | Marketing / support URL | URL |
| `whats_new.txt` | What's New: update it for every release; plain text, no Markdown, and different from the live version's | 4000 |
| `screenshots.json` | Screenshot sets: display type → ordered image paths | 10 per set |

An empty or missing text file leaves that field unchanged. `screenshots.json` points
at App Store-ready images already in the repository, today exactly the live ones:
[`metadata/screenshots/ios/iphone-6.9/`](metadata/screenshots/ios/iphone-6.9) (iPhone
6.9", 1320×2868, `APP_IPHONE_67`) and
[`metadata/screenshots/ios/ipad-13/`](metadata/screenshots/ios/ipad-13) (iPad 13",
2064×2752, `APP_IPAD_PRO_3GEN_129`). A set is replaced only when its ordered images
differ from App Store Connect's. Screenshots are uploaded from RGB copies, never from
the committed files: an RGB PNG without alpha (every committed screenshot today) is
copied byte for byte, and a PNG that stores alpha is laid over black first. iPhone Duo
(`APP_IPHONE_DUO`) and Apple Watch (`"watch"`) sets are supported but none exists for
Scowld yet; adding the images and listing them in `screenshots.json` is all it takes.

`APPSTORE.md` is reference copy; the pipeline reads only `store/metadata/ios/`. After
editing the listing directly in App Store Connect, re-export it (GET requests only;
needs the three `APP_STORE_CONNECT_*` values in the environment and PyJWT):

```bash
python3 -I -u path/to/store-release/run.py --app-root . ios export-listing                   # newest live version
python3 -I -u path/to/store-release/run.py --app-root . ios export-listing --version 2.0.1   # another one
```

## Header and search results images (iOS)

With `IOS_UPLOAD_CREATIVE_ASSETS` on, the images in `store/creative/ios/` go to the App
Store product page: `header/` takes one PNG of exactly 3840×1646, and
`search-results/` one PNG or JPEG in 3:2, from 1920×1280 to 3840×2560. Neither may
store alpha. A new image is uploaded to the Asset Library once and sent to App Review
in a submission of its own, never the version's draft; once Apple approves it, a later
run places it on the version's en-US page while the version can be edited. To change
an image, commit it under a new file name. No image is committed for Scowld yet, so
leave the switch off until one is.

## Secrets

| Secret | Used for |
|--------|----------|
| `APP_STORE_CONNECT_API_KEY_ID` | Admin-role App Store Connect API key: build numbers, cloud-managed distribution signing, upload, build readiness, listing, creative assets, review, and the read-only store plan |
| `APP_STORE_CONNECT_ISSUER_ID` | Its issuer |
| `APP_STORE_CONNECT_API_KEY_P8` | Its private key (`.p8` body) |
| `IOS_DEV_SIGNING_P12_BASE64` | The CI Apple Development identity (base64 `.p12`) that signs the archive; App Store signing happens at export with Apple's cloud-managed certificate |
| `IOS_DEV_SIGNING_P12_PASSWORD` | Its password |

[`ios-release.yml`](../.github/workflows/ios-release.yml) passes each reusable workflow
exactly the secrets it declares, by name (never `secrets: inherit`). Logs of a failed
build are kept as the `ios-release-logs-<run>-<attempt>` artifact (7 days) only after
the App Store Connect key and issuer IDs were removed from every file.

The CI Apple Development identity is certificate "Apple Development: Created via API",
ID `NVNGDQGCKK`, **expiring 2027-10-14**. The same identity signs the archives of Fud
AI, Verceltics, Abysm, iitjee, Quit All and Sesslet, because Apple allows one
API-created development certificate per API key. Renewing it:
[the shared CI signing identity](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/provenance.md#facts-that-only-concern-the-six-apps);
copying it to another repository:
[sharing one development identity](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/secrets.md#sharing-one-development-identity-across-your-apps).
When it is replaced, update both `IOS_DEV_SIGNING_*` secrets here and in every
repository listed above.

## Verifying a release

Each GitHub Release carries `scowld-X.Y.Z-source.tar.gz` (`git archive` of the tag),
its checksum (`.sha256`) and keyless Sigstore bundle (`.sigstore.json`), plus a GitHub
build-provenance attestation. Releases after v2.1.0 are signed by store-release's
`ios-source-archive.yml`, called from this repository:

```bash
sha256sum -c scowld-X.Y.Z-source.tar.gz.sha256
cosign verify-blob scowld-X.Y.Z-source.tar.gz \
  --bundle scowld-X.Y.Z-source.tar.gz.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/apoorvdarshan/store-release/\.github/workflows/ios-source-archive\.yml@[0-9a-f]{40}$' \
  --certificate-github-workflow-repository apoorvdarshan/scowld \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
gh attestation verify scowld-X.Y.Z-source.tar.gz --repo apoorvdarshan/scowld
```

v2.1.0 and earlier were signed by this repository's own pipeline; verify those with
`--certificate-identity-regexp '^https://github.com/apoorvdarshan/scowld/\.github/workflows/ios-release\.yml@refs/tags/v'`
in place of the two `--certificate-*` identity lines above.

## How to release

1. Bump `MARKETING_VERSION` (and, if you like, `CURRENT_PROJECT_VERSION`; the pipeline
   uses the higher of it and the last App Store Connect build + 1).
2. Update `store/metadata/ios/<locale>/whats_new.txt` (plain text), and add one
   `## vX.Y.Z` section to `RELEASE_NOTES.md` for the GitHub Release (optional; a tag
   without one gets GitHub's generated notes; a `## ` heading used twice fails Store
   checks, and two sections for one tag fail the release).
3. Run **iOS Release → Run workflow**. It only validates. Apple refuses versions it has
   already approved, so while the project still has the released version, set
   `marketing_version` to the next one (for example `2.1.1`); the build is validated as
   that version without changing the project. Read the `store-plan` job's summary: it
   lists every write the tag run would make with the current switches, and anything
   that would stop it.
4. Turn on only the switches you want, then push the tag `vX.Y.Z`.
5. If a later step fails, fix the cause and use **Re-run failed jobs**
   ([re-runs](https://github.com/apoorvdarshan/store-release/blob/v0.3.0/docs/rerun.md)):
   waiting for the build is its own job, so a re-run reuses the processed build.

## Checking locally

With a checkout of store-release at the pinned tag and its `requirements.txt` and
`requirements-checks.txt` installed (Python 3.11 or later):

```bash
SR=path/to/store-release
python3 -I -u $SR/run.py --app-root . config check --files
python3 -I -u $SR/run.py --app-root . print-switches --platform ios
python3 -I -u $SR/run.py --app-root . release-notes --check-headings
python3 -I -u $SR/run.py --app-root . ios pr-checks   # the listing, screenshots and images with every switch on
```
