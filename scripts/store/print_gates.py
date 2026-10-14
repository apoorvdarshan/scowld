#!/usr/bin/env python3
"""Print the iOS store automation switches for the run log. Never mutates a store.

Invalid values are rejected earlier by `ios_release.py gates`; this only reports.
"""
from __future__ import annotations

import os

GATES = (
    "IOS_RELEASE_AUTOMATION",
    "IOS_UPLOAD_BUILD",
    "IOS_UPLOAD_LISTING",
    "IOS_UPLOAD_WHATS_NEW",
    "IOS_UPLOAD_SCREENSHOTS",
    "IOS_SUBMIT_REVIEW",
    "IOS_PUBLIC_RELEASE",
)


def enabled(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in {"1", "true", "yes", "on"}


def main() -> None:
    print("iOS store automation switches (false = setup-only / safe):")
    any_on = False
    for name in GATES:
        on = enabled(name)
        any_on = any_on or on
        print(f"  {name}={'true' if on else 'false'}")
    if not enabled("IOS_RELEASE_AUTOMATION"):
        print("  note: IOS_RELEASE_AUTOMATION is off, so every iOS store operation is skipped")
    if not any_on:
        print("all switches off — no upload, listing change or review submission ran")
    else:
        print("WARNING: one or more live switches are on")


if __name__ == "__main__":
    main()
