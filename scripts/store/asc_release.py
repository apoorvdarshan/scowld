#!/usr/bin/env python3
"""App Store Connect listing, What's New, screenshots and review submission.

Every operation has its own switch. ios-release.yml sets these environment
flags from the resolved IOS_* repository variables:

  UPLOAD_LISTING      name, subtitle, privacy policy URL, description, keywords,
                      promotional text, marketing and support URLs
  UPLOAD_WHATS_NEW    What's New
  UPLOAD_SCREENSHOTS  the screenshots listed in each locale's screenshots.json
  SUBMIT_IOS_REVIEW   select THIS run's processed build and submit for review
  PUBLIC_RELEASE      release automatically after approval (otherwise manual)

The listing lives in store/metadata/ios/<locale>/ (exported from the live App
Store listing by asc_export_listing.py), so the repository is its source of
truth. Only fields whose text differs from App Store Connect are sent.

Scowld sells nothing in-app (2.0 removed purchases), so no in-app purchase or
subscription is submitted; submission stops instead if App Store Connect holds
products that would have to go to review with the version.

`--dry-run` validates the switches and local files only (no network).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[2]
ASC_BASE = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_BUNDLE_ID = "com.apoorvdarshan.Scowld"
METADATA_DIR = ROOT / "store" / "metadata" / "ios"

# (App Store Connect attribute, file in store/metadata/ios/<locale>/, max length)
VERSION_FIELDS = (
    ("description", "description.txt", 4000),
    ("keywords", "keywords.txt", 100),
    ("promotionalText", "promotional_text.txt", 170),
    ("marketingUrl", "marketing_url.txt", None),
    ("supportUrl", "support_url.txt", None),
)
APP_INFO_FIELDS = (
    ("name", "name.txt", 30),
    ("subtitle", "subtitle.txt", 30),
    ("privacyPolicyUrl", "privacy_url.txt", None),
)
WHATS_NEW_FIELD = ("whatsNew", "whats_new.txt", 4000)
URL_FIELDS = {"marketingUrl", "supportUrl", "privacyPolicyUrl"}
SCREENSHOT_MANIFEST = "screenshots.json"

# Accepted portrait sizes per App Store Connect display type (landscape = swapped).
SCREENSHOT_SIZES = {
    "APP_IPHONE_67": {(1260, 2736), (1290, 2796), (1320, 2868), (1284, 2778)},
    "APP_IPHONE_65": {(1242, 2688), (1284, 2778)},
    "APP_IPAD_PRO_3GEN_129": {(2048, 2732), (2064, 2752)},
}
SCREENSHOT_SET_MAX = 10
SCREENSHOT_PROCESSING_SECONDS = 300

EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}
# READY_FOR_REVIEW means the version already sits in a draft review submission
# (for example after a failed submit); it can still be submitted.
SUBMITTABLE_VERSION_STATES = EDITABLE_VERSION_STATES | {"READY_FOR_REVIEW"}
EDITABLE_APP_INFO_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED"}
LIVE_VERSION_STATES = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
# In-app products in these states would have to go to App Review with a version.
PENDING_PRODUCT_STATES = {"READY_TO_SUBMIT", "DEVELOPER_REJECTED", "READY_FOR_REVIEW"}

RELEASE_TYPE_PUBLIC = "AFTER_APPROVAL"
RELEASE_TYPE_MANUAL = "MANUAL"


def fail(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


class AscHttpError(SystemExit):
    """An App Store Connect HTTP error; exits like fail() unless a caller retries."""

    def __init__(self, status: int, message: str) -> None:
        super().__init__(f"error: {message}")
        self.status = status


def truthy(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in {"1", "true", "yes", "on"}


def read_text(path: Path) -> str | None:
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8").strip()
    return text or None


# MARK: - HTTP client


class AscClient:
    # JWTs are minted for 20 minutes; refresh well before that during long waits.
    TOKEN_MAX_AGE_SECONDS = 600

    def __init__(self, token: str | None = None, *, token_factory: Any | None = None) -> None:
        if token is None and token_factory is None:
            raise ValueError("AscClient needs a token or a token_factory")
        self._token_factory = token_factory
        self._token = token if token is not None else token_factory()
        self._token_minted = time.monotonic()

    def _authorization(self) -> str:
        if (
            self._token_factory is not None
            and time.monotonic() - self._token_minted > self.TOKEN_MAX_AGE_SECONDS
        ):
            self._token = self._token_factory()
            self._token_minted = time.monotonic()
        return f"Bearer {self._token}"

    def request(self, method: str, path: str, *, body: dict[str, Any] | None = None) -> dict[str, Any] | None:
        url = path if path.startswith("http") else f"{ASC_BASE}{path}"
        headers = {"Authorization": self._authorization(), "Accept": "application/json"}
        data: bytes | None = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                payload = resp.read()
                return json.loads(payload.decode("utf-8")) if payload else None
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            print(f"error: ASC {method} {path} → HTTP {exc.code}: {detail[:2000]}", file=sys.stderr)
            raise AscHttpError(exc.code, f"ASC {method} {path} → HTTP {exc.code}") from None

    def get(self, path: str) -> dict[str, Any]:
        result = self.request("GET", path)
        assert result is not None
        return result

    def patch(self, path: str, body: dict[str, Any]) -> dict[str, Any] | None:
        return self.request("PATCH", path, body=body)

    def post(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        result = self.request("POST", path, body=body)
        assert result is not None
        return result

    def delete(self, path: str) -> None:
        self.request("DELETE", path)

    def upload_bytes(self, url: str, data: bytes, headers: dict[str, str], *, method: str = "PUT") -> None:
        req = urllib.request.Request(url, data=data, method=method.upper(), headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=300):
                return
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            fail(f"ASC asset upload → HTTP {exc.code}: {detail[:1000]}")


def make_asc_token(key_id: str, issuer_id: str, private_key: str) -> str:
    import jwt  # noqa: PLC0415 - only live runs need PyJWT

    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})


def load_credentials() -> tuple[str, str, str]:
    key_id = os.environ.get("APP_STORE_CONNECT_API_KEY_ID", "").strip()
    issuer_id = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    key_p8 = os.environ.get("APP_STORE_CONNECT_API_KEY_P8", "").strip()
    if not key_id or not issuer_id or not key_p8:
        fail(
            "missing ASC credentials — set APP_STORE_CONNECT_API_KEY_ID, "
            "APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8"
        )
    return key_id, issuer_id, key_p8.replace("\\n", "\n")


def client_from_environment() -> AscClient:
    """Client whose JWT is re-minted automatically during long-running steps."""
    key_id, issuer_id, key_p8 = load_credentials()
    return AscClient(token_factory=lambda: make_asc_token(key_id, issuer_id, key_p8))


def iter_collection(client: Any, path: str) -> list[dict[str, Any]]:
    """Return every record in an ASC collection, following links.next."""
    rows: list[dict[str, Any]] = []
    next_path: str | None = path
    while next_path:
        payload = client.get(next_path)
        rows.extend(payload.get("data") or [])
        next_path = (payload.get("links") or {}).get("next")
    return rows


def find_app(client: Any, bundle_id: str) -> str:
    payload = client.get("/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle_id}))
    matches = [row for row in payload.get("data") or [] if (row.get("attributes") or {}).get("bundleId") == bundle_id]
    if not matches:
        fail(f"no App Store Connect app for bundle id {bundle_id}")
    if len(matches) > 1:
        fail(f"ambiguous: {len(matches)} App Store Connect apps use bundle id {bundle_id}")
    return matches[0]["id"]


def ios_versions(client: Any, app_id: str) -> list[dict[str, Any]]:
    # The app relationship listing works for keys that cannot list /appStoreVersions.
    return iter_collection(
        client,
        f"/apps/{app_id}/appStoreVersions?" + urllib.parse.urlencode({"limit": "50", "filter[platform]": "IOS"}),
    )


def get_ios_app_store_version(client: Any, app_id: str, version_string: str) -> dict[str, Any]:
    matches = [
        row for row in ios_versions(client, app_id)
        if (row.get("attributes") or {}).get("versionString") == version_string
    ]
    if not matches:
        fail(
            f"no iOS App Store version {version_string!r} in App Store Connect — create version "
            f"{version_string} there (App Store tab, + Version) and rerun the failed job"
        )
    if len(matches) > 1:
        fail(f"ambiguous: {len(matches)} iOS App Store versions are named {version_string!r}")
    return matches[0]


# MARK: - Local listing files


def metadata_locales(metadata_dir: Path) -> list[str]:
    if not metadata_dir.is_dir():
        return []
    return sorted(p.name for p in metadata_dir.iterdir() if p.is_dir() and not p.name.startswith("."))


def load_fields(loc_dir: Path, fields: tuple[tuple[str, str, int | None], ...]) -> dict[str, str]:
    """Read and validate text files; empty or missing files leave that field unchanged."""
    values: dict[str, str] = {}
    for field, filename, limit in fields:
        value = read_text(loc_dir / filename)
        if value is None:
            continue
        if limit is not None and len(value) > limit:
            fail(f"{loc_dir / filename} is {len(value)} characters; App Store Connect allows {limit}")
        if field in URL_FIELDS and not re.fullmatch(r"https?://\S+", value):
            fail(f"{loc_dir / filename} must be a single http(s) URL")
        values[field] = value
    return values


def image_size(path: Path) -> tuple[int, int, bool]:
    """(width, height, has_alpha) for a PNG or JPEG file, read from its header."""
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        width, height = struct.unpack(">II", data[16:24])
        return width, height, data[25] in (4, 6)
    if data[:2] == b"\xff\xd8":
        index = 2
        while index + 9 < len(data):
            if data[index] != 0xFF:
                index += 1
                continue
            marker = data[index + 1]
            length = struct.unpack(">H", data[index + 2:index + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2):
                height, width = struct.unpack(">HH", data[index + 5:index + 9])
                return width, height, False
            index += 2 + length
    fail(f"{path} is not a PNG or JPEG image")
    raise AssertionError("unreachable")


def load_screenshot_manifest(loc_dir: Path, root: Path = ROOT) -> dict[str, list[Path]]:
    """Validate <locale>/screenshots.json: display type → ordered image paths (repo-relative)."""
    manifest_path = loc_dir / SCREENSHOT_MANIFEST
    if not manifest_path.is_file():
        fail(
            f"screenshot upload is on, but {manifest_path} does not exist; list the "
            "App Store-ready images per display type there (see store/README.md)"
        )
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"{manifest_path} is not valid JSON: {exc}")
    if not isinstance(manifest, dict) or not manifest:
        fail(f"{manifest_path} must map display types to lists of image paths")
    plan: dict[str, list[Path]] = {}
    for display_type, entries in manifest.items():
        accepted = SCREENSHOT_SIZES.get(display_type)
        if accepted is None:
            fail(f"{manifest_path}: unsupported display type {display_type!r}; use one of {sorted(SCREENSHOT_SIZES)}")
        if not isinstance(entries, list) or not entries or not all(isinstance(e, str) for e in entries):
            fail(f"{manifest_path}: {display_type} must list at least one image path")
        if len(entries) > SCREENSHOT_SET_MAX:
            fail(f"{manifest_path}: {display_type} lists {len(entries)} images; App Store Connect allows {SCREENSHOT_SET_MAX}")
        files: list[Path] = []
        for entry in entries:
            path = (root / entry).resolve()
            if root.resolve() not in path.parents or not path.is_file():
                fail(f"{manifest_path}: {entry} is not an image file in this repository")
            width, height, has_alpha = image_size(path)
            if (width, height) not in accepted and (height, width) not in accepted:
                sizes = ", ".join(f"{w}x{h}" for w, h in sorted(accepted))
                fail(f"{entry} is {width}x{height}; {display_type} accepts {sizes} (or landscape)")
            if has_alpha:
                fail(f"{entry} has an alpha channel; App Store screenshots must be opaque")
            files.append(path)
        plan[display_type] = files
    return plan


def validate_local_inputs(
    *,
    upload_listing: bool,
    upload_whats_new: bool,
    upload_screenshots: bool,
    metadata_dir: Path,
    root: Path = ROOT,
) -> dict[str, dict[str, Any]]:
    """Check every enabled operation's local files before any network call."""
    plan: dict[str, dict[str, Any]] = {}
    if not (upload_listing or upload_whats_new or upload_screenshots):
        return plan
    locales = metadata_locales(metadata_dir)
    if not locales:
        fail(f"no locale folders in {metadata_dir}")
    for locale in locales:
        loc_dir = metadata_dir / locale
        entry: dict[str, Any] = {}
        if upload_listing:
            entry["version"] = load_fields(loc_dir, VERSION_FIELDS)
            entry["app_info"] = load_fields(loc_dir, APP_INFO_FIELDS)
            if "description" not in entry["version"]:
                fail(f"{loc_dir / 'description.txt'} is missing or empty")
        if upload_whats_new:
            whats_new = load_fields(loc_dir, (WHATS_NEW_FIELD,))
            if WHATS_NEW_FIELD[0] not in whats_new:
                fail(f"What's New upload is on, but {loc_dir / WHATS_NEW_FIELD[1]} is missing or empty")
            entry["whats_new"] = whats_new[WHATS_NEW_FIELD[0]]
        if upload_screenshots:
            entry["screenshots"] = load_screenshot_manifest(loc_dir, root)
        plan[locale] = entry
    return plan


# MARK: - Listing and What's New


def localization_for_locale(client: Any, collection_path: str, locale: str) -> dict[str, Any] | None:
    for row in iter_collection(client, f"{collection_path}?limit=50"):
        if (row.get("attributes") or {}).get("locale") == locale:
            return row
    return None


def changed_fields(current: dict[str, Any], wanted: dict[str, str]) -> dict[str, str]:
    return {
        field: value for field, value in wanted.items()
        if (current.get(field) or "").strip() != value
    }


def app_info_state(info: dict[str, Any]) -> str:
    attrs = info.get("attributes") or {}
    return attrs.get("state") or attrs.get("appStoreState") or ""


def upload_version_fields(client: Any, version_id: str, locale: str, wanted: dict[str, str], label: str) -> None:
    loc = localization_for_locale(client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", locale)
    if loc is None:
        fail(f"version has no {locale} localization in App Store Connect; add the language there first")
    changes = changed_fields(loc.get("attributes") or {}, wanted)
    if not changes:
        print(f"  {label} ({locale}): already up to date")
        return
    client.patch(
        f"/appStoreVersionLocalizations/{loc['id']}",
        {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": changes}},
    )
    print(f"  {label} ({locale}): updated {', '.join(sorted(changes))}")


def upload_app_info_fields(client: Any, app_id: str, locale: str, wanted: dict[str, str]) -> None:
    """Name, subtitle and privacy URL live on the app info that ships with the version."""
    if not wanted:
        return
    infos = iter_collection(client, f"/apps/{app_id}/appInfos")
    editable = [info for info in infos if app_info_state(info) in EDITABLE_APP_INFO_STATES]
    if len(editable) > 1:
        fail(f"ambiguous: {len(editable)} editable app infos")
    target = editable[0] if editable else None
    live = [info for info in infos if app_info_state(info) in {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE"}]
    source = target or next(iter(live or infos), None)
    if source is None:
        fail("app has no app info in App Store Connect")
    loc = localization_for_locale(client, f"/appInfos/{source['id']}/appInfoLocalizations", locale)
    if loc is None:
        fail(f"app info has no {locale} localization in App Store Connect; add the language there first")
    changes = changed_fields(loc.get("attributes") or {}, wanted)
    if not changes:
        print(f"  app name/subtitle/privacy URL ({locale}): already up to date")
        return
    if target is None:
        fail(
            f"{', '.join(sorted(changes))} ({locale}) changed, but App Store Connect has no editable "
            "app info; they can only change together with a new version"
        )
    client.patch(
        f"/appInfoLocalizations/{loc['id']}",
        {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": changes}},
    )
    print(f"  app name/subtitle/privacy URL ({locale}): updated {', '.join(sorted(changes))}")


def live_whats_new(client: Any, app_id: str, exclude_version_id: str, locale: str) -> tuple[str, str] | None:
    """(version, What's New) of the newest live version, if any."""
    live = [
        row for row in ios_versions(client, app_id)
        if row.get("id") != exclude_version_id
        and (row.get("attributes") or {}).get("appStoreState") in LIVE_VERSION_STATES
    ]
    if not live:
        return None
    newest = max(live, key=lambda row: (row.get("attributes") or {}).get("createdDate") or "")
    loc = localization_for_locale(client, f"/appStoreVersions/{newest['id']}/appStoreVersionLocalizations", locale)
    text = ((loc or {}).get("attributes") or {}).get("whatsNew") or ""
    return (newest.get("attributes") or {}).get("versionString", "?"), text.strip()


def upload_whats_new(client: Any, app_id: str, version_id: str, locale: str, text: str) -> None:
    previous = live_whats_new(client, app_id, version_id, locale)
    if previous and previous[1] == text:
        fail(
            f"What's New ({locale}) is identical to live version {previous[0]}; update "
            f"store/metadata/ios/{locale}/{WHATS_NEW_FIELD[1]} for this release"
        )
    upload_version_fields(client, version_id, locale, {WHATS_NEW_FIELD[0]: text}, "What's New")


# MARK: - Screenshots


def md5_hex(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()  # noqa: S324 - App Store Connect's checksum


def ensure_screenshot_set(client: Any, version_loc_id: str, display_type: str) -> str:
    for item in iter_collection(client, f"/appStoreVersionLocalizations/{version_loc_id}/appScreenshotSets?limit=50"):
        if (item.get("attributes") or {}).get("screenshotDisplayType") == display_type:
            return item["id"]
    created = client.post(
        "/appScreenshotSets",
        {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": version_loc_id}
                    }
                },
            }
        },
    )
    return created["data"]["id"]


def upload_screenshot_file(client: Any, set_id: str, path: Path, checksum: str) -> str:
    raw = path.read_bytes()
    reserved = client.post(
        "/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(raw)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
            }
        },
    )["data"]
    operations = (reserved.get("attributes") or {}).get("uploadOperations") or []
    if not operations:
        fail(f"App Store Connect returned no upload operations for {path.name}")
    for op in operations:
        offset = int(op.get("offset", 0))
        chunk = raw[offset:offset + int(op["length"])]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        client.upload_bytes(op["url"], chunk, headers, method=op.get("method") or "PUT")
    client.patch(
        f"/appScreenshots/{reserved['id']}",
        {
            "data": {
                "type": "appScreenshots",
                "id": reserved["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
            }
        },
    )
    return reserved["id"]


def wait_for_screenshots(
    client: Any,
    screenshot_ids: list[str],
    *,
    timeout: float = SCREENSHOT_PROCESSING_SECONDS,
    now: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> None:
    deadline = now() + timeout
    pending = list(screenshot_ids)
    while pending:
        still: list[str] = []
        for shot_id in pending:
            attrs = (client.get(f"/appScreenshots/{shot_id}").get("data") or {}).get("attributes") or {}
            delivery = attrs.get("assetDeliveryState") or {}
            state = delivery.get("state")
            if state == "COMPLETE":
                continue
            if state == "FAILED":
                errors = "; ".join(e.get("description") or e.get("code") or "" for e in delivery.get("errors") or [])
                fail(f"App Store Connect rejected screenshot {attrs.get('fileName') or shot_id}: {errors or 'FAILED'}")
            still.append(shot_id)
        pending = still
        if pending:
            if now() > deadline:
                fail(f"{len(pending)} screenshot(s) were still processing after {int(timeout)} s")
            sleep(3)


def sync_screenshot_set(client: Any, version_loc_id: str, locale: str, display_type: str, files: list[Path]) -> None:
    set_id = ensure_screenshot_set(client, version_loc_id, display_type)
    current = iter_collection(client, f"/appScreenshotSets/{set_id}/appScreenshots?limit=50")
    wanted = [md5_hex(path) for path in files]
    if [(row.get("attributes") or {}).get("sourceFileChecksum") for row in current] == wanted:
        print(f"  screenshots {display_type} ({locale}): already up to date")
        return
    # The version is not live yet, so replacing the whole set is safe; rerun on failure.
    for row in current:
        client.delete(f"/appScreenshots/{row['id']}")
    new_ids = [upload_screenshot_file(client, set_id, path, checksum) for path, checksum in zip(files, wanted)]
    wait_for_screenshots(client, new_ids)
    client.patch(
        f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
        {"data": [{"type": "appScreenshots", "id": shot_id} for shot_id in new_ids]},
    )
    print(f"  screenshots {display_type} ({locale}): uploaded {len(new_ids)} in order")


def upload_screenshots(client: Any, version_id: str, locale: str, plan: dict[str, list[Path]]) -> None:
    loc = localization_for_locale(client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", locale)
    if loc is None:
        fail(f"version has no {locale} localization in App Store Connect; add the language there first")
    for display_type, files in plan.items():
        sync_screenshot_set(client, loc["id"], locale, display_type, files)


# MARK: - Build selection and review


def pending_in_app_products(client: Any, app_id: str) -> list[str]:
    """Products that App Review would expect with this version (Scowld has none)."""
    pending: list[str] = []
    for group in iter_collection(client, f"/apps/{app_id}/subscriptionGroups?limit=200"):
        for sub in iter_collection(client, f"/subscriptionGroups/{group['id']}/subscriptions?limit=200"):
            attrs = sub.get("attributes") or {}
            if attrs.get("state") in PENDING_PRODUCT_STATES:
                pending.append(f"subscription {attrs.get('productId') or sub['id']} ({attrs.get('state')})")
    for iap in iter_collection(client, f"/apps/{app_id}/inAppPurchasesV2?limit=200"):
        attrs = iap.get("attributes") or {}
        if attrs.get("state") in PENDING_PRODUCT_STATES:
            pending.append(f"in-app purchase {attrs.get('productId') or iap['id']} ({attrs.get('state')})")
    return pending


def verify_build(client: Any, build_id: str, version_string: str, build_number: str) -> None:
    """Re-read the build and refuse anything but this run's processed build."""
    payload = client.get(
        f"/builds/{build_id}?"
        + urllib.parse.urlencode(
            {
                "include": "preReleaseVersion",
                "fields[builds]": "version,processingState,expired,preReleaseVersion",
                "fields[preReleaseVersions]": "version,platform",
            }
        )
    )
    data = payload.get("data") or {}
    attrs = data.get("attributes") or {}
    pre = next((row for row in payload.get("included") or [] if row.get("type") == "preReleaseVersions"), {})
    pre_attrs = pre.get("attributes") or {}
    problems = []
    if data.get("id") != build_id:
        problems.append(f"id {data.get('id')!r}")
    if attrs.get("version") != build_number:
        problems.append(f"build number {attrs.get('version')!r}")
    if attrs.get("processingState") != "VALID":
        problems.append(f"processing state {attrs.get('processingState')!r}")
    if attrs.get("expired"):
        problems.append("expired")
    if pre_attrs.get("version") != version_string or pre_attrs.get("platform") != "IOS":
        problems.append(f"version {pre_attrs.get('platform')} {pre_attrs.get('version')!r}")
    if problems:
        fail(
            f"build {build_id} is not {version_string} ({build_number}), VALID and unexpired: "
            + ", ".join(problems)
        )


def attached_build_id(client: Any, version_id: str) -> str | None:
    payload = client.get(f"/appStoreVersions/{version_id}/build")
    return (payload.get("data") or {}).get("id")


def confirm_selected_build(client: Any, version_id: str, build_id: str) -> None:
    current = attached_build_id(client, version_id)
    if current != build_id:
        fail(
            f"App Store version {version_id} has build {current or 'none'} selected, "
            f"expected {build_id}; not submitting"
        )


def select_build(client: Any, version_id: str, build_id: str, version_string: str, build_number: str) -> None:
    """Explicitly select this run's build for the version, then read it back."""
    verify_build(client, build_id, version_string, build_number)
    client.request(
        "PATCH",
        f"/appStoreVersions/{version_id}/relationships/build",
        body={"data": {"type": "builds", "id": build_id}},
    )
    confirm_selected_build(client, version_id, build_id)
    print(f"  selected build {build_number} ({build_id}) for version {version_string}")


def set_release_type(client: Any, version_id: str, *, public_release: bool) -> None:
    release_type = RELEASE_TYPE_PUBLIC if public_release else RELEASE_TYPE_MANUAL
    client.patch(
        f"/appStoreVersions/{version_id}",
        {"data": {"type": "appStoreVersions", "id": version_id, "attributes": {"releaseType": release_type}}},
    )
    print(
        "  release type: "
        + ("release automatically after approval" if public_release else "manual release after approval")
    )


def get_or_create_draft_submission(client: Any, app_id: str) -> str:
    """Return the app's draft (READY_FOR_REVIEW) iOS review submission, creating one."""
    drafts = client.get(
        f"/apps/{app_id}/reviewSubmissions?"
        + urllib.parse.urlencode({"filter[state]": "READY_FOR_REVIEW", "filter[platform]": "IOS", "limit": "5"})
    ).get("data") or []
    if len(drafts) > 1:
        fail(f"ambiguous: {len(drafts)} draft review submissions; remove the extras in App Store Connect")
    if drafts:
        return drafts[0]["id"]
    created = client.post(
        "/reviewSubmissions",
        {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    return created["data"]["id"]


def draft_holds_version(client: Any, submission_id: str, version_id: str) -> bool:
    """True if the draft already holds this version; fails if it holds anything else."""
    holds = False
    others: list[str] = []
    # Relationships are only returned when requested with `include`.
    for item in iter_collection(client, f"/reviewSubmissions/{submission_id}/items?limit=50&include=appStoreVersion"):
        related = (((item.get("relationships") or {}).get("appStoreVersion") or {}).get("data") or {}).get("id")
        if related == version_id:
            holds = True
        else:
            others.append(item.get("id", "?"))
    if others:
        fail(
            f"draft review submission {submission_id} also holds other items ({', '.join(others)}); "
            "remove them in App Store Connect so only this version goes to review"
        )
    return holds


def submit_for_review(client: Any, submission_id: str, version_id: str, *, already_added: bool) -> None:
    if not already_added:
        client.post(
            "/reviewSubmissionItems",
            {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                    },
                }
            },
        )
    # Submitting is a PATCH with submitted=true; there is no /submit action.
    client.request(
        "PATCH",
        f"/reviewSubmissions/{submission_id}",
        body={"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}},
    )
    print(f"  submitted App Store version {version_id} for review (submission {submission_id})")


# MARK: - Entry point


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--metadata-dir", type=Path, default=METADATA_DIR, help="store/metadata/ios")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--version", help="Marketing version from the release tag (v2.0.2 → 2.0.2)")
    parser.add_argument("--build-id", help="App Store Connect id of the build uploaded by this run")
    parser.add_argument("--build-number", help="CFBundleVersion of the build uploaded by this run")
    parser.add_argument("--dry-run", action="store_true", help="Validate switches and local files only — no network")
    args = parser.parse_args(argv)

    do_listing = truthy("UPLOAD_LISTING")
    do_whats_new = truthy("UPLOAD_WHATS_NEW")
    do_screenshots = truthy("UPLOAD_SCREENSHOTS")
    do_submit = truthy("SUBMIT_IOS_REVIEW")
    do_public = truthy("PUBLIC_RELEASE")

    if not (do_listing or do_whats_new or do_screenshots or do_submit):
        print("ASC release skipped — UPLOAD_LISTING / UPLOAD_WHATS_NEW / UPLOAD_SCREENSHOTS / SUBMIT_IOS_REVIEW are off")
        return
    if do_public and not do_submit:
        fail("PUBLIC_RELEASE only applies when SUBMIT_IOS_REVIEW is on")
    if do_submit and not (args.build_id and args.build_number):
        fail("submitting needs --build-id and --build-number for the build uploaded by this run; an older build is never substituted")

    plan = validate_local_inputs(
        upload_listing=do_listing,
        upload_whats_new=do_whats_new,
        upload_screenshots=do_screenshots,
        metadata_dir=args.metadata_dir,
    )
    if args.dry_run:
        print(
            f"ASC dry-run — local inputs OK for {', '.join(plan) or 'no locales'}; no API calls "
            f"(listing={do_listing} whats_new={do_whats_new} screenshots={do_screenshots} "
            f"submit={do_submit} public_release={do_public})"
        )
        return

    if not args.version:
        fail("--version is required for live App Store Connect calls")
    client = client_from_environment()
    app_id = find_app(client, args.bundle_id)
    version = get_ios_app_store_version(client, app_id, args.version)
    version_id = version["id"]
    state = (version.get("attributes") or {}).get("appStoreState") or ""
    print(f"ASC app={app_id} version={args.version} id={version_id} state={state}")
    edits_metadata = do_listing or do_whats_new or do_screenshots

    if state == "WAITING_FOR_REVIEW":
        if edits_metadata:
            fail(f"cannot change the listing while version {args.version} is WAITING_FOR_REVIEW")
        # A rerun after a successful submit: only accept it if review holds this run's build.
        confirm_selected_build(client, version_id, args.build_id)
        print("ASC submit skipped — version already WAITING_FOR_REVIEW with this run's build (idempotent)")
        return
    if edits_metadata and state not in EDITABLE_VERSION_STATES:
        fail(
            f"version {args.version} is not editable (state={state}); expected one of "
            f"{', '.join(sorted(EDITABLE_VERSION_STATES))}"
        )
    if do_submit and state not in SUBMITTABLE_VERSION_STATES:
        fail(f"version {args.version} cannot be submitted for review (state={state})")

    for locale, entry in plan.items():
        if do_listing:
            upload_app_info_fields(client, app_id, locale, entry["app_info"])
            upload_version_fields(client, version_id, locale, entry["version"], "listing")
        if do_whats_new:
            upload_whats_new(client, app_id, version_id, locale, entry["whats_new"])
        if do_screenshots:
            upload_screenshots(client, version_id, locale, entry["screenshots"])

    if do_submit:
        pending = pending_in_app_products(client, app_id)
        if pending:
            fail(
                "App Store Connect has in-app products that would have to go to review with this "
                f"version ({'; '.join(pending)}). Scowld's release automation does not submit "
                "in-app purchases; submit them in App Store Connect or extend the automation, then rerun."
            )
        print("selecting this run's build…")
        select_build(client, version_id, args.build_id, args.version, args.build_number)
        set_release_type(client, version_id, public_release=do_public)
        submission_id = get_or_create_draft_submission(client, app_id)
        already_added = draft_holds_version(client, submission_id, version_id)
        # Recheck immediately before submitting: the selection must still be this run's build.
        verify_build(client, args.build_id, args.version, args.build_number)
        confirm_selected_build(client, version_id, args.build_id)
        print("submitting for App Store review…")
        submit_for_review(client, submission_id, version_id, already_added=already_added)

    print("ASC release step finished")


if __name__ == "__main__":
    main()
