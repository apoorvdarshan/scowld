#!/usr/bin/env python3
"""App Store Connect listing, What's New, screenshots, creative assets and review submission.

Every operation has its own switch. ios-release.yml sets these environment
flags from the resolved IOS_* repository variables:

  UPLOAD_LISTING      name, subtitle, privacy policy URL, description, keywords,
                      promotional text, marketing and support URLs
  UPLOAD_WHATS_NEW    What's New
  UPLOAD_SCREENSHOTS  the screenshots listed in each locale's screenshots.json
                      (iPhone, iPad, iPhone Duo and Apple Watch sets), uploaded
                      as RGB copies
  UPLOAD_CREATIVE_ASSETS
                      product page header and search results images
                      (store/creative/ios)
  SUBMIT_IOS_REVIEW   select THIS run's processed build and submit for review
  PUBLIC_RELEASE      release automatically after approval (otherwise manual)
  CREATE_IOS_VERSION  with --create-version: create the tag's App Store version
                      when it is missing

The listing lives in store/metadata/ios/<locale>/ (exported from the live App
Store listing by asc_export_listing.py), so the repository is its source of
truth. Only fields whose text differs from App Store Connect are sent. What's
New must be plain text: App Store Connect shows Markdown literally, so it is
refused.

Screenshots are uploaded from RGB copies in a temporary folder, never from the
committed files: App Store Connect refuses a PNG that stores an alpha channel,
even when every pixel is opaque. A PNG that already is RGB without alpha is
copied byte for byte (so it still matches the set App Store Connect holds); any
other one has its transparent pixels laid over black, colour profile kept.

Product page header and search results images (UPLOAD_CREATIVE_ASSETS) live in
the app's Asset Library. A new image is uploaded once, sent to App Review in a
review submission of its own (never the version's draft), and placed on the
version's en-US localization once Apple approves it.

Reruns are idempotent. In READY_FOR_REVIEW (the version already sits in a draft
review submission) text can still change but screenshots and creative
placements cannot; in WAITING_FOR_REVIEW (already submitted) nothing can. A
step that can no longer change only checks that App Store Connect already
matches the repository, and those checks run before anything is written.

Scowld's in-app products (tips, and Scowld Premium's subscriptions and minute
packs) are not submitted by this script: submission stops instead if App Store
Connect holds products that would have to go to review with the version, so
new products are added to the version's submission in App Store Connect by hand.

`--create-version` (IOS_CREATE_VERSION) runs first on a release run: it adds the
App Store version for the tag when App Store Connect does not have it yet, and
leaves an existing one alone. It refuses when another version is still on its
way to the store or the tag's version is not newer than every existing one.

`--dry-run` validates the switches and local files only (no network), staging
the RGB screenshot copies as the store step does.
`--preflight` uses GET requests only, before the build is uploaded: the version
exists in a state that allows the enabled steps and has every repository
locale, What's New differs from the live version, screenshots that can no
longer change already match, no in-app product would have to ship with it, the
draft the version goes out in is usable, and the header and search results
images can go on the version now.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import struct
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[2]
ASC_BASE = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_BUNDLE_ID = "com.apoorvdarshan.Scowld"
# Scowld's App Store Connect app (apps.apple.com/app/id6760672848).
DEFAULT_APP_ID = "6760672848"
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
# App Store Connect shows What's New as plain text, so Markdown would appear
# literally on the App Store. "- " bullets are plain text and fine.
MARKDOWN_SYNTAX = (
    (re.compile(r"\*\*|__"), "bold markers (** or __)"),
    (re.compile(r"`"), "backticks"),
    (re.compile(r"\[[^\]\n]+\]\([^)\n]*\)"), "links [text](url)"),
    (re.compile(r"^ {0,3}#{1,6}(\s|$)", re.MULTILINE), "headings (#)"),
)
SCREENSHOT_MANIFEST = "screenshots.json"

# Accepted portrait sizes per App Store Connect display type (landscape = swapped).
SCREENSHOT_SIZES = {
    "APP_IPHONE_67": {(1260, 2736), (1290, 2796), (1320, 2868), (1284, 2778)},
    "APP_IPHONE_65": {(1242, 2688), (1284, 2778)},
    "APP_IPAD_PRO_3GEN_129": {(2048, 2732), (2064, 2752)},
    # One iPhone Duo set takes both screens: outer 1398x2034 and inner 2007x2853.
    # APP_IPHONE_DUO is not in Apple's OpenAPI spec yet, but App Store Connect accepts it.
    "APP_IPHONE_DUO": {(1398, 2034), (2007, 2853)},
}
# Apple Watch screenshots are listed under this key in screenshots.json. The
# sets are optional: without the key the live Watch sets are left alone. Each
# frame's size picks its display type (Apple's screenshot specifications), so
# one list can fill more than one Watch set; the Watch sets go after the others.
WATCH_KEY = "watch"
WATCH_DISPLAY_TYPES = {
    (416, 496): "APP_WATCH_SERIES_10",  # Series 10 and 11
    (422, 514): "APP_WATCH_ULTRA",  # Ultra 3
    (410, 502): "APP_WATCH_ULTRA",  # Ultra and Ultra 2
    (396, 484): "APP_WATCH_SERIES_7",  # Series 7 to 9
    (368, 448): "APP_WATCH_SERIES_4",  # Series 4 to 6 and SE
    (312, 390): "APP_WATCH_SERIES_3",
}
WATCH_LABELS = {
    "APP_WATCH_SERIES_10": "Apple Watch Series 10",
    "APP_WATCH_ULTRA": "Apple Watch Ultra",
    "APP_WATCH_SERIES_7": "Apple Watch Series 7",
    "APP_WATCH_SERIES_4": "Apple Watch Series 4",
    "APP_WATCH_SERIES_3": "Apple Watch Series 3",
}
SCREENSHOT_SET_MAX = 10
SCREENSHOT_PROCESSING_SECONDS = 300
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# PNG chunks that describe colour, copied from a screenshot to its RGB copy
# (Pillow writes an ICC profile, iCCP, itself).
PNG_COLOUR_CHUNKS = (b"sRGB", b"gAMA", b"cHRM", b"cICP")

# Product page creative assets: the folder under --creative-dir, the placement
# type, a label for logs, and the formats Apple takes. Each folder holds at most
# one image; a slot without an image is left alone.
HEADER_PLACEMENT = "PRODUCT_PAGE_HEADER_ASSET"
SEARCH_PLACEMENT = "APP_STORE_SEARCH_RESULTS_ASSET"
CREATIVE_SLOTS = (
    ("header", HEADER_PLACEMENT, "product page header", ("png",)),
    ("search-results", SEARCH_PLACEMENT, "search results", ("png", "jpeg")),
)
CREATIVE_EXTENSIONS = {".png": "png", ".jpg": "jpeg", ".jpeg": "jpeg"}
# Apple's image specs: the header is a 3840x1646 PNG; search results images are
# 3:2 PNG or JPEG from 1920x1280 to 3840x2560.
HEADER_SIZE = (3840, 1646)
SEARCH_RESULTS_WIDTHS = (1920, 3840)
CREATIVE_PLACEMENT_GROUP = "DEFAULT_PROFILE"
DEFAULT_CREATIVE_DIR = ROOT / "store" / "creative" / "ios"
# The images go on this localization of the version only.
CREATIVE_LOCALE = "en-US"
# Asset Library image states (AppAssetLibraryAssetState). AWAITING_UPLOAD is the
# reservation an interrupted upload leaves behind: like a failed or archived
# image it is ignored, and the image is uploaded again.
CREATIVE_DEAD_STATES = {"AWAITING_UPLOAD", "FAILED", "ARCHIVED", "REJECTED"}
# Uploaded and still being processed; App Review takes it once it is ready.
CREATIVE_PROCESSING_STATES = {"UPLOAD_COMPLETE", "COMPLETE"}
# Processed, not yet submitted (READY_FOR_REVIEW: in a draft review submission).
CREATIVE_READY_STATES = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW"}
CREATIVE_PENDING_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED"}
# Processing a freshly uploaded image usually takes seconds.
CREATIVE_PROCESSING_TIMEOUT_SECONDS = 600
CREATIVE_POLL_SECONDS = 5
# A review submission item's relationships, requested explicitly (App Store
# Connect leaves them out otherwise).
DRAFT_ITEM_INCLUDE = "subscriptionVersion,appStoreVersion,inAppPurchaseVersion,appAssetLibraryImage"

# Everything (text and screenshots) can change in these version states.
EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}
# READY_FOR_REVIEW means the version already sits in a draft review submission
# (for example after a failed submit). Its listing and What's New text can still
# change and it can still be submitted, but its screenshots can no longer be
# replaced, so they are only checked against the repository.
TEXT_EDITABLE_VERSION_STATES = EDITABLE_VERSION_STATES | {"READY_FOR_REVIEW"}
SUBMITTABLE_VERSION_STATES = TEXT_EDITABLE_VERSION_STATES
# WAITING_FOR_REVIEW after this pipeline's own submit (a rerun): nothing can change,
# so every enabled operation only checks that App Store Connect already matches.
SUBMITTED_VERSION_STATE = "WAITING_FOR_REVIEW"
# App info (name, subtitle, privacy URL) is editable while its version is.
EDITABLE_APP_INFO_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "READY_FOR_REVIEW",
}
LIVE_APP_INFO_STATES = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE"}
LIVE_VERSION_STATES = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
# Versions in these states are finished. Any other state means the version is
# still on its way to the store, and App Store Connect allows only one such
# version per platform, so no new version is created next to it.
FINISHED_VERSION_STATES = {
    "READY_FOR_SALE",
    "REPLACED_WITH_NEW_VERSION",
    "REMOVED_FROM_SALE",
    "DEVELOPER_REMOVED_FROM_SALE",
}
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


def markdown_syntax(text: str) -> list[str]:
    """The kinds of Markdown syntax found in text (empty for plain text)."""
    return [label for pattern, label in MARKDOWN_SYNTAX if pattern.search(text)]


def attrs(row: dict[str, Any] | None) -> dict[str, Any]:
    return (row or {}).get("attributes") or {}


def related_id(row: dict[str, Any], name: str) -> str | None:
    """The id a JSON:API row's `name` relationship points at, if it was included."""
    related = (((row.get("relationships") or {}).get(name) or {}).get("data")) or {}
    return related.get("id") if isinstance(related, dict) else None


# MARK: - Image files


def png_chunks(raw: bytes, *, strict: bool = True) -> list[tuple[bytes, bytes]]:
    """(type, data) of every chunk of a PNG, up to IEND.

    Raises ValueError when the bytes are not a PNG with an IHDR header. Strict
    (the default) also requires a well-formed file: every chunk complete with a
    matching CRC, image data that decompresses to the rows the header describes,
    and a final IEND, so a truncated or corrupt file fails before anything is
    uploaded. Lenient reading (deciding how to copy a screenshot, which only
    needs the header) stops at the first chunk that runs past the end of the file.
    """
    if not raw.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG")
    chunks: list[tuple[bytes, bytes]] = []
    offset = len(PNG_SIGNATURE)
    while offset + 8 <= len(raw):
        length = int.from_bytes(raw[offset : offset + 4], "big")
        kind = raw[offset + 4 : offset + 8]
        start = offset + 8
        end = start + length
        if end + (4 if strict else 0) > len(raw):
            if strict or not chunks:
                raise ValueError(f"truncated {kind.decode('latin-1')!r} chunk")
            break
        data = raw[start:end]
        if strict and zlib.crc32(kind + data) != int.from_bytes(raw[end : end + 4], "big"):
            raise ValueError(f"the {kind.decode('latin-1')!r} chunk fails its CRC check")
        chunks.append((kind, data))
        offset = end + 4  # data, then the CRC
        if kind == b"IEND":
            break
    if not chunks or chunks[0][0] != b"IHDR" or len(chunks[0][1]) < 13:
        raise ValueError("no IHDR header")
    if strict:
        if chunks[-1][0] != b"IEND":
            raise ValueError("no IEND chunk (the file is truncated)")
        check_png_image_data(chunks)
    return chunks


# Samples per pixel for each PNG colour type.
PNG_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def check_png_image_data(chunks: list[tuple[bytes, bytes]]) -> None:
    """Raises ValueError unless the IDAT data is one complete zlib stream of the header's size.

    Decompresses in bounded steps; the size is checked for non-interlaced images
    (Pillow writes those), an interlaced image only needs a complete stream.
    """
    header = chunks[0][1]
    width, height = png_size(chunks)
    bit_depth, colour_type, interlace = header[8], header[9], header[12]
    if colour_type not in PNG_CHANNELS:
        raise ValueError(f"unknown PNG colour type {colour_type}")
    idat = [data for kind, data in chunks if kind == b"IDAT"]
    if not idat:
        raise ValueError("no image data (IDAT)")
    inflater = zlib.decompressobj()
    size = 0
    try:
        for data in idat:
            pending = data
            while pending:
                size += len(inflater.decompress(pending, 1 << 20))
                pending = inflater.unconsumed_tail
        size += len(inflater.flush())
    except zlib.error as exc:
        raise ValueError(f"the image data does not decompress ({exc})") from None
    if not inflater.eof:
        raise ValueError("the image data ends early (the file is truncated)")
    if interlace == 0:
        expected = height * (1 + (width * PNG_CHANNELS[colour_type] * bit_depth + 7) // 8)
        if size != expected:
            raise ValueError(
                f"the image data holds {size} bytes, not the {expected} a {width}x{height} image needs"
            )


def png_size(chunks: list[tuple[bytes, bytes]]) -> tuple[int, int]:
    header = chunks[0][1]
    return int.from_bytes(header[0:4], "big"), int.from_bytes(header[4:8], "big")


def png_stores_alpha(chunks: list[tuple[bytes, bytes]]) -> bool:
    """True when a PNG stores alpha: grey or RGB with alpha (colour type 4 or 6), or a tRNS chunk.

    App Store Connect refuses such files even when every pixel is opaque.
    """
    colour_type = chunks[0][1][9]
    return colour_type in (4, 6) or any(kind == b"tRNS" for kind, _ in chunks)


def jpeg_size(raw: bytes) -> tuple[int, int] | None:
    """(width, height) from a JPEG's start-of-frame segment, or None when there is none."""
    if raw[:3] != b"\xff\xd8\xff":
        return None
    offset = 2
    while offset + 9 < len(raw):
        if raw[offset] != 0xFF:
            offset += 1
            continue
        marker = raw[offset + 1]
        if marker == 0xFF:
            offset += 1
            continue
        if marker in (0x01, 0xD8) or 0xD0 <= marker <= 0xD7:
            offset += 2
            continue
        # SOF0-SOF15, except DHT (C4), JPG (C8) and DAC (CC).
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height = int.from_bytes(raw[offset + 5 : offset + 7], "big")
            width = int.from_bytes(raw[offset + 7 : offset + 9], "big")
            return width, height
        offset += 2 + int.from_bytes(raw[offset + 2 : offset + 4], "big")
    return None


def staged_png(path: Path, label: str) -> tuple[int, int]:
    """The size of a staged screenshot; fails unless it is a PNG without alpha.

    The last guard before upload: staging (stage_screenshots) writes RGB, so a
    file that still stores alpha was not staged by it.
    """
    try:
        chunks = png_chunks(path.read_bytes())
    except ValueError as exc:
        fail(f"the {label} screenshot {path.name} is not a readable PNG ({exc})")
    if png_stores_alpha(chunks):
        fail(
            f"the {label} screenshot {path.name} stores an alpha channel (PNG colour type 4 or 6, "
            "or a tRNS chunk), which App Store Connect refuses; screenshots are uploaded from the "
            "RGB copies stage_screenshots makes, never as they are"
        )
    return png_size(chunks)


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
            f"{version_string} there (App Store tab, + Version) and rerun the failed job, or turn on "
            "IOS_CREATE_VERSION so the release run creates it"
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


def image_size(path: Path) -> tuple[int, int]:
    """(width, height) of a PNG or JPEG file, read from its header."""
    data = path.read_bytes()
    if data[:8] == PNG_SIGNATURE and data[12:16] == b"IHDR":
        width, height = struct.unpack(">II", data[16:24])
        return width, height
    size = jpeg_size(data)
    if size is None:
        fail(f"{path} is not a PNG or JPEG image")
    return size


def load_screenshot_manifest(loc_dir: Path, root: Path = ROOT) -> dict[str, list[Path]]:
    """Validate <locale>/screenshots.json: display type → ordered image paths (repo-relative).

    Apple Watch frames are listed under "watch": each frame's size picks its
    display type (watch_sets), and the Watch sets come after the others.
    Whether a file stores alpha is settled when it is staged (stage_screenshots).
    """
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
    watch: list[Path] = []
    for display_type, entries in manifest.items():
        accepted = SCREENSHOT_SIZES.get(display_type)
        if accepted is None and display_type != WATCH_KEY:
            fail(
                f"{manifest_path}: unsupported display type {display_type!r}; use one of "
                f"{sorted(SCREENSHOT_SIZES)}, or {WATCH_KEY!r} for Apple Watch frames"
            )
        if not isinstance(entries, list) or not entries or not all(isinstance(e, str) for e in entries):
            fail(f"{manifest_path}: {display_type} must list at least one image path")
        files: list[Path] = []
        for entry in entries:
            path = (root / entry).resolve()
            if root.resolve() not in path.parents or not path.is_file():
                fail(f"{manifest_path}: {entry} is not an image file in this repository")
            if accepted is not None:
                width, height = image_size(path)
                if (width, height) not in accepted and (height, width) not in accepted:
                    sizes = ", ".join(f"{w}x{h}" for w, h in sorted(accepted))
                    fail(f"{entry} is {width}x{height}; {display_type} accepts {sizes} (or landscape)")
            files.append(path)
        if accepted is None:
            watch.extend(files)
        else:
            plan[display_type] = files
    plan.update(watch_sets(watch))
    for display_type, files in plan.items():
        if len(files) > SCREENSHOT_SET_MAX:
            fail(
                f"{manifest_path}: {display_type} lists {len(files)} images; App Store Connect "
                f"allows {SCREENSHOT_SET_MAX}"
            )
    return plan


def watch_sets(frames: list[Path]) -> dict[str, list[Path]]:
    """The Apple Watch frames grouped by the display type their size belongs to, in the listed order."""
    groups: dict[str, list[Path]] = {}
    for path in frames:
        size = image_size(path)
        display_type = WATCH_DISPLAY_TYPES.get(size)
        if display_type is None:
            accepted = ", ".join(f"{w}x{h}" for w, h in WATCH_DISPLAY_TYPES)
            fail(
                f"the Apple Watch screenshot {path.name} is {size[0]}x{size[1]}, which is not an "
                f"Apple Watch screenshot size ({accepted})"
            )
        groups.setdefault(display_type, []).append(path)
    return groups


def validate_local_inputs(
    *,
    upload_listing: bool,
    upload_whats_new: bool,
    upload_screenshots: bool,
    metadata_dir: Path,
    root: Path = ROOT,
    upload_creative: bool = False,
    creative_dir: Path | None = None,
) -> dict[str, dict[str, Any]]:
    """Check every enabled operation's local files before any network call."""
    plan: dict[str, dict[str, Any]] = {}
    if upload_creative:
        creative_sources(creative_dir or DEFAULT_CREATIVE_DIR)
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
            found = markdown_syntax(whats_new[WHATS_NEW_FIELD[0]])
            if found:
                fail(
                    f"{loc_dir / WHATS_NEW_FIELD[1]} uses Markdown ({', '.join(found)}); App Store "
                    "Connect shows it literally, so write plain text ('- ' bullets are fine)"
                )
            entry["whats_new"] = whats_new[WHATS_NEW_FIELD[0]]
        if upload_screenshots:
            entry["screenshots"] = load_screenshot_manifest(loc_dir, root)
        plan[locale] = entry
    return plan


# MARK: - RGB screenshot copies


def try_import_pillow():
    try:
        from PIL import Image  # type: ignore[import-untyped]  # noqa: PLC0415 - only screenshots need Pillow

        return Image
    except ImportError:
        return None


def opaque_rgb(Image, img):
    """The image as RGB, with transparent pixels laid over black."""
    rgba = img.convert("RGBA")
    canvas = Image.new("RGB", rgba.size, (0, 0, 0))
    canvas.paste(rgba, mask=rgba.getchannel("A"))
    return canvas


def colour_chunks(raw: bytes) -> list[tuple[bytes, bytes]]:
    """The source PNG's colour chunks other than its ICC profile (Pillow keeps that one)."""
    try:
        chunks = png_chunks(raw, strict=False)
    except ValueError:
        return []
    return [(kind, data) for kind, data in chunks if kind in PNG_COLOUR_CHUNKS]


def prepare_asc_png(Image, raw: bytes) -> bytes:
    """An RGB PNG of the frame, without alpha, colour profile kept.

    Transparent pixels are laid over black once; the size never changes (the
    manifest only lists frames at a size App Store Connect accepts).
    """
    from PIL import PngImagePlugin  # type: ignore[import-untyped]  # noqa: PLC0415

    with Image.open(io.BytesIO(raw)) as img:
        icc_profile = img.info.get("icc_profile")
        out_img = opaque_rgb(Image, img)
    info = PngImagePlugin.PngInfo()
    for kind, data in colour_chunks(raw):
        info.add(kind, data)
    out = io.BytesIO()
    options = {"icc_profile": icc_profile} if icc_profile else {}
    out_img.save(out, format="PNG", pnginfo=info, **options)
    return out.getvalue()


def rgb_copy(Image, path: Path, label: str) -> bytes:
    """The bytes App Store Connect gets for a screenshot: the file as RGB, without alpha.

    A JPEG, or a PNG that already is RGB without alpha (colour type 2, no tRNS
    chunk), is its own RGB copy, so it is copied byte for byte and its checksum
    still matches the set App Store Connect holds. Any other PNG is converted
    with Pillow. Without Pillow it is copied as it is, so it must not store alpha.
    """
    raw = path.read_bytes()
    if not raw.startswith(PNG_SIGNATURE):
        return raw  # a JPEG (image_size reads nothing else), which never stores alpha
    try:
        chunks = png_chunks(raw, strict=False)
    except ValueError as exc:
        fail(f"the {label} screenshot {path.name} is not a readable PNG ({exc})")
    if chunks[0][1][9] == 2 and not png_stores_alpha(chunks):
        return raw  # staged_png checks the copy is complete and well formed
    if Image is None:
        if png_stores_alpha(chunks):
            fail(
                f"{label} {path.name}: App Store screenshots cannot store an alpha channel; install "
                "Pillow (requirements-store.txt) so staging can flatten it, or re-export it as RGB"
            )
        return raw
    try:
        png_chunks(raw)  # Pillow only gets a complete, well-formed file
    except ValueError as exc:
        fail(f"the {label} screenshot {path.name} is not a readable PNG ({exc})")
    return prepare_asc_png(Image, raw)


def stage_screenshots(plan: dict[str, dict[str, Any]], staging_dir: Path) -> None:
    """Point every locale's screenshots at RGB copies in staging_dir.

    The committed files are only read, never rewritten. Each copy keeps its file
    name and goes through the last guard before upload (staged_png; a JPEG must
    be readable), so a file App Store Connect would refuse stops the run before
    any call.
    """
    Image = try_import_pillow()
    copies: dict[Path, Path] = {}
    for locale, entry in plan.items():
        for display_type, files in (entry.get("screenshots") or {}).items():
            label = f"{WATCH_LABELS.get(display_type, display_type)} ({locale})"
            for index, path in enumerate(files):
                if path not in copies:
                    data = rgb_copy(Image, path, label)
                    copy = staging_dir / str(len(copies)) / path.name
                    copy.parent.mkdir(parents=True)
                    copy.write_bytes(data)
                    if data.startswith(PNG_SIGNATURE):
                        staged_png(copy, label)
                    elif jpeg_size(data) is None:
                        fail(f"the {label} screenshot {path.name} is not a readable JPEG")
                    copies[path] = copy
                files[index] = copies[path]


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


def refuse_locked_change(label: str, locale: str, changes: Any, locked: str) -> None:
    """A change is needed, but App Store Connect no longer allows it (see `locked`)."""
    fail(
        f"{label} ({locale}) differs from App Store Connect ({', '.join(sorted(changes))}), but {locked}; "
        "change it in App Store Connect (or remove the version from review) so both match, then rerun"
    )


def app_info_state(info: dict[str, Any]) -> str:
    attrs = info.get("attributes") or {}
    return attrs.get("state") or attrs.get("appStoreState") or ""


def upload_version_fields(
    client: Any, version_id: str, locale: str, wanted: dict[str, str], label: str, *, locked: str | None = None
) -> None:
    """Send only the fields that differ. With `locked` (the reason edits are no longer
    allowed), nothing is written: matching fields pass, differing fields fail."""
    loc = localization_for_locale(client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", locale)
    if loc is None:
        fail(f"version has no {locale} localization in App Store Connect; add the language there first")
    changes = changed_fields(loc.get("attributes") or {}, wanted)
    if not changes:
        print(f"  {label} ({locale}): already up to date")
        return
    if locked:
        refuse_locked_change(label, locale, changes, locked)
    client.patch(
        f"/appStoreVersionLocalizations/{loc['id']}",
        {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": changes}},
    )
    print(f"  {label} ({locale}): updated {', '.join(sorted(changes))}")


def app_info_for_listing(client: Any, app_id: str) -> tuple[dict[str, Any], bool]:
    """(app info record the listing is compared with, whether it is editable).

    The editable record (it ships with the new version) wins. Without one, the record
    already submitted with a version (a rerun after submitting) is compared, and
    otherwise the live one.
    """
    infos = iter_collection(client, f"/apps/{app_id}/appInfos")
    editable = [info for info in infos if app_info_state(info) in EDITABLE_APP_INFO_STATES]
    if len(editable) > 1:
        fail(f"ambiguous: {len(editable)} editable app infos")
    if editable:
        return editable[0], True
    retired = LIVE_APP_INFO_STATES | {"REPLACED_WITH_NEW_INFO", "REPLACED_WITH_NEW_VERSION"}
    submitted = [info for info in infos if app_info_state(info) not in retired]
    live = [info for info in infos if app_info_state(info) in LIVE_APP_INFO_STATES]
    source = submitted[0] if len(submitted) == 1 else next(iter(live or infos), None)
    if source is None:
        fail("app has no app info in App Store Connect")
    return source, False


def upload_app_info_fields(
    client: Any, app_id: str, locale: str, wanted: dict[str, str], *, locked: str | None = None
) -> None:
    """Name, subtitle and privacy URL live on the app info that ships with the version."""
    if not wanted:
        return
    info, editable = app_info_for_listing(client, app_id)
    loc = localization_for_locale(client, f"/appInfos/{info['id']}/appInfoLocalizations", locale)
    if loc is None:
        fail(f"app info has no {locale} localization in App Store Connect; add the language there first")
    changes = changed_fields(loc.get("attributes") or {}, wanted)
    if not changes:
        print(f"  app name/subtitle/privacy URL ({locale}): already up to date")
        return
    if locked:
        refuse_locked_change("app name/subtitle/privacy URL", locale, changes, locked)
    if not editable:
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


def refuse_stale_whats_new(client: Any, app_id: str, version_id: str, locale: str, text: str) -> None:
    previous = live_whats_new(client, app_id, version_id, locale)
    if previous and previous[1] == text:
        fail(
            f"What's New ({locale}) is identical to live version {previous[0]}; update "
            f"store/metadata/ios/{locale}/{WHATS_NEW_FIELD[1]} for this release"
        )


def upload_whats_new(
    client: Any, app_id: str, version_id: str, locale: str, text: str, *, locked: str | None = None
) -> None:
    refuse_stale_whats_new(client, app_id, version_id, locale, text)
    upload_version_fields(client, version_id, locale, {WHATS_NEW_FIELD[0]: text}, "What's New", locked=locked)


# MARK: - Screenshots


def md5_hex(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()  # noqa: S324 - App Store Connect's checksum


def find_screenshot_set(client: Any, version_loc_id: str, display_type: str) -> str | None:
    for item in iter_collection(client, f"/appStoreVersionLocalizations/{version_loc_id}/appScreenshotSets?limit=50"):
        if (item.get("attributes") or {}).get("screenshotDisplayType") == display_type:
            return item["id"]
    return None


def ensure_screenshot_set(client: Any, version_loc_id: str, display_type: str) -> str:
    existing = find_screenshot_set(client, version_loc_id, display_type)
    if existing is not None:
        return existing
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


def send_upload_operations(client: Any, reserved: dict[str, Any], raw: bytes, name: str) -> None:
    """Send a file's bytes the way the reservation's uploadOperations ask for."""
    operations = attrs(reserved).get("uploadOperations") or []
    if not operations:
        fail(f"App Store Connect returned no upload operations for {name}")
    for op in operations:
        offset = int(op.get("offset", 0))
        chunk = raw[offset:offset + int(op["length"])]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        client.upload_bytes(op["url"], chunk, headers, method=op.get("method") or "PUT")


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
    send_upload_operations(client, reserved, raw, path.name)
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


def sync_screenshot_set(
    client: Any,
    version_loc_id: str,
    locale: str,
    display_type: str,
    files: list[Path],
    *,
    locked: str | None = None,
) -> None:
    """Replace the set when its images differ. With `locked`, nothing is written:
    an identical set passes and a differing one fails."""
    set_id = find_screenshot_set(client, version_loc_id, display_type)
    current = iter_collection(client, f"/appScreenshotSets/{set_id}/appScreenshots?limit=50") if set_id else []
    wanted = [md5_hex(path) for path in files]
    if [(row.get("attributes") or {}).get("sourceFileChecksum") for row in current] == wanted:
        print(f"  screenshots {display_type} ({locale}): already up to date")
        return
    if locked:
        refuse_locked_change(f"screenshots {display_type}", locale, ["images"], locked)
    if set_id is None:
        set_id = ensure_screenshot_set(client, version_loc_id, display_type)
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


def upload_screenshots(
    client: Any, version_id: str, locale: str, plan: dict[str, list[Path]], *, locked: str | None = None
) -> None:
    loc = localization_for_locale(client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", locale)
    if loc is None:
        fail(f"version has no {locale} localization in App Store Connect; add the language there first")
    if not any(display_type in WATCH_LABELS for display_type in plan):
        print(f"  no Apple Watch screenshots listed ({locale}); the Watch sets in App Store Connect are left alone")
    for display_type, files in plan.items():
        sync_screenshot_set(client, loc["id"], locale, display_type, files, locked=locked)


def sync_metadata(
    client: Any,
    *,
    app_id: str,
    version_id: str,
    plan: dict[str, dict[str, Any]],
    listing: bool,
    whats_new: bool,
    screenshots: bool,
    text_locked: str | None,
    screenshots_locked: str | None,
    check_only: bool = False,
) -> None:
    """Listing, What's New and screenshots for every locale.

    An operation App Store Connect no longer allows for this version (`*_locked` holds
    the reason) only checks that App Store Connect already matches the repository,
    which keeps reruns idempotent. Those checks run first, so a change that cannot be
    made fails before anything is written. `check_only` runs just those checks.
    """
    for locked_pass in ((True,) if check_only else (True, False)):
        for locale, entry in plan.items():
            if listing and (text_locked is not None) is locked_pass:
                upload_app_info_fields(client, app_id, locale, entry["app_info"], locked=text_locked)
                upload_version_fields(client, version_id, locale, entry["version"], "listing", locked=text_locked)
            if whats_new and (text_locked is not None) is locked_pass:
                upload_whats_new(client, app_id, version_id, locale, entry["whats_new"], locked=text_locked)
            if screenshots and (screenshots_locked is not None) is locked_pass:
                upload_screenshots(client, version_id, locale, entry["screenshots"], locked=screenshots_locked)


def metadata_locks(version_string: str, state: str) -> tuple[str | None, str | None]:
    """(text lock, screenshot lock) for this version state; None = may change."""
    text_locked = None
    if state == SUBMITTED_VERSION_STATE:
        text_locked = f"version {version_string} is {state} and can no longer be edited"
    screenshots_locked = None
    if state not in EDITABLE_VERSION_STATES:
        screenshots_locked = f"version {version_string} is {state}, where screenshots can no longer change"
    return text_locked, screenshots_locked


# MARK: - Header and search results images


def creative_problem(placement_type: str, path: Path, formats: tuple[str, ...]) -> str | None:
    """Why App Store Connect would refuse this image for the slot, or None when it fits."""
    raw = path.read_bytes()
    kind = "png" if raw.startswith(PNG_SIGNATURE) else "jpeg" if raw[:3] == b"\xff\xd8\xff" else None
    if kind is None:
        return "is not a PNG or JPEG file"
    if CREATIVE_EXTENSIONS[path.suffix.lower()] != kind:
        return f"holds {kind.upper()} data but is named {path.suffix}"
    if kind not in formats:
        return f"is a {kind.upper()}; this slot takes {' or '.join(f.upper() for f in formats)}"
    if kind == "png":
        try:
            chunks = png_chunks(raw)
        except ValueError as exc:
            return f"is not a readable PNG ({exc})"
        if png_stores_alpha(chunks):
            return (
                "stores an alpha channel (PNG colour type 4 or 6, or a tRNS chunk), which App Store "
                "Connect refuses; re-export it as RGB"
            )
        width, height = png_size(chunks)
    else:
        size = jpeg_size(raw)
        if size is None:
            return "is not a readable JPEG"
        width, height = size
    if placement_type == HEADER_PLACEMENT:
        if (width, height) != HEADER_SIZE:
            return f"is {width}x{height}; the header must be exactly {HEADER_SIZE[0]}x{HEADER_SIZE[1]}"
        return None
    low, high = SEARCH_RESULTS_WIDTHS
    if not (low <= width <= high and width * 2 == height * 3):
        return (
            f"is {width}x{height}; search results images are 3:2, from {low}x{low * 2 // 3} "
            f"to {high}x{high * 2 // 3}"
        )
    return None


def creative_sources(creative_dir: Path) -> list[tuple[str, str, Path]]:
    """(placement type, label, image) for every creative slot that has an image.

    Checks each image's format, size and alpha first, so a file App Store
    Connect would refuse stops the run before any call. Fails when no slot has
    an image.
    """
    found = []
    for folder, placement_type, label, formats in CREATIVE_SLOTS:
        slot_dir = creative_dir / folder
        images = sorted(
            p
            for p in (slot_dir.iterdir() if slot_dir.is_dir() else [])
            if p.is_file() and p.suffix.lower() in CREATIVE_EXTENSIONS
        )
        if len(images) > 1:
            fail(f"the {label} slot takes one image; {slot_dir} has {len(images)}")
        if not images:
            print(f"  no {label} image in {slot_dir}; that slot is left alone")
            continue
        problem = creative_problem(placement_type, images[0], formats)
        if problem:
            fail(f"the {label} image {images[0].name} {problem}")
        found.append((placement_type, label, images[0]))
    if not found:
        fail(f"creative asset upload is on, but {creative_dir} has no header or search results image")
    return found


def asset_library_id(client: Any, app_id: str) -> str:
    library_id = (client.get(f"/apps/{app_id}/assetLibrary").get("data") or {}).get("id")
    if not library_id:
        fail(f"App Store Connect returned no Asset Library for app {app_id}")
    return library_id


def library_images(client: Any, library_id: str) -> list[dict[str, Any]]:
    query = urllib.parse.urlencode({"filter[category]": "CREATIVE_ASSETS", "limit": "200"})
    return iter_collection(client, f"/appAssetLibraries/{library_id}/images?{query}")


def library_image_for(images: list[dict[str, Any]], path: Path) -> dict[str, Any] | None:
    """The newest usable library image uploaded from this file (same name and size).

    Reservations an interrupted upload left (AWAITING_UPLOAD), failed and
    archived images do not count, so the file is uploaded again. A file whose
    only upload App Review rejected stops the run.
    """
    size = path.stat().st_size
    same = [
        image
        for image in images
        if attrs(image).get("fileName") == path.name and attrs(image).get("fileSize") == size
    ]
    usable = [image for image in same if attrs(image).get("state") not in CREATIVE_DEAD_STATES]
    rejected = [image for image in same if attrs(image).get("state") == "REJECTED"]
    if not usable and rejected:
        fail(
            f"App Review rejected {path.name}; replace the image (with a new file name) and re-run. "
            f"Details: {json.dumps(attrs(rejected[0]).get('stateDetails'))}"
        )
    return max(usable, key=lambda image: attrs(image).get("createdDate") or "") if usable else None


def wait_for_library_image(client: Any, image_id: str, name: str) -> dict[str, Any]:
    """Poll an uploaded image until Apple has processed it; fails on FAILED or timeout."""
    deadline = time.monotonic() + CREATIVE_PROCESSING_TIMEOUT_SECONDS
    while True:
        image = client.get(f"/appAssetLibraryImages/{image_id}").get("data") or {}
        state = attrs(image).get("state") or ""
        asset = attrs(image).get("imageAsset") or {}
        if state == "FAILED":
            fail(
                f"Apple could not process {name} ({image_id}): "
                f"{json.dumps(attrs(image).get('stateDetails'))}"
            )
        if state in CREATIVE_READY_STATES and asset.get("width") and asset.get("height"):
            return image
        if state in CREATIVE_PENDING_STATES or state == "APPROVED":
            return image
        if time.monotonic() >= deadline:
            fail(f"Apple did not finish processing {name} ({image_id}) in time; it is {state or 'in an unknown state'}")
        print(f"  waiting for Apple to process {name} ({state or 'unknown state'})")
        time.sleep(CREATIVE_POLL_SECONDS)


def upload_library_image(client: Any, library_id: str, path: Path) -> dict[str, Any]:
    """Reserve, upload and commit one creative image, then wait until Apple has processed it."""
    raw = path.read_bytes()
    reserved = client.post(
        "/appAssetLibraryImages",
        {
            "data": {
                "type": "appAssetLibraryImages",
                "attributes": {
                    "fileName": path.name,
                    "fileSize": len(raw),
                    "category": "CREATIVE_ASSETS",
                },
                "relationships": {
                    "assetLibrary": {"data": {"type": "appAssetLibraries", "id": library_id}}
                },
            }
        },
    )["data"]
    image_id = reserved["id"]
    send_upload_operations(client, reserved, raw, path.name)
    client.patch(
        f"/appAssetLibraryImages/{image_id}",
        {
            "data": {
                "type": "appAssetLibraryImages",
                "id": image_id,
                "attributes": {"uploaded": True},
            }
        },
    )
    print(f"  uploaded {path.name} to the Asset Library ({image_id})")
    return wait_for_library_image(client, image_id, path.name)


class CreativeStep:
    """What one creative slot needs, decided before anything is written.

    action: upload (then review), review, pending (in App Review), place,
    placed, or locked (approved, but the version cannot be edited).
    """

    def __init__(
        self,
        placement_type: str,
        label: str,
        path: Path,
        image: dict[str, Any] | None,
        action: str,
        swap_out: dict[str, Any] | None = None,
    ) -> None:
        self.placement_type = placement_type
        self.label = label
        self.path = path
        self.image = image
        self.action = action
        # The localization's placement in this slot that holds another image.
        self.swap_out = swap_out


class CreativePlan:
    def __init__(self, library_id: str, localization_id: str, steps: list[CreativeStep]) -> None:
        self.library_id = library_id
        self.localization_id = localization_id
        self.steps = steps


def image_placement_ids(client: Any, image_id: str) -> set[str]:
    return {
        row["id"]
        for row in iter_collection(client, f"/appAssetLibraryImages/{image_id}/relationships/placements?limit=50")
    }


def slot_placements(client: Any, localization_id: str, placement_type: str) -> list[dict[str, Any]]:
    query = urllib.parse.urlencode({"filter[placementType]": placement_type, "limit": "50"})
    rows = iter_collection(client, f"/appStoreVersionLocalizations/{localization_id}/placements?{query}")
    return [row for row in rows if attrs(row).get("placementType", placement_type) == placement_type]


def plan_creative_assets(
    client: Any,
    *,
    app_id: str,
    version_id: str,
    locale: str,
    creative_dir: Path,
    editable: bool,
) -> CreativePlan:
    """Read-only: decide what each header / search results image needs.

    Fails before anything is written when an image App Review rejected has not
    been replaced, when a locked version (in a review submission) would need an
    upload or a review submission, or when an image is in a state the release
    cannot resolve.
    """
    sources = creative_sources(creative_dir)
    library_id = asset_library_id(client, app_id)
    images = library_images(client, library_id)
    localization = localization_for_locale(
        client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", locale
    )
    if localization is None:
        fail(f"version has no {locale} localization in App Store Connect; add the language there first")
    localization_id = localization["id"]
    steps: list[CreativeStep] = []
    for placement_type, label, path in sources:
        image = library_image_for(images, path)
        state = attrs(image).get("state") or ""
        if image is None or state in CREATIVE_PROCESSING_STATES | CREATIVE_READY_STATES:
            if not editable:
                fail(
                    f"cannot send the {label} image {path.name} to App Review while the version is in "
                    "a review submission; re-run once the version can be edited"
                )
            steps.append(CreativeStep(placement_type, label, path, image, "review" if image else "upload"))
            continue
        if state in CREATIVE_PENDING_STATES:
            print(f"  {label}: {path.name} is {state}; it is placed once App Review approves it")
            steps.append(CreativeStep(placement_type, label, path, image, "pending"))
            continue
        if state != "APPROVED":
            fail(f"the {label} image {path.name} is {state or 'in an unknown state'}; resolve it in App Store Connect")
        # Placed when one of the image's placements is this slot on this localization.
        placed = image_placement_ids(client, image["id"])
        slot = slot_placements(client, localization_id, placement_type)
        if any(row["id"] in placed and attrs(row).get("state") != "FAILED" for row in slot):
            print(f"  {label}: {path.name} is already on the {locale} product page")
            steps.append(CreativeStep(placement_type, label, path, image, "placed"))
            continue
        if not editable:
            # Approval can land between a submit and a re-run; the image is
            # placed by a later run, once the version can be edited.
            print(f"  {label}: {path.name} is approved; it is placed once the version can be edited")
            steps.append(CreativeStep(placement_type, label, path, image, "locked"))
            continue
        if len(slot) > 1:
            fail(
                f"the {locale} {label} slot holds {len(slot)} placements "
                f"({', '.join(row['id'] for row in slot)}); leave one in App Store Connect and re-run"
            )
        steps.append(CreativeStep(placement_type, label, path, image, "place", slot[0] if slot else None))
    return CreativePlan(library_id, localization_id, steps)


def place_creative_image(client: Any, localization_id: str, step: CreativeStep) -> None:
    """Put an approved image in its slot; replaces the slot's other image in the same request."""
    assert step.image is not None
    group = attrs(step.swap_out).get("placementGroup") or CREATIVE_PLACEMENT_GROUP
    relationships: dict[str, Any] = {
        "image": {"data": {"type": "appAssetLibraryImages", "id": step.image["id"]}},
        "appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
        },
    }
    if step.swap_out is not None:
        relationships["placementToSwapOut"] = {
            "data": {"type": "appAssetLibraryPlacements", "id": step.swap_out["id"]}
        }
    client.post(
        "/appAssetLibraryPlacements",
        {
            "data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {"placementType": step.placement_type, "placementGroup": group},
                "relationships": relationships,
            }
        },
    )
    replaced = f", replacing placement {step.swap_out['id']}" if step.swap_out else ""
    print(f"  {step.label}: placed {step.path.name} on the product page{replaced}")


def apply_creative_plan(
    client: Any, plan: CreativePlan, *, app_id: str, reserved_draft: str | None = None
) -> dict[str, str]:
    """Upload, review and place what plan_creative_assets decided. Returns placement type -> outcome."""
    outcomes: dict[str, str] = {}
    to_review: list[tuple[str, dict[str, Any]]] = []
    for step in plan.steps:
        if step.action == "upload":
            step.image = upload_library_image(client, plan.library_id, step.path)
        elif step.action == "review" and step.image is not None and (
            attrs(step.image).get("state") in CREATIVE_PROCESSING_STATES
        ):
            # An earlier run uploaded it; Apple may still be processing it.
            step.image = wait_for_library_image(client, step.image["id"], step.path.name)
        if step.action in {"upload", "review"}:
            assert step.image is not None
            to_review.append((step.label, step.image))
            outcomes[step.placement_type] = "submitted for review"
    if to_review:
        submit_creative_review(client, app_id, to_review, reserved_draft=reserved_draft)
    for step in plan.steps:
        if step.action == "place":
            place_creative_image(client, plan.localization_id, step)
            outcomes[step.placement_type] = "placed"
        elif step.action in {"pending", "placed", "locked"}:
            outcomes[step.placement_type] = step.action
    return outcomes


def submit_creative_review(
    client: Any,
    app_id: str,
    images: list[tuple[str, dict[str, Any]]],
    *,
    reserved_draft: str | None = None,
) -> str:
    """Send not-yet-reviewed creative images to App Review in a submission of their own.

    A draft an earlier attempt left holding only some of these images is
    finished first, else an empty draft, and a new one is created only when
    neither exists, so re-runs never pile up drafts. The draft this run keeps
    for the version (reserved_draft) is never taken. Nothing is submitted
    unless the draft then holds exactly these images.
    """
    wanted = {image["id"] for _, image in images}
    partial = empty = None
    for draft in draft_submission_ids(client, app_id):
        if draft == reserved_draft:
            continue
        items = draft_item_relationships(client, draft)
        # An item that is not an image adds None, which is never wanted.
        held = {related_id(item, "appAssetLibraryImage") for item in items}
        if not items:
            empty = empty or draft
        elif held <= wanted:
            partial = draft
            break
    submission_id = partial or empty
    if submission_id:
        print(f"  finishing review submission {submission_id} from an earlier attempt")
    else:
        submission_id = create_draft_submission(client, app_id)
    held = {related_id(item, "appAssetLibraryImage") for item in draft_item_relationships(client, submission_id)}
    for label, image in images:
        if image["id"] in held:
            print(f"  {label}: {attrs(image).get('fileName')} is already in review submission {submission_id}")
            continue
        client.post(
            "/reviewSubmissionItems",
            {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {
                            "data": {"type": "reviewSubmissions", "id": submission_id}
                        },
                        "appAssetLibraryImage": {
                            "data": {"type": "appAssetLibraryImages", "id": image["id"]}
                        },
                    },
                }
            },
        )
        print(f"  {label}: {attrs(image).get('fileName')} added to review submission {submission_id}")
    items = draft_item_relationships(client, submission_id)
    held_ids = [related_id(item, "appAssetLibraryImage") for item in items]
    if len(items) != len(wanted) or set(held_ids) != wanted:
        unexpected = [item.get("id") for item in items if related_id(item, "appAssetLibraryImage") not in wanted]
        fail(
            f"review submission {submission_id} does not hold exactly the header and search results "
            f"images (unexpected items: {unexpected or 'none'}); not submitting it"
        )
    submit_draft(client, submission_id)
    print(f"  submitted creative image review submission {submission_id}")
    return submission_id


# MARK: - Build selection and review


def refuse_pending_in_app_products(client: Any, app_id: str) -> None:
    pending = pending_in_app_products(client, app_id)
    if pending:
        fail(
            "App Store Connect has in-app products that would have to go to review with this "
            f"version ({'; '.join(pending)}). Scowld's release automation does not submit "
            "in-app purchases; submit them in App Store Connect or extend the automation, then rerun."
        )


def require_version_state(version_string: str, state: str, *, edits_metadata: bool, submit: bool) -> None:
    if edits_metadata and state not in TEXT_EDITABLE_VERSION_STATES:
        fail(
            f"version {version_string} is not editable (state={state}); expected one of "
            f"{', '.join(sorted(TEXT_EDITABLE_VERSION_STATES))}"
        )
    if submit and state not in SUBMITTABLE_VERSION_STATES:
        fail(f"version {version_string} cannot be submitted for review (state={state})")


def locales_of(client: Any, collection_path: str) -> set[str]:
    return {
        (row.get("attributes") or {}).get("locale") or ""
        for row in iter_collection(client, f"{collection_path}?limit=50")
    }


def require_localizations(
    client: Any, app_id: str, version_id: str, plan: dict[str, dict[str, Any]], *, listing: bool
) -> None:
    """Every repository locale must already exist on the version (and, for the listing,
    on its app info): the pipeline never adds a language."""
    missing = sorted(set(plan) - locales_of(client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations"))
    if missing:
        fail(f"version has no {', '.join(missing)} localization in App Store Connect; add the language there first")
    needs_app_info = sorted(locale for locale, entry in plan.items() if listing and entry.get("app_info"))
    if needs_app_info:
        info, _ = app_info_for_listing(client, app_id)
        present = locales_of(client, f"/appInfos/{info['id']}/appInfoLocalizations")
        missing = [locale for locale in needs_app_info if locale not in present]
        if missing:
            fail(f"app info has no {', '.join(missing)} localization in App Store Connect; add the language there first")


def version_key(version_string: str) -> tuple[int, ...] | None:
    """2.0.2 -> (2, 0, 2), padded to three parts; None when it is not numeric."""
    if not re.fullmatch(r"[0-9]+(\.[0-9]+){0,2}", version_string or ""):
        return None
    parts = [int(part) for part in version_string.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def ensure_ios_app_store_version(
    client: Any, *, bundle_id: str, expected_app_id: str, version_string: str
) -> None:
    """Create the App Store version for this release when it does not exist yet.

    An existing version with this number is left as it is (the preflight then
    checks its state). Nothing is created when another version is still on its
    way to the store, or when this number is not newer than every existing
    version; the created version is read back before the run continues.
    """
    wanted = version_key(version_string)
    if wanted is None:
        fail(f"version {version_string!r} must look like 2.1 or 2.0.2")
    app_id = find_app(client, bundle_id)
    if app_id != expected_app_id:
        fail(f"{bundle_id} resolved to App Store Connect app {app_id}, expected {expected_app_id}")
    versions = ios_versions(client, app_id)
    existing = [
        row for row in versions if (row.get("attributes") or {}).get("versionString") == version_string
    ]
    if len(existing) > 1:
        fail(f"ambiguous: {len(existing)} iOS App Store versions are named {version_string!r}")
    if existing:
        state = (existing[0].get("attributes") or {}).get("appStoreState") or ""
        print(f"App Store version {version_string} already exists ({state}); nothing to create")
        return
    problems: list[str] = []
    for row in versions:
        attrs = row.get("attributes") or {}
        other = attrs.get("versionString") or ""
        state = attrs.get("appStoreState") or ""
        if state not in FINISHED_VERSION_STATES:
            problems.append(
                f"version {other!r} is still {state or 'in an unknown state'}; release or remove it "
                f"in App Store Connect before {version_string} can be created"
            )
        other_key = version_key(other)
        if other_key is not None and other_key >= wanted:
            problems.append(f"version {version_string} is not newer than the existing version {other}")
    if problems:
        fail(
            f"not creating App Store version {version_string} (nothing was changed):\n  "
            + "\n  ".join(problems)
        )
    client.post(
        "/appStoreVersions",
        {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version_string},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    created = [
        row for row in ios_versions(client, app_id)
        if (row.get("attributes") or {}).get("versionString") == version_string
    ]
    if len(created) != 1:
        fail(
            f"created App Store version {version_string}, but reading it back found "
            f"{len(created)} records; check it in App Store Connect before rerunning"
        )
    state = (created[0].get("attributes") or {}).get("appStoreState") or ""
    print(f"created App Store version {version_string} ({state or 'state not reported yet'})")


def preflight(
    client: Any,
    *,
    bundle_id: str,
    version_string: str,
    plan: dict[str, dict[str, Any]],
    do_listing: bool,
    do_whats_new: bool,
    do_screenshots: bool,
    do_submit: bool,
    do_creative: bool = False,
    creative_dir: Path = DEFAULT_CREATIVE_DIR,
) -> None:
    """Read-only checks run before a build is uploaded, so a release fails early.

    The version must exist (IOS_CREATE_VERSION's step, which runs before this,
    creates a missing one) in a state that allows the enabled steps, with every
    repository locale; What's New must differ from the live version's; screenshots
    that can no longer change must already match; no in-app product may have to ship
    with it. With review submission on, the draft the version goes out in is
    checked too (version_draft). With creative assets on, their Asset Library state
    is checked the way the store step plans it, so an image the version cannot take
    now (rejected, or needing upload or review while the version sits in a review
    submission) stops the run before the build instead of after it. The live run
    repeats every check, because App Store Connect can change in between.
    """
    app_id = find_app(client, bundle_id)
    version = get_ios_app_store_version(client, app_id, version_string)
    state = (version.get("attributes") or {}).get("appStoreState") or ""
    edits_metadata = do_listing or do_whats_new or do_screenshots or do_creative
    require_version_state(version_string, state, edits_metadata=edits_metadata, submit=do_submit)
    if edits_metadata:
        require_localizations(client, app_id, version["id"], plan, listing=do_listing)
    if do_whats_new:
        for locale, entry in plan.items():
            refuse_stale_whats_new(client, app_id, version["id"], locale, entry["whats_new"])
    text_locked, screenshots_locked = metadata_locks(version_string, state)
    sync_metadata(
        client,
        app_id=app_id,
        version_id=version["id"],
        plan=plan,
        listing=do_listing,
        whats_new=do_whats_new,
        screenshots=do_screenshots,
        text_locked=text_locked,
        screenshots_locked=screenshots_locked,
        check_only=True,
    )
    if do_submit:
        refuse_pending_in_app_products(client, app_id)
        # The store step submits the draft holding this version; finding out
        # after the build and upload that it cannot would be too late.
        version_draft(client, app_id, version["id"], state)
    if do_creative:
        plan_creative_assets(
            client,
            app_id=app_id,
            version_id=version["id"],
            locale=CREATIVE_LOCALE,
            creative_dir=creative_dir,
            editable=state in EDITABLE_VERSION_STATES,
        )
    print(f"ASC preflight passed: version {version_string} ({state}) is ready for the enabled steps")


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


def draft_submission_ids(client: Any, app_id: str) -> list[str]:
    """The app's draft (READY_FOR_REVIEW, not yet submitted) iOS review submissions."""
    return [
        row["id"]
        for row in iter_collection(
            client,
            f"/apps/{app_id}/reviewSubmissions?"
            + urllib.parse.urlencode({"filter[state]": "READY_FOR_REVIEW", "filter[platform]": "IOS", "limit": "5"}),
        )
    ]


def draft_item_relationships(client: Any, submission_id: str) -> list[dict[str, Any]]:
    """Return the draft's items with their relationships populated.

    App Store Connect omits `relationships` from Review Submission Items unless
    they are requested with `include`, so every relationship the readers look
    at (versions, products and Asset Library images) is asked for explicitly.
    """
    return iter_collection(
        client,
        f"/reviewSubmissions/{submission_id}/items?limit=50&include={DRAFT_ITEM_INCLUDE}",
    )


def find_draft_submission(client: Any, app_id: str, version_id: str | None = None) -> str | None:
    """The draft to use for the App Store version, if there is one.

    The draft already holding version_id wins; otherwise the draft holding no app
    version (more than one is ambiguous), so another version's draft is never
    touched. A draft holding header or search results images belongs to their own
    review and is skipped, so those images never go out with the version.
    """
    drafts = []
    for submission_id in draft_submission_ids(client, app_id):
        items = draft_item_relationships(client, submission_id)
        if any(related_id(item, "appAssetLibraryImage") for item in items):
            continue
        versions = {related_id(item, "appStoreVersion") for item in items} - {None, ""}
        drafts.append((submission_id, versions))
    if version_id:
        for submission_id, versions in drafts:
            if version_id in versions:
                return submission_id
    free = [submission_id for submission_id, versions in drafts if not versions]
    if len(free) > 1:
        fail(f"ambiguous: {len(free)} draft review submissions; remove the extras in App Store Connect")
    return free[0] if free else None


def create_draft_submission(client: Any, app_id: str) -> str:
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


def version_draft(client: Any, app_id: str, version_id: str, version_state: str) -> str | None:
    """Read-only: pick and check the draft the version goes out in.

    None means there is none yet (one is created at submit). The draft may hold
    nothing but this version (draft_holds_version). A READY_FOR_REVIEW version
    already sits in a draft; when no draft without header or search results
    images holds it, this stops the run instead of submitting another draft. The
    preflight runs it before the build, and the store step again before its first
    write.
    """
    draft = find_draft_submission(client, app_id, version_id)
    holds = draft is not None and draft_holds_version(client, draft, version_id)
    if version_state == "READY_FOR_REVIEW" and not holds:
        fail(
            f"App Store version {version_id} is READY_FOR_REVIEW, but no draft review submission "
            "without header or search results images holds it; remove the version from its "
            "submission in App Store Connect and re-run"
        )
    return draft


def reserve_version_draft(client: Any, app_id: str, version_id: str, version_state: str) -> str | None:
    """Pick and check the version's draft before anything is written, and reserve it.

    The draft is kept for the version: creative images never take it.
    """
    draft = version_draft(client, app_id, version_id, version_state)
    if draft:
        print(f"  review submission {draft} is kept for the version")
    return draft


def draft_holds_version(client: Any, submission_id: str, version_id: str) -> bool:
    """True if the draft already holds this version; fails if it holds anything else."""
    holds = False
    others: list[str] = []
    for item in draft_item_relationships(client, submission_id):
        if related_id(item, "appStoreVersion") == version_id:
            holds = True
        else:
            others.append(item.get("id", "?"))
    if others:
        fail(
            f"draft review submission {submission_id} also holds other items ({', '.join(others)}); "
            "remove them in App Store Connect so only this version goes to review"
        )
    return holds


def submit_draft(client: Any, submission_id: str) -> None:
    """Submit a draft review submission."""
    # Submitting is a PATCH with submitted=true; there is no /submit action.
    client.request(
        "PATCH",
        f"/reviewSubmissions/{submission_id}",
        body={"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}},
    )


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
    submit_draft(client, submission_id)
    print(f"  submitted App Store version {version_id} for review (submission {submission_id})")


# MARK: - Entry point


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--metadata-dir", type=Path, default=METADATA_DIR, help="store/metadata/ios")
    parser.add_argument(
        "--creative-dir",
        type=Path,
        default=DEFAULT_CREATIVE_DIR,
        help="Product page header and search results images, one folder per slot: "
        + ", ".join(folder for folder, _, _, _ in CREATIVE_SLOTS),
    )
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--app-id", default=DEFAULT_APP_ID, help="Expected App Store Connect app id (--create-version)")
    parser.add_argument("--version", help="Marketing version from the release tag (v2.0.2 → 2.0.2)")
    parser.add_argument("--build-id", help="App Store Connect id of the build uploaded by this run")
    parser.add_argument("--build-number", help="CFBundleVersion of the build uploaded by this run")
    parser.add_argument("--dry-run", action="store_true", help="Validate switches and local files only — no network")
    parser.add_argument(
        "--preflight",
        action="store_true",
        help="Read-only App Store Connect checks before the build is uploaded (no changes)",
    )
    parser.add_argument(
        "--create-version",
        action="store_true",
        help="Create the App Store version for --version when it is missing (CREATE_IOS_VERSION)",
    )
    args = parser.parse_args(argv)

    if args.create_version:
        if args.preflight:
            fail("--create-version and --preflight are separate steps; run them one at a time")
        if not truthy("CREATE_IOS_VERSION"):
            print("App Store version creation skipped — CREATE_IOS_VERSION is off")
            return
        if not args.version:
            fail("--create-version needs --version (the marketing version from the tag)")
        if version_key(args.version) is None:
            fail(f"version {args.version!r} must look like 2.1 or 2.0.2")
        if args.dry_run:
            print(f"ASC dry-run — would create App Store version {args.version} if it is missing")
            return
        ensure_ios_app_store_version(
            client_from_environment(),
            bundle_id=args.bundle_id,
            expected_app_id=args.app_id,
            version_string=args.version,
        )
        return

    # The RGB screenshot copies live in a temporary folder, removed when the step ends.
    with tempfile.TemporaryDirectory(prefix="asc-screenshots-") as staging_dir:
        run_store_step(args, Path(staging_dir))


def run_store_step(args: argparse.Namespace, staging_dir: Path) -> None:
    """Listing, What's New, screenshots, creative assets and review: --dry-run, --preflight or the live step."""
    do_listing = truthy("UPLOAD_LISTING")
    do_whats_new = truthy("UPLOAD_WHATS_NEW")
    do_screenshots = truthy("UPLOAD_SCREENSHOTS")
    do_creative = truthy("UPLOAD_CREATIVE_ASSETS")
    do_submit = truthy("SUBMIT_IOS_REVIEW")
    do_public = truthy("PUBLIC_RELEASE")

    if not (do_listing or do_whats_new or do_screenshots or do_creative or do_submit):
        print(
            "ASC release skipped — UPLOAD_LISTING / UPLOAD_WHATS_NEW / UPLOAD_SCREENSHOTS / "
            "UPLOAD_CREATIVE_ASSETS / SUBMIT_IOS_REVIEW are off"
        )
        return
    if do_public and not do_submit:
        fail("PUBLIC_RELEASE only applies when SUBMIT_IOS_REVIEW is on")
    if do_submit and not args.preflight and not (args.build_id and args.build_number):
        fail("submitting needs --build-id and --build-number for the build uploaded by this run; an older build is never substituted")

    plan = validate_local_inputs(
        upload_listing=do_listing,
        upload_whats_new=do_whats_new,
        upload_screenshots=do_screenshots,
        metadata_dir=args.metadata_dir,
        root=ROOT,
        upload_creative=do_creative,
        creative_dir=args.creative_dir,
    )
    if do_screenshots:
        # Every comparison with App Store Connect and every upload uses the RGB
        # copies, never the committed files.
        stage_screenshots(plan, staging_dir)
    if args.dry_run:
        print(
            f"ASC dry-run — local inputs OK for {', '.join(plan) or 'no locales'}; no API calls "
            f"(listing={do_listing} whats_new={do_whats_new} screenshots={do_screenshots} "
            f"creative={do_creative} submit={do_submit} public_release={do_public})"
        )
        return

    if not args.version:
        fail("--version is required for live App Store Connect calls")
    client = client_from_environment()
    edits_metadata = do_listing or do_whats_new or do_screenshots or do_creative
    if args.preflight:
        preflight(
            client,
            bundle_id=args.bundle_id,
            version_string=args.version,
            plan=plan,
            do_listing=do_listing,
            do_whats_new=do_whats_new,
            do_screenshots=do_screenshots,
            do_submit=do_submit,
            do_creative=do_creative,
            creative_dir=args.creative_dir,
        )
        return
    app_id = find_app(client, args.bundle_id)
    version = get_ios_app_store_version(client, app_id, args.version)
    version_id = version["id"]
    state = (version.get("attributes") or {}).get("appStoreState") or ""
    print(f"ASC app={app_id} version={args.version} id={version_id} state={state}")

    # A rerun after this pipeline already submitted: nothing may change any more, so the
    # enabled steps only confirm App Store Connect matches, and review must hold this
    # run's build.
    already_submitted = state == SUBMITTED_VERSION_STATE
    if not already_submitted:
        require_version_state(args.version, state, edits_metadata=edits_metadata, submit=do_submit)
        if do_submit:
            # Checked before any change, so a blocked submission leaves the listing untouched.
            refuse_pending_in_app_products(client, app_id)
    # Pick and check the version's draft before any write. It is reserved for the
    # version, so header and search results images never go out in it.
    reserved_draft: str | None = None
    if do_submit and not already_submitted:
        reserved_draft = reserve_version_draft(client, app_id, version_id, state)

    text_locked, screenshots_locked = metadata_locks(args.version, state)
    # Read-only, before any write: what each header / search results image needs. In a
    # review submission (READY_FOR_REVIEW or WAITING_FOR_REVIEW) creative placements are
    # locked like screenshots.
    creative_plan: CreativePlan | None = None
    if do_creative:
        print("checking ASC product page header and search results images…")
        creative_plan = plan_creative_assets(
            client,
            app_id=app_id,
            version_id=version_id,
            locale=CREATIVE_LOCALE,
            creative_dir=args.creative_dir,
            editable=screenshots_locked is None,
        )
    sync_metadata(
        client,
        app_id=app_id,
        version_id=version_id,
        plan=plan,
        listing=do_listing,
        whats_new=do_whats_new,
        screenshots=do_screenshots,
        text_locked=text_locked,
        screenshots_locked=screenshots_locked,
    )

    if creative_plan is not None:
        print("syncing ASC product page header and search results images…")
        apply_creative_plan(client, creative_plan, app_id=app_id, reserved_draft=reserved_draft)

    if already_submitted:
        if do_submit:
            confirm_selected_build(client, version_id, args.build_id)
            print(f"ASC submit skipped — version already {state} with this run's build (idempotent)")
        print("ASC release step finished")
        return

    if do_submit:
        print("selecting this run's build…")
        select_build(client, version_id, args.build_id, args.version, args.build_number)
        set_release_type(client, version_id, public_release=do_public)
        submission_id = reserved_draft or create_draft_submission(client, app_id)
        already_added = draft_holds_version(client, submission_id, version_id)
        # Recheck immediately before submitting: the selection must still be this run's build.
        verify_build(client, args.build_id, args.version, args.build_number)
        confirm_selected_build(client, version_id, args.build_id)
        print("submitting for App Store review…")
        submit_for_review(client, submission_id, version_id, already_added=already_added)

    print("ASC release step finished")


if __name__ == "__main__":
    main()
