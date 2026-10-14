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
       any listing/What's New/screenshot/review switch ─► read-only preflight: the version
            exists in a state that allows the enabled steps, with every repository locale;
            What's New differs from the live version; screenshots that can no longer change
            already match; no in-app product would have to ship with it (fails before any upload)
       IOS_UPLOAD_BUILD ─► next build number from App Store Connect
                        ─► archive Release ─► verify bundle id/version/build in every .app/.appex
                        ─► cloud-signed export + upload
                        ─► wait until THIS build is VALID (poll 30 s, up to 120 min from upload start)
       IOS_UPLOAD_LISTING / IOS_UPLOAD_WHATS_NEW / IOS_UPLOAD_SCREENSHOTS ─► version listing
       IOS_SUBMIT_REVIEW ─► no pending in-app products ─► select this run's build, read it back
                         ─► set release type ─► recheck build + selection ─► submit for review
  └─ GitHub Release (only if every enabled step succeeded)
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
| `IOS_UPLOAD_BUILD` | Build, sign and upload the binary to App Store Connect, then wait until this build is processed |
| `IOS_UPLOAD_LISTING` | App name, subtitle and privacy policy URL (app info), and description, keywords, promotional text, marketing and support URLs (version) — only fields that differ from App Store Connect are sent |
| `IOS_UPLOAD_WHATS_NEW` | What's New, as plain text: Markdown (`**bold**`, backticks, `[links](…)`, `#` headings) is refused because the App Store shows it literally. Refused if it is identical to the live version's text |
| `IOS_UPLOAD_SCREENSHOTS` | The screenshots listed in each locale's `screenshots.json`; a display type whose images are unchanged is left alone |
| `IOS_SUBMIT_REVIEW` | Select this run's processed build and submit the version for App Review. Requires `IOS_UPLOAD_BUILD` |
| `IOS_PUBLIC_RELEASE` | Release automatically after approval. Off = you release it by hand. Requires `IOS_SUBMIT_REVIEW` |
| `IOS_BUILD_POLL_SECONDS` | Poll interval while App Store Connect processes the build, default 30 (10–600) |
| `IOS_BUILD_WAIT_MINUTES` | Total wait counted from upload start (upload + processing), default 120 (10–300) |

Copy names from [`gates.env.example`](gates.env.example). Scowld needs no shared
`STORE_*` switch: it has no in-app purchases and no RevenueCat catalog.

Listing, What's New, screenshots and review submission act on the App Store
version named by the tag, which the pipeline never creates. **Create the X.Y.Z
App Store version in App Store Connect first** (App Store tab → **+ Version**,
left in Prepare for Submission) whenever any of those switches is on, with every
language in `store/metadata/ios/`. The read-only preflight stops the run before
anything is built or uploaded otherwise. A build-only release (`IOS_UPLOAD_BUILD`
alone) needs no App Store version.

Prepare checks only the store files the enabled switches use: an invalid or
missing screenshot, listing or What's New file never blocks a release that does
not upload it. The **Store automation (offline)** workflow still validates all
of them on every pull request and main push that touches them.

Waiting for the build is its own job, so when a later store step fails (for
example App Store Connect changed in between), **Re-run failed jobs** reuses the
processed build instead of waiting again; the store step re-verifies it before
selecting it. Reruns are idempotent once the version is in review too: in Ready
for Review (it already sits in a draft review submission, for example after a
failed submit) the listing and What's New can still change but screenshots
cannot; in Waiting for Review (already submitted) nothing can. A step that can no
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

Scowld 2.0 sells nothing (no subscriptions, StoreKit purchases or credits), and
App Store Connect lists no in-app products for the app, so the pipeline submits
none. If App Store Connect ever holds a product that would have to go to review
with a version (`READY_TO_SUBMIT`, `DEVELOPER_REJECTED`, `READY_FOR_REVIEW`),
`IOS_SUBMIT_REVIEW` stops before anything is uploaded or changed (in the
preflight, and again before the listing step); add a product catalog and the
Fud AI product-submission step before selling anything.

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
live ones: [`marketing/mockups/`](../marketing/mockups) (iPhone 6.9", 1260×2736,
`APP_IPHONE_67`) and [`marketing/mockups ipad/`](../marketing/mockups%20ipad)
(iPad 13", 2064×2752, `APP_IPAD_PRO_3GEN_129`). Sizes, opacity and the 10-image
limit are checked before any upload; with the screenshot switch on and no
`screenshots.json`, the run fails with that message.

`APPSTORE.md` is reference copy; the pipeline reads only `store/metadata/ios/`.
After editing the listing directly in App Store Connect, re-export it:

```bash
python3 scripts/store/asc_export_listing.py   # newest live version; --version 2.0.1 for another
```

## Secrets

| Secret | Used for |
|--------|----------|
| `APP_STORE_CONNECT_API_KEY_ID` | Admin-role App Store Connect API key: build numbers, cloud-managed distribution signing, upload, build readiness, listing, review |
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
| [`scripts/store/ios_release.py`](../scripts/store/ios_release.py) | Switches (`gates`), tag/version check, build number, wait for this run's build |
| [`scripts/store/asc_release.py`](../scripts/store/asc_release.py) | Listing, What's New, screenshots, build selection, review submission (`--dry-run` = local checks only, `--preflight` = read-only App Store Connect checks) |
| [`scripts/store/asc_export_listing.py`](../scripts/store/asc_export_listing.py) | Read-only export of the live listing into `store/metadata/ios/` |
| [`scripts/store/test_ios_release.py`](../scripts/store/test_ios_release.py) | Offline tests: disabled/invalid switches, tag mismatch, validation mode, build wait timeout/failure/ambiguity/mismatch/old build/missing upload time, selection read-back, token refresh, ES256 token signing (needs the store tooling), preflight, listing, plain-text What's New, screenshots, submission, reruns in review, printed switches, release notes, log redaction |
| [`scripts/store/print_gates.py`](../scripts/store/print_gates.py) | Prints the switches in the run log; an invalid value shows as `INVALID` |
| [`scripts/store/redact_logs.py`](../scripts/store/redact_logs.py) | Removes the App Store Connect key and issuer IDs from failed-build logs before they become an artifact |
| [`scripts/release_notes.py`](../scripts/release_notes.py) | GitHub Release notes from the matching `RELEASE_NOTES.md` section (else GitHub's generated notes; two sections for one tag fail the release) |

The jobs that install the store tooling run on Python 3.13
(`actions/setup-python`): `prepare`, `wait-for-build` and `app-store-connect`
in the release workflow, and the **Store automation (offline)** workflow. They
install [`requirements-store.txt`](../requirements-store.txt) (PyJWT,
hash-pinned, `--require-hashes`). The lock targets that Python only: regenerate
it from `requirements-store.in` with the `uv` command in it. Dependabot proposes
updates weekly and also writes the lock without `--universal` markers. The other
Python steps need only the standard library and run on the runner's own
`python3`: `redact_logs.py` (and the step that writes the `.p8` key) in the
`build` job, and `print_gates.py` and `release_notes.py` in `github-release`.
Steps that talk to App Store Connect run unbuffered (`python3 -u`), so the build
wait's progress shows in the live log.

The **Store automation (offline)** workflow installs `requirements-store.txt`
the same way, runs the offline tests (including signing a throwaway App Store
Connect token with that PyJWT, a test that fails there instead of skipping) and
validates the whole committed listing, screenshots and release notes on every
pull request and main push that touches these files. A Dependabot update to the
store tooling is therefore proven before it can reach a release.

Environment flags read by `asc_release.py` (set by `ios-release.yml` from the
resolved switches): `UPLOAD_LISTING`, `UPLOAD_WHATS_NEW`, `UPLOAD_SCREENSHOTS`,
`SUBMIT_IOS_REVIEW`, `PUBLIC_RELEASE`.

## How to release

1. Bump `MARKETING_VERSION` (and, if you like, `CURRENT_PROJECT_VERSION`; the
   pipeline uses the higher of it and the last App Store Connect build + 1).
2. Update `store/metadata/ios/<locale>/whats_new.txt` (plain text), and add one
   `## vX.Y.Z` section to `RELEASE_NOTES.md` for the GitHub Release (optional).
3. Run **iOS Release → Run workflow** with `marketing_version` = the new version
   to validate signing (nothing is uploaded).
4. If any listing, What's New, screenshot or review switch will be on, create
   the X.Y.Z App Store version in App Store Connect first (App Store tab →
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
