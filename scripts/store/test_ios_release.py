#!/usr/bin/env python3
"""Offline tests for the iOS release switches, build waiting, listing, screenshots,
review submission and reruns, the printed switches, release notes and the
redaction of build-log artifacts.

No network: every App Store Connect call goes to an in-memory fake.
Run: python3 -m unittest scripts/store/test_ios_release.py

Tests marked @committed_files_test check committed repository content (the App
Store listing, screenshots and release notes) rather than code. Pull requests and
main run them. The release's prepare job sets CHECK_COMMITTED_STORE_FILES=false
and validates only the files its enabled switches use, so an unused file never
blocks a release.
"""
from __future__ import annotations

import argparse
import datetime as dt
import http.client
import io
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import zlib
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import asc_release  # noqa: E402
import ios_release  # noqa: E402
import print_gates  # noqa: E402
import redact_logs  # noqa: E402
from ios_release import ReleaseError, resolve_gates  # noqa: E402

ROOT = HERE.parents[1]
CHECK_COMMITTED_FILES = os.environ.get("CHECK_COMMITTED_STORE_FILES", "true").strip().lower() not in {
    "0", "false", "no", "off",
}
committed_files_test = unittest.skipUnless(
    CHECK_COMMITTED_FILES, "CHECK_COMMITTED_STORE_FILES=false: this run checks only the files its switches use"
)
TAG = "v2.0.2"
VERSION = "2.0.2"
ALL_ON = {
    "IOS_RELEASE_AUTOMATION": "true",
    "IOS_UPLOAD_BUILD": "true",
    "IOS_UPLOAD_LISTING": "true",
    "IOS_UPLOAD_WHATS_NEW": "true",
    "IOS_UPLOAD_SCREENSHOTS": "true",
    "IOS_SUBMIT_REVIEW": "true",
    "IOS_PUBLIC_RELEASE": "true",
}
OPS = ("upload_build", "listing", "whats_new", "screenshots", "submit", "public_release")
ASC_FLAGS = ("UPLOAD_LISTING", "UPLOAD_WHATS_NEW", "UPLOAD_SCREENSHOTS", "SUBMIT_IOS_REVIEW", "PUBLIC_RELEASE")


def gates(env: dict[str, str], *, event: str = "push", ref: str = TAG) -> dict:
    return resolve_gates(env, event=event, ref_name=ref, marketing_version=VERSION)


def quiet(fn, *args, **kwargs):
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        return fn(*args, **kwargs)


class GateTests(unittest.TestCase):
    def test_missing_settings_mean_everything_off(self) -> None:
        result = gates({})
        self.assertEqual(result["mode"], "release")
        self.assertFalse(result["master"])
        self.assertFalse(result["build"])
        self.assertFalse(result["asc"])
        for key in OPS:
            self.assertFalse(result[key], key)
        self.assertEqual((result["poll_seconds"], result["wait_minutes"]), (30, 120))

    def test_master_off_ignores_operation_switches(self) -> None:
        result = gates({**ALL_ON, "IOS_RELEASE_AUTOMATION": "false"})
        for key in OPS:
            self.assertFalse(result[key], key)
        self.assertFalse(result["build"])
        self.assertTrue(any("ignored" in note for note in result["notes"]))

    def test_each_operation_is_independent(self) -> None:
        result = gates({"IOS_RELEASE_AUTOMATION": "yes", "IOS_UPLOAD_LISTING": "on"})
        self.assertTrue(result["listing"])
        self.assertTrue(result["asc"])
        self.assertFalse(result["whats_new"])
        self.assertFalse(result["upload_build"])
        self.assertFalse(result["build"])
        screenshots = gates({"IOS_RELEASE_AUTOMATION": "1", "IOS_UPLOAD_SCREENSHOTS": "1"})
        self.assertTrue(screenshots["screenshots"])
        self.assertFalse(screenshots["listing"])

    def test_all_on(self) -> None:
        result = gates(ALL_ON)
        for key in OPS:
            self.assertTrue(result[key], key)
        self.assertTrue(result["build"])
        self.assertTrue(result["master"])

    def test_every_documented_value_is_accepted(self) -> None:
        for value in ("true", "TRUE", " yes ", "on", "1"):
            self.assertTrue(gates({"IOS_RELEASE_AUTOMATION": value, "IOS_UPLOAD_LISTING": value})["listing"])
        for value in ("false", "no", "off", "0", ""):
            self.assertFalse(gates({"IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_LISTING": value})["listing"])

    def test_invalid_values_are_rejected_even_when_master_is_off(self) -> None:
        for name in ("IOS_RELEASE_AUTOMATION", "IOS_UPLOAD_BUILD", "IOS_SUBMIT_REVIEW", "IOS_PUBLIC_RELEASE"):
            for value in ("maybe", "enabled", "2"):
                with self.subTest(name=name, value=value), self.assertRaisesRegex(ReleaseError, name):
                    gates({name: value})
        with self.assertRaisesRegex(ReleaseError, "IOS_UPLOAD_SCREENSHOTS"):
            gates({"IOS_RELEASE_AUTOMATION": "false", "IOS_UPLOAD_SCREENSHOTS": "ture"})

    def test_invalid_values_also_fail_manual_validation_runs(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "IOS_UPLOAD_LISTING"):
            gates({"IOS_UPLOAD_LISTING": "maybe"}, event="workflow_dispatch", ref="main")

    def test_bad_timing_values_are_rejected(self) -> None:
        for env in (
            {"IOS_BUILD_POLL_SECONDS": "5"},
            {"IOS_BUILD_POLL_SECONDS": "601"},
            {"IOS_BUILD_POLL_SECONDS": "thirty"},
            {"IOS_BUILD_POLL_SECONDS": "٣٠"},
            {"IOS_BUILD_WAIT_MINUTES": "0"},
            {"IOS_BUILD_WAIT_MINUTES": "9"},
            {"IOS_BUILD_WAIT_MINUTES": "301"},
        ):
            with self.subTest(env=env), self.assertRaises(ReleaseError):
                gates(env)
        result = gates({"IOS_BUILD_POLL_SECONDS": "45", "IOS_BUILD_WAIT_MINUTES": "90"})
        self.assertEqual((result["poll_seconds"], result["wait_minutes"]), (45, 90))
        bounds = gates({"IOS_BUILD_POLL_SECONDS": "600", "IOS_BUILD_WAIT_MINUTES": "10"})
        self.assertEqual((bounds["poll_seconds"], bounds["wait_minutes"]), (600, 10))

    def test_submit_requires_this_runs_build(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "IOS_UPLOAD_BUILD"):
            gates({"IOS_RELEASE_AUTOMATION": "true", "IOS_SUBMIT_REVIEW": "true"})

    def test_public_release_requires_submit(self) -> None:
        env = {"IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_BUILD": "true", "IOS_PUBLIC_RELEASE": "true"}
        with self.assertRaisesRegex(ReleaseError, "IOS_SUBMIT_REVIEW"):
            gates(env)

    def test_tag_must_match_marketing_version_exactly(self) -> None:
        for ref in ("v2.0.3", "v2.0", "v2.0.2.0", "v2.0.2-beta", "v 2.0.2"):
            with self.subTest(ref=ref), self.assertRaisesRegex(ReleaseError, "does not match"):
                gates({}, ref=ref)
        for ref in ("ios-v2.0.2", "2.0.2", "release-2.0.2"):
            with self.subTest(ref=ref), self.assertRaisesRegex(ReleaseError, "v<version> tag"):
                gates({}, ref=ref)
        self.assertEqual(gates({}, ref="v2.0.2")["marketing_version"], VERSION)

    def test_manual_run_validates_only(self) -> None:
        result = gates(ALL_ON, event="workflow_dispatch", ref="main")
        self.assertEqual(result["mode"], "validate")
        self.assertTrue(result["build"])
        self.assertFalse(result["master"])
        self.assertFalse(result["asc"])
        for key in OPS:
            self.assertFalse(result[key], key)

    def test_manual_run_can_validate_a_future_version(self) -> None:
        result = resolve_gates({}, event="workflow_dispatch", ref_name="main",
                               marketing_version="2.0.1", validation_version="2.0.2")
        self.assertEqual(result["mode"], "validate")
        self.assertEqual(result["marketing_version"], "2.0.2")
        self.assertFalse(result["asc"])
        self.assertTrue(any("not changed" in note for note in result["notes"]))
        default = resolve_gates({}, event="workflow_dispatch", ref_name="main", marketing_version="2.0.1")
        self.assertEqual(default["marketing_version"], "2.0.1")

    def test_version_override_is_rejected_for_releases_and_bad_values(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "manual validation"):
            resolve_gates({}, event="push", ref_name=TAG, marketing_version=VERSION, validation_version="2.0.3")
        for bad in ("2.x", "v2.0.2", "2.0.2.1", "2.0 beta", "٢.٠"):
            with self.subTest(bad=bad), self.assertRaisesRegex(ReleaseError, "must look like"):
                resolve_gates({}, event="workflow_dispatch", ref_name="main",
                              marketing_version=VERSION, validation_version=bad)

    def test_only_tag_pushes_and_manual_runs_are_supported(self) -> None:
        for event in ("pull_request", "schedule", ""):
            with self.subTest(event=event), self.assertRaisesRegex(ReleaseError, "unsupported event"):
                gates({}, event=event)

    def test_project_versions_are_consistent(self) -> None:
        self.assertRegex(ios_release.single_project_value("MARKETING_VERSION"), r"^\d+(\.\d+)*$")
        self.assertRegex(ios_release.single_project_value("CURRENT_PROJECT_VERSION"), r"^\d+$")
        with tempfile.TemporaryDirectory() as tmp:
            pbx = Path(tmp) / "project.pbxproj"
            pbx.write_text("MARKETING_VERSION = 1.0;\nMARKETING_VERSION = 1.1;\n")
            with self.assertRaisesRegex(ReleaseError, "identical"):
                ios_release.single_project_value("MARKETING_VERSION", pbx)

    def test_cli_writes_outputs_for_the_workflow(self) -> None:
        with tempfile.NamedTemporaryFile("r", suffix=".out") as out:
            env = {
                "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REF_NAME": "main",
                "GITHUB_OUTPUT": out.name,
                "VALIDATION_MARKETING_VERSION": "9.9.9",
            }
            with mock.patch.dict(os.environ, env, clear=False):
                quiet(ios_release.main, ["gates"])
            written = dict(line.split("=", 1) for line in Path(out.name).read_text().splitlines())
        self.assertEqual(written["mode"], "validate")
        self.assertEqual(written["build"], "true")
        self.assertEqual(written["upload_build"], "false")
        self.assertEqual(written["asc"], "false")
        self.assertEqual(written["marketing_version"], "9.9.9")

    def test_cli_exits_non_zero_on_invalid_switches(self) -> None:
        env = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF_NAME": TAG, "IOS_UPLOAD_BUILD": "sure"}
        with mock.patch.dict(os.environ, env, clear=False), self.assertRaises(SystemExit) as caught:
            quiet(ios_release.main, ["gates"])
        self.assertEqual(caught.exception.code, 1)


class BuildNumberTests(unittest.TestCase):
    def test_next_build_number(self) -> None:
        self.assertEqual(ios_release.next_build_number(14, ["1", "13", "12"]), 14)
        self.assertEqual(ios_release.next_build_number(14, ["13", "14"]), 15)
        self.assertEqual(ios_release.next_build_number(1, []), 1)
        self.assertEqual(ios_release.next_build_number(5, ["7.1", "abc", "9"]), 10)
        self.assertEqual(ios_release.next_build_number(5, ["٩٩"]), 5)  # only ASCII digits count


APP = "APP1"
STARTED = 1_800_000_000.0  # this run's upload start (epoch seconds)


def iso(epoch: float) -> str:
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat()


MISSING = object()


def build_row(
    build_id: str = "B1",
    *,
    number: str = "14",
    state: str = "VALID",
    expired: bool = False,
    uploaded: Any = STARTED + 60,
    app: str = APP,
    pre: str = "P1",
) -> dict:
    """`uploaded`: epoch seconds, a raw uploadedDate value (str/None), or MISSING to omit it."""
    attributes: dict[str, Any] = {"version": number, "processingState": state, "expired": expired}
    if uploaded is not MISSING:
        attributes["uploadedDate"] = iso(uploaded) if isinstance(uploaded, (int, float)) else uploaded
    return {
        "type": "builds",
        "id": build_id,
        "attributes": attributes,
        "relationships": {
            "preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": pre}},
            "app": {"data": {"type": "apps", "id": app}},
        },
    }


def pre_row(pre_id: str = "P1", version: str = VERSION, platform: str = "IOS") -> dict:
    return {"type": "preReleaseVersions", "id": pre_id, "attributes": {"version": version, "platform": platform}}


class FakeClock:
    def __init__(self, start: float) -> None:
        self.time = start
        self.sleeps: list[float] = []

    def now(self) -> float:
        return self.time

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.time += seconds


class SequenceClient:
    """Returns queued /builds payloads (or raises queued exceptions) per GET."""

    def __init__(self, responses: list) -> None:
        self.responses = list(responses)
        self.paths: list[str] = []

    def get(self, path: str) -> dict:
        self.paths.append(path)
        item = self.responses.pop(0) if len(self.responses) > 1 else self.responses[0]
        if isinstance(item, BaseException):
            raise item
        return item


def wait(client: SequenceClient, clock: FakeClock, *, minutes: int = 120, transient=None) -> dict:
    with redirect_stdout(io.StringIO()):
        return ios_release.wait_for_build(
            client,
            app_id=APP,
            marketing_version=VERSION,
            build_number="14",
            uploaded_after=STARTED,
            deadline=STARTED + minutes * 60,
            poll_seconds=30,
            now=clock.now,
            sleep=clock.sleep,
            is_transient=transient,
        )


class WaitForBuildTests(unittest.TestCase):
    def test_waits_through_missing_and_processing_then_returns_build(self) -> None:
        client = SequenceClient(
            [
                {"data": []},
                {"data": [build_row(state="PROCESSING")], "included": [pre_row()]},
                {"data": [build_row()], "included": [pre_row()]},
            ]
        )
        clock = FakeClock(STARTED + 120)
        build = wait(client, clock)
        self.assertEqual(build["id"], "B1")
        self.assertEqual(clock.sleeps, [30, 30])
        self.assertIn("filter%5Bversion%5D=14", client.paths[0])
        self.assertIn("filter%5Bapp%5D=APP1", client.paths[0])

    def test_times_out_without_using_another_build(self) -> None:
        client = SequenceClient([{"data": [build_row(state="PROCESSING")], "included": [pre_row()]}])
        clock = FakeClock(STARTED)
        with self.assertRaisesRegex(ReleaseError, "timed out"):
            wait(client, clock, minutes=10)
        self.assertLessEqual(clock.time, STARTED + 10 * 60 + 30)

    def test_ready_build_after_the_deadline_is_still_a_timeout(self) -> None:
        client = SequenceClient([{"data": [build_row()], "included": [pre_row()]}])
        clock = FakeClock(STARTED + 121 * 60)  # job started after the 120-minute budget
        with self.assertRaisesRegex(ReleaseError, "timed out"):
            wait(client, clock)
        self.assertEqual(client.paths, [], "must not poll once the budget is spent")

    def test_processing_failure_stops(self) -> None:
        for state in ("FAILED", "INVALID"):
            client = SequenceClient([{"data": [build_row(state=state)], "included": [pre_row()]}])
            with self.subTest(state=state), self.assertRaisesRegex(ReleaseError, state):
                wait(client, FakeClock(STARTED))

    def test_expired_build_is_rejected(self) -> None:
        client = SequenceClient([{"data": [build_row(expired=True)], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "expired"):
            wait(client, FakeClock(STARTED))

    def test_ambiguous_match_stops(self) -> None:
        client = SequenceClient([{"data": [build_row("B1"), build_row("B2")], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "ambiguous"):
            wait(client, FakeClock(STARTED))

    def test_older_upload_is_never_substituted(self) -> None:
        old = build_row(uploaded=STARTED - 3600)
        client = SequenceClient([{"data": [old], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "older build"):
            wait(client, FakeClock(STARTED))

    def test_build_without_an_upload_time_is_never_used(self) -> None:
        # Fails closed: a VALID build whose uploadedDate is missing or empty cannot be
        # shown to be this run's upload, so the wait runs out instead of using it.
        for uploaded in (MISSING, None, ""):
            client = SequenceClient([{"data": [build_row(uploaded=uploaded)], "included": [pre_row()]}])
            clock = FakeClock(STARTED)
            with self.subTest(uploaded=uploaded), self.assertRaisesRegex(ReleaseError, "timed out"):
                wait(client, clock, minutes=10)
            self.assertGreater(len(client.paths), 1, "it kept polling")

    def test_upload_time_reported_later_is_accepted(self) -> None:
        client = SequenceClient([
            {"data": [build_row(uploaded=MISSING)], "included": [pre_row()]},
            {"data": [build_row()], "included": [pre_row()]},
        ])
        self.assertEqual(wait(client, FakeClock(STARTED))["id"], "B1")

    def test_unreadable_upload_time_stops(self) -> None:
        for uploaded in ("yesterday", 12345, ["2026"]):
            row = build_row()
            row["attributes"]["uploadedDate"] = uploaded
            client = SequenceClient([{"data": [row], "included": [pre_row()]}])
            with self.subTest(uploaded=uploaded), self.assertRaisesRegex(ReleaseError, "unreadable uploadedDate"):
                wait(client, FakeClock(STARTED))

    def test_processing_failure_stops_even_without_an_upload_time(self) -> None:
        client = SequenceClient([{"data": [build_row(state="FAILED", uploaded=MISSING)], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "FAILED"):
            wait(client, FakeClock(STARTED))

    def test_other_versions_and_platforms_are_ignored(self) -> None:
        other_version = build_row("BX", pre="P2")
        other_platform = build_row("BY", pre="P3")
        client = SequenceClient(
            [
                {"data": [other_version, other_platform],
                 "included": [pre_row("P2", "2.0.1"), pre_row("P3", VERSION, "MAC_OS")]},
                {"data": [other_version, build_row("B1")], "included": [pre_row("P2", "2.0.1"), pre_row()]},
            ]
        )
        self.assertEqual(wait(client, FakeClock(STARTED))["id"], "B1")

    def test_build_from_another_app_is_a_mismatch(self) -> None:
        client = SequenceClient([{"data": [build_row(app="OTHER")], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "another app"):
            wait(client, FakeClock(STARTED))

    def test_transient_errors_are_retried_and_others_raise(self) -> None:
        transient = asc_release.AscHttpError(503, "unavailable")
        client = SequenceClient([transient, {"data": [build_row()], "included": [pre_row()]}])
        with redirect_stderr(io.StringIO()):
            build = wait(client, FakeClock(STARTED), transient=ios_release.is_transient_error)
        self.assertEqual(build["id"], "B1")
        fatal = SequenceClient([asc_release.AscHttpError(401, "unauthorized")])
        with self.assertRaises(SystemExit):
            wait(fatal, FakeClock(STARTED), transient=ios_release.is_transient_error)


class TransientErrorTests(unittest.TestCase):
    def test_real_retry_rule(self) -> None:
        transient = [
            http.client.RemoteDisconnected("closed"),
            ConnectionResetError("reset"),
            http.client.IncompleteRead(b""),
            urllib.error.URLError("dns"),
            TimeoutError("slow"),
            asc_release.AscHttpError(503, "busy"),
            asc_release.AscHttpError(429, "rate limited"),
            urllib.error.HTTPError("https://x", 502, "bad gateway", {}, None),
        ]
        fatal = [
            asc_release.AscHttpError(401, "unauthorized"),
            asc_release.AscHttpError(409, "conflict"),
            urllib.error.HTTPError("https://x", 404, "missing", {}, None),
            ValueError("bad"),
            ReleaseError("mismatch"),
            SystemExit(1),
        ]
        for exc in transient:
            with self.subTest(exc=repr(exc)):
                self.assertTrue(ios_release.is_transient_error(exc))
        for exc in fatal:
            with self.subTest(exc=repr(exc)):
                self.assertFalse(ios_release.is_transient_error(exc))


class CmdWaitBuildTests(unittest.TestCase):
    def test_deadline_counts_from_upload_start_and_app_lookup_is_retried(self) -> None:
        lookups = []

        def find_app(_client, bundle_id):
            lookups.append(bundle_id)
            if len(lookups) == 1:
                raise http.client.RemoteDisconnected("closed")
            return APP

        fake_module = mock.Mock(find_app=find_app)
        captured = {}

        def fake_wait(client, **kwargs):
            captured.update(kwargs)
            return {"id": "B9"}

        args = argparse.Namespace(version=VERSION, build=14, started_at=STARTED, wait_minutes=120, poll_seconds=30)
        with tempfile.NamedTemporaryFile("r", suffix=".out") as out, \
                mock.patch.object(ios_release, "asc_client", return_value=(fake_module, object())), \
                mock.patch.object(ios_release, "wait_for_build", side_effect=fake_wait), \
                mock.patch.object(ios_release.time, "sleep"), \
                mock.patch.object(ios_release.time, "time", return_value=STARTED + 30), \
                mock.patch.dict(os.environ, {"GITHUB_OUTPUT": out.name}), redirect_stdout(io.StringIO()):
            ios_release.cmd_wait_build(args)
            written = Path(out.name).read_text()
        self.assertEqual(lookups, [ios_release.BUNDLE_ID] * 2)
        self.assertEqual(ios_release.BUNDLE_ID, "com.apoorvdarshan.Scowld")
        self.assertEqual(captured["deadline"], STARTED + 120 * 60)
        self.assertEqual(captured["uploaded_after"], STARTED)
        self.assertEqual(captured["build_number"], "14")
        self.assertIs(captured["is_transient"], ios_release.is_transient_error)
        self.assertIn("build_id=B9", written)

    def test_app_lookup_gives_up_at_the_deadline(self) -> None:
        def boom():
            raise http.client.RemoteDisconnected("closed")

        clock = FakeClock(STARTED)
        with redirect_stdout(io.StringIO()), self.assertRaises(http.client.RemoteDisconnected):
            ios_release.call_with_retries(boom, deadline=STARTED + 90, poll_seconds=30, now=clock.now, sleep=clock.sleep)
        self.assertEqual(clock.sleeps, [30, 30, 30])


class TokenRefreshTests(unittest.TestCase):
    def test_token_is_reminted_during_long_waits(self) -> None:
        minted: list[str] = []

        def factory() -> str:
            minted.append(f"t{len(minted)}")
            return minted[-1]

        with mock.patch.object(asc_release.time, "monotonic", side_effect=[0, 100, 700, 700, 800]):
            client = asc_release.AscClient(token_factory=factory)
            self.assertEqual(client._authorization(), "Bearer t0")
            self.assertEqual(client._authorization(), "Bearer t1")
            self.assertEqual(client._authorization(), "Bearer t1")


# MARK: - Listing, What's New and screenshots


def png(path: Path, width: int, height: int, *, alpha: bool = False, seed: int = 0) -> Path:
    """A real (tiny-header) PNG with the given dimensions; seed makes contents unique."""
    path.parent.mkdir(parents=True, exist_ok=True)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6 if alpha else 2, 0, 0, 0)
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))  # noqa: E731
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"tEXt", f"seed{seed}".encode()) + chunk(b"IEND", b""))
    return path


class RouteClient:
    """Fake App Store Connect: GETs answered from `routes`, every write recorded."""

    def __init__(self, routes: dict[str, Any]) -> None:
        self.routes = routes
        self.calls: list[tuple[str, str, Any]] = []
        self.created = 0

    def get(self, path: str) -> dict:
        self.calls.append(("GET", path, None))
        if path in self.routes:
            value = self.routes[path]
        else:
            matches = [key for key in self.routes if key.endswith("*") and path.startswith(key[:-1])]
            if not matches:
                raise AssertionError(f"unexpected GET {path}")
            value = self.routes[max(matches, key=len)]
        return value(path) if callable(value) else value

    def post(self, path: str, body: dict) -> dict:
        self.calls.append(("POST", path, body))
        self.created += 1
        new_id = f"NEW{self.created}"
        if path == "/appScreenshots":
            return {"data": {"id": new_id, "attributes": {"uploadOperations": [
                {"url": f"https://upload.example/{new_id}", "method": "PUT", "offset": 0,
                 "length": body["data"]["attributes"]["fileSize"],
                 "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]}]}}}
        return {"data": {"id": new_id}}

    def patch(self, path: str, body: dict) -> dict:
        self.calls.append(("PATCH", path, body))
        return {"data": body.get("data")}

    def request(self, method: str, path: str, *, body: dict | None = None):
        self.calls.append((method, path, body))
        return None

    def delete(self, path: str) -> None:
        self.calls.append(("DELETE", path, None))

    def upload_bytes(self, url: str, data: bytes, headers: dict, *, method: str = "PUT") -> None:
        self.calls.append(("UPLOAD", url, len(data)))

    def writes(self) -> list[tuple[str, str, Any]]:
        return [call for call in self.calls if call[0] != "GET"]


def loc_rows(locale: str = "en-US", loc_id: str = "VL1", **attrs: Any) -> dict:
    return {"data": [{"id": loc_id, "attributes": {"locale": locale, **attrs}}]}


class LocalInputTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.meta = self.root / "store" / "metadata" / "ios"
        self.loc = self.meta / "en-US"
        self.loc.mkdir(parents=True)
        (self.loc / "description.txt").write_text("A companion\n")

    def validate(self, **flags: bool) -> dict:
        options = {"upload_listing": False, "upload_whats_new": False, "upload_screenshots": False, **flags}
        return quiet(asc_release.validate_local_inputs, metadata_dir=self.meta, root=self.root, **options)

    def assert_fails(self, pattern: str, **flags: bool) -> None:
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.validate_local_inputs(
                metadata_dir=self.meta, root=self.root,
                **{"upload_listing": False, "upload_whats_new": False, "upload_screenshots": False, **flags},
            )
        self.assertRegex(err.getvalue(), pattern)

    def test_listing_fields_are_read_trimmed_and_limited(self) -> None:
        (self.loc / "name.txt").write_text("Scowld - AI Voice Companion\n")
        (self.loc / "keywords.txt").write_text("ai,voice\n")
        (self.loc / "support_url.txt").write_text("https://scowld.xyz\n")
        plan = self.validate(upload_listing=True)
        self.assertEqual(plan["en-US"]["version"], {"description": "A companion", "keywords": "ai,voice",
                                                     "supportUrl": "https://scowld.xyz"})
        self.assertEqual(plan["en-US"]["app_info"], {"name": "Scowld - AI Voice Companion"})

        (self.loc / "subtitle.txt").write_text("x" * 31)
        self.assert_fails("subtitle.txt is 31 characters; App Store Connect allows 30", upload_listing=True)
        (self.loc / "subtitle.txt").write_text("ok")
        (self.loc / "keywords.txt").write_text("k" * 101)
        self.assert_fails("keywords.txt is 101 characters", upload_listing=True)
        (self.loc / "keywords.txt").write_text("ok")
        (self.loc / "marketing_url.txt").write_text("scowld.xyz")
        self.assert_fails("marketing_url.txt must be a single http", upload_listing=True)

    def test_listing_needs_a_description(self) -> None:
        (self.loc / "description.txt").write_text("  \n")
        self.assert_fails("description.txt is missing or empty", upload_listing=True)

    def test_whats_new_requires_text(self) -> None:
        self.assert_fails("whats_new.txt is missing or empty", upload_whats_new=True)
        (self.loc / "whats_new.txt").write_text("Fixes\n")
        self.assertEqual(self.validate(upload_whats_new=True)["en-US"]["whats_new"], "Fixes")

    def test_whats_new_must_be_plain_text(self) -> None:
        # App Store Connect shows Markdown literally, so it never reaches the store.
        for text, kind in (
            ("- **Faster** replies", "bold markers"),
            ("- Uses `gpt-5` by default", "backticks"),
            ("- Read [the blog](https://scowld.xyz/blog)", "links"),
            ("## What's new\n- Faster replies", "headings"),
        ):
            (self.loc / "whats_new.txt").write_text(text)
            with self.subTest(text=text):
                self.assert_fails(rf"uses Markdown \({kind}", upload_whats_new=True)
        for text in ("- Faster replies\n- Fixes", "• Captions\n#1 request: hands-free mode", "50% faster, 2 * 3 = 6"):
            (self.loc / "whats_new.txt").write_text(text)
            with self.subTest(text=text):
                self.assertEqual(self.validate(upload_whats_new=True)["en-US"]["whats_new"], text)

    def test_screenshots_fail_clearly_without_a_manifest(self) -> None:
        self.assert_fails(r"screenshots\.json does not exist", upload_screenshots=True)

    def test_screenshot_manifest_is_validated(self) -> None:
        good = png(self.root / "marketing" / "a.png", 1260, 2736)
        png(self.root / "marketing" / "ipad.png", 2064, 2752, seed=1)
        png(self.root / "marketing" / "small.png", 1179, 2556, seed=2)
        png(self.root / "marketing" / "alpha.png", 1290, 2796, alpha=True, seed=3)
        manifest = self.loc / "screenshots.json"

        manifest.write_text(json.dumps({"APP_IPHONE_67": ["marketing/a.png"], "APP_IPAD_PRO_3GEN_129": ["marketing/ipad.png"]}))
        plan = self.validate(upload_screenshots=True)["en-US"]["screenshots"]
        self.assertEqual(plan["APP_IPHONE_67"], [good.resolve()])

        cases = {
            "1179x2556; APP_IPHONE_67 accepts": {"APP_IPHONE_67": ["marketing/small.png"]},
            "alpha channel": {"APP_IPHONE_67": ["marketing/alpha.png"]},
            "unsupported display type": {"APP_WATCH": ["marketing/a.png"]},
            "not an image file in this repository": {"APP_IPHONE_67": ["../outside.png"]},
            "lists 11 images": {"APP_IPHONE_67": ["marketing/a.png"] * 11},
            "must list at least one": {"APP_IPHONE_67": []},
        }
        for pattern, content in cases.items():
            manifest.write_text(json.dumps(content))
            with self.subTest(pattern=pattern):
                self.assert_fails(pattern, upload_screenshots=True)
        manifest.write_text("{not json")
        self.assert_fails("not valid JSON", upload_screenshots=True)

    def test_landscape_screenshots_are_accepted(self) -> None:
        png(self.root / "marketing" / "wide.png", 2796, 1290)
        (self.loc / "screenshots.json").write_text(json.dumps({"APP_IPHONE_67": ["marketing/wide.png"]}))
        self.assertEqual(len(self.validate(upload_screenshots=True)["en-US"]["screenshots"]["APP_IPHONE_67"]), 1)

    @committed_files_test
    def test_committed_store_metadata_is_valid(self) -> None:
        plan = quiet(asc_release.validate_local_inputs, upload_listing=True, upload_whats_new=True,
                     upload_screenshots=True, metadata_dir=asc_release.METADATA_DIR)
        self.assertIn("en-US", plan)
        for locale, entry in plan.items():
            with self.subTest(locale=locale):
                self.assertTrue(entry["version"]["description"])
                self.assertTrue(entry["app_info"]["name"])
                self.assertTrue(entry["screenshots"], "every locale lists App Store-ready screenshots")


class ListingUploadTests(unittest.TestCase):
    def test_only_changed_version_fields_are_sent(self) -> None:
        client = RouteClient({
            "/appStoreVersions/V1/appStoreVersionLocalizations?limit=50":
                loc_rows(description="Same", keywords="old,words", supportUrl="https://scowld.xyz"),
        })
        quiet(asc_release.upload_version_fields, client, "V1", "en-US",
              {"description": "Same", "keywords": "new,words", "supportUrl": "https://scowld.xyz"}, "listing")
        self.assertEqual(client.writes(), [("PATCH", "/appStoreVersionLocalizations/VL1", {
            "data": {"type": "appStoreVersionLocalizations", "id": "VL1", "attributes": {"keywords": "new,words"}}})])

        unchanged = RouteClient({"/appStoreVersions/V1/appStoreVersionLocalizations?limit=50": loc_rows(description="Same")})
        quiet(asc_release.upload_version_fields, unchanged, "V1", "en-US", {"description": "Same"}, "listing")
        self.assertEqual(unchanged.writes(), [])

    def test_missing_localization_fails(self) -> None:
        client = RouteClient({"/appStoreVersions/V1/appStoreVersionLocalizations?limit=50": loc_rows(locale="de-DE")})
        with self.assertRaises(SystemExit):
            quiet(asc_release.upload_version_fields, client, "V1", "en-US", {"description": "x"}, "listing")

    def app_infos(self, *states: str) -> dict:
        return {"data": [{"id": f"AI{i}", "attributes": {"state": state}} for i, state in enumerate(states)]}

    def test_app_name_and_subtitle_go_to_the_editable_app_info(self) -> None:
        client = RouteClient({
            f"/apps/{APP}/appInfos": self.app_infos("READY_FOR_DISTRIBUTION", "PREPARE_FOR_SUBMISSION"),
            "/appInfos/AI1/appInfoLocalizations?limit=50": loc_rows(loc_id="IL1", name="Scowld", subtitle="Old"),
        })
        quiet(asc_release.upload_app_info_fields, client, APP, "en-US", {"name": "Scowld", "subtitle": "New"})
        self.assertEqual(client.writes(), [("PATCH", "/appInfoLocalizations/IL1", {
            "data": {"type": "appInfoLocalizations", "id": "IL1", "attributes": {"subtitle": "New"}}})])

    def test_unchanged_app_info_needs_no_editable_record(self) -> None:
        client = RouteClient({
            f"/apps/{APP}/appInfos": self.app_infos("READY_FOR_DISTRIBUTION"),
            "/appInfos/AI0/appInfoLocalizations?limit=50": loc_rows(loc_id="IL0", name="Scowld"),
        })
        quiet(asc_release.upload_app_info_fields, client, APP, "en-US", {"name": "Scowld"})
        self.assertEqual(client.writes(), [])

    def test_changed_app_info_without_an_editable_record_fails(self) -> None:
        client = RouteClient({
            f"/apps/{APP}/appInfos": self.app_infos("READY_FOR_DISTRIBUTION"),
            "/appInfos/AI0/appInfoLocalizations?limit=50": loc_rows(loc_id="IL0", name="Scowld"),
        })
        with self.assertRaises(SystemExit):
            quiet(asc_release.upload_app_info_fields, client, APP, "en-US", {"name": "Scowld 2"})
        self.assertEqual(client.writes(), [])

    def test_app_info_in_a_draft_submission_is_still_editable(self) -> None:
        client = RouteClient({
            f"/apps/{APP}/appInfos": self.app_infos("READY_FOR_DISTRIBUTION", "READY_FOR_REVIEW"),
            "/appInfos/AI1/appInfoLocalizations?limit=50": loc_rows(loc_id="IL1", subtitle="Old"),
        })
        quiet(asc_release.upload_app_info_fields, client, APP, "en-US", {"subtitle": "New"})
        self.assertEqual([w[1] for w in client.writes()], ["/appInfoLocalizations/IL1"])

    def test_submitted_app_info_is_compared_when_none_is_editable(self) -> None:
        # Rerun after submitting: the live app info still has the old name, the
        # submitted one already has the new name, so nothing has to change.
        client = RouteClient({
            f"/apps/{APP}/appInfos": self.app_infos("READY_FOR_DISTRIBUTION", "WAITING_FOR_REVIEW"),
            "/appInfos/AI0/appInfoLocalizations?limit=50": loc_rows(loc_id="IL0", name="Scowld Old"),
            "/appInfos/AI1/appInfoLocalizations?limit=50": loc_rows(loc_id="IL1", name="Scowld"),
        })
        quiet(asc_release.upload_app_info_fields, client, APP, "en-US", {"name": "Scowld"},
              locked="version 2.0.2 is WAITING_FOR_REVIEW")
        self.assertEqual(client.writes(), [])
        with self.assertRaises(SystemExit):
            quiet(asc_release.upload_app_info_fields, client, APP, "en-US", {"name": "Scowld 3"},
                  locked="version 2.0.2 is WAITING_FOR_REVIEW")
        self.assertEqual(client.writes(), [])

    def test_locked_listing_is_only_compared(self) -> None:
        client = RouteClient({"/appStoreVersions/V1/appStoreVersionLocalizations?limit=50": loc_rows(description="Old")})
        quiet(asc_release.upload_version_fields, client, "V1", "en-US", {"description": "Old"}, "listing",
              locked="version 2.0.2 is WAITING_FOR_REVIEW")
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.upload_version_fields(client, "V1", "en-US", {"description": "New"}, "listing",
                                              locked="version 2.0.2 is WAITING_FOR_REVIEW")
        self.assertIn("listing (en-US) differs from App Store Connect (description), but version 2.0.2 "
                      "is WAITING_FOR_REVIEW", err.getvalue())
        self.assertEqual(client.writes(), [])

    def versions(self, live_notes: str) -> dict:
        return {
            f"/apps/{APP}/appStoreVersions?*": {"data": [
                {"id": "V0", "attributes": {"versionString": "2.0", "appStoreState": "READY_FOR_SALE", "createdDate": "2026-06-09T00:00:00Z"}},
                {"id": "VLIVE", "attributes": {"versionString": "2.0.1", "appStoreState": "READY_FOR_SALE", "createdDate": "2026-07-09T00:00:00Z"}},
                {"id": "V1", "attributes": {"versionString": VERSION, "appStoreState": "PREPARE_FOR_SUBMISSION", "createdDate": "2026-10-14T00:00:00Z"}},
            ]},
            "/appStoreVersions/VLIVE/appStoreVersionLocalizations?limit=50": loc_rows(loc_id="LIVE", whatsNew=live_notes),
            "/appStoreVersions/V1/appStoreVersionLocalizations?limit=50": loc_rows(whatsNew=""),
        }

    def test_whats_new_is_uploaded_when_it_differs_from_the_live_version(self) -> None:
        client = RouteClient(self.versions("- Old notes"))
        quiet(asc_release.upload_whats_new, client, APP, "V1", "en-US", "- New notes")
        self.assertEqual(client.writes()[0][2]["data"]["attributes"], {"whatsNew": "- New notes"})

    def test_stale_whats_new_from_the_live_version_is_refused(self) -> None:
        client = RouteClient(self.versions("- Same notes"))
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.upload_whats_new(client, APP, "V1", "en-US", "- Same notes")
        self.assertIn("identical to live version 2.0.1", err.getvalue())
        self.assertEqual(client.writes(), [])


class ScreenshotSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.files = [png(Path(tmp.name) / f"{i}.png", 1260, 2736, seed=i) for i in range(3)]
        self.sums = [asc_release.md5_hex(path) for path in self.files]

    def routes(self, current: list[str], states: dict[str, list[str]] | None = None) -> dict:
        polls = {key: list(value) for key, value in (states or {}).items()}

        def screenshot(path: str) -> dict:
            shot_id = path.rsplit("/", 1)[1]
            queue = polls.get(shot_id) or ["COMPLETE"]
            state = queue.pop(0) if len(queue) > 1 else queue[0]
            return {"data": {"id": shot_id, "attributes": {"fileName": f"{shot_id}.png", "assetDeliveryState": {
                "state": state, "errors": [{"code": "IMAGE_INCORRECT_DIMENSIONS"}] if state == "FAILED" else []}}}}

        return {
            "/appStoreVersionLocalizations/VL1/appScreenshotSets?limit=50": {"data": [
                {"id": "SET1", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]},
            "/appScreenshotSets/SET1/appScreenshots?limit=50": {"data": [
                {"id": f"OLD{i}", "attributes": {"sourceFileChecksum": checksum}} for i, checksum in enumerate(current)]},
            "/appScreenshots/*": screenshot,
        }

    def test_identical_screenshots_are_left_alone(self) -> None:
        client = RouteClient(self.routes(self.sums))
        quiet(asc_release.sync_screenshot_set, client, "VL1", "en-US", "APP_IPHONE_67", self.files)
        self.assertEqual(client.writes(), [])

    def test_changed_screenshots_replace_the_set_in_order(self) -> None:
        client = RouteClient(self.routes(["stale", self.sums[1]]))
        with mock.patch.object(asc_release.time, "sleep"):
            quiet(asc_release.sync_screenshot_set, client, "VL1", "en-US", "APP_IPHONE_67", self.files)
        writes = client.writes()
        self.assertEqual([w[:2] for w in writes[:2]], [("DELETE", "/appScreenshots/OLD0"), ("DELETE", "/appScreenshots/OLD1")])
        commits = [w for w in writes if w[0] == "PATCH" and w[1].startswith("/appScreenshots/")]
        self.assertEqual([c[2]["data"]["attributes"]["sourceFileChecksum"] for c in commits], self.sums)
        self.assertEqual(len([w for w in writes if w[0] == "UPLOAD"]), 3)
        order = writes[-1]
        self.assertEqual(order[1], "/appScreenshotSets/SET1/relationships/appScreenshots")
        self.assertEqual([item["id"] for item in order[2]["data"]], ["NEW1", "NEW2", "NEW3"])

    def test_missing_set_is_created(self) -> None:
        routes = self.routes([])
        routes["/appStoreVersionLocalizations/VL1/appScreenshotSets?limit=50"] = {"data": []}
        routes["/appScreenshotSets/NEW1/appScreenshots?limit=50"] = {"data": []}
        client = RouteClient(routes)
        quiet(asc_release.sync_screenshot_set, client, "VL1", "en-US", "APP_IPHONE_67", self.files[:1])
        self.assertEqual(client.writes()[0][1], "/appScreenshotSets")
        self.assertEqual(client.writes()[0][2]["data"]["attributes"]["screenshotDisplayType"], "APP_IPHONE_67")

    def test_rejected_screenshot_fails_the_run(self) -> None:
        client = RouteClient(self.routes(["stale"], {"NEW1": ["UPLOAD_COMPLETE", "FAILED"]}))
        err = io.StringIO()
        with mock.patch.object(asc_release.time, "sleep"), redirect_stdout(io.StringIO()), redirect_stderr(err), \
                self.assertRaises(SystemExit):
            asc_release.sync_screenshot_set(client, "VL1", "en-US", "APP_IPHONE_67", self.files[:1])
        self.assertIn("IMAGE_INCORRECT_DIMENSIONS", err.getvalue())
        self.assertNotIn("/appScreenshotSets/SET1/relationships/appScreenshots", [w[1] for w in client.writes()])

    def test_locked_set_is_only_compared(self) -> None:
        same = RouteClient(self.routes(self.sums))
        quiet(asc_release.sync_screenshot_set, same, "VL1", "en-US", "APP_IPHONE_67", self.files, locked="in review")
        self.assertEqual(same.writes(), [])
        changed = RouteClient(self.routes(["stale"]))
        with self.assertRaises(SystemExit):
            quiet(asc_release.sync_screenshot_set, changed, "VL1", "en-US", "APP_IPHONE_67", self.files, locked="in review")
        self.assertEqual(changed.writes(), [])
        routes = self.routes([])
        routes["/appStoreVersionLocalizations/VL1/appScreenshotSets?limit=50"] = {"data": []}
        missing = RouteClient(routes)
        with self.assertRaises(SystemExit):
            quiet(asc_release.sync_screenshot_set, missing, "VL1", "en-US", "APP_IPHONE_67", self.files, locked="in review")
        self.assertEqual(missing.writes(), [], "a missing set is not created while locked")

    def test_screenshot_processing_times_out(self) -> None:
        client = RouteClient(self.routes([], {"S1": ["UPLOAD_COMPLETE"]}))
        clock = FakeClock(0)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            asc_release.wait_for_screenshots(client, ["S1"], timeout=10, now=clock.now, sleep=clock.sleep)
        self.assertGreater(clock.time, 10)


# MARK: - Build selection and review submission


class SelectionClient:
    """Fake ASC client for build verification and selection."""

    def __init__(self, *, build: dict, included: list, attached: str | None, sticky: bool = True) -> None:
        self.build = build
        self.included = included
        self.attached = attached
        self.sticky = sticky
        self.calls: list[tuple[str, str, dict | None]] = []

    def get(self, path: str) -> dict:
        self.calls.append(("GET", path, None))
        if path.startswith(f"/builds/{self.build['id']}"):
            return {"data": self.build, "included": self.included}
        if path.endswith("/build"):
            return {"data": {"type": "builds", "id": self.attached} if self.attached else None}
        raise AssertionError(f"unexpected GET {path}")

    def patch(self, path: str, body: dict) -> dict:
        self.calls.append(("PATCH", path, body))
        return {"data": body["data"]}

    def request(self, method: str, path: str, *, body: dict | None = None):
        self.calls.append((method, path, body))
        if method == "PATCH" and path.endswith("/relationships/build") and self.sticky:
            self.attached = body["data"]["id"]
        return None


class BuildSelectionTests(unittest.TestCase):
    def test_selects_and_reads_back_this_runs_build(self) -> None:
        client = SelectionClient(build=build_row("B9"), included=[pre_row()], attached="OLD")
        quiet(asc_release.select_build, client, "V1", "B9", VERSION, "14")
        self.assertEqual(client.attached, "B9")
        methods = [(m, p) for m, p, _ in client.calls]
        self.assertIn(("PATCH", "/appStoreVersions/V1/relationships/build"), methods)
        self.assertEqual(methods[-1], ("GET", "/appStoreVersions/V1/build"))

    def test_selection_that_does_not_stick_fails(self) -> None:
        client = SelectionClient(build=build_row("B9"), included=[pre_row()], attached="OLD", sticky=False)
        with self.assertRaises(SystemExit):
            quiet(asc_release.select_build, client, "V1", "B9", VERSION, "14")

    def test_unprocessed_expired_or_wrong_build_is_refused(self) -> None:
        cases = {
            "processing": (build_row("B9", state="PROCESSING"), [pre_row()]),
            "expired": (build_row("B9", expired=True), [pre_row()]),
            "number": (build_row("B9", number="15"), [pre_row()]),
            "version": (build_row("B9"), [pre_row(version="2.0.1")]),
            "platform": (build_row("B9"), [pre_row(platform="MAC_OS")]),
        }
        for label, (build, included) in cases.items():
            client = SelectionClient(build=build, included=included, attached=None)
            with self.subTest(label), self.assertRaises(SystemExit):
                quiet(asc_release.select_build, client, "V1", "B9", VERSION, "14")
            self.assertFalse([c for c in client.calls if c[0] == "PATCH"], label)

    def test_release_type(self) -> None:
        for public, expected in ((True, "AFTER_APPROVAL"), (False, "MANUAL")):
            client = SelectionClient(build=build_row(), included=[], attached=None)
            quiet(asc_release.set_release_type, client, "V1", public_release=public)
            self.assertEqual(client.calls[-1][2]["data"]["attributes"]["releaseType"], expected)


class FakeAsc:
    """App Store Connect stand-in for asc_release.main() (live path, no network)."""

    def __init__(self, *, state: str = "PREPARE_FOR_SUBMISSION", attached: str | None = "OLD",
                 revert_after_select: bool = False, products: list[dict] | None = None,
                 draft_items: list[dict] | None = None, drafts: int = 1, versions: list[str] | None = None) -> None:
        self.state = state
        self.attached = attached
        self.revert_after_select = revert_after_select
        self.products = products or []
        self.draft_items = draft_items or []
        self.drafts = drafts
        self.versions = versions if versions is not None else [VERSION]
        self.build_reads = 0
        self.calls: list[tuple[str, str]] = []

    def get(self, path: str) -> dict:
        self.calls.append(("GET", path))
        if path.startswith("/apps?"):
            return {"data": [{"id": APP, "attributes": {"bundleId": "com.apoorvdarshan.Scowld"}}]}
        if path.startswith(f"/apps/{APP}/appStoreVersions"):
            return {"data": [{"id": "V1", "attributes": {"versionString": v, "appStoreState": self.state}}
                             for v in self.versions]}
        if path.startswith("/builds/B9"):
            return {"data": build_row("B9"), "included": [pre_row()]}
        if path == "/appStoreVersions/V1/build":
            self.build_reads += 1
            if self.revert_after_select and self.build_reads >= 2:
                return {"data": {"type": "builds", "id": "OLD"}}
            return {"data": {"type": "builds", "id": self.attached} if self.attached else None}
        if path.startswith(f"/apps/{APP}/subscriptionGroups"):
            return {"data": [{"id": "G1"}] if self.products else []}
        if path.startswith("/subscriptionGroups/G1/subscriptions"):
            return {"data": self.products}
        if path.startswith(f"/apps/{APP}/inAppPurchasesV2"):
            return {"data": []}
        if path.startswith(f"/apps/{APP}/reviewSubmissions"):
            return {"data": [{"id": f"SUB{i + 1}"} for i in range(self.drafts)]}
        if path.startswith("/reviewSubmissions/SUB1/items"):
            return {"data": self.draft_items}
        raise AssertionError(f"unexpected GET {path}")

    def post(self, path: str, body: dict) -> dict:
        self.calls.append(("POST", path))
        return {"data": {"id": "ITEM"}}

    def patch(self, path: str, body: dict) -> dict:
        self.calls.append(("PATCH", path))
        return {"data": body["data"]}

    def request(self, method: str, path: str, *, body: dict | None = None):
        self.calls.append((method, path))
        if method == "PATCH" and path == "/appStoreVersions/V1/relationships/build":
            self.attached = body["data"]["id"]
        return None


class LiveSubmitFlowTests(unittest.TestCase):
    def run_main(self, fake: FakeAsc, **flags: str) -> tuple[int, str]:
        argv = ["--version", VERSION, "--build-id", "B9", "--build-number", "14"]
        env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        env.update({"SUBMIT_IOS_REVIEW": "true", **flags})
        err = io.StringIO()
        code = 0
        with mock.patch.dict(os.environ, env, clear=True), \
                mock.patch.object(asc_release, "client_from_environment", return_value=fake), \
                redirect_stdout(io.StringIO()), redirect_stderr(err):
            try:
                asc_release.main(argv)
            except SystemExit as exc:
                code = exc.code if isinstance(exc.code, int) else 1
        return code, err.getvalue()

    def test_selects_rechecks_then_submits(self) -> None:
        fake = FakeAsc()
        code, _ = self.run_main(fake)
        self.assertEqual(code, 0)
        calls = fake.calls
        select = calls.index(("PATCH", "/appStoreVersions/V1/relationships/build"))
        submit = calls.index(("PATCH", "/reviewSubmissions/SUB1"))
        reads = [i for i, c in enumerate(calls) if c == ("GET", "/appStoreVersions/V1/build")]
        build_checks = [i for i, c in enumerate(calls) if c[0] == "GET" and c[1].startswith("/builds/B9")]
        self.assertEqual(len(reads), 2, "selection must be read back and rechecked")
        self.assertTrue(select < reads[0] < reads[1] < submit)
        self.assertEqual(len(build_checks), 2)
        self.assertTrue(build_checks[1] < reads[1] < submit, "build must be re-verified just before submit")
        self.assertIn(("PATCH", "/appStoreVersions/V1"), calls)  # release type
        self.assertIn(("POST", "/reviewSubmissionItems"), calls)
        product_check = next(i for i, c in enumerate(calls) if "subscriptionGroups" in c[1])
        self.assertLess(product_check, select, "products are checked before anything is changed")

    def test_selection_changed_before_submit_aborts(self) -> None:
        fake = FakeAsc(revert_after_select=True)
        code, _ = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertNotIn(("PATCH", "/reviewSubmissions/SUB1"), fake.calls)

    def test_waiting_for_review_with_another_build_aborts(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="OTHER")
        code, _ = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertNotIn(("PATCH", "/reviewSubmissions/SUB1"), fake.calls)

    def test_waiting_for_review_with_this_build_is_idempotent(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9")
        code, _ = self.run_main(fake)
        self.assertEqual(code, 0)
        self.assertFalse([c for c in fake.calls if c[0] != "GET"], "nothing is changed on a rerun")

    def test_non_submittable_version_is_refused(self) -> None:
        for state in ("READY_FOR_SALE", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
            fake = FakeAsc(state=state)
            code, _ = self.run_main(fake)
            with self.subTest(state=state):
                self.assertEqual(code, 1)
                self.assertFalse([c for c in fake.calls if c[0] != "GET"])

    def test_missing_version_tells_how_to_fix_it(self) -> None:
        fake = FakeAsc(versions=["2.0.1"])
        code, err = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("create version 2.0.2", err)

    def test_pending_in_app_products_block_submission(self) -> None:
        fake = FakeAsc(products=[{"id": "S1", "attributes": {"productId": "com.apoorvdarshan.Scowld.plus", "state": "READY_TO_SUBMIT"}}])
        code, err = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("com.apoorvdarshan.Scowld.plus", err)
        self.assertFalse([c for c in fake.calls if c[0] != "GET"])

    def test_pending_products_stop_the_run_before_the_listing_changes(self) -> None:
        fake = FakeAsc(products=[{"id": "S1", "attributes": {"productId": "plus", "state": "READY_TO_SUBMIT"}}])
        code, _ = self.run_main(fake, UPLOAD_LISTING="true")
        self.assertEqual(code, 1)
        self.assertFalse([c for c in fake.calls if c[0] != "GET"], "listing untouched when submission is blocked")

    def test_approved_products_do_not_block(self) -> None:
        fake = FakeAsc(products=[{"id": "S1", "attributes": {"productId": "p", "state": "APPROVED"}}])
        self.assertEqual(self.run_main(fake)[0], 0)

    def test_draft_with_unrelated_items_is_not_submitted(self) -> None:
        fake = FakeAsc(draft_items=[{"id": "EVENT1", "relationships": {"appStoreVersion": {"data": None}}}])
        code, err = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("EVENT1", err)
        self.assertNotIn(("PATCH", "/reviewSubmissions/SUB1"), fake.calls)

    def test_draft_already_holding_this_version_is_reused(self) -> None:
        fake = FakeAsc(draft_items=[{"id": "I1", "relationships": {"appStoreVersion": {"data": {"id": "V1"}}}}])
        self.assertEqual(self.run_main(fake)[0], 0)
        self.assertNotIn(("POST", "/reviewSubmissionItems"), fake.calls)
        self.assertIn(("PATCH", "/reviewSubmissions/SUB1"), fake.calls)

    def test_several_drafts_are_ambiguous(self) -> None:
        fake = FakeAsc(drafts=2)
        code, err = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("ambiguous", err)

    def test_new_draft_is_created_for_ios(self) -> None:
        fake = FakeAsc(drafts=0)
        posted: list[dict] = []
        original = fake.post

        def post(path: str, body: dict) -> dict:
            posted.append(body)
            return {"data": {"id": "SUB1"}} if path == "/reviewSubmissions" else original(path, body)

        fake.post = post  # type: ignore[method-assign]
        self.assertEqual(self.run_main(fake)[0], 0)
        self.assertEqual(posted[0]["data"]["attributes"], {"platform": "IOS"})


class RerunTests(unittest.TestCase):
    """'Re-run failed jobs' after the version reached a draft or a submitted review."""

    def routes(self, *, state: str, info_state: str, whats_new: str = "- New notes", attached: str = "B9",
               screenshot_sums: list[str] | None = None) -> dict:
        return {
            "/apps?*": {"data": [{"id": APP, "attributes": {"bundleId": "com.apoorvdarshan.Scowld"}}]},
            f"/apps/{APP}/appStoreVersions?*": {"data": [
                {"id": "VLIVE", "attributes": {"versionString": "2.0.1", "appStoreState": "READY_FOR_SALE",
                                               "createdDate": "2026-07-09T00:00:00Z"}},
                {"id": "V1", "attributes": {"versionString": VERSION, "appStoreState": state,
                                            "createdDate": "2026-10-14T00:00:00Z"}}]},
            "/appStoreVersions/VLIVE/appStoreVersionLocalizations?limit=50": loc_rows(loc_id="LIVE", whatsNew="- Old notes"),
            "/appStoreVersions/V1/appStoreVersionLocalizations?limit=50":
                loc_rows(loc_id="VL1", description="A companion", whatsNew=whats_new),
            # The live app info still has the old name; the one submitted with 2.0.2 has the new one.
            f"/apps/{APP}/appInfos": {"data": [{"id": "AI0", "attributes": {"state": "READY_FOR_DISTRIBUTION"}},
                                               {"id": "AI1", "attributes": {"state": info_state}}]},
            "/appInfos/AI0/appInfoLocalizations?limit=50": loc_rows(loc_id="IL0", name="Scowld Old"),
            "/appInfos/AI1/appInfoLocalizations?limit=50": loc_rows(loc_id="IL1", name="Scowld"),
            "/appStoreVersionLocalizations/VL1/appScreenshotSets?limit=50": {"data": [
                {"id": "SET1", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]},
            "/appScreenshotSets/SET1/appScreenshots?limit=50": {"data": [
                {"id": f"S{i}", "attributes": {"sourceFileChecksum": c}} for i, c in enumerate(screenshot_sums or [])]},
            f"/apps/{APP}/subscriptionGroups?limit=200": {"data": []},
            f"/apps/{APP}/inAppPurchasesV2?limit=200": {"data": []},
            "/builds/B9?*": {"data": build_row("B9"), "included": [pre_row()]},
            "/appStoreVersions/V1/build": {"data": {"type": "builds", "id": attached}},
            f"/apps/{APP}/reviewSubmissions?*": {"data": [{"id": "SUB1"}]},
            "/reviewSubmissions/SUB1/items?*": {"data": [
                {"id": "I1", "relationships": {"appStoreVersion": {"data": {"id": "V1"}}}}]},
        }

    def run_main(self, client: RouteClient, *, screenshots: bool = False, **flags: str) -> tuple[int, str]:
        env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        env.update({"UPLOAD_LISTING": "true", "UPLOAD_WHATS_NEW": "true", "SUBMIT_IOS_REVIEW": "true", **flags})
        err = io.StringIO()
        code = 0
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            loc = root / "store" / "en-US"
            loc.mkdir(parents=True)
            (loc / "description.txt").write_text("A companion")
            (loc / "name.txt").write_text("Scowld")
            (loc / "whats_new.txt").write_text("- New notes")
            if screenshots:
                png(root / "shots" / "a.png", 1260, 2736)
                (loc / "screenshots.json").write_text(json.dumps({"APP_IPHONE_67": ["shots/a.png"]}))
                env["UPLOAD_SCREENSHOTS"] = "true"
            argv = ["--version", VERSION, "--build-id", "B9", "--build-number", "14",
                    "--metadata-dir", str(root / "store")]
            with mock.patch.dict(os.environ, env, clear=True), \
                    mock.patch.object(asc_release, "client_from_environment", return_value=client), \
                    mock.patch.object(asc_release, "ROOT", root), \
                    redirect_stdout(io.StringIO()), redirect_stderr(err):
                try:
                    asc_release.main(argv)
                except SystemExit as exc:
                    code = exc.code if isinstance(exc.code, int) else 1
        return code, err.getvalue()

    def test_draft_submission_rerun_updates_text_then_submits(self) -> None:
        client = RouteClient(self.routes(state="READY_FOR_REVIEW", info_state="READY_FOR_REVIEW", whats_new=""))
        code, err = self.run_main(client)
        self.assertEqual(code, 0, err)
        writes = [(method, path) for method, path, _ in client.writes()]
        self.assertIn(("PATCH", "/appStoreVersionLocalizations/VL1"), writes, "What's New is still editable")
        self.assertEqual(writes[-1], ("PATCH", "/reviewSubmissions/SUB1"))
        self.assertNotIn(("POST", "/reviewSubmissionItems"), writes, "the draft already holds the version")

    def test_submitted_rerun_with_matching_listing_changes_nothing(self) -> None:
        client = RouteClient(self.routes(state="WAITING_FOR_REVIEW", info_state="WAITING_FOR_REVIEW"))
        code, err = self.run_main(client)
        self.assertEqual(code, 0, err)
        self.assertEqual(client.writes(), [])

    def test_submitted_rerun_refuses_a_change_it_cannot_make(self) -> None:
        client = RouteClient(self.routes(state="WAITING_FOR_REVIEW", info_state="WAITING_FOR_REVIEW",
                                         whats_new="- Other notes"))
        code, err = self.run_main(client)
        self.assertEqual(code, 1)
        self.assertIn("What's New (en-US) differs from App Store Connect (whatsNew)", err)
        self.assertIn("WAITING_FOR_REVIEW", err)
        self.assertEqual(client.writes(), [])

    def test_submitted_rerun_with_another_build_in_review_fails(self) -> None:
        client = RouteClient(self.routes(state="WAITING_FOR_REVIEW", info_state="WAITING_FOR_REVIEW", attached="OTHER"))
        code, err = self.run_main(client)
        self.assertEqual(code, 1)
        self.assertIn("expected B9", err)
        self.assertEqual(client.writes(), [])

    def test_screenshots_that_cannot_change_fail_before_any_write(self) -> None:
        # The listing would change (allowed in a draft), but the screenshots differ too
        # (not allowed): nothing is written at all.
        client = RouteClient(self.routes(state="READY_FOR_REVIEW", info_state="READY_FOR_REVIEW", whats_new="",
                                         screenshot_sums=["old"]))
        code, err = self.run_main(client, screenshots=True)
        self.assertEqual(code, 1)
        self.assertIn("screenshots can no longer change", err)
        self.assertEqual(client.writes(), [])

    def test_unchanged_screenshots_pass_in_a_draft_submission(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            checksum = asc_release.md5_hex(png(Path(tmp) / "a.png", 1260, 2736))
        client = RouteClient(self.routes(state="READY_FOR_REVIEW", info_state="READY_FOR_REVIEW",
                                         screenshot_sums=[checksum]))
        code, err = self.run_main(client, screenshots=True)
        self.assertEqual(code, 0, err)
        self.assertFalse([w for w in client.writes() if "Screenshot" in w[1]], "screenshots untouched")


class PreflightTests(unittest.TestCase):
    """Read-only checks that run before the build is uploaded."""

    def routes(self, *, state: str = "PREPARE_FOR_SUBMISSION", live_notes: str = "- Old notes",
               versions: tuple[str, ...] = (VERSION,), products: list[dict] | None = None,
               version_locales: tuple[str, ...] = ("en-US",), app_info_locales: tuple[str, ...] = ("en-US",),
               screenshot_sums: list[str] | None = None) -> dict:
        rows = [{"id": "VLIVE", "attributes": {"versionString": "2.0.1", "appStoreState": "READY_FOR_SALE",
                                                "createdDate": "2026-07-09T00:00:00Z"}}]
        rows += [{"id": f"V{i}", "attributes": {"versionString": v, "appStoreState": state,
                                                 "createdDate": "2026-10-14T00:00:00Z"}} for i, v in enumerate(versions)]
        return {
            "/apps?*": {"data": [{"id": APP, "attributes": {"bundleId": "com.apoorvdarshan.Scowld"}}]},
            f"/apps/{APP}/appStoreVersions?*": {"data": rows},
            "/appStoreVersions/VLIVE/appStoreVersionLocalizations?limit=50": loc_rows(loc_id="LIVE", whatsNew=live_notes),
            "/appStoreVersions/V0/appStoreVersionLocalizations?limit=50": {"data": [
                {"id": f"VL{i}", "attributes": {"locale": locale}} for i, locale in enumerate(version_locales)]},
            f"/apps/{APP}/appInfos": {"data": [{"id": "AI0", "attributes": {"state": "READY_FOR_DISTRIBUTION"}},
                                               {"id": "AI1", "attributes": {"state": "PREPARE_FOR_SUBMISSION"}}]},
            "/appInfos/AI1/appInfoLocalizations?limit=50": {"data": [
                {"id": f"IL{i}", "attributes": {"locale": locale}} for i, locale in enumerate(app_info_locales)]},
            "/appStoreVersionLocalizations/VL0/appScreenshotSets?limit=50": {"data": [
                {"id": "SET1", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]},
            "/appScreenshotSets/SET1/appScreenshots?limit=50": {"data": [
                {"id": f"S{i}", "attributes": {"sourceFileChecksum": checksum}}
                for i, checksum in enumerate(screenshot_sums or [])]},
            f"/apps/{APP}/subscriptionGroups?limit=200": {"data": [{"id": "G1"}] if products else []},
            "/subscriptionGroups/G1/subscriptions?limit=200": {"data": products or []},
            f"/apps/{APP}/inAppPurchasesV2?limit=200": {"data": []},
        }

    def run_preflight(self, client: RouteClient, **flags: str) -> tuple[int, str]:
        env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        env.update(flags)
        err = io.StringIO()
        code = 0
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            loc = root / "store" / "en-US"
            loc.mkdir(parents=True)
            (loc / "description.txt").write_text("A companion")
            (loc / "name.txt").write_text("Scowld")
            (loc / "whats_new.txt").write_text("- New notes")
            self.shot = png(root / "shots" / "a.png", 1260, 2736)
            (loc / "screenshots.json").write_text(json.dumps({"APP_IPHONE_67": ["shots/a.png"]}))
            argv = ["--preflight", "--version", VERSION, "--metadata-dir", str(root / "store")]
            with mock.patch.dict(os.environ, env, clear=True), \
                    mock.patch.object(asc_release, "client_from_environment", return_value=client), \
                    mock.patch.object(asc_release, "ROOT", root), \
                    redirect_stdout(io.StringIO()), redirect_stderr(err):
                try:
                    asc_release.main(argv)
                except SystemExit as exc:
                    code = exc.code if isinstance(exc.code, int) else 1
        return code, err.getvalue()

    def test_ready_version_passes_with_reads_only(self) -> None:
        client = RouteClient(self.routes())
        code, err = self.run_preflight(client, UPLOAD_LISTING="true", UPLOAD_WHATS_NEW="true", SUBMIT_IOS_REVIEW="true")
        self.assertEqual(code, 0, err)
        self.assertEqual(client.writes(), [])

    def test_missing_version_fails_before_the_build(self) -> None:
        code, err = self.run_preflight(RouteClient(self.routes(versions=())), UPLOAD_LISTING="true")
        self.assertEqual(code, 1)
        self.assertIn("create version 2.0.2", err)

    def test_version_that_cannot_change_fails(self) -> None:
        code, err = self.run_preflight(RouteClient(self.routes(state="WAITING_FOR_REVIEW")), SUBMIT_IOS_REVIEW="true")
        self.assertEqual(code, 1)
        self.assertIn("cannot be submitted", err)
        for state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
            code, err = self.run_preflight(RouteClient(self.routes(state=state)), UPLOAD_LISTING="true")
            with self.subTest(state=state):
                self.assertEqual(code, 1)
                self.assertIn("not editable", err)

    def test_missing_locale_fails_before_the_build(self) -> None:
        client = RouteClient(self.routes(version_locales=("de-DE",)))
        code, err = self.run_preflight(client, UPLOAD_WHATS_NEW="true")
        self.assertEqual(code, 1)
        self.assertIn("version has no en-US localization", err)
        client = RouteClient(self.routes(app_info_locales=("de-DE",)))
        code, err = self.run_preflight(client, UPLOAD_LISTING="true")
        self.assertEqual(code, 1)
        self.assertIn("app info has no en-US localization", err)
        self.assertEqual(client.writes(), [])

    def test_draft_submission_still_takes_text_and_unchanged_screenshots(self) -> None:
        # READY_FOR_REVIEW: listing and What's New can still change, screenshots cannot.
        client = RouteClient(self.routes(state="READY_FOR_REVIEW"))
        code, err = self.run_preflight(client, UPLOAD_LISTING="true", UPLOAD_WHATS_NEW="true", SUBMIT_IOS_REVIEW="true")
        self.assertEqual(code, 0, err)
        stale = RouteClient(self.routes(state="READY_FOR_REVIEW", screenshot_sums=["old"]))
        code, err = self.run_preflight(stale, UPLOAD_SCREENSHOTS="true")
        self.assertEqual(code, 1)
        self.assertIn("screenshots APP_IPHONE_67 (en-US) differs", err)
        self.assertIn("READY_FOR_REVIEW", err)
        self.assertEqual(stale.writes(), [])

    def test_unchanged_screenshots_pass_in_a_draft_submission(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            checksum = asc_release.md5_hex(png(Path(tmp) / "a.png", 1260, 2736))
        client = RouteClient(self.routes(state="READY_FOR_REVIEW", screenshot_sums=[checksum]))
        code, err = self.run_preflight(client, UPLOAD_SCREENSHOTS="true")
        self.assertEqual(code, 0, err)
        self.assertEqual(client.writes(), [])

    def test_stale_whats_new_fails_before_the_build(self) -> None:
        code, err = self.run_preflight(RouteClient(self.routes(live_notes="- New notes")), UPLOAD_WHATS_NEW="true")
        self.assertEqual(code, 1)
        self.assertIn("identical to live version 2.0.1", err)

    def test_pending_products_fail_before_the_build(self) -> None:
        products = [{"id": "S1", "attributes": {"productId": "plus", "state": "READY_TO_SUBMIT"}}]
        code, err = self.run_preflight(RouteClient(self.routes(products=products)), SUBMIT_IOS_REVIEW="true")
        self.assertEqual(code, 1)
        self.assertIn("plus", err)

    def test_preflight_does_not_need_a_build(self) -> None:
        code, err = self.run_preflight(RouteClient(self.routes()), SUBMIT_IOS_REVIEW="true", PUBLIC_RELEASE="true")
        self.assertEqual(code, 0, err)


class AscCliTests(unittest.TestCase):
    def run_cli(self, env: dict[str, str], *args: str) -> tuple[int, str]:
        out = io.StringIO()
        full_env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        full_env.update(env)
        with mock.patch.dict(os.environ, full_env, clear=True), redirect_stdout(out), redirect_stderr(out):
            try:
                asc_release.main(["--dry-run", *args])
            except SystemExit as exc:
                return (exc.code if isinstance(exc.code, int) else 1), out.getvalue()
        return 0, out.getvalue()

    def test_everything_off_is_a_no_op(self) -> None:
        code, output = self.run_cli({})
        self.assertEqual(code, 0)
        self.assertIn("skipped", output)

    def test_submit_without_this_runs_build_fails(self) -> None:
        code, output = self.run_cli({"SUBMIT_IOS_REVIEW": "true"})
        self.assertEqual(code, 1)
        self.assertIn("--build-id", output)

    def test_public_release_without_submit_fails(self) -> None:
        code, _ = self.run_cli({"UPLOAD_LISTING": "true", "PUBLIC_RELEASE": "true"})
        self.assertEqual(code, 1)

    def test_dry_run_never_creates_a_client(self) -> None:
        # Its own files: the committed ones are checked by @committed_files_test tests.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            loc = root / "meta" / "en-US"
            loc.mkdir(parents=True)
            (loc / "description.txt").write_text("A companion")
            png(root / "shots" / "a.png", 1260, 2736)
            (loc / "screenshots.json").write_text(json.dumps({"APP_IPHONE_67": ["shots/a.png"]}))
            with mock.patch.object(asc_release, "client_from_environment", side_effect=AssertionError("network")), \
                    mock.patch.object(asc_release, "ROOT", root):
                code, output = self.run_cli({"UPLOAD_LISTING": "true", "UPLOAD_SCREENSHOTS": "true"},
                                            "--metadata-dir", str(root / "meta"))
        self.assertEqual(code, 0, output)
        self.assertIn("no API calls", output)


class ReleaseNotesTests(unittest.TestCase):
    SCRIPT = ROOT / "scripts" / "release_notes.py"

    def run_notes(self, tag: str, path: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(self.SCRIPT), tag, "--file", path],
                              capture_output=True, text=True, check=False)

    def notes(self, text: str, tag: str) -> tuple[int, str]:
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
            handle.write(text)
        self.addCleanup(os.unlink, handle.name)
        result = self.run_notes(tag, handle.name)
        return result.returncode, result.stdout

    def test_matching_section_missing_section_and_empty_section(self) -> None:
        text = "# Notes\n\n## v2.0.2\n\n- Faster replies\n\n## v2.0.1\n\n## Unreleased\n- wip\n"
        self.assertEqual(self.notes(text, "v2.0.2"), (0, "- Faster replies\n"))
        self.assertEqual(self.notes(text, "v9.9")[0], 3, "missing section → GitHub generated notes")
        self.assertEqual(self.notes(text, "v2.0.1")[0], 2, "empty section fails the release")
        self.assertEqual(self.notes(text, "Unreleased")[0], 2)

    def test_duplicate_sections_for_the_tag_fail(self) -> None:
        text = "## v2.0.2\n\n- First draft\n\n## v2.0.1\n\n- Old\n\n## v2.0.2 \n\n- Second draft\n"
        self.assertEqual(self.notes(text, "v2.0.2"), (2, ""), "ambiguous notes are never published")
        self.assertEqual(self.notes(text, "v2.0.1"), (0, "- Old\n"))

    def test_missing_notes_file_means_generated_notes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self.run_notes("v2.0.2", str(Path(tmp) / "RELEASE_NOTES.md"))
        self.assertEqual((result.returncode, result.stdout), (3, ""))
        self.assertIn("GitHub will generate the notes", result.stderr)

    @committed_files_test
    def test_committed_release_notes_have_one_section_per_heading(self) -> None:
        text = (ROOT / "RELEASE_NOTES.md").read_text(encoding="utf-8")
        headings = [heading.strip() for heading in re.findall(r"^## (.*)$", text, flags=re.MULTILINE)]
        self.assertEqual(sorted({h for h in headings if headings.count(h) > 1}), [])


class PrintGatesTests(unittest.TestCase):
    def output(self, env: dict[str, str]) -> str:
        full = {k: v for k, v in os.environ.items() if not k.startswith("IOS_")}
        full.update(env)
        out = io.StringIO()
        with mock.patch.dict(os.environ, full, clear=True), redirect_stdout(out):
            print_gates.main()
        return out.getvalue()

    def test_invalid_values_are_shown_as_invalid(self) -> None:
        text = self.output({"IOS_RELEASE_AUTOMATION": "true", "IOS_SUBMIT_REVIEW": "maybe"})
        self.assertIn("IOS_SUBMIT_REVIEW=INVALID 'maybe' (a release run fails)", text)
        self.assertIn("ERROR: IOS_SUBMIT_REVIEW has an invalid value", text)
        self.assertNotIn("IOS_SUBMIT_REVIEW=false", text)
        master = self.output({"IOS_RELEASE_AUTOMATION": "enabled"})
        self.assertIn("IOS_RELEASE_AUTOMATION=INVALID 'enabled'", master)

    def test_unset_off_and_ignored_switches(self) -> None:
        text = self.output({"IOS_UPLOAD_BUILD": "true", "IOS_UPLOAD_LISTING": "off"})
        self.assertIn("IOS_RELEASE_AUTOMATION=false (unset)", text)
        self.assertIn("IOS_UPLOAD_BUILD=true (ignored: IOS_RELEASE_AUTOMATION is off)", text)
        self.assertIn("IOS_UPLOAD_LISTING=false\n", text)
        self.assertIn("IOS_RELEASE_AUTOMATION is off", text)
        self.assertNotIn("ERROR", text)

    def test_live_switches_warn(self) -> None:
        self.assertIn("WARNING: one or more live switches are on",
                      self.output({"IOS_RELEASE_AUTOMATION": "yes", "IOS_UPLOAD_BUILD": " ON "}))

    def test_reports_exactly_what_the_gates_parse(self) -> None:
        self.assertEqual(print_gates.TRUE_VALUES, ios_release.TRUE_VALUES)
        self.assertEqual(print_gates.FALSE_VALUES, ios_release.FALSE_VALUES)
        self.assertEqual(print_gates.GATES, (ios_release.MASTER, *(name for name, _ in ios_release.OPERATION_SWITCHES)))


class FindAppTests(unittest.TestCase):
    APP_ROW = {"id": "A1", "attributes": {"bundleId": "com.apoorvdarshan.Scowld"}}

    def find(self, rows: list[dict]) -> str:
        return quiet(asc_release.find_app, RouteClient({"/apps?*": {"data": rows}}), "com.apoorvdarshan.Scowld")

    def test_exactly_one_app_must_have_the_bundle_id(self) -> None:
        widget = {"id": "A2", "attributes": {"bundleId": "com.apoorvdarshan.Scowld.widget"}}
        self.assertEqual(self.find([widget, self.APP_ROW]), "A1")
        for rows in ([], [widget], [self.APP_ROW, {**self.APP_ROW, "id": "A3"}]):
            with self.subTest(rows=rows), self.assertRaises(SystemExit):
                self.find(rows)


class RedactLogsTests(unittest.TestCase):
    # Obviously fake values in the real formats (10-character key ID, UUID issuer).
    KEY = "TESTKEY000"
    ISSUER = "00000000-1111-2222-3333-444444444444"

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name) / "logs"
        self.root.mkdir()

    def redact(self, env: dict[str, str] | None = None) -> int:
        env = env if env is not None else {"ASC_KEY_ID": self.KEY, "ASC_ISSUER_ID": self.ISSUER}
        with mock.patch.dict(os.environ, env), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return redact_logs.main(["redact_logs.py", str(self.root)])

    def assert_clean(self, path: Path) -> None:
        data = path.read_bytes()
        for value in (self.KEY, self.ISSUER):
            for encoding in ("utf-8", "utf-16-le", "utf-16-be"):
                self.assertNotIn(value.encode(encoding), data, f"{path.name} ({encoding})")

    def test_text_binary_and_utf16_files_are_all_redacted(self) -> None:
        text = self.root / "export.log"
        text.write_text(f"-authenticationKeyID {self.KEY} -authenticationKeyIssuerID {self.ISSUER}\n"
                        f"-authenticationKeyPath /tmp/asc-keys/AuthKey_{self.KEY}.p8\n")
        bundle = self.root / "Scowld.xcdistributionlogs"
        bundle.mkdir()
        binary = bundle / "IDEDistributionOptions.plist"
        binary.write_bytes(b"bplist00\x00\x01\xff" + self.KEY.encode() + b"\x00" + self.ISSUER.encode())
        utf16 = bundle / "IDEDistribution.verbose.log"
        utf16.write_bytes(f"key {self.KEY} issuer {self.ISSUER}".encode("utf-16"))
        big_endian = self.root / "altool.log"
        big_endian.write_bytes(self.ISSUER.encode("utf-16-be"))
        clean = self.root / "clean.log"
        clean.write_text("nothing secret\n")

        self.assertEqual(self.redact(), 0)
        for path in (text, binary, utf16, big_endian):
            self.assert_clean(path)
        self.assertIn("AuthKey_<ASC_KEY_ID>.p8", text.read_text())
        self.assertIn("<ASC_ISSUER_ID>".encode("utf-16-le"), utf16.read_bytes())
        self.assertTrue(binary.read_bytes().startswith(b"bplist00\x00\x01\xff<ASC_KEY_ID>\x00"))
        self.assertEqual(clean.read_text(), "nothing secret\n")

    def test_symlinks_are_removed_not_followed(self) -> None:
        outside = self.root.parent / "outside.txt"
        outside.write_text(self.KEY)
        (self.root / "link.log").symlink_to(outside)
        (self.root / "dir-link").symlink_to(self.root.parent, target_is_directory=True)
        self.assertEqual(self.redact(), 0)
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), [])
        self.assertEqual(outside.read_text(), self.KEY, "nothing outside the folder is touched")

    @unittest.skipIf(hasattr(os, "geteuid") and os.geteuid() == 0, "root ignores file permissions")
    def test_file_that_cannot_be_rewritten_is_dropped(self) -> None:
        stuck = self.root / "read-only.log"
        stuck.write_text(self.KEY)
        stuck.chmod(0o444)
        self.assertEqual(self.redact(), 0)
        self.assertFalse(stuck.exists())

    @unittest.skipIf(hasattr(os, "geteuid") and os.geteuid() == 0, "root ignores file permissions")
    def test_file_that_can_be_neither_rewritten_nor_dropped_fails(self) -> None:
        folder = self.root / "locked"
        folder.mkdir()
        (folder / "stuck.log").write_text(self.KEY)
        (folder / "stuck.log").chmod(0o444)
        folder.chmod(0o555)
        self.addCleanup(folder.chmod, 0o755)
        self.assertEqual(self.redact(), 1)

    def test_empty_ids_never_match_everything(self) -> None:
        log = self.root / "a.log"
        log.write_text("abc")
        self.assertEqual(self.redact({"ASC_KEY_ID": "", "ASC_ISSUER_ID": "  "}), 0)
        self.assertEqual(log.read_text(), "abc")

    def test_missing_folder_is_not_an_error(self) -> None:
        self.root.rmdir()
        self.assertEqual(self.redact(), 0)


if __name__ == "__main__":
    unittest.main()
