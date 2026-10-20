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

Needs APP_STORE_CONNECT_API_KEY_ID / _ISSUER_ID / _API_KEY_P8 and the pinned asc
on PATH (python3 scripts/store/asc_cli.py install --dest DIR, then add DIR to
PATH). asc runs read-only (ASC_READ_ONLY), so an export can never change App
Store Connect.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asc_release as release  # noqa: E402

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg"}


def repo_images(root: Path) -> dict[str, Path]:
    images: dict[str, Path] = {}
    for path in sorted(root.rglob("*")):
        if path.suffix.lower() in IMAGE_SUFFIXES and path.is_file() and ".git" not in path.parts:
            images.setdefault(release.md5_hex(path), path)
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
    parser.add_argument("--out", type=Path, default=release.METADATA_DIR)
    parser.add_argument("--bundle-id", default=release.DEFAULT_BUNDLE_ID)
    args = parser.parse_args(argv)

    asc = release.asc_from_environment(read_only=True)
    app_id = release.find_app(asc, args.bundle_id)
    versions = release.ios_versions(asc, app_id)
    if args.version:
        version = release.get_ios_app_store_version(asc, app_id, args.version)
    else:
        live = [v for v in versions if release.attrs(v).get("appStoreState") in release.LIVE_VERSION_STATES]
        if not live:
            release.fail("no live iOS version; pass --version")
        version = max(live, key=lambda v: release.attrs(v).get("createdDate") or "")
    version_name = release.attrs(version)["versionString"]

    infos = release.rows(release.call(asc, "apps", "info", "list", "--app", app_id))
    live_infos = [i for i in infos if release.app_info_state(i) in release.LIVE_APP_INFO_STATES]
    info = (live_infos or infos or [None])[0]
    info_locs = {
        release.attrs(row)["locale"]: release.attrs(row)
        for row in (release.app_info_localizations(asc, app_id, info["id"]) if info else [])
    }
    version_locs = {release.attrs(row)["locale"]: row for row in release.version_localizations(asc, version["id"])}

    images = repo_images(release.ROOT)
    missing: list[str] = []
    for locale in sorted(set(info_locs) | set(version_locs)):
        loc_dir = args.out / locale
        loc_dir.mkdir(parents=True, exist_ok=True)
        info_attrs = info_locs.get(locale, {})
        for field, filename, _ in release.APP_INFO_FIELDS:
            write_field(loc_dir / filename, info_attrs.get(field))
        version_row = version_locs.get(locale)
        version_attrs = release.attrs(version_row)
        for field, filename, _ in release.VERSION_FIELDS + (release.WHATS_NEW_FIELD,):
            write_field(loc_dir / filename, version_attrs.get(field))

        manifest: dict[str, list[str]] = {}
        if version_row:
            for display_type, shots in release.screenshot_sets(asc, version_row["id"]).items():
                paths: list[str] = []
                for shot in shots:
                    shot_attrs = release.attrs(shot)
                    match = images.get(shot_attrs.get("sourceFileChecksum") or "")
                    if match is None:
                        missing.append(f"{locale} {display_type} {shot_attrs.get('fileName')}")
                        break
                    paths.append(match.relative_to(release.ROOT).as_posix())
                else:
                    manifest[display_type] = paths
        manifest_path = loc_dir / release.SCREENSHOT_MANIFEST
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
