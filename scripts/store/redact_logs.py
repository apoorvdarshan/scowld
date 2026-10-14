#!/usr/bin/env python3
"""Redact App Store Connect credential IDs from a folder before it is uploaded.

Usage: redact_logs.py <folder>
Reads the values to remove from ASC_KEY_ID and ASC_ISSUER_ID.

The build job uploads its logs as an artifact when it fails, and artifacts are not
masked like the job log. xcodebuild and altool echo both IDs into their logs and
into the copied .xcdistributionlogs bundles, which can hold binary or UTF-16 files.
So every regular file is rewritten byte for byte, binary or not, replacing each ID
in UTF-8 and in UTF-16 (little- and big-endian) with <ASC_KEY_ID> /
<ASC_ISSUER_ID>. Symbolic links are deleted, not followed.

Exit status 0 means no file under the folder still contains either ID. A file
that cannot be rewritten is deleted; if that fails too the exit status is 1, and
the workflow then uploads nothing.

Runs on the macOS runner's system Python, so it stays compatible with 3.9.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ENVIRONMENT = (("ASC_KEY_ID", "<ASC_KEY_ID>"), ("ASC_ISSUER_ID", "<ASC_ISSUER_ID>"))
ENCODINGS = ("utf-8", "utf-16-le", "utf-16-be")


def secrets_from_environment(environ: dict[str, str] | None = None) -> dict[str, str]:
    """ID value -> placeholder, skipping unset values (an empty pattern matches everywhere)."""
    environ = os.environ if environ is None else environ
    found = {}
    for name, placeholder in ENVIRONMENT:
        value = (environ.get(name) or "").strip()
        if value:
            found[value] = placeholder
    return found


def redact_bytes(data: bytes, secrets: dict[str, str]) -> bytes:
    for value, placeholder in secrets.items():
        for encoding in ENCODINGS:
            data = data.replace(value.encode(encoding), placeholder.encode(encoding))
    return data


def contains_secret(data: bytes, secrets: dict[str, str]) -> bool:
    return any(value.encode(encoding) in data for value in secrets for encoding in ENCODINGS)


def redact_tree(root: Path, secrets: dict[str, str]) -> tuple[int, int, list[Path]]:
    """Returns (files rewritten, entries deleted, files that still hold an ID)."""
    rewritten = deleted = 0
    leftovers: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in list(dirnames) + filenames:
            path = Path(dirpath) / name
            if path.is_symlink():
                path.unlink()
                deleted += 1
                if name in dirnames:
                    dirnames.remove(name)
                continue
            if name in dirnames or not path.is_file():
                continue
            try:
                data = path.read_bytes()
                cleaned = redact_bytes(data, secrets)
                if cleaned != data:
                    path.write_bytes(cleaned)
                    rewritten += 1
                if not contains_secret(path.read_bytes(), secrets):
                    continue
            except OSError as exc:
                print(f"warning: could not redact {path}: {exc}", file=sys.stderr)
            # Rewriting failed or left an ID behind: the file must not be uploaded.
            try:
                path.unlink()
                deleted += 1
            except OSError as exc:
                print(f"error: {path} still holds a credential ID and cannot be deleted: {exc}", file=sys.stderr)
                leftovers.append(path)
    return rewritten, deleted, leftovers


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    root = Path(argv[1])
    if not root.is_dir():
        print(f"nothing to redact: {root} does not exist")
        return 0
    secrets = secrets_from_environment()
    if not secrets:
        print("warning: ASC_KEY_ID and ASC_ISSUER_ID are empty; nothing to redact", file=sys.stderr)
        return 0
    rewritten, deleted, leftovers = redact_tree(root, secrets)
    print(f"redacted credential IDs in {rewritten} file(s); removed {deleted} link(s) or unredactable file(s)")
    return 1 if leftovers else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
