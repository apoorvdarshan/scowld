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
    master = enabled(GATES[0])
    print("iOS store automation switches (false = setup-only / safe):")
    for name in GATES:
        on = enabled(name)
        note = " (ignored: IOS_RELEASE_AUTOMATION is off)" if on and not master and name != GATES[0] else ""
        print(f"  {name}={'true' if on else 'false'}{note}")
    live = master and any(enabled(name) for name in GATES[1:])
    if not master:
        print("IOS_RELEASE_AUTOMATION is off — no upload, listing change or review submission runs")
    elif live:
        print("WARNING: one or more live switches are on")
    else:
        print("IOS_RELEASE_AUTOMATION is on but every operation switch is off — nothing reaches the App Store")


if __name__ == "__main__":
    main()
