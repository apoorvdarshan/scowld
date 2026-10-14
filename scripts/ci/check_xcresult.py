#!/usr/bin/env python3
"""Fail unless every named test bundle in an .xcresult actually ran tests.

Usage: check_xcresult.py <Tests.xcresult> <bundle> [<bundle> ...]

Prints per-bundle counts (and appends them to $GITHUB_STEP_SUMMARY when set).
A bundle that is missing, or whose tests were all skipped, is an error.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from collections import Counter


def test_cases(node: dict) -> list[dict]:
    if node.get("nodeType") == "Test Case":
        return [node]
    found: list[dict] = []
    for child in node.get("children") or []:
        found.extend(test_cases(child))
    return found


def bundles(tree: dict) -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = {}

    def walk(node: dict) -> None:
        if node.get("nodeType") in {"Unit test bundle", "UI test bundle"}:
            result.setdefault(node.get("name", ""), []).extend(test_cases(node))
            return
        for child in node.get("children") or []:
            walk(child)

    for node in tree.get("testNodes") or []:
        walk(node)
    return result


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    path, required = argv[1], argv[2:]
    raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", path])
    found = bundles(json.loads(raw))

    ok = True
    lines = []
    for name in required:
        cases = found.get(name)
        if cases is None:
            print(f"error: test bundle {name} did not run", file=sys.stderr)
            ok = False
            continue
        counts = Counter(case.get("result", "Unknown") for case in cases)
        ran = sum(count for result, count in counts.items() if result != "Skipped")
        detail = ", ".join(f"{count} {result.lower()}" for result, count in sorted(counts.items()))
        lines.append(f"{name}: {ran} tests ran ({detail})")
        if ran == 0:
            print(f"error: test bundle {name} ran zero tests", file=sys.stderr)
            ok = False
    for line in lines:
        print(line)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary and lines:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("\n".join(f"- {line}" for line in lines) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
