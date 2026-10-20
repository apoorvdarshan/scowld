#!/usr/bin/env python3
"""App Store Connect listing, What's New, screenshots, creative assets and review submission.

Every App Store Connect call goes through the pinned App Store Connect CLI
(`asc`, see asc_cli.py); this script decides what may change and checks the
results. Every operation has its own switch. ios-release.yml sets these
environment flags from the resolved IOS_* repository variables:

  UPLOAD_LISTING          name, subtitle, privacy policy URL, description, keywords,
                          promotional text, marketing and support URLs
  UPLOAD_WHATS_NEW        What's New
  UPLOAD_SCREENSHOTS      the screenshots listed in each locale's screenshots.json
  UPLOAD_CREATIVE_ASSETS  the product page header and search results images in
                          store/creative/ios: a new image is uploaded to the Asset
                          Library and reviewed on its own, and once Apple approves
                          it a later run places it on the version
  SUBMIT_IOS_REVIEW       select THIS run's processed build and submit for review
  PUBLIC_RELEASE          release automatically after approval (otherwise manual)
  CREATE_IOS_VERSION      with --create-version: create the tag's App Store version
                          when it is missing

The listing lives in store/metadata/ios/<locale>/ (exported from the live App
Store listing by asc_export_listing.py), so the repository is its source of
truth. Only fields whose text differs from App Store Connect are sent. What's
New must be plain text: App Store Connect shows Markdown literally, so it is
refused.

Reruns are idempotent. In READY_FOR_REVIEW (the version already sits in a draft
review submission) text can still change but screenshots and creative assets
cannot; in WAITING_FOR_REVIEW (already submitted) nothing can. A step that can no
longer change only checks that App Store Connect already matches the repository,
and those checks run before anything is written.

Scowld's in-app products (tips, and Scowld Premium's subscriptions and minute
packs) are not submitted by this script: submission stops instead if App Store
Connect holds products that would have to go to review with the version, so
new products are added to the version's submission in App Store Connect by hand.
A draft review submission is submitted only while it holds this version and
nothing else.

`--create-version` (IOS_CREATE_VERSION) runs first on a release run: it adds the
App Store version for the tag when App Store Connect does not have it yet, and
leaves an existing one alone. It refuses when another version is still on its
way to the store or the tag's version is not newer than every existing one.

`--dry-run` validates the switches and local files only (no asc calls).
`--preflight` runs asc read-only (ASC_READ_ONLY), before the build is uploaded:
the version exists in a state that allows the enabled steps and has every
repository locale, What's New differs from the live version, screenshots and
creative assets that can no longer change already match, and no in-app product
would have to ship with it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_cli  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BUNDLE_ID = "com.apoorvdarshan.Scowld"
# Scowld's App Store Connect app record (apps.apple.com/app/id6760672848). Every
# run checks that this record carries exactly DEFAULT_BUNDLE_ID before touching
# anything.
ASC_APP_ID = "6760672848"
PLATFORM = "IOS"
METADATA_DIR = ROOT / "store" / "metadata" / "ios"
CREATIVE_DIR = ROOT / "store" / "creative" / "ios"

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
# The `asc localizations update` flag for each field.
FIELD_FLAGS = {
    "description": "--description",
    "keywords": "--keywords",
    "promotionalText": "--promotional-text",
    "marketingUrl": "--marketing-url",
    "supportUrl": "--support-url",
    "whatsNew": "--whats-new",
    "name": "--name",
    "subtitle": "--subtitle",
    "privacyPolicyUrl": "--privacy-policy-url",
}
# App Store Connect shows What's New as plain text, so Markdown would appear
# literally on the App Store. "- " bullets are plain text and fine.
MARKDOWN_SYNTAX = (
    (re.compile(r"\*\*|__"), "bold markers (** or __)"),
    (re.compile(r"`"), "backticks"),
    (re.compile(r"\[[^\]\n]+\]\([^)\n]*\)"), "links [text](url)"),
    (re.compile(r"^ {0,3}#{1,6}(\s|$)", re.MULTILINE), "headings (#)"),
)
SCREENSHOT_MANIFEST = "screenshots.json"

# Accepted portrait sizes per App Store Connect display type (landscape = swapped),
# exactly what the pinned asc accepts (`asc screenshots sizes --display-type TYPE`).
SCREENSHOT_SIZES = {
    "APP_IPHONE_67": {(1260, 2736), (1290, 2796), (1320, 2868)},
    "APP_IPHONE_65": {(1242, 2688), (1284, 2778)},
    "APP_IPAD_PRO_3GEN_129": {(2048, 2732), (2064, 2752)},
}
SCREENSHOT_SET_MAX = 10
SCREENSHOT_PROCESSING_SECONDS = 300

# Product page creative assets: the folder under --creative-dir, the placement
# type, and a label for logs. Each folder holds at most one image.
CREATIVE_SLOTS = (
    ("header", "PRODUCT_PAGE_HEADER_ASSET", "product page header"),
    ("search-results", "APP_STORE_SEARCH_RESULTS_ASSET", "search results"),
)
# Apple's image specs per slot (asc asset-library specs): the header is a 21:9
# 3840x1646 PNG; search results are 3:2 PNG or JPEG from 1920x1280 to 3840x2560.
# A 5244x2950 16:9 PNG is a universal image that fits either.
UNIVERSAL_CREATIVE_SIZE = (5244, 2950)
CREATIVE_EXTENSIONS = {".png", ".jpg", ".jpeg"}
# Library image states: still being reviewed, or finished without approval.
CREATIVE_PENDING_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED"}
CREATIVE_UNSUBMITTED_STATES = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "COMPLETE", "UPLOAD_COMPLETE"}
CREATIVE_DEAD_STATES = {"REJECTED", "FAILED", "ARCHIVED"}

# Everything (text, screenshots and creative assets) can change in these version states.
EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}
# READY_FOR_REVIEW means the version already sits in a draft review submission
# (for example after a failed submit). Its listing and What's New text can still
# change and it can still be submitted, but its screenshots and creative assets
# can no longer change, so they are only checked against the repository.
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


# MARK: - asc


def data(payload: Any) -> Any:
    return (payload or {}).get("data") if isinstance(payload, dict) else None


def rows(payload: Any) -> list[dict[str, Any]]:
    value = data(payload)
    return value if isinstance(value, list) else []


def attrs(row: dict[str, Any] | None) -> dict[str, Any]:
    return (row or {}).get("attributes") or {}


def related_id(row: dict[str, Any], name: str) -> str | None:
    return (((row.get("relationships") or {}).get(name) or {}).get("data") or {}).get("id")


def asc_value(text: str) -> str:
    """A flag value for asc, which reads a leading @ as @file:/@env: (escaped as @@)."""
    return "@" + text if text.startswith("@") else text


def load_credentials() -> tuple[str, str, str]:
    key_id = os.environ.get("APP_STORE_CONNECT_API_KEY_ID", "").strip()
    issuer_id = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    key_p8 = os.environ.get("APP_STORE_CONNECT_API_KEY_P8", "").strip()
    if not key_id or not issuer_id or not key_p8:
        fail(
            "missing ASC credentials — set APP_STORE_CONNECT_API_KEY_ID, "
            "APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8"
        )
    return key_id, issuer_id, key_p8


def asc_from_environment(*, read_only: bool = False) -> asc_cli.Asc:
    """asc with the release credentials; read_only makes asc refuse every write."""
    load_credentials()
    return asc_cli.Asc(read_only=read_only)


def call(asc: asc_cli.Asc, *args: str) -> Any:
    """Run asc and stop the release with a readable error when it fails."""
    try:
        return asc.run(*args)
    except asc_cli.AscError as exc:
        fail(str(exc))


def find_app(asc: asc_cli.Asc, bundle_id: str, app_id: str = ASC_APP_ID) -> str:
    """The pinned App Store Connect app, after checking it carries exactly bundle_id."""
    record = data(call(asc, "apps", "view", "--id", app_id)) or {}
    if record.get("id") != app_id:
        fail(f"App Store Connect returned app {record.get('id')!r}, expected {app_id}")
    found = attrs(record).get("bundleId")
    if found != bundle_id:
        fail(f"App Store Connect app {app_id} has bundle id {found!r}, expected {bundle_id}")
    return app_id


def ios_versions(asc: asc_cli.Asc, app_id: str) -> list[dict[str, Any]]:
    return rows(call(asc, "versions", "list", "--app", app_id, "--platform", PLATFORM, "--paginate"))


def get_ios_app_store_version(asc: asc_cli.Asc, app_id: str, version_string: str) -> dict[str, Any]:
    matches = [row for row in ios_versions(asc, app_id) if attrs(row).get("versionString") == version_string]
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


def image_dimensions(path: Path) -> tuple[str | None, int, int]:
    """(format, width, height) of a PNG or JPEG, read from its headers."""
    raw = Path(path).read_bytes()
    if raw.startswith(asc_cli.PNG_SIGNATURE) and len(raw) >= 24:
        return "png", int.from_bytes(raw[16:20], "big"), int.from_bytes(raw[20:24], "big")
    if raw[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(raw):
            if raw[i] != 0xFF:
                i += 1
                continue
            marker = raw[i + 1]
            if marker == 0xFF or marker in (0x01, 0xD8) or 0xD0 <= marker <= 0xD7:
                i += 1 if marker == 0xFF else 2
                continue
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                return "jpeg", int.from_bytes(raw[i + 7:i + 9], "big"), int.from_bytes(raw[i + 5:i + 7], "big")
            i += 2 + int.from_bytes(raw[i + 2:i + 4], "big")
    return None, 0, 0


def image_size(path: Path) -> tuple[int, int]:
    """(width, height) of a PNG or JPEG file, read from its header."""
    kind, width, height = image_dimensions(path)
    if kind is None:
        fail(f"{path} is not a PNG or JPEG image")
    return width, height


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
            width, height = image_size(path)
            if (width, height) not in accepted and (height, width) not in accepted:
                sizes = ", ".join(f"{w}x{h}" for w, h in sorted(accepted))
                fail(f"{entry} is {width}x{height}; {display_type} accepts {sizes} (or landscape)")
            # asc refuses a PNG that stores alpha (colour type 4 or 6, or a tRNS
            # chunk) even when every pixel is opaque, so the file must have none.
            if asc_cli.image_has_alpha(path):
                fail(
                    f"{entry} stores an alpha channel or transparency; App Store screenshots must be opaque, "
                    "and asc refuses such a PNG even when every pixel is opaque. Re-export it as an RGB PNG"
                )
            files.append(path)
        plan[display_type] = files
    return plan


def creative_size_problem(placement_type: str, path: Path) -> str | None:
    """Why Apple would refuse this image for the slot, or None when it fits."""
    kind, width, height = image_dimensions(path)
    if kind is None:
        return "is not a PNG or JPEG"
    if kind == "png" and (width, height) == UNIVERSAL_CREATIVE_SIZE:
        return None
    if placement_type == "PRODUCT_PAGE_HEADER_ASSET":
        if kind != "png" or (width, height) != (3840, 1646):
            return f"is a {width}x{height} {kind.upper()}; the header must be a 3840x1646 PNG"
        return None
    if not (1920 <= width <= 3840 and width * 2 == height * 3):
        return f"is {width}x{height}; search results images are 3:2, from 1920x1280 to 3840x2560"
    return None


def creative_sources(creative_dir: Path) -> list[tuple[str, str, Path]]:
    """(placement type, label, image) for every creative slot that has an image.

    Each image is checked like Apple checks it (alpha, format and size) before
    anything is built or uploaded.
    """
    found = []
    for folder, placement_type, label in CREATIVE_SLOTS:
        slot_dir = creative_dir / folder
        images = sorted(
            p for p in slot_dir.glob("*") if p.is_file() and p.suffix.lower() in CREATIVE_EXTENSIONS
        ) if slot_dir.is_dir() else []
        if len(images) > 1:
            fail(f"the {label} slot takes one image; {slot_dir} has {len(images)}")
        if images and asc_cli.image_has_alpha(images[0]):
            fail(f"the {label} image {images[0].name} has an alpha channel, which App Store Connect refuses; re-export it as RGB")
        problem = creative_size_problem(placement_type, images[0]) if images else None
        if problem:
            fail(f"the {label} image {images[0].name} {problem}")
        if images:
            found.append((placement_type, label, images[0]))
    if not found:
        fail(f"creative asset upload is on, but {creative_dir} has no header or search results image")
    return found


def validate_local_inputs(
    *,
    upload_listing: bool,
    upload_whats_new: bool,
    upload_screenshots: bool,
    metadata_dir: Path,
    root: Path = ROOT,
    upload_creative: bool = False,
    creative_dir: Path = CREATIVE_DIR,
) -> dict[str, dict[str, Any]]:
    """Check every enabled operation's local files before any asc call.

    Returns locale → what that locale uploads. Creative assets go on every
    locale's version, so they need the locale folders too.
    """
    plan: dict[str, dict[str, Any]] = {}
    if not (upload_listing or upload_whats_new or upload_screenshots or upload_creative):
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
    if upload_creative:
        creative_sources(creative_dir)
    return plan


# MARK: - Listing and What's New


def version_localizations(asc: asc_cli.Asc, version_id: str) -> list[dict[str, Any]]:
    return rows(call(asc, "localizations", "list", "--version", version_id, "--paginate"))


def app_info_localizations(asc: asc_cli.Asc, app_id: str, info_id: str) -> list[dict[str, Any]]:
    return rows(
        call(asc, "localizations", "list", "--type", "app-info", "--app", app_id, "--app-info", info_id, "--paginate")
    )


def localization_for_locale(localizations: list[dict[str, Any]], locale: str) -> dict[str, Any] | None:
    for row in localizations:
        if attrs(row).get("locale") == locale:
            return row
    return None


def changed_fields(current: dict[str, Any], wanted: dict[str, str]) -> dict[str, str]:
    return {
        field: value for field, value in wanted.items()
        if (current.get(field) or "").strip() != value
    }


def update_localization(
    asc: asc_cli.Asc, localization_id: str, changes: dict[str, str], *, app_info: bool = False
) -> None:
    """Send the changed fields of one version (or app info) localization in one asc call."""
    args = ["localizations", "update"] + (["--type", "app-info"] if app_info else []) + ["--id", localization_id]
    for field in sorted(changes):
        args += [FIELD_FLAGS[field], asc_value(changes[field])]
    call(asc, *args)


def refuse_locked_change(label: str, locale: str, changes: Any, locked: str) -> None:
    """A change is needed, but App Store Connect no longer allows it (see `locked`)."""
    fail(
        f"{label} ({locale}) differs from App Store Connect ({', '.join(sorted(changes))}), but {locked}; "
        "change it in App Store Connect (or remove the version from review) so both match, then rerun"
    )


def app_info_state(info: dict[str, Any]) -> str:
    return attrs(info).get("state") or attrs(info).get("appStoreState") or ""


def upload_version_fields(
    asc: asc_cli.Asc, version_id: str, locale: str, wanted: dict[str, str], label: str, *, locked: str | None = None
) -> None:
    """Send only the fields that differ. With `locked` (the reason edits are no longer
    allowed), nothing is written: matching fields pass, differing fields fail."""
    loc = localization_for_locale(version_localizations(asc, version_id), locale)
    if loc is None:
        fail(f"version has no {locale} localization in App Store Connect; add the language there first")
    changes = changed_fields(attrs(loc), wanted)
    if not changes:
        print(f"  {label} ({locale}): already up to date")
        return
    if locked:
        refuse_locked_change(label, locale, changes, locked)
    update_localization(asc, loc["id"], changes)
    print(f"  {label} ({locale}): updated {', '.join(sorted(changes))}")


def app_info_for_listing(asc: asc_cli.Asc, app_id: str) -> tuple[dict[str, Any], bool]:
    """(app info record the listing is compared with, whether it is editable).

    The editable record (it ships with the new version) wins. Without one, the record
    already submitted with a version (a rerun after submitting) is compared, and
    otherwise the live one.
    """
    infos = rows(call(asc, "apps", "info", "list", "--app", app_id))
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
    asc: asc_cli.Asc, app_id: str, locale: str, wanted: dict[str, str], *, locked: str | None = None
) -> None:
    """Name, subtitle and privacy URL live on the app info that ships with the version."""
    if not wanted:
        return
    info, editable = app_info_for_listing(asc, app_id)
    loc = localization_for_locale(app_info_localizations(asc, app_id, info["id"]), locale)
    if loc is None:
        fail(f"app info has no {locale} localization in App Store Connect; add the language there first")
    changes = changed_fields(attrs(loc), wanted)
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
    update_localization(asc, loc["id"], changes, app_info=True)
    print(f"  app name/subtitle/privacy URL ({locale}): updated {', '.join(sorted(changes))}")


def live_whats_new(asc: asc_cli.Asc, app_id: str, exclude_version_id: str, locale: str) -> tuple[str, str] | None:
    """(version, What's New) of the newest live version, if any."""
    live = [
        row for row in ios_versions(asc, app_id)
        if row.get("id") != exclude_version_id and attrs(row).get("appStoreState") in LIVE_VERSION_STATES
    ]
    if not live:
        return None
    newest = max(live, key=lambda row: attrs(row).get("createdDate") or "")
    loc = localization_for_locale(version_localizations(asc, newest["id"]), locale)
    text = attrs(loc).get("whatsNew") or ""
    return attrs(newest).get("versionString", "?"), text.strip()


def refuse_stale_whats_new(asc: asc_cli.Asc, app_id: str, version_id: str, locale: str, text: str) -> None:
    previous = live_whats_new(asc, app_id, version_id, locale)
    if previous and previous[1] == text:
        fail(
            f"What's New ({locale}) is identical to live version {previous[0]}; update "
            f"store/metadata/ios/{locale}/{WHATS_NEW_FIELD[1]} for this release"
        )


def upload_whats_new(
    asc: asc_cli.Asc, app_id: str, version_id: str, locale: str, text: str, *, locked: str | None = None
) -> None:
    refuse_stale_whats_new(asc, app_id, version_id, locale, text)
    upload_version_fields(asc, version_id, locale, {WHATS_NEW_FIELD[0]: text}, "What's New", locked=locked)


# MARK: - Screenshots


def md5_hex(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()  # noqa: S324 - App Store Connect's checksum


def screenshot_sets(asc: asc_cli.Asc, version_loc_id: str) -> dict[str, list[dict[str, Any]]]:
    """Display type → the screenshots App Store Connect holds in that set, in order."""
    payload = call(asc, "screenshots", "list", "--version-localization", version_loc_id)
    sets: dict[str, list[dict[str, Any]]] = {}
    for entry in (payload or {}).get("sets") or []:
        sets[attrs(entry.get("set")).get("screenshotDisplayType")] = list(entry.get("screenshots") or [])
    return sets


def checksums(shots: list[dict[str, Any]]) -> list[Any]:
    return [attrs(shot).get("sourceFileChecksum") for shot in shots]


def upload_screenshot_files(asc: asc_cli.Asc, version_loc_id: str, display_type: str, files: list[Path]) -> None:
    """Replace the set with `files`, in the manifest's order.

    asc uploads a folder in file-name order, so each file goes up on its own: the
    first replaces the whole set (--replace), and every later one is appended.
    asc creates a missing set and waits until Apple has processed each image.
    """
    device_type = display_type.removeprefix("APP_")
    for index, path in enumerate(files):
        args = ["screenshots", "upload", "--version-localization", version_loc_id, "--path", str(path),
                "--device-type", device_type]
        if index == 0:
            args += ["--replace", "--confirm"]
        call(asc, *args)


def wait_for_screenshots(
    asc: asc_cli.Asc,
    version_loc_id: str,
    display_type: str,
    *,
    timeout: float = SCREENSHOT_PROCESSING_SECONDS,
    now: Callable[[], float] | None = None,
    sleep: Callable[[float], None] | None = None,
) -> list[dict[str, Any]]:
    """Poll the set until App Store Connect has processed every screenshot in it.

    asc already waits for each image it uploads; this re-reads the whole set, so a
    screenshot Apple failed to process stops the run with Apple's reason.
    """
    now = now or time.monotonic
    sleep = sleep or time.sleep
    deadline = now() + timeout
    while True:
        shots = screenshot_sets(asc, version_loc_id).get(display_type) or []
        pending = 0
        for shot in shots:
            delivery = attrs(shot).get("assetDeliveryState") or {}
            state = delivery.get("state")
            if state == "COMPLETE":
                continue
            if state == "FAILED":
                errors = "; ".join(e.get("description") or e.get("code") or "" for e in delivery.get("errors") or [])
                name = attrs(shot).get("fileName") or shot.get("id")
                fail(f"App Store Connect rejected screenshot {name}: {errors or 'FAILED'}")
            pending += 1
        if not pending:
            return shots
        if now() > deadline:
            fail(f"{pending} screenshot(s) were still processing after {int(timeout)} s")
        sleep(3)


def sync_screenshot_set(
    asc: asc_cli.Asc,
    version_loc_id: str,
    locale: str,
    display_type: str,
    files: list[Path],
    *,
    locked: str | None = None,
) -> None:
    """Replace the set when its images differ. With `locked`, nothing is written:
    an identical set passes and a differing (or missing) one fails."""
    current = screenshot_sets(asc, version_loc_id).get(display_type) or []
    wanted = [md5_hex(path) for path in files]
    if checksums(current) == wanted:
        print(f"  screenshots {display_type} ({locale}): already up to date")
        return
    if locked:
        refuse_locked_change(f"screenshots {display_type}", locale, ["images"], locked)
    # The version is not live yet, so replacing the whole set is safe; rerun on failure.
    upload_screenshot_files(asc, version_loc_id, display_type, files)
    shots = wait_for_screenshots(asc, version_loc_id, display_type)
    if checksums(shots) != wanted:
        fail(
            f"after uploading, App Store Connect's screenshots {display_type} ({locale}) do not match "
            f"{SCREENSHOT_MANIFEST} (same images in the same order); rerun to replace the set again"
        )
    print(f"  screenshots {display_type} ({locale}): uploaded {len(files)} in order")


def upload_screenshots(
    asc: asc_cli.Asc, version_id: str, locale: str, plan: dict[str, list[Path]], *, locked: str | None = None
) -> None:
    loc = localization_for_locale(version_localizations(asc, version_id), locale)
    if loc is None:
        fail(f"version has no {locale} localization in App Store Connect; add the language there first")
    for display_type, files in plan.items():
        sync_screenshot_set(asc, loc["id"], locale, display_type, files, locked=locked)


# MARK: - Creative assets


def library_images(asc: asc_cli.Asc, library_id: str) -> list[dict[str, Any]]:
    return rows(
        call(asc, "asset-library", "images", "list", "--library-id", library_id, "--category", "CREATIVE_ASSETS", "--paginate")
    )


def library_image_for(images: list[dict[str, Any]], path: Path) -> dict[str, Any] | None:
    """The newest usable library image uploaded from this exact file (name and size)."""
    size = path.stat().st_size
    matches = [
        image
        for image in images
        if attrs(image).get("fileName") == path.name
        and attrs(image).get("fileSize") == size
        and attrs(image).get("state") not in CREATIVE_DEAD_STATES
    ]
    rejected = [
        image
        for image in images
        if attrs(image).get("fileName") == path.name
        and attrs(image).get("fileSize") == size
        and attrs(image).get("state") == "REJECTED"
    ]
    if not matches and rejected:
        fail(
            f"App Review rejected {path.name}; replace the image (a new file name) and re-run. "
            f"Details: {json.dumps(attrs(rejected[0]).get('stateDetails'))}"
        )
    return max(matches, key=lambda image: attrs(image).get("createdDate") or "") if matches else None


def sync_creative_assets(
    asc: asc_cli.Asc,
    *,
    app_id: str,
    version_id: str,
    locales: list[str],
    creative_dir: Path,
    editable: bool,
) -> dict[str, str]:
    """Put the repository's header and search results images on every locale's version.

    An image is uploaded to the Asset Library once (matched by file name and size)
    and reviewed on its own. Only approved images are placed, because a version
    that is already approved only takes approved assets; one that is still in
    review or not yet submitted is placed on a later run. With editable=False
    (the version is in a review submission) nothing is written: an image that
    still has to be uploaded or sent to App Review fails the step, and an
    approved image that is not placed yet waits for a later run. Returns
    placement type -> outcome.
    """
    sources = creative_sources(creative_dir)
    library_id = (data(call(asc, "asset-library", "view", "--app", app_id)) or {}).get("id")
    if not library_id:
        fail(f"App Store Connect returned no Asset Library for app {app_id}")
    images = library_images(asc, library_id)
    localizations = version_localizations(asc, version_id)
    version_locs = []
    for locale in locales:
        loc = localization_for_locale(localizations, locale)
        if loc is None:
            fail(f"version has no {locale} localization in App Store Connect; add the language there first")
        version_locs.append((locale, loc))
    outcomes: dict[str, str] = {}
    to_review: list[tuple[str, dict[str, Any]]] = []
    for placement_type, label, path in sources:
        image = library_image_for(images, path)
        if image is None:
            if not editable:
                fail(f"cannot upload the {label} image while the version waits for review")
            # asc waits for processing and prints a receipt (imageId, ready, state).
            receipt = call(asc, "asset-library", "images", "upload", "--library-id", library_id, "--file", str(path))
            if not receipt.get("imageId") or not receipt.get("ready"):
                fail(f"Apple did not finish processing the {label} image {path.name}: {json.dumps(receipt)}")
            image = {"id": receipt["imageId"], "attributes": {"fileName": path.name, "state": receipt.get("state")}}
            print(f"  uploaded {path.name} to the Asset Library ({image['id']})")
        state = attrs(image).get("state") or ""
        if state in CREATIVE_UNSUBMITTED_STATES or not state:
            if not editable:
                fail(
                    f"cannot send the {label} image {path.name} to App Review while the version waits for "
                    "review; re-run once the version can be edited, or submit it in App Store Connect"
                )
            to_review.append((label, image))
            outcomes[placement_type] = "submitted for review"
            continue
        if state in CREATIVE_PENDING_STATES:
            outcomes[placement_type] = f"in App Review ({state}); placed on a later run"
            print(f"  {label}: {path.name} is {state}; it is placed once App Review approves it")
            continue
        if state != "APPROVED":
            fail(f"the {label} image {path.name} is {state}; resolve it in App Store Connect")
        placed = []
        waiting = []
        for locale, loc in version_locs:
            current = rows(
                call(
                    asc, "localizations", "placements", "list", "--localization-id", loc["id"],
                    "--placement-type", placement_type, "--include", "image",
                )
            )
            if any(related_id(row, "image") == image["id"] for row in current):
                print(f"  {label} ({locale}): {path.name} is already on the product page")
                continue
            if not editable:
                # Approval can land between a submit and a rerun; that is not a
                # mismatch, so the rerun passes and placement waits for an editable version.
                waiting.append(locale)
                continue
            if current:
                call(
                    asc, "localizations", "placements", "swap", "--localization-id", loc["id"],
                    "--image-id", image["id"], "--placement-type", placement_type, "--placement-id", current[0]["id"],
                    "--confirm",
                )
            else:
                call(
                    asc, "localizations", "placements", "create", "--localization-id", loc["id"],
                    "--image-id", image["id"], "--placement-type", placement_type, "--placement-group", "DEFAULT_PROFILE",
                )
            placed.append(locale)
            print(f"  {label} ({locale}): placed {path.name} on the product page")
        if waiting:
            outcomes[placement_type] = "approved; placed once the version can be edited"
            print(f"  {label} ({', '.join(waiting)}): {path.name} is approved; it is placed on a later run, "
                  "once the version can be edited")
        else:
            outcomes[placement_type] = "placed" if placed else "already placed"
    if to_review:
        submit_creative_review(asc, app_id, to_review)
    return outcomes


def submit_creative_review(asc: asc_cli.Asc, app_id: str, images: list[tuple[str, dict[str, Any]]]) -> str:
    """Send not-yet-reviewed creative images to App Review in a submission of their own.

    A draft an earlier attempt left behind holding only some of these images
    (or nothing yet) is finished instead of starting another one.
    """
    wanted = {image["id"] for _, image in images}
    submission_id = None
    for draft in draft_submission_ids(asc, app_id):
        held = {related_id(item, "appAssetLibraryImage") for item in submission_items(asc, draft)}
        if held <= wanted:
            submission_id = draft
            print(f"  finishing creative review submission {draft} from an earlier attempt")
            break
    if submission_id is None:
        submission = data(call(asc, "review", "submissions-create", "--app", app_id, "--platform", PLATFORM)) or {}
        submission_id = submission.get("id")
    if not submission_id:
        fail("asc did not report the new review submission's id")
    for label, image in images:
        call(
            asc, "review", "items-add", "--submission", submission_id, "--item-type", "appAssetLibraryImages",
            "--item-id", image["id"], "--if-exists", "skip",
        )
        print(f"  {label}: {attrs(image).get('fileName')} added to creative review submission {submission_id}")
    items = submission_items(asc, submission_id)
    unexpected = [item["id"] for item in items if related_id(item, "appAssetLibraryImage") not in wanted]
    if unexpected or len(items) != len(images):
        fail(f"review submission {submission_id} holds unexpected items {unexpected}; not submitting it")
    call(asc, "review", "submissions-submit", "--id", submission_id, "--confirm")
    print(f"  submitted {len(images)} creative image(s) for App Review ({submission_id})")
    return submission_id


def sync_metadata(
    asc: asc_cli.Asc,
    *,
    app_id: str,
    version_id: str,
    plan: dict[str, dict[str, Any]],
    listing: bool,
    whats_new: bool,
    screenshots: bool,
    text_locked: str | None,
    screenshots_locked: str | None,
    creative: bool = False,
    creative_dir: Path = CREATIVE_DIR,
    check_only: bool = False,
) -> None:
    """Listing, What's New and screenshots for every locale, then the creative assets.

    An operation App Store Connect no longer allows for this version (`*_locked` holds
    the reason) only checks that App Store Connect already matches the repository,
    which keeps reruns idempotent. Those checks run first, so a change that cannot be
    made fails before anything is written. `check_only` runs just those checks.
    Creative assets change only when screenshots can.
    """
    for locked_pass in ((True,) if check_only else (True, False)):
        for locale, entry in plan.items():
            if listing and (text_locked is not None) is locked_pass:
                upload_app_info_fields(asc, app_id, locale, entry["app_info"], locked=text_locked)
                upload_version_fields(asc, version_id, locale, entry["version"], "listing", locked=text_locked)
            if whats_new and (text_locked is not None) is locked_pass:
                upload_whats_new(asc, app_id, version_id, locale, entry["whats_new"], locked=text_locked)
            if screenshots and (screenshots_locked is not None) is locked_pass:
                upload_screenshots(asc, version_id, locale, entry["screenshots"], locked=screenshots_locked)
        if creative and (screenshots_locked is not None) is locked_pass:
            sync_creative_assets(
                asc, app_id=app_id, version_id=version_id, locales=list(plan), creative_dir=creative_dir,
                editable=screenshots_locked is None,
            )


def metadata_locks(version_string: str, state: str) -> tuple[str | None, str | None]:
    """(text lock, screenshot lock) for this version state; None = may change."""
    text_locked = None
    if state == SUBMITTED_VERSION_STATE:
        text_locked = f"version {version_string} is {state} and can no longer be edited"
    screenshots_locked = None
    if state not in EDITABLE_VERSION_STATES:
        screenshots_locked = f"version {version_string} is {state}, where screenshots can no longer change"
    return text_locked, screenshots_locked


# MARK: - Build selection and review


def pending_in_app_products(asc: asc_cli.Asc, app_id: str) -> list[str]:
    """Products that App Review would expect with this version (Scowld has none)."""
    pending: list[str] = []
    for sub in rows(call(asc, "subscriptions", "list", "--app", app_id, "--paginate")):
        a = attrs(sub)
        if a.get("state") in PENDING_PRODUCT_STATES:
            pending.append(f"subscription {a.get('productId') or sub['id']} ({a.get('state')})")
    for iap in rows(call(asc, "iap", "list", "--app", app_id, "--paginate")):
        a = attrs(iap)
        if a.get("state") in PENDING_PRODUCT_STATES:
            pending.append(f"in-app purchase {a.get('productId') or iap['id']} ({a.get('state')})")
    return pending


def refuse_pending_in_app_products(asc: asc_cli.Asc, app_id: str) -> None:
    pending = pending_in_app_products(asc, app_id)
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


def require_localizations(
    asc: asc_cli.Asc, app_id: str, version_id: str, plan: dict[str, dict[str, Any]], *, listing: bool
) -> None:
    """Every repository locale must already exist on the version (and, for the listing,
    on its app info): the pipeline never adds a language."""
    present = {attrs(row).get("locale") for row in version_localizations(asc, version_id)}
    missing = sorted(set(plan) - present)
    if missing:
        fail(f"version has no {', '.join(missing)} localization in App Store Connect; add the language there first")
    needs_app_info = sorted(locale for locale, entry in plan.items() if listing and entry.get("app_info"))
    if needs_app_info:
        info, _ = app_info_for_listing(asc, app_id)
        present = {attrs(row).get("locale") for row in app_info_localizations(asc, app_id, info["id"])}
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
    asc: asc_cli.Asc, *, bundle_id: str, expected_app_id: str, version_string: str
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
    app_id = find_app(asc, bundle_id, expected_app_id)
    versions = ios_versions(asc, app_id)
    existing = [row for row in versions if attrs(row).get("versionString") == version_string]
    if len(existing) > 1:
        fail(f"ambiguous: {len(existing)} iOS App Store versions are named {version_string!r}")
    if existing:
        state = attrs(existing[0]).get("appStoreState") or ""
        print(f"App Store version {version_string} already exists ({state}); nothing to create")
        return
    problems: list[str] = []
    for row in versions:
        other = attrs(row).get("versionString") or ""
        state = attrs(row).get("appStoreState") or ""
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
    call(asc, "versions", "create", "--app", app_id, "--version", version_string, "--platform", PLATFORM)
    created = [row for row in ios_versions(asc, app_id) if attrs(row).get("versionString") == version_string]
    if len(created) != 1:
        fail(
            f"created App Store version {version_string}, but reading it back found "
            f"{len(created)} records; check it in App Store Connect before rerunning"
        )
    state = attrs(created[0]).get("appStoreState") or ""
    print(f"created App Store version {version_string} ({state or 'state not reported yet'})")


def preflight(
    asc: asc_cli.Asc,
    *,
    bundle_id: str,
    version_string: str,
    plan: dict[str, dict[str, Any]],
    do_listing: bool,
    do_whats_new: bool,
    do_screenshots: bool,
    do_submit: bool,
    do_creative: bool = False,
    creative_dir: Path = CREATIVE_DIR,
) -> None:
    """Read-only checks run before a build is uploaded, so a release fails early.

    The version must exist (IOS_CREATE_VERSION's step, which runs before this,
    creates a missing one) in a state that allows the enabled steps, with every
    repository locale; What's New must differ from the live version's; screenshots
    and creative assets that can no longer change must already match; no in-app
    product may have to ship with it. The live run repeats every check, because
    App Store Connect can change in between. The caller passes a read-only asc.
    """
    app_id = find_app(asc, bundle_id)
    version = get_ios_app_store_version(asc, app_id, version_string)
    state = attrs(version).get("appStoreState") or ""
    edits_metadata = do_listing or do_whats_new or do_screenshots or do_creative
    require_version_state(version_string, state, edits_metadata=edits_metadata, submit=do_submit)
    if edits_metadata:
        require_localizations(asc, app_id, version["id"], plan, listing=do_listing)
    if do_whats_new:
        for locale, entry in plan.items():
            refuse_stale_whats_new(asc, app_id, version["id"], locale, entry["whats_new"])
    text_locked, screenshots_locked = metadata_locks(version_string, state)
    sync_metadata(
        asc,
        app_id=app_id,
        version_id=version["id"],
        plan=plan,
        listing=do_listing,
        whats_new=do_whats_new,
        screenshots=do_screenshots,
        text_locked=text_locked,
        screenshots_locked=screenshots_locked,
        creative=do_creative,
        creative_dir=creative_dir,
        check_only=True,
    )
    if do_submit:
        refuse_pending_in_app_products(asc, app_id)
    print(f"ASC preflight passed: version {version_string} ({state}) is ready for the enabled steps")


def verify_build(asc: asc_cli.Asc, build_id: str, version_string: str, build_number: str) -> None:
    """Re-read the build and refuse anything but this run's processed build."""
    payload = call(asc, "builds", "list", "--app", ASC_APP_ID, "--build-number", build_number, "--version",
                   version_string, "--platform", PLATFORM, "--processing-state", "all", "--include", "preReleaseVersion")
    included = {(row.get("type"), row.get("id")): row for row in (payload or {}).get("included") or []}
    build = next((row for row in rows(payload) if row.get("id") == build_id), None)
    problems = []
    if build is None:
        problems.append("not listed for this app, version and build number")
        a: dict[str, Any] = {}
        pre: dict[str, Any] = {}
    else:
        a = attrs(build)
        pre = attrs(included.get(("preReleaseVersions", related_id(build, "preReleaseVersion"))))
    if build is not None and a.get("version") != build_number:
        problems.append(f"build number {a.get('version')!r}")
    if build is not None and a.get("processingState") != "VALID":
        problems.append(f"processing state {a.get('processingState')!r}")
    if a.get("expired"):
        problems.append("expired")
    if build is not None and (pre.get("version") != version_string or pre.get("platform") != PLATFORM):
        problems.append(f"version {pre.get('platform')} {pre.get('version')!r}")
    if problems:
        fail(
            f"build {build_id} is not {version_string} ({build_number}), VALID and unexpired: "
            + ", ".join(problems)
        )


def attached_build_id(asc: asc_cli.Asc, version_id: str) -> str | None:
    payload = call(asc, "versions", "view", "--version-id", version_id, "--include", "build")
    return related_id(data(payload) or {}, "build")


def confirm_selected_build(asc: asc_cli.Asc, version_id: str, build_id: str) -> None:
    current = attached_build_id(asc, version_id)
    if current != build_id:
        fail(
            f"App Store version {version_id} has build {current or 'none'} selected, "
            f"expected {build_id}; not submitting"
        )


def select_build(asc: asc_cli.Asc, version_id: str, build_id: str, version_string: str, build_number: str) -> None:
    """Explicitly select this run's build for the version, then read it back."""
    verify_build(asc, build_id, version_string, build_number)
    call(asc, "versions", "attach-build", "--version-id", version_id, "--build-id", build_id)
    confirm_selected_build(asc, version_id, build_id)
    print(f"  selected build {build_number} ({build_id}) for version {version_string}")


def set_release_type(asc: asc_cli.Asc, version_id: str, *, public_release: bool) -> None:
    release_type = RELEASE_TYPE_PUBLIC if public_release else RELEASE_TYPE_MANUAL
    call(asc, "versions", "update", "--version-id", version_id, "--release-type", release_type)
    print(
        "  release type: "
        + ("release automatically after approval" if public_release else "manual release after approval")
    )


# Review submission items carry their related ids only when asc asks for them.
ITEM_RELATIONSHIPS = ("appStoreVersion", "subscriptionVersion", "inAppPurchaseVersion", "appAssetLibraryImage")


def submission_items(asc: asc_cli.Asc, submission_id: str) -> list[dict[str, Any]]:
    """The submission's items with their related ids."""
    return rows(
        call(
            asc, "review", "items-list", "--submission", submission_id, "--include", ",".join(ITEM_RELATIONSHIPS),
            "--paginate",
        )
    )


def draft_submission_ids(asc: asc_cli.Asc, app_id: str) -> list[str]:
    payload = call(
        asc, "review", "submissions-list", "--app", app_id, "--platform", PLATFORM, "--state", "READY_FOR_REVIEW",
        "--paginate",
    )
    return [row["id"] for row in rows(payload)]


def find_draft_submission(asc: asc_cli.Asc, app_id: str, version_id: str | None = None) -> str | None:
    """The app's draft (READY_FOR_REVIEW) iOS review submission to use for the version, if there is one.

    The draft already holding version_id wins. Otherwise only a draft holding no
    app version is reused (more than one is ambiguous), so another version's
    draft is never touched. A draft holding creative images belongs to their own
    review and is skipped. Nothing is created here: a draft is created only when
    the version is about to be added, so a run that stops earlier leaves no
    empty draft behind.
    """
    drafts = []
    for submission_id in draft_submission_ids(asc, app_id):
        items = submission_items(asc, submission_id)
        if not any(related_id(item, "appAssetLibraryImage") for item in items):
            drafts.append((submission_id, {related_id(item, "appStoreVersion") for item in items} - {None, ""}))
    if version_id:
        for submission_id, versions in drafts:
            if version_id in versions:
                return submission_id
    reusable = [submission_id for submission_id, versions in drafts if not versions]
    if len(reusable) > 1:
        fail(f"ambiguous: {len(reusable)} draft review submissions; remove the extras in App Store Connect")
    return reusable[0] if reusable else None


def create_draft_submission(asc: asc_cli.Asc, app_id: str) -> str:
    created = data(call(asc, "review", "submissions-create", "--app", app_id, "--platform", PLATFORM)) or {}
    if not created.get("id"):
        fail("asc did not report the new review submission's id")
    return created["id"]


def draft_holds_version(asc: asc_cli.Asc, submission_id: str, version_id: str) -> bool:
    """True if the draft already holds this version; fails if it holds anything else."""
    holds = False
    others: list[str] = []
    for item in submission_items(asc, submission_id):
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


def check_draft_items(asc: asc_cli.Asc, submission_id: str, *, version_id: str) -> None:
    """Right before submitting: the draft must hold this version and nothing else.

    A reused draft can gain items added by hand or by another tool, and Scowld's
    release submits nothing but the version, so they must not ride along into
    App Review. A draft without the version is never submitted.
    """
    items = submission_items(asc, submission_id)
    if not any(related_id(item, "appStoreVersion") == version_id for item in items):
        fail(f"review submission {submission_id} does not hold App Store version {version_id}; not submitting it")
    unexpected = [item.get("id") for item in items if related_id(item, "appStoreVersion") != version_id]
    if unexpected:
        fail(
            f"review submission {submission_id} holds items this release did not choose "
            f"({', '.join(map(str, unexpected))}); remove them in App Store Connect and rerun"
        )


def submit_for_review(
    asc: asc_cli.Asc, app_id: str, submission_id: str | None, version_id: str, *, already_added: bool
) -> None:
    """Add the version to the draft unless it already holds it, re-check the draft, submit it."""
    if not already_added:
        if submission_id is None:
            # Created only now, right before the version is added to it.
            submission_id = create_draft_submission(asc, app_id)
        call(
            asc, "review", "items-add", "--submission", submission_id, "--item-type", "appStoreVersions",
            "--item-id", version_id, "--if-exists", "skip",
        )
    assert submission_id is not None
    check_draft_items(asc, submission_id, version_id=version_id)
    call(asc, "review", "submissions-submit", "--id", submission_id, "--confirm")
    print(f"  submitted App Store version {version_id} for review (submission {submission_id})")


# MARK: - Entry point


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--metadata-dir", type=Path, default=METADATA_DIR, help="store/metadata/ios")
    parser.add_argument(
        "--creative-dir",
        type=Path,
        default=CREATIVE_DIR,
        help="Product page header and search results images, one per folder: "
        + ", ".join(slot[0] for slot in CREATIVE_SLOTS),
    )
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--version", help="Marketing version from the release tag (v2.0.2 → 2.0.2)")
    parser.add_argument("--build-id", help="App Store Connect id of the build uploaded by this run")
    parser.add_argument("--build-number", help="CFBundleVersion of the build uploaded by this run")
    parser.add_argument("--dry-run", action="store_true", help="Validate switches and local files only — no asc calls")
    parser.add_argument(
        "--preflight",
        action="store_true",
        help="Read-only App Store Connect checks before the build is uploaded (asc in read-only mode)",
    )
    parser.add_argument(
        "--create-version",
        action="store_true",
        help="Create the App Store version for --version when it is missing (CREATE_IOS_VERSION)",
    )
    args = parser.parse_args(argv)

    # find_app() checks the pinned app's bundle id, so only this app is accepted.
    if args.bundle_id != DEFAULT_BUNDLE_ID:
        fail(f"this publisher only supports the Scowld iOS bundle ({DEFAULT_BUNDLE_ID})")

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
            asc_from_environment(),
            bundle_id=args.bundle_id,
            expected_app_id=ASC_APP_ID,
            version_string=args.version,
        )
        return

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
    if args.dry_run:
        print(
            f"ASC dry-run — local inputs OK for {', '.join(plan) or 'no locales'}; no asc calls "
            f"(listing={do_listing} whats_new={do_whats_new} screenshots={do_screenshots} "
            f"creative={do_creative} submit={do_submit} public_release={do_public})"
        )
        return

    if not args.version:
        fail("--version is required for live App Store Connect calls")
    edits_metadata = do_listing or do_whats_new or do_screenshots or do_creative
    if args.preflight:
        preflight(
            asc_from_environment(read_only=True),
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
    asc = asc_from_environment()
    app_id = find_app(asc, args.bundle_id)
    version = get_ios_app_store_version(asc, app_id, args.version)
    version_id = version["id"]
    state = attrs(version).get("appStoreState") or ""
    print(f"ASC app={app_id} version={args.version} id={version_id} state={state}")

    # A rerun after this pipeline already submitted: nothing may change any more, so the
    # enabled steps only confirm App Store Connect matches, and review must hold this
    # run's build.
    already_submitted = state == SUBMITTED_VERSION_STATE
    if not already_submitted:
        require_version_state(args.version, state, edits_metadata=edits_metadata, submit=do_submit)
        if do_submit:
            # Checked before any change, so a blocked submission leaves the listing untouched.
            refuse_pending_in_app_products(asc, app_id)

    text_locked, screenshots_locked = metadata_locks(args.version, state)
    sync_metadata(
        asc,
        app_id=app_id,
        version_id=version_id,
        plan=plan,
        listing=do_listing,
        whats_new=do_whats_new,
        screenshots=do_screenshots,
        text_locked=text_locked,
        screenshots_locked=screenshots_locked,
        creative=do_creative,
        creative_dir=args.creative_dir,
    )

    if already_submitted:
        if do_submit:
            confirm_selected_build(asc, version_id, args.build_id)
            print(f"ASC submit skipped — version already {state} with this run's build (idempotent)")
        print("ASC release step finished")
        return

    if do_submit:
        # The draft is looked up and checked before anything else is changed; it
        # is created only when the version has to be added to one.
        submission_id = find_draft_submission(asc, app_id, version_id)
        already_added = draft_holds_version(asc, submission_id, version_id) if submission_id else False
        if state == "READY_FOR_REVIEW" and not already_added:
            # READY_FOR_REVIEW means a draft already holds the version; adding it to
            # another one is never right, so stop before anything is written.
            fail(
                f"version {args.version} is READY_FOR_REVIEW, but no draft review submission this release can "
                "use holds it; check its draft in App Store Connect (or remove the version from it) and rerun"
            )
        print("selecting this run's build…")
        select_build(asc, version_id, args.build_id, args.version, args.build_number)
        set_release_type(asc, version_id, public_release=do_public)
        # Recheck immediately before submitting: the selection must still be this run's build.
        verify_build(asc, args.build_id, args.version, args.build_number)
        confirm_selected_build(asc, version_id, args.build_id)
        print("submitting for App Store review…")
        submit_for_review(asc, app_id, submission_id, version_id, already_added=already_added)

    print("ASC release step finished")


if __name__ == "__main__":
    main()
