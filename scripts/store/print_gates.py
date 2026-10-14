#!/usr/bin/env python3
"""Print the iOS store automation switches for the run log. Never mutates a store.

What a run may actually do is resolved by `ios_release.py gates`, which fails the
run on an invalid value; this only reports. An invalid value is shown as INVALID
(never as false), so the log matches what the release run will do.
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
# Same values as ios_release.parse_switch (a test keeps the two in sync).
TRUE_VALUES = {"1", "true", "yes", "on"}
FALSE_VALUES = {"", "0", "false", "no", "off"}


def describe(name: str) -> tuple[str, bool | None]:
    """(text for the log, True/False for on/off, or None when the value is invalid)."""
    raw = os.environ.get(name, "")
    value = raw.strip().lower()
    if value in TRUE_VALUES:
        return "true", True
    if value in FALSE_VALUES:
        return ("false" if value else "false (unset)"), False
    return f"INVALID {raw!r} (a release run fails)", None


def main() -> None:
    states = {name: describe(name) for name in GATES}
    master = states[GATES[0]][1] is True
    print("iOS store automation switches (false = setup-only / safe):")
    for name in GATES:
        shown, on = states[name]
        note = " (ignored: IOS_RELEASE_AUTOMATION is off)" if on and not master and name != GATES[0] else ""
        print(f"  {name}={shown}{note}")
    invalid = [name for name in GATES if states[name][1] is None]
    if invalid:
        print(
            f"ERROR: {', '.join(invalid)} {'has' if len(invalid) == 1 else 'have'} an invalid value; "
            "use true/false (or leave it unset). A release run fails until this is fixed."
        )
    live = master and any(states[name][1] is True for name in GATES[1:])
    if not master:
        print("IOS_RELEASE_AUTOMATION is off — no upload, listing change or review submission runs")
    elif live:
        print("WARNING: one or more live switches are on")
    else:
        print("IOS_RELEASE_AUTOMATION is on but every operation switch is off — nothing reaches the App Store")


if __name__ == "__main__":
    main()
