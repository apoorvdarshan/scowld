#!/usr/bin/env python3
"""Export the live App Store listing into store/metadata/ios/<locale>/ (read-only).

Run it after the listing was edited directly in App Store Connect, so the
repository stays the source of truth:

    python3 scripts/store/asc_export_listing.py            # newest live version
    python3 scripts/store/asc_export_listing.py --version 2.0.1

Writes one text file per field (see asc_release.py) for every locale, and a
screenshots.json per locale that maps each live screenshot set to the identical
image in this repository (matched by MD5). Screenshots with no identical file
in the repository are reported and left out.

Needs APP_STORE_CONNECT_API_KEY_ID / _ISSUER_ID / _API_KEY_P8 and PyJWT. Only GET
requests are made.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asc_release as asc  # noqa: E402

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg"}


class ReadOnlyClient:
    """Exposes only GET, so an export can never change App Store Connect."""

    def __init__(self, client: Any) -> None:
        self._client = client

    def get(self, path: str) -> dict[str, Any]:
        return self._client.get(path)


def repo_images(root: Path) -> dict[str, Path]:
    images: dict[str, Path] = {}
    for path in sorted(root.rglob("*")):
        if path.suffix.lower() in IMAGE_SUFFIXES and path.is_file() and ".git" not in path.parts:
            images.setdefault(asc.md5_hex(path), path)
    return images


def write_field(path: Path, value: str | None) -> None:
    text = (value or "").strip()
    if text:
        path.write_text(text + "\n", encoding="utf-8")
    elif path.exists():
        path.unlink()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", help="App Store version to export (default: the newest live one)")
    parser.add_argument("--out", type=Path, default=asc.METADATA_DIR)
    parser.add_argument("--bundle-id", default=asc.DEFAULT_BUNDLE_ID)
    args = parser.parse_args(argv)

    client = ReadOnlyClient(asc.client_from_environment())
    app_id = asc.find_app(client, args.bundle_id)
    versions = asc.ios_versions(client, app_id)
    if args.version:
        version = asc.get_ios_app_store_version(client, app_id, args.version)
    else:
        live = [v for v in versions if (v.get("attributes") or {}).get("appStoreState") in asc.LIVE_VERSION_STATES]
        if not live:
            asc.fail("no live iOS version; pass --version")
        version = max(live, key=lambda v: (v.get("attributes") or {}).get("createdDate") or "")
    version_name = version["attributes"]["versionString"]

    infos = asc.iter_collection(client, f"/apps/{app_id}/appInfos")
    live_infos = [i for i in infos if asc.app_info_state(i) in {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE"}]
    info = (live_infos or infos or [None])[0]
    info_locs = {
        row["attributes"]["locale"]: row["attributes"]
        for row in (asc.iter_collection(client, f"/appInfos/{info['id']}/appInfoLocalizations?limit=50") if info else [])
    }
    version_locs = {
        row["attributes"]["locale"]: row
        for row in asc.iter_collection(client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50")
    }

    images = repo_images(asc.ROOT)
    missing: list[str] = []
    for locale in sorted(set(info_locs) | set(version_locs)):
        loc_dir = args.out / locale
        loc_dir.mkdir(parents=True, exist_ok=True)
        info_attrs = info_locs.get(locale, {})
        for field, filename, _ in asc.APP_INFO_FIELDS:
            write_field(loc_dir / filename, info_attrs.get(field))
        version_row = version_locs.get(locale)
        version_attrs = (version_row or {}).get("attributes") or {}
        for field, filename, _ in asc.VERSION_FIELDS + (asc.WHATS_NEW_FIELD,):
            write_field(loc_dir / filename, version_attrs.get(field))

        manifest: dict[str, list[str]] = {}
        if version_row:
            for shot_set in asc.iter_collection(client, f"/appStoreVersionLocalizations/{version_row['id']}/appScreenshotSets?limit=50"):
                display_type = shot_set["attributes"]["screenshotDisplayType"]
                paths: list[str] = []
                for shot in asc.iter_collection(client, f"/appScreenshotSets/{shot_set['id']}/appScreenshots?limit=50"):
                    attrs = shot.get("attributes") or {}
                    match = images.get(attrs.get("sourceFileChecksum") or "")
                    if match is None:
                        missing.append(f"{locale} {display_type} {attrs.get('fileName')}")
                        break
                    paths.append(match.relative_to(asc.ROOT).as_posix())
                else:
                    manifest[display_type] = paths
        manifest_path = loc_dir / asc.SCREENSHOT_MANIFEST
        if manifest:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        elif manifest_path.exists():
            manifest_path.unlink()
        print(f"exported {locale} from version {version_name} ({len(manifest)} screenshot set(s))")

    for item in missing:
        print(f"warning: no identical repository image for live screenshot {item}; that set was not exported")
    return 0


if __name__ == "__main__":
    sys.exit(main())
