#!/usr/bin/env python3
"""Offline tests for the iOS release switches, build waiting, listing, screenshots,
creative assets, review submission and reruns, the asc runner, the printed
switches, release notes and the redaction of build-log artifacts.

No network: every App Store Connect call goes to an in-memory fake of App Store
Connect behind asc (FakeAsc, SequenceAsc), and the asc runner is tested with an
injected runner.
Run: python3 -m unittest scripts/store/test_ios_release.py

Tests marked @committed_files_test check committed repository content (the App
Store listing, screenshots and release notes) rather than code. Pull requests and
main run them. The release's prepare job sets CHECK_COMMITTED_STORE_FILES=false
and validates only the files its enabled switches use, so an unused file never
blocks a release.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import io
import json
import os
import plistlib
import re
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import asc_cli  # noqa: E402
import asc_export_listing  # noqa: E402
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
    "IOS_CREATE_VERSION": "true",
    "IOS_UPLOAD_BUILD": "true",
    "IOS_UPLOAD_LISTING": "true",
    "IOS_UPLOAD_WHATS_NEW": "true",
    "IOS_UPLOAD_SCREENSHOTS": "true",
    "IOS_UPLOAD_CREATIVE_ASSETS": "true",
    "IOS_SUBMIT_REVIEW": "true",
    "IOS_PUBLIC_RELEASE": "true",
}
OPS = ("create_version", "upload_build", "listing", "whats_new", "screenshots", "creative", "submit", "public_release")
ASC_FLAGS = ("UPLOAD_LISTING", "UPLOAD_WHATS_NEW", "UPLOAD_SCREENSHOTS", "UPLOAD_CREATIVE_ASSETS", "SUBMIT_IOS_REVIEW",
             "PUBLIC_RELEASE", "CREATE_IOS_VERSION")
APP = asc_release.ASC_APP_ID
BUNDLE = asc_release.DEFAULT_BUNDLE_ID


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

    def test_creative_assets_are_their_own_switch(self) -> None:
        result = gates({"IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_CREATIVE_ASSETS": "true"})
        self.assertTrue(result["creative"])
        self.assertTrue(result["asc"])
        self.assertFalse(result["screenshots"])
        self.assertFalse(result["build"])
        self.assertFalse(gates({"IOS_UPLOAD_CREATIVE_ASSETS": "true"})["creative"], "the master switch is off")
        with self.assertRaisesRegex(ReleaseError, "IOS_UPLOAD_CREATIVE_ASSETS"):
            gates({"IOS_UPLOAD_CREATIVE_ASSETS": "sometimes"})

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
        for name in ("IOS_RELEASE_AUTOMATION", "IOS_CREATE_VERSION", "IOS_UPLOAD_BUILD", "IOS_SUBMIT_REVIEW",
                     "IOS_PUBLIC_RELEASE", "IOS_UPLOAD_CREATIVE_ASSETS"):
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

    def test_create_version_needs_only_the_master_switch(self) -> None:
        result = gates({"IOS_RELEASE_AUTOMATION": "true", "IOS_CREATE_VERSION": "true"})
        self.assertTrue(result["create_version"])
        self.assertFalse(result["build"])
        self.assertFalse(result["asc"])
        self.assertFalse(gates({"IOS_CREATE_VERSION": "true"})["create_version"])
        self.assertFalse(gates(ALL_ON, event="workflow_dispatch", ref="main")["create_version"])

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
        self.assertEqual(written["create_version"], "false")
        self.assertEqual(written["creative"], "false")
        self.assertEqual(written["asc"], "false")
        self.assertEqual(written["marketing_version"], "9.9.9")

    def test_cli_exits_non_zero_on_invalid_switches(self) -> None:
        env = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF_NAME": TAG, "IOS_UPLOAD_BUILD": "sure"}
        with mock.patch.dict(os.environ, env, clear=False), self.assertRaises(SystemExit) as caught:
            quiet(ios_release.main, ["gates"])
        self.assertEqual(caught.exception.code, 1)


class ExportComplianceTests(unittest.TestCase):
    """ITSAppUsesNonExemptEncryption must be declared, or App Store Connect asks about every build."""

    NO = "\t\t\t\tINFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;\n"
    YES = "\t\t\t\tINFOPLIST_KEY_ITSAppUsesNonExemptEncryption = YES;\n"
    CODE = "\t\t\t\tINFOPLIST_KEY_ITSEncryptionExportComplianceCode = ABC123;\n"

    @staticmethod
    def configuration(name: str, bundle_id: str, extra: str = "") -> str:
        """One XCBuildConfiguration as Xcode writes it (unquoted bundle id, nested list)."""
        return (
            f"\t\tAAA{name}{bundle_id[-5:]} /* {name} */ = {{\n"
            "\t\t\tisa = XCBuildConfiguration;\n"
            "\t\t\tbuildSettings = {\n"
            "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
            "\t\t\t\t\t\"$(inherited)\",\n"
            "\t\t\t\t);\n"
            f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {bundle_id};\n"
            f"{extra}"
            "\t\t\t};\n"
            f"\t\t\tname = {name};\n"
            "\t\t};\n"
        )

    def project(self, text: str) -> Path:
        with tempfile.NamedTemporaryFile("w", suffix=".pbxproj", delete=False) as handle:
            handle.write("/* project */\n" + text)
        self.addCleanup(os.unlink, handle.name)
        return Path(handle.name)

    def check(self, debug: str, release: str, others: str = "") -> str:
        app = ios_release.BUNDLE_ID
        return ios_release.check_export_compliance(self.project(
            self.configuration("Debug", app, debug) + self.configuration("Release", app, release) + others))

    def test_the_app_declares_no_non_exempt_encryption(self) -> None:
        self.assertEqual(ios_release.check_export_compliance(), "NO")
        configurations = ios_release.app_build_configurations()
        self.assertEqual(sorted(configurations), ["Debug", "Release"])
        for name, settings in configurations.items():
            self.assertEqual(settings["INFOPLIST_KEY_ITSAppUsesNonExemptEncryption"], "NO", name)

    def test_no_in_every_configuration_passes(self) -> None:
        self.assertEqual(self.check(self.NO, self.NO), "NO")

    def test_a_configuration_without_the_key_fails_before_the_build(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "Release configuration does not declare export compliance"):
            self.check(self.NO, "")
        with self.assertRaisesRegex(ReleaseError, "Debug configuration does not declare export compliance"):
            self.check("", self.NO)

    def test_a_value_on_another_target_does_not_count_for_the_app(self) -> None:
        tests = (self.configuration("Debug", ios_release.BUNDLE_ID + "Tests", self.NO)
                 + self.configuration("Release", ios_release.BUNDLE_ID + "Tests", self.NO))
        with self.assertRaisesRegex(ReleaseError, "does not declare export compliance"):
            self.check("", "", tests)
        self.assertEqual(self.check(self.NO, self.NO, self.configuration("Release", "com.example.Other", self.YES)),
                         "NO")

    def test_yes_needs_the_compliance_code(self) -> None:
        with self.assertRaisesRegex(ReleaseError,
                                    "YES in the Release configuration needs INFOPLIST_KEY_ITSEncryptionExportComplianceCode"):
            self.check(self.YES + self.CODE, self.YES)
        self.assertEqual(self.check(self.YES + self.CODE, self.YES + self.CODE), "YES")

    def test_mixed_or_unknown_values_fail(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "in every app configuration alike"):
            self.check(self.NO, self.YES + self.CODE)
        with self.assertRaisesRegex(ReleaseError, "must be NO or YES; the Release configuration has 'maybe'"):
            self.check(self.NO, "\t\t\t\tINFOPLIST_KEY_ITSAppUsesNonExemptEncryption = maybe;\n")

    def test_missing_app_configurations_fail(self) -> None:
        for text in (self.configuration("Release", "com.example.Other", self.NO),
                     self.configuration("Release", ios_release.BUNDLE_ID, self.NO)):
            with self.subTest(text=text), \
                    self.assertRaisesRegex(ReleaseError, "could not find the Debug and Release configurations"):
                ios_release.check_export_compliance(self.project(text))

    def archived(self, values: Any, *, raw: bytes | None = None) -> Path:
        with tempfile.NamedTemporaryFile("wb", suffix=".plist", delete=False) as handle:
            handle.write(raw if raw is not None else plistlib.dumps(values))
        self.addCleanup(os.unlink, handle.name)
        return Path(handle.name)

    def test_the_archived_app_must_carry_the_answer(self) -> None:
        base = {"CFBundleIdentifier": ios_release.BUNDLE_ID}
        self.assertEqual(ios_release.check_archived_export_compliance(
            self.archived({**base, "ITSAppUsesNonExemptEncryption": False})), "NO")
        self.assertEqual(ios_release.check_archived_export_compliance(self.archived(
            {**base, "ITSAppUsesNonExemptEncryption": True, "ITSEncryptionExportComplianceCode": "ABC123"})), "YES")
        for values, message in (
            (base, "does not declare ITSAppUsesNonExemptEncryption"),
            ({**base, "ITSAppUsesNonExemptEncryption": True}, "without ITSEncryptionExportComplianceCode"),
            ({**base, "ITSAppUsesNonExemptEncryption": True, "ITSEncryptionExportComplianceCode": " "},
             "without ITSEncryptionExportComplianceCode"),
            ({**base, "ITSAppUsesNonExemptEncryption": "NO"}, "expected true or false"),
        ):
            with self.subTest(values=values), self.assertRaisesRegex(ReleaseError, message):
                ios_release.check_archived_export_compliance(self.archived(values))
        with self.assertRaisesRegex(ReleaseError, "cannot read"):
            ios_release.check_archived_export_compliance(self.archived(None, raw=b"not a plist"))

    def test_archive_check_command_exits_non_zero_when_the_answer_is_missing(self) -> None:
        ok = self.archived({"ITSAppUsesNonExemptEncryption": False})
        out = io.StringIO()
        with redirect_stdout(out):
            ios_release.main(["export-compliance", "--info-plist", str(ok)])
        self.assertIn("ITSAppUsesNonExemptEncryption = NO", out.getvalue())
        missing = self.archived({"CFBundleIdentifier": ios_release.BUNDLE_ID})
        with self.assertRaises(SystemExit) as caught, redirect_stderr(io.StringIO()) as err:
            ios_release.main(["export-compliance", "--info-plist", str(missing)])
        self.assertEqual(caught.exception.code, 1)
        self.assertIn("export compliance", err.getvalue())

    def test_gates_check_it_only_when_this_run_builds(self) -> None:
        for env, fails in (({"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF_NAME": "main"}, True),
                           ({"GITHUB_EVENT_NAME": "push", "GITHUB_REF_NAME": TAG}, False)):
            missing = mock.patch.object(ios_release, "check_export_compliance",
                                        side_effect=ReleaseError("the app does not declare export compliance"))
            with self.subTest(env=env), missing as check, \
                    mock.patch.object(ios_release, "single_project_value", return_value=VERSION), \
                    mock.patch.dict(os.environ, env, clear=True), redirect_stdout(io.StringIO()), \
                    redirect_stderr(io.StringIO()) as err:
                if fails:
                    with self.assertRaises(SystemExit):
                        ios_release.main(["gates"])
                    self.assertIn("export compliance", err.getvalue())
                else:
                    ios_release.main(["gates"])
                    check.assert_not_called()


class BuildNumberTests(unittest.TestCase):
    def test_next_build_number(self) -> None:
        self.assertEqual(ios_release.next_build_number(14, ["1", "13", "12"]), 14)
        self.assertEqual(ios_release.next_build_number(14, ["13", "14"]), 15)
        self.assertEqual(ios_release.next_build_number(1, []), 1)
        self.assertEqual(ios_release.next_build_number(5, ["7.1", "abc", "9"]), 10)
        self.assertEqual(ios_release.next_build_number(5, ["٩٩"]), 5)  # only ASCII digits count

    def test_command_counts_every_build_of_the_pinned_app_read_only(self) -> None:
        builds = {"data": [{"id": "B1", "attributes": {"version": "13"}}, {"id": "B2", "attributes": {"version": "21"}}]}
        fake = FakeAsc(builds=builds)
        with tempfile.NamedTemporaryFile("r", suffix=".out") as out, \
                mock.patch.object(ios_release, "asc_client", return_value=(asc_release, fake)), \
                mock.patch.object(ios_release, "single_project_value", return_value="14"), \
                mock.patch.dict(os.environ, {"GITHUB_OUTPUT": out.name}), redirect_stdout(io.StringIO()):
            ios_release.cmd_build_number(argparse.Namespace())
            written = Path(out.name).read_text()
        self.assertIn("build_number=22", written)
        self.assertEqual(fake.calls[0], ("apps", "view", "--id", APP))
        query = [c for c in fake.calls if c[:2] == ("builds", "list")][0]
        self.assertEqual((flag(query, "--app"), flag(query, "--processing-state")), (APP, "all"))
        self.assertIn("--paginate", query)
        self.assertEqual(fake.writes(), [])


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


def png_header(color_type: int, *, trns: bool = False) -> bytes:
    """A PNG signature and IHDR (plus an optional tRNS chunk) with the given colour type."""
    def chunk(kind: bytes, body: bytes) -> bytes:
        return len(body).to_bytes(4, "big") + kind + body + zlib.crc32(kind + body).to_bytes(4, "big")

    ihdr = (16).to_bytes(4, "big") + (16).to_bytes(4, "big") + bytes([8, color_type, 0, 0, 0])
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + (chunk(b"tRNS", b"\x00\x00") if trns else b"") + chunk(b"IDAT", b"x")


def asc_error(code: int) -> asc_cli.AscError:
    return asc_cli.AscError(("builds", "list"), code, "failed")


class FakeClock:
    def __init__(self, start: float) -> None:
        self.time = start
        self.sleeps: list[float] = []

    def now(self) -> float:
        return self.time

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.time += seconds


class SequenceAsc:
    """Returns queued asc payloads (or raises queued exceptions) per call."""

    def __init__(self, responses: list) -> None:
        self.responses = list(responses)
        self.calls: list[tuple[str, ...]] = []

    def run(self, *args: str, **_: object) -> Any:
        self.calls.append(args)
        item = self.responses.pop(0) if len(self.responses) > 1 else self.responses[0]
        if isinstance(item, BaseException):
            raise item
        return item


def wait(client: SequenceAsc, clock: FakeClock, *, minutes: int = 120, transient=None) -> dict:
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
        client = SequenceAsc(
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
        query = client.calls[0]
        self.assertEqual(query[:2], ("builds", "list"))
        self.assertEqual((flag(query, "--app"), flag(query, "--build-number")), (APP, "14"))
        self.assertEqual(flag(query, "--processing-state"), "all")
        self.assertIn("preReleaseVersion,app", query)

    def test_times_out_without_using_another_build(self) -> None:
        client = SequenceAsc([{"data": [build_row(state="PROCESSING")], "included": [pre_row()]}])
        clock = FakeClock(STARTED)
        with self.assertRaisesRegex(ReleaseError, "timed out"):
            wait(client, clock, minutes=10)
        self.assertLessEqual(clock.time, STARTED + 10 * 60 + 30)

    def test_ready_build_after_the_deadline_is_still_a_timeout(self) -> None:
        client = SequenceAsc([{"data": [build_row()], "included": [pre_row()]}])
        clock = FakeClock(STARTED + 121 * 60)  # job started after the 120-minute budget
        with self.assertRaisesRegex(ReleaseError, "timed out"):
            wait(client, clock)
        self.assertEqual(client.calls, [], "must not poll once the budget is spent")

    def test_processing_failure_stops(self) -> None:
        for state in ("FAILED", "INVALID"):
            client = SequenceAsc([{"data": [build_row(state=state)], "included": [pre_row()]}])
            with self.subTest(state=state), self.assertRaisesRegex(ReleaseError, state):
                wait(client, FakeClock(STARTED))

    def test_expired_build_is_rejected(self) -> None:
        client = SequenceAsc([{"data": [build_row(expired=True)], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "expired"):
            wait(client, FakeClock(STARTED))

    def test_ambiguous_match_stops(self) -> None:
        client = SequenceAsc([{"data": [build_row("B1"), build_row("B2")], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "ambiguous"):
            wait(client, FakeClock(STARTED))

    def test_older_upload_is_never_substituted(self) -> None:
        old = build_row(uploaded=STARTED - 3600)
        client = SequenceAsc([{"data": [old], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "older build"):
            wait(client, FakeClock(STARTED))

    def test_build_without_an_upload_time_is_never_used(self) -> None:
        # Fails closed: a VALID build whose uploadedDate is missing or empty cannot be
        # shown to be this run's upload, so the wait runs out instead of using it.
        for uploaded in (MISSING, None, ""):
            client = SequenceAsc([{"data": [build_row(uploaded=uploaded)], "included": [pre_row()]}])
            clock = FakeClock(STARTED)
            with self.subTest(uploaded=uploaded), self.assertRaisesRegex(ReleaseError, "timed out"):
                wait(client, clock, minutes=10)
            self.assertGreater(len(client.calls), 1, "it kept polling")

    def test_upload_time_reported_later_is_accepted(self) -> None:
        client = SequenceAsc([
            {"data": [build_row(uploaded=MISSING)], "included": [pre_row()]},
            {"data": [build_row()], "included": [pre_row()]},
        ])
        self.assertEqual(wait(client, FakeClock(STARTED))["id"], "B1")

    def test_unreadable_upload_time_stops(self) -> None:
        for uploaded in ("yesterday", 12345, ["2026"]):
            row = build_row()
            row["attributes"]["uploadedDate"] = uploaded
            client = SequenceAsc([{"data": [row], "included": [pre_row()]}])
            with self.subTest(uploaded=uploaded), self.assertRaisesRegex(ReleaseError, "unreadable uploadedDate"):
                wait(client, FakeClock(STARTED))

    def test_processing_failure_stops_even_without_an_upload_time(self) -> None:
        client = SequenceAsc([{"data": [build_row(state="FAILED", uploaded=MISSING)], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "FAILED"):
            wait(client, FakeClock(STARTED))

    def test_other_versions_and_platforms_are_ignored(self) -> None:
        other_version = build_row("BX", pre="P2")
        other_platform = build_row("BY", pre="P3")
        client = SequenceAsc(
            [
                {"data": [other_version, other_platform],
                 "included": [pre_row("P2", "2.0.1"), pre_row("P3", VERSION, "MAC_OS")]},
                {"data": [other_version, build_row("B1")], "included": [pre_row("P2", "2.0.1"), pre_row()]},
            ]
        )
        self.assertEqual(wait(client, FakeClock(STARTED))["id"], "B1")

    def test_build_from_another_app_is_a_mismatch(self) -> None:
        client = SequenceAsc([{"data": [build_row(app="OTHER")], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "another app"):
            wait(client, FakeClock(STARTED))

    def test_transient_errors_are_retried_and_others_raise(self) -> None:
        client = SequenceAsc([asc_error(63), {"data": [build_row()], "included": [pre_row()]}])
        with redirect_stderr(io.StringIO()):
            build = wait(client, FakeClock(STARTED), transient=ios_release.is_transient_error)
        self.assertEqual(build["id"], "B1")
        fatal = SequenceAsc([asc_error(3)])
        with self.assertRaises(asc_cli.AscError):
            wait(fatal, FakeClock(STARTED), transient=ios_release.is_transient_error)


class TransientErrorTests(unittest.TestCase):
    def test_retry_rule_follows_asc_exit_codes(self) -> None:
        # HTTP 408 (18), 429 (39), any 5xx (60-99) and an asc call that ran out of time (124).
        for code in (18, 39, 60, 62, 63, 99, 124):
            with self.subTest(code=code):
                self.assertTrue(ios_release.is_transient_error(asc_error(code)))
        # Generic, usage, auth, not found, conflict, read-only refusal, other 4xx, unverified or missing asc.
        for code in (1, 2, 3, 4, 5, 6, 10, 32, 126, 127):
            with self.subTest(code=code):
                self.assertFalse(ios_release.is_transient_error(asc_error(code)))
        # Network errors happen inside asc, which reports them by exit code and message.
        for exc in (ValueError("bad"), ReleaseError("mismatch"), SystemExit(1), ConnectionResetError("reset")):
            with self.subTest(exc=repr(exc)):
                self.assertFalse(ios_release.is_transient_error(exc))

    def test_network_drops_reported_as_exit_1_are_retried(self) -> None:
        for detail in ('Get "https://api.appstoreconnect.apple.com/v1/builds": read tcp: connection reset by peer',
                       "dial tcp: lookup api.appstoreconnect.apple.com: no such host",
                       "net/http: TLS handshake timeout", "unexpected EOF"):
            with self.subTest(detail=detail):
                self.assertTrue(ios_release.is_transient_error(asc_cli.AscError(("builds", "list"), 1, detail)))
        for detail in ("invalid character '<' looking for beginning of value", "build not found"):
            with self.subTest(detail=detail):
                self.assertFalse(ios_release.is_transient_error(asc_cli.AscError(("builds", "list"), 1, detail)))
        # Only exit 1 is read this way: an auth failure that mentions a timeout still stops.
        self.assertFalse(ios_release.is_transient_error(asc_cli.AscError(("builds", "list"), 3, "i/o timeout")))

    def test_a_network_drop_during_the_wait_is_retried(self) -> None:
        drop = asc_cli.AscError(("builds", "list"), 1, "read tcp 10.0.0.1:443: connection reset by peer")
        client = SequenceAsc([drop, {"data": [build_row()], "included": [pre_row()]}])
        self.assertEqual(wait(client, FakeClock(STARTED), transient=ios_release.is_transient_error)["id"], "B1")
        self.assertEqual(len(client.calls), 2)


class CmdWaitBuildTests(unittest.TestCase):
    def test_deadline_counts_from_upload_start_and_app_lookup_is_retried(self) -> None:
        lookups = []

        class Lookup:
            def run(self, *args: str, **_: object):
                lookups.append(args)
                if len(lookups) == 1:
                    raise asc_error(63)
                return {"data": {"id": APP, "attributes": {"bundleId": ios_release.BUNDLE_ID}}}

        captured = {}

        def fake_wait(client, **kwargs):
            captured.update(kwargs)
            return {"id": "B9"}

        args = argparse.Namespace(version=VERSION, build=14, started_at=STARTED, wait_minutes=120, poll_seconds=30)
        with tempfile.NamedTemporaryFile("r", suffix=".out") as out, \
                mock.patch.object(ios_release, "asc_client", return_value=(asc_release, Lookup())), \
                mock.patch.object(ios_release, "wait_for_build", side_effect=fake_wait), \
                mock.patch.object(ios_release.time, "sleep"), \
                mock.patch.object(ios_release.time, "time", return_value=STARTED + 30), \
                mock.patch.dict(os.environ, {"GITHUB_OUTPUT": out.name}), redirect_stdout(io.StringIO()):
            ios_release.cmd_wait_build(args)
            written = Path(out.name).read_text()
        self.assertEqual(lookups, [("apps", "view", "--id", APP)] * 2)
        self.assertEqual(ios_release.BUNDLE_ID, "com.apoorvdarshan.Scowld")
        self.assertEqual(captured["app_id"], APP)
        self.assertEqual(captured["deadline"], STARTED + 120 * 60)
        self.assertEqual(captured["uploaded_after"], STARTED)
        self.assertEqual(captured["build_number"], "14")
        self.assertIs(captured["is_transient"], ios_release.is_transient_error)
        self.assertIn("build_id=B9", written)

    def test_another_app_record_stops_the_wait(self) -> None:
        class Other:
            def run(self, *args: str, **_: object):
                return {"data": {"id": APP, "attributes": {"bundleId": "com.example.other"}}}

        args = argparse.Namespace(version=VERSION, build=14, started_at=STARTED, wait_minutes=120, poll_seconds=30)
        with mock.patch.object(ios_release, "asc_client", return_value=(asc_release, Other())), \
                mock.patch.object(ios_release.time, "time", return_value=STARTED), \
                redirect_stdout(io.StringIO()), self.assertRaises(ReleaseError):
            ios_release.cmd_wait_build(args)

    def test_app_lookup_gives_up_at_the_deadline(self) -> None:
        def boom():
            raise asc_error(63)

        clock = FakeClock(STARTED)
        with redirect_stdout(io.StringIO()), self.assertRaises(asc_cli.AscError):
            ios_release.call_with_retries(boom, deadline=STARTED + 90, poll_seconds=30, now=clock.now, sleep=clock.sleep)
        self.assertEqual(clock.sleeps, [30, 30, 30])

    def test_checks_run_asc_read_only(self) -> None:
        env = {"APP_STORE_CONNECT_API_KEY_ID": "K", "APP_STORE_CONNECT_ISSUER_ID": "I", "APP_STORE_CONNECT_API_KEY_P8": "P"}
        with mock.patch.dict(os.environ, env, clear=True):
            _, client = ios_release.asc_client()
        self.assertTrue(client.read_only)


class AscRunnerTests(unittest.TestCase):
    ENV = {
        "APP_STORE_CONNECT_API_KEY_ID": "TESTKEY0001",
        "APP_STORE_CONNECT_ISSUER_ID": "00000000-test-4000-8000-issuer000001",
        "APP_STORE_CONNECT_API_KEY_P8": "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----",
        "ASC_PROFILE": "personal",
        "ASC_CONFIG_PATH": "/home/me/.asc/config.json",
    }

    def run_once(self, *, returncode: int = 0, stdout: str = '{"data": []}', stderr: str = "", read_only=False, env=None):
        seen: dict = {}

        def runner(argv, **kwargs):
            seen["argv"], seen["env"] = argv, kwargs["env"]
            return mock.Mock(returncode=returncode, stdout=stdout, stderr=stderr)

        with mock.patch.dict(os.environ, env or self.ENV, clear=True):
            result = asc_cli.Asc(binary="asc", read_only=read_only, runner=runner).run("apps", "view", "--id", APP)
        return result, seen

    def test_credentials_come_from_the_release_secrets_and_nothing_else(self) -> None:
        result, seen = self.run_once()
        self.assertEqual(result, {"data": []})
        self.assertEqual(seen["argv"], ["asc", "apps", "view", "--id", APP, "--output", "json"])
        env = seen["env"]
        self.assertEqual(env["ASC_KEY_ID"], "TESTKEY0001")
        self.assertEqual(env["ASC_ISSUER_ID"], self.ENV["APP_STORE_CONNECT_ISSUER_ID"])
        self.assertIn("\nabc\n", env["ASC_PRIVATE_KEY"])
        for name in ("ASC_PROFILE", "ASC_CONFIG_PATH"):
            self.assertNotIn(name, env)
        for name, value in (("ASC_BYPASS_KEYCHAIN", "1"), ("ASC_TELEMETRY_DISABLED", "1"), ("DO_NOT_TRACK", "1"),
                            ("ASC_SKILLS_AUTO_CHECK", "0"), ("ASC_STRICT_AUTH", "1"), ("ASC_MAX_RETRIES", "5")):
            self.assertEqual(env[name], value, name)
        self.assertNotIn("ASC_READ_ONLY", env)

    def test_read_only_from_the_caller_or_the_job(self) -> None:
        _, seen = self.run_once(read_only=True)
        self.assertEqual(seen["env"]["ASC_READ_ONLY"], "1")
        _, seen = self.run_once(env={**self.ENV, "ASC_READ_ONLY": "1"})
        self.assertEqual(seen["env"]["ASC_READ_ONLY"], "1")

    def test_failures_keep_the_exit_code_and_hide_the_ids(self) -> None:
        stderr = f"401 for key {self.ENV['APP_STORE_CONNECT_API_KEY_ID']} issuer {self.ENV['APP_STORE_CONNECT_ISSUER_ID']}"
        with self.assertRaises(asc_cli.AscError) as caught:
            self.run_once(returncode=3, stderr=stderr)
        self.assertEqual(caught.exception.exit_code, 3)
        self.assertNotIn("TESTKEY0001", str(caught.exception))
        self.assertNotIn("issuer000001", str(caught.exception))
        with self.assertRaises(asc_cli.AscError):
            self.run_once(stdout="not json")

    def test_install_accepts_only_the_pinned_binary(self) -> None:
        good = b"pinned-binary"
        with mock.patch.dict(asc_cli.ASC_SHA256, {"linux_amd64": hashlib.sha256(good).hexdigest()}):
            with tempfile.TemporaryDirectory() as tmp:
                opener = lambda url, timeout: io.BytesIO(good)  # noqa: E731
                target = quiet(asc_cli.install, Path(tmp), key="linux_amd64", opener=opener)
                self.assertEqual(target.read_bytes(), good)
                self.assertTrue(os.access(target, os.X_OK))
                bad = lambda url, timeout: io.BytesIO(b"tampered")  # noqa: E731
                with self.assertRaises(SystemExit):
                    quiet(asc_cli.install, Path(tmp) / "other", key="linux_amd64", opener=bad)
                self.assertFalse((Path(tmp) / "other" / "asc").exists())

    def test_the_pin_is_one_exact_release_with_both_ci_platforms(self) -> None:
        self.assertRegex(asc_cli.ASC_VERSION, r"^[0-9]+\.[0-9]+\.[0-9]+$")
        self.assertEqual(set(asc_cli.ASC_SHA256), {"linux_amd64", "macOS_arm64"})
        for digest in asc_cli.ASC_SHA256.values():
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
        self.assertEqual(asc_cli.platform_key("Linux", "x86_64"), "linux_amd64")
        self.assertEqual(asc_cli.platform_key("Darwin", "arm64"), "macOS_arm64")
        with self.assertRaises(SystemExit):
            asc_cli.platform_key("Windows", "x86_64")

    def test_only_the_pinned_binary_receives_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "asc"
            binary.write_bytes(b"pinned-binary")
            pinned = {asc_cli.platform_key(): hashlib.sha256(b"pinned-binary").hexdigest()}
            with mock.patch.dict(asc_cli.ASC_SHA256, pinned), mock.patch.object(asc_cli.shutil, "which", return_value=str(binary)):
                self.assertEqual(asc_cli.verified_binary("asc"), str(binary))
                binary.write_bytes(b"something else")
                with self.assertRaises(asc_cli.AscError) as caught:
                    asc_cli.verified_binary("asc")
                self.assertEqual(caught.exception.exit_code, 126)
                # A real run checks the binary before anything is executed.
                with mock.patch.object(asc_cli.subprocess, "run") as run, self.assertRaises(asc_cli.AscError):
                    asc_cli.Asc().run("apps", "view", "--id", APP)
                run.assert_not_called()
            with mock.patch.object(asc_cli.shutil, "which", return_value=None), self.assertRaises(asc_cli.AscError):
                asc_cli.verified_binary("asc")
        # No environment variable can point the release at another executable.
        with mock.patch.dict(os.environ, {"ASC_BIN": "/tmp/evil"}):
            self.assertEqual(asc_cli.Asc().binary, "asc")

    def test_alpha_is_detected_the_way_asc_refuses_it(self) -> None:
        cases = {"rgb": (png_header(2), False), "rgba": (png_header(6), True), "gray-alpha": (png_header(4), True),
                 "rgb-trns": (png_header(2, trns=True), True), "jpeg": (b"\xff\xd8\xff\xe0rest", False)}
        with tempfile.TemporaryDirectory() as tmp:
            for name, (content, expected) in cases.items():
                path = Path(tmp) / name
                path.write_bytes(content)
                with self.subTest(name=name):
                    self.assertEqual(asc_cli.image_has_alpha(path), expected)

    def test_check_requires_the_pinned_checksum_and_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "asc"
            for reported, passes in ((asc_cli.ASC_VERSION, True), ("5.14.0", False)):
                binary.write_text(f"#!/bin/sh\necho '{reported} (commit: test)'\n")
                binary.chmod(0o755)
                pinned = {asc_cli.platform_key(): hashlib.sha256(binary.read_bytes()).hexdigest()}
                with self.subTest(reported=reported), mock.patch.dict(asc_cli.ASC_SHA256, pinned), \
                        mock.patch.object(asc_cli.shutil, "which", return_value=str(binary)):
                    if passes:
                        self.assertEqual(asc_cli.check_version(asc_cli.Asc()), asc_cli.ASC_VERSION)
                    else:
                        with self.assertRaisesRegex(SystemExit, "expected the pinned"):
                            asc_cli.check_version(asc_cli.Asc())
            with mock.patch.object(asc_cli.shutil, "which", return_value=str(binary)), \
                    self.assertRaisesRegex(SystemExit, "not the pinned asc"):
                asc_cli.check_version(asc_cli.Asc())

    def test_a_leading_at_sign_is_escaped(self) -> None:
        self.assertEqual(asc_release.asc_value("@scowld on X"), "@@scowld on X")
        self.assertEqual(asc_release.asc_value("Talk with Scowld"), "Talk with Scowld")

    def test_live_runs_need_the_credentials(self) -> None:
        err = io.StringIO()
        with mock.patch.dict(os.environ, {}, clear=True), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.asc_from_environment()
        self.assertIn("missing ASC credentials", err.getvalue())
        with mock.patch.dict(os.environ, {k: v for k, v in self.ENV.items() if k.startswith("APP_STORE")}, clear=True):
            self.assertTrue(asc_release.asc_from_environment(read_only=True).read_only)
            self.assertFalse(asc_release.asc_from_environment().read_only)


# MARK: - A fake App Store Connect behind asc


MUTATIONS = {
    ("versions", "create"), ("versions", "update"), ("versions", "attach-build"), ("localizations", "update"),
    ("screenshots", "upload"), ("asset-library", "images", "upload"), ("localizations", "placements", "create"),
    ("localizations", "placements", "swap"), ("review", "submissions-create"), ("review", "items-add"),
    ("review", "submissions-submit"),
}


def is_write(call: tuple[str, ...]) -> bool:
    return call[:2] in MUTATIONS or call[:3] in MUTATIONS


def flag(call: tuple[str, ...], name: str) -> str:
    return call[call.index(name) + 1]


def version_row(version_id: str, number: str, state: str, created: str = "2026-10-14T00:00:00Z") -> dict:
    return {"id": version_id, "attributes": {"versionString": number, "appStoreState": state, "createdDate": created}}


LIVE_VERSION = version_row("VLIVE", "2.0.1", "READY_FOR_SALE", "2026-07-09T00:00:00Z")


def shot(checksum: str, name: str = "shot.png", state: str = "COMPLETE") -> dict:
    return {"id": f"S-{checksum}", "attributes": {"fileName": name, "sourceFileChecksum": checksum,
                                                   "assetDeliveryState": {"state": state}}}


def item(item_id: str, relation: str, related: str) -> dict:
    return {"id": item_id, "relationships": {relation: {"data": {"id": related}}}}


ITEM_RELATIONS = {"appStoreVersions": "appStoreVersion", "subscriptionVersions": "subscriptionVersion",
                  "inAppPurchaseVersions": "inAppPurchaseVersion", "appAssetLibraryImages": "appAssetLibraryImage"}


class FakeAsc:
    """A stateful App Store Connect behind `asc` (no network).

    The app has the live version 2.0.1 (VLIVE) and the release's version (V1, one
    localization VL1, VL2… per locale), app infos AI0, AI1… with localizations IL0,
    IL1…, screenshot sets on VL1, builds, products, draft review submissions and an
    Asset Library. Writes change that state, so a second run sees the first run's
    result.
    """

    def __init__(
        self,
        *,
        state: str = "PREPARE_FOR_SUBMISSION",
        versions: list[dict] | None = None,
        bundle: str = BUNDLE,
        app_id: str = APP,
        version_text: dict | None = None,
        live_notes: str = "- Old notes",
        locales: tuple[str, ...] = ("en-US",),
        version_locs: dict[str, list[dict]] | None = None,
        app_infos: tuple[str, ...] = ("READY_FOR_DISTRIBUTION", "PREPARE_FOR_SUBMISSION"),
        app_info_text: dict[str, dict] | None = None,
        app_info_locales: tuple[str, ...] = ("en-US",),
        shots: dict[str, list] | None = None,
        upload_state: str = "COMPLETE",
        attached: str | None = "OLD",
        sticky: bool = True,
        revert_after_select: bool = False,
        builds: dict | None = None,
        subscriptions: list[dict] | None = None,
        iaps: list[dict] | None = None,
        drafts: list[str] | None = None,
        draft_items: dict[str, list[dict]] | None = None,
        refuse_items: set[str] | None = None,
        library: list[dict] | None = None,
        placements: dict[str, list[dict]] | None = None,
        created_rows: int = 1,
    ) -> None:
        self.versions = versions if versions is not None else [LIVE_VERSION, version_row("V1", VERSION, state)]
        self.bundle = bundle
        self.app_id = app_id
        self.version_locs = {
            "VLIVE": [{"id": "LIVE", "attributes": {"locale": "en-US", "whatsNew": live_notes}}],
            "V1": [{"id": f"VL{n + 1}", "attributes": {"locale": locale, **(version_text or {})}}
                   for n, locale in enumerate(locales)],
        }
        self.version_locs.update(version_locs or {})
        self.app_infos = [{"id": f"AI{i}", "attributes": {"state": s}} for i, s in enumerate(app_infos)]
        self.app_info_locs = {
            f"AI{i}": [{"id": f"IL{i}" if n == 0 else f"IL{i}-{locale}",
                        "attributes": {"locale": locale, **(app_info_text or {}).get(f"AI{i}", {})}}
                       for n, locale in enumerate(app_info_locales)]
            for i in range(len(app_infos))
        }
        self.sets = {"VL1": {display: [s if isinstance(s, dict) else shot(s) for s in rows_]
                             for display, rows_ in (shots or {}).items()}}
        self.upload_state = upload_state
        self.attached = attached
        self.sticky = sticky
        self.revert_after_select = revert_after_select
        self.builds = builds if builds is not None else {"data": [build_row("B9")], "included": [pre_row()]}
        self.subscriptions = subscriptions or []
        self.iaps = iaps or []
        self.drafts = list(drafts or [])
        self.items = {k: list(v) for k, v in (draft_items or {}).items()}
        self.refuse_items = refuse_items or set()
        self.library = list(library or [])
        self.placements = {k: list(v) for k, v in (placements or {}).items()}
        self.created_rows = created_rows
        self.calls: list[tuple[str, ...]] = []
        self.modes: list[bool] = []
        self.submitted: list[str] = []
        self.version_views = 0
        self.uploads = 0

    def connect(self, *, read_only: bool = False) -> "FakeAsc":
        """Stands in for asc_release.asc_from_environment and records the mode asked for."""
        self.modes.append(read_only)
        return self

    def writes(self) -> list[tuple[str, ...]]:
        return [c for c in self.calls if is_write(c)]

    def run(self, *args: str, **_: object) -> Any:  # noqa: C901 - one branch per asc command
        self.calls.append(args)
        two, three = args[:2], args[:3]
        if two == ("apps", "view"):
            return {"data": {"type": "apps", "id": self.app_id, "attributes": {"bundleId": self.bundle}}}
        if three == ("apps", "info", "list"):
            return {"data": self.app_infos}
        if two == ("versions", "list"):
            return {"data": list(self.versions)}
        if two == ("versions", "create"):
            for _ in range(self.created_rows):
                self.versions.append(version_row("NEW", flag(args, "--version"), "PREPARE_FOR_SUBMISSION"))
            return {"data": {"id": "NEW"}}
        if two == ("versions", "view"):
            self.version_views += 1
            build = "OLD" if self.revert_after_select and self.version_views >= 2 else self.attached
            relation = {"build": {"data": {"type": "builds", "id": build} if build else None}}
            return {"data": {"id": flag(args, "--version-id"), "relationships": relation}}
        if two == ("versions", "attach-build"):
            if self.sticky:
                self.attached = flag(args, "--build-id")
            return {"data": {}}
        if two == ("versions", "update"):
            return {"data": {}}
        if two == ("builds", "list"):
            return self.builds
        if three == ("localizations", "placements", "list"):
            wanted = flag(args, "--placement-type")
            return {"data": [p for p in self.placements.get(flag(args, "--localization-id"), [])
                             if p["attributes"]["placementType"] == wanted]}
        if three in {("localizations", "placements", "create"), ("localizations", "placements", "swap")}:
            loc, kind = flag(args, "--localization-id"), flag(args, "--placement-type")
            held = [p for p in self.placements.get(loc, []) if p["attributes"]["placementType"] != kind]
            held.append({"id": f"PL-{loc}-{kind}", "attributes": {"placementType": kind},
                         "relationships": {"image": {"data": {"id": flag(args, "--image-id")}}}})
            self.placements[loc] = held
            return {"data": {}}
        if two == ("localizations", "list"):
            if "--type" in args and flag(args, "--type") == "app-info":
                return {"data": self.app_info_locs.get(flag(args, "--app-info"), [])}
            return {"data": self.version_locs.get(flag(args, "--version"), [])}
        if two == ("localizations", "update"):
            groups = self.app_info_locs if "--type" in args else self.version_locs
            target = next(row for rows_ in groups.values() for row in rows_ if row["id"] == flag(args, "--id"))
            fields = {option: field for field, option in asc_release.FIELD_FLAGS.items()}
            for index, arg in enumerate(args[:-1]):
                if arg in fields:
                    value = args[index + 1]
                    target["attributes"][fields[arg]] = value[1:] if value.startswith("@@") else value
            return {"data": target}
        if two == ("screenshots", "list"):
            loc = flag(args, "--version-localization")
            return {"versionLocalizationId": loc, "sets": [
                {"set": {"id": f"SET-{display}", "attributes": {"screenshotDisplayType": display}},
                 "screenshots": list(rows_)}
                for display, rows_ in self.sets.get(loc, {}).items()]}
        if two == ("screenshots", "upload"):
            loc, display = flag(args, "--version-localization"), "APP_" + flag(args, "--device-type")
            sets = self.sets.setdefault(loc, {})
            if "--replace" in args:
                assert "--confirm" in args, "--replace needs --confirm"
                sets[display] = []
            path = Path(flag(args, "--path"))
            raw = path.read_bytes()
            self.uploads += 1
            delivery: dict[str, Any] = {"state": self.upload_state}
            if self.upload_state == "FAILED":
                delivery["errors"] = [{"code": "IMAGE_INCORRECT_DIMENSIONS"}]
            sets.setdefault(display, []).append({"id": f"SHOT{self.uploads}", "attributes": {
                "fileName": path.name, "fileSize": len(raw), "sourceFileChecksum": hashlib.md5(raw).hexdigest(),
                "assetDeliveryState": delivery}})
            return {"versionLocalizationId": loc, "results": [{"fileName": path.name, "assetId": f"SHOT{self.uploads}"}]}
        if two == ("subscriptions", "list"):
            return {"data": self.subscriptions}
        if two == ("iap", "list"):
            return {"data": self.iaps}
        if two == ("review", "submissions-list"):
            return {"data": [{"id": d, "attributes": {"state": "READY_FOR_REVIEW", "platform": "IOS"}} for d in self.drafts]}
        if two == ("review", "submissions-create"):
            new = f"SUB{len(self.drafts) + len(self.submitted) + 1}"
            self.drafts.append(new)
            return {"data": {"id": new}}
        if two == ("review", "items-list"):
            return {"data": list(self.items.get(flag(args, "--submission"), []))}
        if two == ("review", "items-add"):
            item_type, item_id = flag(args, "--item-type"), flag(args, "--item-id")
            if item_id in self.refuse_items:
                raise asc_cli.AscError(args, 5, "conflict")
            relation = ITEM_RELATIONS[item_type]
            held = self.items.setdefault(flag(args, "--submission"), [])
            if any(asc_release.related_id(row, relation) == item_id for row in held):
                if flag(args, "--if-exists") != "skip":
                    raise asc_cli.AscError(args, 5, "already on the submission")
                return {"data": {}}
            held.append(item(f"ITEM-{item_id}", relation, item_id))
            return {"data": {}}
        if two == ("review", "submissions-submit"):
            submission = flag(args, "--id")
            self.submitted.append(submission)
            if submission in self.drafts:
                self.drafts.remove(submission)
            for row in self.items.get(submission, []):
                image_id = asc_release.related_id(row, "appAssetLibraryImage")
                for image in self.library:
                    if image["id"] == image_id:
                        image["attributes"]["state"] = "WAITING_FOR_REVIEW"
            return {"data": {}}
        if two == ("asset-library", "view"):
            return {"data": {"id": "LIB1"}}
        if three == ("asset-library", "images", "list"):
            return {"data": self.library}
        if three == ("asset-library", "images", "upload"):
            path = Path(flag(args, "--file"))
            image_id = f"IMG{len(self.library) + 1}"
            self.library.append({"id": image_id, "attributes": {"fileName": path.name, "fileSize": path.stat().st_size,
                                                                "state": "PREPARE_FOR_SUBMISSION", "createdDate": "z"}})
            return {"imageId": image_id, "ready": True, "state": "PREPARE_FOR_SUBMISSION"}
        raise AssertionError(f"unexpected asc call {args}")


def run_release(fake: FakeAsc, env: dict[str, str], argv: list[str], *, root: Path | None = None) -> tuple[int, str]:
    """asc_release.main() against `fake`; returns (exit code, stdout + stderr)."""
    full_env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
    full_env.update(env)
    out = io.StringIO()
    code = 0
    with contextlib.ExitStack() as stack:
        stack.enter_context(mock.patch.dict(os.environ, full_env, clear=True))
        stack.enter_context(mock.patch.object(asc_release, "asc_from_environment", side_effect=fake.connect))
        if root is not None:
            stack.enter_context(mock.patch.object(asc_release, "ROOT", root))
        stack.enter_context(redirect_stdout(out))
        stack.enter_context(redirect_stderr(out))
        try:
            asc_release.main(argv)
        except SystemExit as exc:
            code = exc.code if isinstance(exc.code, int) else 1
    return code, out.getvalue()


def write_listing(root: Path, *, locales: tuple[str, ...] = ("en-US",), whats_new: str = "- New notes",
                  screenshots: dict | None = None) -> Path:
    """A store/metadata/ios tree under root; returns its path."""
    meta = root / "store" / "metadata" / "ios"
    for locale in locales:
        loc = meta / locale
        loc.mkdir(parents=True, exist_ok=True)
        (loc / "description.txt").write_text("A companion")
        (loc / "name.txt").write_text("Scowld")
        (loc / "whats_new.txt").write_text(whats_new)
        if screenshots is not None:
            (loc / "screenshots.json").write_text(json.dumps(screenshots))
    return meta


# MARK: - Listing, What's New and screenshots


def png(path: Path, width: int, height: int, *, alpha: bool = False, trns: bool = False, seed: int = 0) -> Path:
    """A real (tiny-header) PNG with the given dimensions; seed makes contents unique.

    alpha stores an alpha channel (colour type 6); trns adds a transparency chunk to
    an RGB image. asc refuses both, even when every pixel is opaque.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6 if alpha else 2, 0, 0, 0)
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))  # noqa: E731
    transparency = chunk(b"tRNS", b"\x00\x00\x00\x00\x00\x00") if trns else b""
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + transparency + chunk(b"tEXt", f"seed{seed}".encode())
                     + chunk(b"IEND", b""))
    return path


class LocalInputTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.meta = self.root / "store" / "metadata" / "ios"
        self.loc = self.meta / "en-US"
        self.loc.mkdir(parents=True)
        (self.loc / "description.txt").write_text("A companion\n")

    def validate(self, **flags: Any) -> dict:
        options = {"upload_listing": False, "upload_whats_new": False, "upload_screenshots": False, **flags}
        return quiet(asc_release.validate_local_inputs, metadata_dir=self.meta, root=self.root, **options)

    def assert_fails(self, pattern: str, **flags: Any) -> None:
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
        good = png(self.root / "store" / "metadata" / "screenshots" / "a.png", 1260, 2736)
        png(self.root / "store" / "metadata" / "screenshots" / "ipad.png", 2064, 2752, seed=1)
        png(self.root / "store" / "metadata" / "screenshots" / "small.png", 1179, 2556, seed=2)
        png(self.root / "store" / "metadata" / "screenshots" / "alpha.png", 1290, 2796, alpha=True, seed=3)
        png(self.root / "store" / "metadata" / "screenshots" / "trns.png", 1290, 2796, trns=True, seed=4)
        manifest = self.loc / "screenshots.json"

        manifest.write_text(json.dumps({"APP_IPHONE_67": ["store/metadata/screenshots/a.png"], "APP_IPAD_PRO_3GEN_129": ["store/metadata/screenshots/ipad.png"]}))
        plan = self.validate(upload_screenshots=True)["en-US"]["screenshots"]
        self.assertEqual(plan["APP_IPHONE_67"], [good.resolve()])

        cases = {
            "1179x2556; APP_IPHONE_67 accepts": {"APP_IPHONE_67": ["store/metadata/screenshots/small.png"]},
            "alpha.png stores an alpha channel": {"APP_IPHONE_67": ["store/metadata/screenshots/alpha.png"]},
            # An RGB PNG with a transparency chunk: asc refuses it as well.
            "trns.png stores an alpha channel or transparency": {"APP_IPHONE_67": ["store/metadata/screenshots/trns.png"]},
            "unsupported display type": {"APP_WATCH": ["store/metadata/screenshots/a.png"]},
            "not an image file in this repository": {"APP_IPHONE_67": ["../outside.png"]},
            "lists 11 images": {"APP_IPHONE_67": ["store/metadata/screenshots/a.png"] * 11},
            "must list at least one": {"APP_IPHONE_67": []},
        }
        for pattern, content in cases.items():
            manifest.write_text(json.dumps(content))
            with self.subTest(pattern=pattern):
                self.assert_fails(pattern, upload_screenshots=True)
        manifest.write_text("{not json")
        self.assert_fails("not valid JSON", upload_screenshots=True)

    def test_landscape_screenshots_are_accepted(self) -> None:
        png(self.root / "store" / "metadata" / "screenshots" / "wide.png", 2796, 1290)
        (self.loc / "screenshots.json").write_text(json.dumps({"APP_IPHONE_67": ["store/metadata/screenshots/wide.png"]}))
        self.assertEqual(len(self.validate(upload_screenshots=True)["en-US"]["screenshots"]["APP_IPHONE_67"]), 1)

    @committed_files_test
    def test_committed_screenshots_store_no_alpha(self) -> None:
        # asc refuses any PNG that stores alpha, even a fully opaque one, and the
        # pipeline uploads the committed files as they are.
        for path in sorted((ROOT / "store" / "metadata" / "screenshots" / "ios").rglob("*.png")):
            with self.subTest(path=path.name):
                self.assertFalse(asc_cli.image_has_alpha(path))

    def test_creative_assets_need_one_image_per_slot_and_go_to_every_locale(self) -> None:
        creative = self.root / "creative"
        self.assert_fails("no header or search results image", upload_creative=True, creative_dir=creative)
        (creative / "header").mkdir(parents=True)
        (creative / "header" / "a.png").write_bytes(b"x")
        (creative / "header" / "b.jpg").write_bytes(b"y")
        self.assert_fails("the product page header slot takes one image", upload_creative=True, creative_dir=creative)
        (creative / "header" / "b.jpg").unlink()
        (creative / "header" / "a.png").write_bytes(png_header(6))
        self.assert_fails("the product page header image a.png has an alpha channel", upload_creative=True,
                          creative_dir=creative)
        (creative / "header" / "a.png").write_bytes(png_header(2))
        (creative / "header" / "notes.txt").write_text("not an image")
        (self.meta / "de-DE").mkdir()
        self.assertEqual(self.validate(upload_creative=True, creative_dir=creative), {"de-DE": {}, "en-US": {}})

    def test_the_creative_folder_is_never_read_while_the_switch_is_off(self) -> None:
        self.assertEqual(self.validate(upload_listing=True, creative_dir=self.root / "missing")["en-US"]["version"],
                         {"description": "A companion"})

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
        fake = FakeAsc(version_text={"description": "Same", "keywords": "old,words", "supportUrl": "https://scowld.xyz"})
        quiet(asc_release.upload_version_fields, fake, "V1", "en-US",
              {"description": "Same", "keywords": "new,words", "supportUrl": "https://scowld.xyz"}, "listing")
        self.assertEqual(fake.writes(), [("localizations", "update", "--id", "VL1", "--keywords", "new,words")])
        # The update landed, so a second run sends nothing.
        quiet(asc_release.upload_version_fields, fake, "V1", "en-US", {"keywords": "new,words"}, "listing")
        self.assertEqual(len(fake.writes()), 1)

        unchanged = FakeAsc(version_text={"description": "Same"})
        quiet(asc_release.upload_version_fields, unchanged, "V1", "en-US", {"description": "Same"}, "listing")
        self.assertEqual(unchanged.writes(), [])

    def test_text_starting_with_an_at_sign_is_sent_literally(self) -> None:
        fake = FakeAsc(version_text={"promotionalText": "Old"})
        quiet(asc_release.upload_version_fields, fake, "V1", "en-US", {"promotionalText": "@scowld on X"}, "listing")
        self.assertEqual(flag(fake.writes()[0], "--promotional-text"), "@@scowld on X")
        self.assertEqual(fake.version_locs["V1"][0]["attributes"]["promotionalText"], "@scowld on X")

    def test_missing_localization_fails(self) -> None:
        fake = FakeAsc(locales=("de-DE",))
        with self.assertRaises(SystemExit):
            quiet(asc_release.upload_version_fields, fake, "V1", "en-US", {"description": "x"}, "listing")
        self.assertEqual(fake.writes(), [])

    def test_app_name_and_subtitle_go_to_the_editable_app_info(self) -> None:
        fake = FakeAsc(app_infos=("READY_FOR_DISTRIBUTION", "PREPARE_FOR_SUBMISSION"),
                       app_info_text={"AI1": {"name": "Scowld", "subtitle": "Old"}})
        quiet(asc_release.upload_app_info_fields, fake, APP, "en-US", {"name": "Scowld", "subtitle": "New"})
        self.assertEqual(fake.writes(), [("localizations", "update", "--type", "app-info", "--id", "IL1", "--subtitle", "New")])
        read = [c for c in fake.calls if c[:2] == ("localizations", "list")][0]
        self.assertEqual((flag(read, "--type"), flag(read, "--app-info")), ("app-info", "AI1"))

    def test_unchanged_app_info_needs_no_editable_record(self) -> None:
        fake = FakeAsc(app_infos=("READY_FOR_DISTRIBUTION",), app_info_text={"AI0": {"name": "Scowld"}})
        quiet(asc_release.upload_app_info_fields, fake, APP, "en-US", {"name": "Scowld"})
        self.assertEqual(fake.writes(), [])

    def test_changed_app_info_without_an_editable_record_fails(self) -> None:
        fake = FakeAsc(app_infos=("READY_FOR_DISTRIBUTION",), app_info_text={"AI0": {"name": "Scowld"}})
        with self.assertRaises(SystemExit):
            quiet(asc_release.upload_app_info_fields, fake, APP, "en-US", {"name": "Scowld 2"})
        self.assertEqual(fake.writes(), [])

    def test_app_info_in_a_draft_submission_is_still_editable(self) -> None:
        fake = FakeAsc(app_infos=("READY_FOR_DISTRIBUTION", "READY_FOR_REVIEW"), app_info_text={"AI1": {"subtitle": "Old"}})
        quiet(asc_release.upload_app_info_fields, fake, APP, "en-US", {"subtitle": "New"})
        self.assertEqual([flag(w, "--id") for w in fake.writes()], ["IL1"])

    def test_submitted_app_info_is_compared_when_none_is_editable(self) -> None:
        # Rerun after submitting: the live app info still has the old name, the
        # submitted one already has the new name, so nothing has to change.
        fake = FakeAsc(app_infos=("READY_FOR_DISTRIBUTION", "WAITING_FOR_REVIEW"),
                       app_info_text={"AI0": {"name": "Scowld Old"}, "AI1": {"name": "Scowld"}})
        quiet(asc_release.upload_app_info_fields, fake, APP, "en-US", {"name": "Scowld"},
              locked="version 2.0.2 is WAITING_FOR_REVIEW")
        self.assertEqual(fake.writes(), [])
        with self.assertRaises(SystemExit):
            quiet(asc_release.upload_app_info_fields, fake, APP, "en-US", {"name": "Scowld 3"},
                  locked="version 2.0.2 is WAITING_FOR_REVIEW")
        self.assertEqual(fake.writes(), [])

    def test_locked_listing_is_only_compared(self) -> None:
        fake = FakeAsc(version_text={"description": "Old"})
        quiet(asc_release.upload_version_fields, fake, "V1", "en-US", {"description": "Old"}, "listing",
              locked="version 2.0.2 is WAITING_FOR_REVIEW")
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.upload_version_fields(fake, "V1", "en-US", {"description": "New"}, "listing",
                                              locked="version 2.0.2 is WAITING_FOR_REVIEW")
        self.assertIn("listing (en-US) differs from App Store Connect (description), but version 2.0.2 "
                      "is WAITING_FOR_REVIEW", err.getvalue())
        self.assertEqual(fake.writes(), [])

    def versions(self, live_notes: str) -> FakeAsc:
        older = version_row("V0", "2.0", "READY_FOR_SALE", "2026-06-09T00:00:00Z")
        return FakeAsc(versions=[older, LIVE_VERSION, version_row("V1", VERSION, "PREPARE_FOR_SUBMISSION")],
                       live_notes=live_notes, version_text={"whatsNew": ""},
                       version_locs={"V0": [{"id": "OLDEST", "attributes": {"locale": "en-US", "whatsNew": "- New notes"}}]})

    def test_whats_new_is_uploaded_when_it_differs_from_the_live_version(self) -> None:
        fake = self.versions("- Old notes")
        quiet(asc_release.upload_whats_new, fake, APP, "V1", "en-US", "- New notes")
        self.assertEqual(fake.writes(), [("localizations", "update", "--id", "VL1", "--whats-new", "- New notes")])

    def test_stale_whats_new_from_the_live_version_is_refused(self) -> None:
        fake = self.versions("- Same notes")
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.upload_whats_new(fake, APP, "V1", "en-US", "- Same notes")
        self.assertIn("identical to live version 2.0.1", err.getvalue())
        self.assertEqual(fake.writes(), [])


class ScreenshotSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        # The manifest's order, which is not the file names' order.
        self.files = [png(Path(tmp.name) / f"{name}.png", 1260, 2736, seed=i)
                      for i, name in enumerate(("chat", "paywall", "chats"))]
        self.sums = [asc_release.md5_hex(path) for path in self.files]

    def sync(self, fake: FakeAsc, files: list[Path] | None = None, **kwargs) -> None:
        quiet(asc_release.sync_screenshot_set, fake, "VL1", "en-US", "APP_IPHONE_67", files or self.files, **kwargs)

    def test_identical_screenshots_are_left_alone(self) -> None:
        fake = FakeAsc(shots={"APP_IPHONE_67": self.sums})
        self.sync(fake)
        self.assertEqual(fake.writes(), [])

    def test_changed_screenshots_replace_the_set_in_manifest_order(self) -> None:
        fake = FakeAsc(shots={"APP_IPHONE_67": ["stale", self.sums[1]]})
        self.sync(fake)
        uploads = fake.writes()
        self.assertEqual([Path(flag(c, "--path")).name for c in uploads], ["chat.png", "paywall.png", "chats.png"])
        self.assertEqual({(flag(c, "--version-localization"), flag(c, "--device-type")) for c in uploads},
                         {("VL1", "IPHONE_67")})
        self.assertIn("--replace", uploads[0])
        self.assertIn("--confirm", uploads[0])
        for later in uploads[1:]:
            self.assertNotIn("--replace", later, "later files are appended, keeping the order")
        live = fake.sets["VL1"]["APP_IPHONE_67"]
        self.assertEqual(asc_release.checksums(live), self.sums)
        self.assertEqual([s["attributes"]["fileName"] for s in live], ["chat.png", "paywall.png", "chats.png"])
        # Now App Store Connect matches, so a rerun uploads nothing.
        self.sync(fake)
        self.assertEqual(len(fake.writes()), 3)

    def test_missing_set_is_created_by_the_upload(self) -> None:
        fake = FakeAsc()
        self.sync(fake, self.files[:1])
        self.assertEqual(len(fake.writes()), 1)
        self.assertEqual(asc_release.checksums(fake.sets["VL1"]["APP_IPHONE_67"]), self.sums[:1])

    def test_rejected_screenshot_fails_the_run(self) -> None:
        fake = FakeAsc(shots={"APP_IPHONE_67": ["stale"]}, upload_state="FAILED")
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.sync_screenshot_set(fake, "VL1", "en-US", "APP_IPHONE_67", self.files[:1])
        self.assertIn("IMAGE_INCORRECT_DIMENSIONS", err.getvalue())

    def test_an_asc_upload_failure_stops_before_the_next_file(self) -> None:
        fake = FakeAsc(shots={"APP_IPHONE_67": ["stale"]})
        original = fake.run

        def run(*args, **kwargs):
            if args[:2] == ("screenshots", "upload") and Path(flag(args, "--path")).name == "paywall.png":
                fake.calls.append(args)
                raise asc_cli.AscError(args, 1, "screenshot delivery failed: IMAGE_TOO_LARGE")
            return original(*args, **kwargs)

        fake.run = run  # type: ignore[method-assign]
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.sync_screenshot_set(fake, "VL1", "en-US", "APP_IPHONE_67", self.files)
        self.assertIn("IMAGE_TOO_LARGE", err.getvalue())
        self.assertEqual([Path(flag(c, "--path")).name for c in fake.writes()], ["chat.png", "paywall.png"])

    def test_an_upload_that_does_not_land_fails(self) -> None:
        fake = FakeAsc(shots={"APP_IPHONE_67": ["stale"]})
        original = fake.run
        fake.run = lambda *a, **k: {} if a[:2] == ("screenshots", "upload") else original(*a, **k)  # type: ignore[method-assign]
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.sync_screenshot_set(fake, "VL1", "en-US", "APP_IPHONE_67", self.files)
        self.assertIn("do not match screenshots.json", err.getvalue())

    def test_locked_set_is_only_compared(self) -> None:
        same = FakeAsc(shots={"APP_IPHONE_67": self.sums})
        self.sync(same, locked="in review")
        self.assertEqual(same.writes(), [])
        changed = FakeAsc(shots={"APP_IPHONE_67": ["stale"]})
        with self.assertRaises(SystemExit):
            self.sync(changed, locked="in review")
        self.assertEqual(changed.writes(), [])
        missing = FakeAsc()
        with self.assertRaises(SystemExit):
            self.sync(missing, locked="in review")
        self.assertEqual(missing.writes(), [], "a missing set is not created while locked")

    def sets(self, state: str) -> dict:
        return {"sets": [{"set": {"attributes": {"screenshotDisplayType": "APP_IPHONE_67"}},
                          "screenshots": [shot(self.sums[0], state=state)]}]}

    def test_screenshot_processing_times_out(self) -> None:
        clock = FakeClock(0)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            asc_release.wait_for_screenshots(SequenceAsc([self.sets("UPLOAD_COMPLETE")]), "VL1", "APP_IPHONE_67",
                                             timeout=10, now=clock.now, sleep=clock.sleep)
        self.assertGreater(clock.time, 10)

    def test_processing_is_awaited_until_every_screenshot_is_complete(self) -> None:
        client = SequenceAsc([self.sets("UPLOAD_COMPLETE"), self.sets("UPLOAD_COMPLETE"), self.sets("COMPLETE")])
        clock = FakeClock(0)
        shots = quiet(asc_release.wait_for_screenshots, client, "VL1", "APP_IPHONE_67", now=clock.now, sleep=clock.sleep)
        self.assertEqual(asc_release.checksums(shots), self.sums[:1])
        self.assertEqual(clock.sleeps, [3, 3])
        self.assertEqual({c[:2] for c in client.calls}, {("screenshots", "list")})


class CreativeAssetTests(unittest.TestCase):
    ENV = {"UPLOAD_CREATIVE_ASSETS": "true"}

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.dir = self.root / "creative"
        for folder, content in (("header", b"header-image"), ("search-results", b"search-image")):
            (self.dir / folder).mkdir(parents=True)
            (self.dir / folder / f"{folder}.png").write_bytes(content)
        self.meta = write_listing(self.root)

    def image(self, image_id: str, folder: str, state: str) -> dict:
        path = self.dir / folder / f"{folder}.png"
        return {"id": image_id, "attributes": {"fileName": path.name, "fileSize": path.stat().st_size, "state": state,
                                               "createdDate": "2026-10-20"}}

    def run_creative(self, fake: FakeAsc, env: dict[str, str] | None = None, *extra: str) -> int:
        argv = ["--version", VERSION, "--creative-dir", str(self.dir), "--metadata-dir", str(self.meta), *extra]
        return run_release(fake, env or self.ENV, argv)[0]

    def test_new_images_are_uploaded_and_reviewed_on_their_own(self) -> None:
        fake = FakeAsc()
        self.assertEqual(self.run_creative(fake), 0)
        uploads = [Path(flag(c, "--file")).name for c in fake.writes() if c[:3] == ("asset-library", "images", "upload")]
        self.assertEqual(uploads, ["header.png", "search-results.png"])
        review = [c for c in fake.writes() if c[:1] == ("review",)]
        self.assertEqual([c[:2] for c in review], [("review", "submissions-create"), ("review", "items-add"),
                                                   ("review", "items-add"), ("review", "submissions-submit")])
        self.assertEqual({flag(c, "--item-type") for c in review if c[:2] == ("review", "items-add")}, {"appAssetLibraryImages"})
        self.assertFalse([c for c in fake.writes() if c[:2] == ("localizations", "placements")])
        # Apple now reviews them: a rerun neither uploads, submits nor places anything.
        writes = len(fake.writes())
        self.assertEqual(self.run_creative(fake), 0)
        self.assertEqual(len(fake.writes()), writes)

    def test_images_in_review_are_neither_reuploaded_nor_placed(self) -> None:
        fake = FakeAsc(library=[self.image("H", "header", "WAITING_FOR_REVIEW"), self.image("S", "search-results", "IN_REVIEW")])
        self.assertEqual(self.run_creative(fake), 0)
        self.assertEqual(fake.writes(), [])

    def test_approved_images_are_placed_and_existing_ones_swapped(self) -> None:
        old = {"id": "PL-old", "attributes": {"placementType": "PRODUCT_PAGE_HEADER_ASSET"},
               "relationships": {"image": {"data": {"id": "OLDIMG"}}}}
        fake = FakeAsc(library=[self.image("H", "header", "APPROVED"), self.image("S", "search-results", "APPROVED")],
                       placements={"VL1": [old]})
        self.assertEqual(self.run_creative(fake), 0)
        swap = [c for c in fake.writes() if c[:3] == ("localizations", "placements", "swap")][0]
        self.assertEqual((flag(swap, "--image-id"), flag(swap, "--placement-id"), flag(swap, "--localization-id")),
                         ("H", "PL-old", "VL1"))
        self.assertIn("--confirm", swap)
        create = [c for c in fake.writes() if c[:3] == ("localizations", "placements", "create")][0]
        self.assertEqual((flag(create, "--image-id"), flag(create, "--placement-type"), flag(create, "--placement-group")),
                         ("S", "APP_STORE_SEARCH_RESULTS_ASSET", "DEFAULT_PROFILE"))
        # A second run finds both placed and writes nothing.
        writes = len(fake.writes())
        self.assertEqual(self.run_creative(fake), 0)
        self.assertEqual(len(fake.writes()), writes)

    def test_approved_images_go_on_every_repository_locale(self) -> None:
        write_listing(self.root, locales=("en-US", "de-DE"))
        fake = FakeAsc(locales=("en-US", "de-DE"),
                       library=[self.image("H", "header", "APPROVED"), self.image("S", "search-results", "APPROVED")])
        self.assertEqual(self.run_creative(fake), 0)
        placed = sorted((flag(c, "--localization-id"), flag(c, "--image-id")) for c in fake.writes())
        self.assertEqual(placed, [("VL1", "H"), ("VL1", "S"), ("VL2", "H"), ("VL2", "S")])

    def test_a_locale_the_version_lacks_fails_before_anything_is_written(self) -> None:
        write_listing(self.root, locales=("en-US", "de-DE"))
        fake = FakeAsc(library=[self.image("H", "header", "APPROVED")])
        self.assertEqual(self.run_creative(fake), 1)
        self.assertEqual(fake.writes(), [])

    def test_an_image_with_alpha_fails_before_any_call(self) -> None:
        for content in (png_header(6), png_header(2, trns=True)):
            (self.dir / "header" / "header.png").write_bytes(content)
            fake = FakeAsc()
            with self.subTest(content=content[25:26]):
                self.assertEqual(self.run_creative(fake), 1)
                self.assertEqual(fake.calls, [])

    def test_a_rejected_image_stops_the_run(self) -> None:
        fake = FakeAsc(library=[self.image("H", "header", "REJECTED")])
        self.assertEqual(self.run_creative(fake), 1)
        self.assertEqual(fake.writes(), [])

    def test_a_locked_version_takes_no_new_images(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9")
        self.assertEqual(self.run_creative(fake), 1)
        self.assertEqual(fake.writes(), [])

    def test_a_locked_version_sends_nothing_to_review(self) -> None:
        for state in ("WAITING_FOR_REVIEW", "READY_FOR_REVIEW"):
            for image_state in ("UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION"):
                fake = FakeAsc(state=state, attached="B9", library=[self.image("H", "header", image_state)])
                with self.subTest(state=state, image_state=image_state):
                    self.assertEqual(self.run_creative(fake), 1)
                    self.assertEqual(fake.writes(), [])

    def test_a_locked_version_passes_when_nothing_has_to_change(self) -> None:
        placed = {"id": "PL-H", "attributes": {"placementType": "PRODUCT_PAGE_HEADER_ASSET"},
                  "relationships": {"image": {"data": {"id": "H"}}}}
        for state in ("WAITING_FOR_REVIEW", "READY_FOR_REVIEW"):
            fake = FakeAsc(state=state, attached="B9", placements={"VL1": [placed]},
                           library=[self.image("H", "header", "APPROVED"), self.image("S", "search-results", "IN_REVIEW")])
            with self.subTest(state=state):
                self.assertEqual(self.run_creative(fake), 0)
                self.assertEqual(fake.writes(), [])
            fake = FakeAsc(state=state, attached="B9", library=[self.image("H", "header", "APPROVED")])
            with self.subTest(state=state, placed=False):
                self.assertEqual(self.run_creative(fake), 1, "placing an image is a change")
                self.assertEqual(fake.writes(), [])

    def test_a_retry_finishes_the_creative_draft_it_left_behind(self) -> None:
        library = [self.image("H", "header", "PREPARE_FOR_SUBMISSION"), self.image("S", "search-results", "PREPARE_FOR_SUBMISSION")]
        fake = FakeAsc(library=library, drafts=["OLD"], draft_items={"OLD": [item("I-H", "appAssetLibraryImage", "H")]})
        self.assertEqual(self.run_creative(fake), 0)
        self.assertNotIn(("review", "submissions-create"), [c[:2] for c in fake.writes()])
        self.assertEqual(flag(fake.writes()[-1], "--id"), "OLD")
        # A draft holding anything else is left alone and a new one is used.
        library = [self.image("H", "header", "PREPARE_FOR_SUBMISSION"), self.image("S", "search-results", "PREPARE_FOR_SUBMISSION")]
        fake = FakeAsc(library=library, drafts=["VERSION"], draft_items={"VERSION": [item("X", "appStoreVersion", "V1")]})
        self.assertEqual(self.run_creative(fake), 0)
        self.assertNotEqual(flag(fake.writes()[-1], "--id"), "VERSION")

    def test_a_creative_submission_with_other_items_is_not_submitted(self) -> None:
        fake = FakeAsc()
        original = fake.run

        def run(*args, **kwargs):
            result = original(*args, **kwargs)
            if args[:2] == ("review", "submissions-create"):
                fake.items[result["data"]["id"]] = [item("X", "appStoreVersion", "V1")]
            return result

        fake.run = run  # type: ignore[method-assign]
        self.assertEqual(self.run_creative(fake), 1)
        self.assertNotIn(("review", "submissions-submit"), [c[:2] for c in fake.writes()])

    def test_creative_and_version_reviews_stay_separate(self) -> None:
        fake = FakeAsc()
        code = self.run_creative(fake, {**self.ENV, "SUBMIT_IOS_REVIEW": "true"}, "--build-id", "B9", "--build-number", "14")
        self.assertEqual(code, 0)
        self.assertEqual(fake.submitted, ["SUB1", "SUB2"])
        self.assertEqual({asc_release.related_id(i, "appAssetLibraryImage") for i in fake.items["SUB1"]}, {"IMG1", "IMG2"})
        self.assertEqual([asc_release.related_id(i, "appStoreVersion") for i in fake.items["SUB2"]], ["V1"])

    def test_switch_off_never_touches_creative_assets(self) -> None:
        fake = FakeAsc(version_text={"description": "Old"})
        code, output = run_release(fake, {"UPLOAD_LISTING": "true"},
                                   ["--version", VERSION, "--creative-dir", str(self.root / "missing"),
                                    "--metadata-dir", str(self.meta)])
        self.assertEqual(code, 0, output)
        self.assertFalse([c for c in fake.calls if c[0] == "asset-library" or c[:2] == ("localizations", "placements")])


# MARK: - Build selection and review submission


class BuildSelectionTests(unittest.TestCase):
    def test_selects_and_reads_back_this_runs_build(self) -> None:
        fake = FakeAsc()
        quiet(asc_release.select_build, fake, "V1", "B9", VERSION, "14")
        self.assertEqual(fake.attached, "B9")
        self.assertEqual([c[:2] for c in fake.calls], [("builds", "list"), ("versions", "attach-build"), ("versions", "view")])
        query = fake.calls[0]
        self.assertEqual((flag(query, "--app"), flag(query, "--build-number"), flag(query, "--version")), (APP, "14", VERSION))
        self.assertEqual(flag(fake.calls[1], "--build-id"), "B9")

    def test_selection_that_does_not_stick_fails(self) -> None:
        fake = FakeAsc(sticky=False)
        with self.assertRaises(SystemExit):
            quiet(asc_release.select_build, fake, "V1", "B9", VERSION, "14")

    def test_unprocessed_expired_or_wrong_build_is_refused(self) -> None:
        cases = {
            "processing": ([build_row("B9", state="PROCESSING")], [pre_row()]),
            "expired": ([build_row("B9", expired=True)], [pre_row()]),
            "number": ([build_row("B9", number="15")], [pre_row()]),
            "version": ([build_row("B9")], [pre_row(version="2.0.1")]),
            "platform": ([build_row("B9")], [pre_row(platform="MAC_OS")]),
            "missing": ([build_row("B8")], [pre_row()]),
        }
        for label, (builds, included) in cases.items():
            fake = FakeAsc(builds={"data": builds, "included": included})
            with self.subTest(label), self.assertRaises(SystemExit):
                quiet(asc_release.select_build, fake, "V1", "B9", VERSION, "14")
            self.assertEqual(fake.writes(), [], label)

    def test_release_type(self) -> None:
        for public, expected in ((True, "AFTER_APPROVAL"), (False, "MANUAL")):
            fake = FakeAsc()
            quiet(asc_release.set_release_type, fake, "V1", public_release=public)
            self.assertEqual(fake.writes(), [("versions", "update", "--version-id", "V1", "--release-type", expected)])


SUBMIT_ARGS = ["--version", VERSION, "--build-id", "B9", "--build-number", "14"]


class LiveSubmitFlowTests(unittest.TestCase):
    def run_main(self, fake: FakeAsc, **flags: str) -> tuple[int, str]:
        return run_release(fake, {"SUBMIT_IOS_REVIEW": "true", **flags}, SUBMIT_ARGS)

    def test_selects_rechecks_then_submits(self) -> None:
        fake = FakeAsc()
        code, output = self.run_main(fake)
        self.assertEqual(code, 0, output)
        self.assertEqual(fake.modes, [False])
        names = [c[:2] for c in fake.calls]
        select = names.index(("versions", "attach-build"))
        submit = names.index(("review", "submissions-submit"))
        reads = [i for i, n in enumerate(names) if n == ("versions", "view")]
        build_checks = [i for i, n in enumerate(names) if n == ("builds", "list")]
        self.assertEqual(len(reads), 2, "selection must be read back and rechecked")
        self.assertTrue(select < reads[0] < reads[1] < submit)
        self.assertEqual(len(build_checks), 2)
        self.assertTrue(build_checks[1] < reads[1] < submit, "build must be re-verified just before submit")
        self.assertIn(("versions", "update"), names)  # release type
        add = names.index(("review", "items-add"))
        self.assertEqual((flag(fake.calls[add], "--item-type"), flag(fake.calls[add], "--item-id")), ("appStoreVersions", "V1"))
        create = names.index(("review", "submissions-create"))
        self.assertTrue(reads[1] < create < add, "the draft is created only right before the version is added")
        self.assertLess(names.index(("review", "submissions-list")), select, "the draft is checked before any change")
        self.assertTrue(any(add < i < submit for i, n in enumerate(names) if n == ("review", "items-list")),
                        "the draft is re-read right before it is submitted")
        product_check = names.index(("subscriptions", "list"))
        self.assertLess(product_check, select, "products are checked before anything is changed")
        self.assertLess(names.index(("iap", "list")), select)
        self.assertEqual(fake.submitted, ["SUB1"])

    def test_selection_changed_before_submit_aborts(self) -> None:
        fake = FakeAsc(revert_after_select=True)
        code, _ = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertEqual(fake.submitted, [])

    def test_waiting_for_review_with_another_build_aborts(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="OTHER")
        code, _ = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertEqual(fake.writes(), [])

    def test_waiting_for_review_with_this_build_is_idempotent(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9")
        code, output = self.run_main(fake)
        self.assertEqual(code, 0, output)
        self.assertEqual(fake.writes(), [], "nothing is changed on a rerun")

    def test_non_submittable_version_is_refused(self) -> None:
        for state in ("READY_FOR_SALE", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
            fake = FakeAsc(state=state)
            code, _ = self.run_main(fake)
            with self.subTest(state=state):
                self.assertEqual(code, 1)
                self.assertEqual(fake.writes(), [])

    def test_missing_version_tells_how_to_fix_it(self) -> None:
        fake = FakeAsc(versions=[LIVE_VERSION])
        code, output = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("create version 2.0.2", output)

    def test_pending_in_app_products_block_submission(self) -> None:
        cases = (
            {"subscriptions": [{"id": "S1", "attributes": {"productId": "com.apoorvdarshan.Scowld.premium.weekly",
                                                           "state": "READY_TO_SUBMIT"}}]},
            {"iaps": [{"id": "I1", "attributes": {"productId": "com.apoorvdarshan.Scowld.minutes.20",
                                                  "state": "DEVELOPER_REJECTED"}}]},
        )
        for products in cases:
            fake = FakeAsc(**products)
            code, output = self.run_main(fake)
            with self.subTest(products=products):
                self.assertEqual(code, 1)
                self.assertIn("com.apoorvdarshan.Scowld.", output)
                self.assertIn("does not submit in-app purchases", output)
                self.assertEqual(fake.writes(), [])

    def test_pending_products_stop_the_run_before_the_listing_changes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            meta = write_listing(Path(tmp))
            fake = FakeAsc(version_text={"description": "Old"},
                           subscriptions=[{"id": "S1", "attributes": {"productId": "plus", "state": "READY_TO_SUBMIT"}}])
            code, _ = run_release(fake, {"SUBMIT_IOS_REVIEW": "true", "UPLOAD_LISTING": "true"},
                                  [*SUBMIT_ARGS, "--metadata-dir", str(meta)])
        self.assertEqual(code, 1)
        self.assertEqual(fake.writes(), [], "listing untouched when submission is blocked")

    def test_approved_products_do_not_block(self) -> None:
        fake = FakeAsc(subscriptions=[{"id": "S1", "attributes": {"productId": "p", "state": "APPROVED"}}],
                       iaps=[{"id": "I1", "attributes": {"productId": "q", "state": "APPROVED"}}])
        self.assertEqual(self.run_main(fake)[0], 0)

    def test_draft_with_unrelated_items_is_not_submitted(self) -> None:
        for stray in (item("EVENT1", "appStoreVersion", ""), item("IAP-ITEM", "inAppPurchaseVersion", "OTHER-IAPv1")):
            fake = FakeAsc(drafts=["SUB1"], draft_items={"SUB1": [stray]})
            code, output = self.run_main(fake)
            with self.subTest(stray=stray["id"]):
                self.assertEqual(code, 1)
                self.assertIn(stray["id"], output)
                self.assertEqual(fake.writes(), [], "the draft is checked before anything is changed")

    def test_a_rerun_with_nothing_to_send_leaves_no_empty_draft(self) -> None:
        # Already submitted: nothing to add, so no draft is created.
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9")
        self.assertEqual(self.run_main(fake)[0], 0)
        self.assertEqual(fake.writes(), [])
        # A run that stops at the selection recheck never created a draft either.
        fake = FakeAsc(revert_after_select=True)
        self.assertEqual(self.run_main(fake)[0], 1)
        self.assertNotIn(("review", "submissions-create"), [c[:2] for c in fake.writes()])
        self.assertEqual(fake.drafts, [])

    def test_a_draft_without_this_version_is_never_submitted(self) -> None:
        # The version does not land in the draft (asc skips it): the read before
        # submitting refuses the draft.
        fake = FakeAsc(drafts=["D1"], draft_items={"D1": []})
        original = fake.run
        fake.run = lambda *a, **k: {"data": {}} if a[:2] == ("review", "items-add") else original(*a, **k)  # type: ignore[method-assign]
        code, output = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("does not hold App Store version V1", output)
        self.assertEqual(fake.submitted, [])
        # READY_FOR_REVIEW says a draft already holds the version; when no usable
        # draft does, nothing is added, created, selected or submitted.
        for drafts, items in (([], {}), (["D1"], {"D1": []}),
                              (["IMAGES"], {"IMAGES": [item("I", "appAssetLibraryImage", "H"),
                                                       item("V", "appStoreVersion", "V1")]})):
            fake = FakeAsc(state="READY_FOR_REVIEW", drafts=drafts, draft_items=items)
            code, output = self.run_main(fake)
            with self.subTest(drafts=drafts):
                self.assertEqual(code, 1)
                self.assertIn("READY_FOR_REVIEW, but no draft review submission", output)
                self.assertEqual(fake.writes(), [])

    def test_a_reused_draft_with_items_this_release_did_not_choose_is_not_submitted(self) -> None:
        # Scowld submits nothing but the version. An item added by hand after the
        # draft was picked up is caught by the read right before submitting.
        fake = FakeAsc(drafts=["SUB1"], draft_items={"SUB1": []})
        original = fake.run

        def run(*args, **kwargs):
            result = original(*args, **kwargs)
            if args[:2] == ("review", "items-add"):
                fake.items["SUB1"].append(item("BY-HAND", "subscriptionVersion", "SUBv9"))
            return result

        fake.run = run  # type: ignore[method-assign]
        code, output = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("holds items this release did not choose (BY-HAND)", output)
        self.assertEqual(fake.submitted, [])

    def test_draft_already_holding_this_version_is_reused(self) -> None:
        fake = FakeAsc(drafts=["SUB1"], draft_items={"SUB1": [item("I1", "appStoreVersion", "V1")]})
        self.assertEqual(self.run_main(fake)[0], 0)
        self.assertNotIn(("review", "items-add"), [c[:2] for c in fake.writes()])
        self.assertEqual(fake.submitted, ["SUB1"])

    def test_several_drafts_are_ambiguous(self) -> None:
        fake = FakeAsc(drafts=["SUB1", "SUB2"])
        code, output = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("ambiguous", output)
        self.assertEqual(fake.writes(), [])

    def test_new_draft_is_created_for_ios(self) -> None:
        fake = FakeAsc()
        self.assertEqual(self.run_main(fake)[0], 0)
        create = [c for c in fake.writes() if c[:2] == ("review", "submissions-create")][0]
        self.assertEqual((flag(create, "--app"), flag(create, "--platform")), (APP, "IOS"))

    def test_a_creative_draft_is_never_used_for_the_version(self) -> None:
        creative = [item("IMG", "appAssetLibraryImage", "H")]
        fake = FakeAsc(drafts=["CREATIVE"], draft_items={"CREATIVE": creative})
        self.assertEqual(self.run_main(fake)[0], 0)
        self.assertIn(("review", "submissions-create"), [c[:2] for c in fake.writes()])
        self.assertEqual(fake.submitted, ["SUB2"])
        # Next to the version's own draft it is not counted either (no ambiguity).
        fake = FakeAsc(drafts=["CREATIVE", "D1"], draft_items={"CREATIVE": creative, "D1": []})
        self.assertEqual(self.run_main(fake)[0], 0)
        self.assertEqual(fake.submitted, ["D1"])

    def test_public_release_sets_after_approval(self) -> None:
        fake = FakeAsc()
        self.assertEqual(self.run_main(fake, PUBLIC_RELEASE="true")[0], 0)
        update = [c for c in fake.writes() if c[:2] == ("versions", "update")][0]
        self.assertEqual(flag(update, "--release-type"), "AFTER_APPROVAL")


class RerunTests(unittest.TestCase):
    """'Re-run failed jobs' after the version reached a draft or a submitted review."""

    def fake(self, *, state: str, info_state: str, whats_new: str = "- New notes", attached: str = "B9",
             screenshot_sums: list[str] | None = None) -> FakeAsc:
        # The live app info still has the old name; the one submitted with 2.0.2 has the new one.
        return FakeAsc(state=state, attached=attached, version_text={"description": "A companion", "whatsNew": whats_new},
                       app_infos=("READY_FOR_DISTRIBUTION", info_state),
                       app_info_text={"AI0": {"name": "Scowld Old"}, "AI1": {"name": "Scowld"}},
                       shots={"APP_IPHONE_67": screenshot_sums} if screenshot_sums is not None else None,
                       drafts=["SUB1"], draft_items={"SUB1": [item("I1", "appStoreVersion", "V1")]})

    def run_main(self, fake: FakeAsc, *, screenshots: bool = False) -> tuple[int, str]:
        env = {"UPLOAD_LISTING": "true", "UPLOAD_WHATS_NEW": "true", "SUBMIT_IOS_REVIEW": "true"}
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = None
            if screenshots:
                png(root / "shots" / "a.png", 1260, 2736)
                manifest = {"APP_IPHONE_67": ["shots/a.png"]}
                env["UPLOAD_SCREENSHOTS"] = "true"
            meta = write_listing(root, screenshots=manifest)
            return run_release(fake, env, [*SUBMIT_ARGS, "--metadata-dir", str(meta)], root=root)

    def test_draft_submission_rerun_updates_text_then_submits(self) -> None:
        fake = self.fake(state="READY_FOR_REVIEW", info_state="READY_FOR_REVIEW", whats_new="")
        code, output = self.run_main(fake)
        self.assertEqual(code, 0, output)
        update = [c for c in fake.writes() if c[:2] == ("localizations", "update")]
        self.assertEqual([(flag(c, "--id"), flag(c, "--whats-new")) for c in update], [("VL1", "- New notes")],
                         "What's New is still editable")
        self.assertEqual(fake.writes()[-1], ("review", "submissions-submit", "--id", "SUB1", "--confirm"))
        self.assertNotIn(("review", "items-add"), [c[:2] for c in fake.writes()], "the draft already holds the version")

    def test_submitted_rerun_with_matching_listing_changes_nothing(self) -> None:
        fake = self.fake(state="WAITING_FOR_REVIEW", info_state="WAITING_FOR_REVIEW")
        code, output = self.run_main(fake)
        self.assertEqual(code, 0, output)
        self.assertEqual(fake.writes(), [])

    def test_submitted_rerun_refuses_a_change_it_cannot_make(self) -> None:
        fake = self.fake(state="WAITING_FOR_REVIEW", info_state="WAITING_FOR_REVIEW", whats_new="- Other notes")
        code, output = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("What's New (en-US) differs from App Store Connect (whatsNew)", output)
        self.assertIn("WAITING_FOR_REVIEW", output)
        self.assertEqual(fake.writes(), [])

    def test_submitted_rerun_with_another_build_in_review_fails(self) -> None:
        fake = self.fake(state="WAITING_FOR_REVIEW", info_state="WAITING_FOR_REVIEW", attached="OTHER")
        code, output = self.run_main(fake)
        self.assertEqual(code, 1)
        self.assertIn("expected B9", output)
        self.assertEqual(fake.writes(), [])

    def test_screenshots_that_cannot_change_fail_before_any_write(self) -> None:
        # The listing would change (allowed in a draft), but the screenshots differ too
        # (not allowed): nothing is written at all.
        fake = self.fake(state="READY_FOR_REVIEW", info_state="READY_FOR_REVIEW", whats_new="", screenshot_sums=["old"])
        code, output = self.run_main(fake, screenshots=True)
        self.assertEqual(code, 1)
        self.assertIn("screenshots can no longer change", output)
        self.assertEqual(fake.writes(), [])

    def test_unchanged_screenshots_pass_in_a_draft_submission(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            checksum = asc_release.md5_hex(png(Path(tmp) / "a.png", 1260, 2736))
        fake = self.fake(state="READY_FOR_REVIEW", info_state="READY_FOR_REVIEW", screenshot_sums=[checksum])
        code, output = self.run_main(fake, screenshots=True)
        self.assertEqual(code, 0, output)
        self.assertNotIn(("screenshots", "upload"), [c[:2] for c in fake.writes()], "screenshots untouched")


class PreflightTests(unittest.TestCase):
    """Read-only checks that run before the build is uploaded."""

    def fake(self, *, state: str = "PREPARE_FOR_SUBMISSION", live_notes: str = "- Old notes",
             versions: list[dict] | None = None, products: list[dict] | None = None,
             version_locales: tuple[str, ...] = ("en-US",), app_info_locales: tuple[str, ...] = ("en-US",),
             screenshot_sums: list[str] | None = None, **extra: Any) -> FakeAsc:
        return FakeAsc(state=state, live_notes=live_notes, versions=versions, subscriptions=products,
                       locales=version_locales, app_info_locales=app_info_locales,
                       shots={"APP_IPHONE_67": screenshot_sums} if screenshot_sums is not None else None, **extra)

    def run_preflight(self, fake: FakeAsc, *extra: str, **flags: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.shot = png(root / "shots" / "a.png", 1260, 2736)
            meta = write_listing(root, screenshots={"APP_IPHONE_67": ["shots/a.png"]})
            code, output = run_release(fake, flags, ["--preflight", "--version", VERSION, "--metadata-dir", str(meta), *extra],
                                       root=root)
        self.assertTrue(all(fake.modes), "the preflight runs asc read-only")
        self.assertEqual(fake.writes(), [])
        return code, output

    def test_ready_version_passes_with_reads_only(self) -> None:
        fake = self.fake()
        code, output = self.run_preflight(fake, UPLOAD_LISTING="true", UPLOAD_WHATS_NEW="true", SUBMIT_IOS_REVIEW="true")
        self.assertEqual(code, 0, output)
        self.assertEqual(fake.modes, [True])

    def test_missing_version_fails_before_the_build(self) -> None:
        code, output = self.run_preflight(self.fake(versions=[LIVE_VERSION]), UPLOAD_LISTING="true")
        self.assertEqual(code, 1)
        self.assertIn("create version 2.0.2", output)

    def test_version_that_cannot_change_fails(self) -> None:
        code, output = self.run_preflight(self.fake(state="WAITING_FOR_REVIEW"), SUBMIT_IOS_REVIEW="true")
        self.assertEqual(code, 1)
        self.assertIn("cannot be submitted", output)
        for state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
            code, output = self.run_preflight(self.fake(state=state), UPLOAD_LISTING="true")
            with self.subTest(state=state):
                self.assertEqual(code, 1)
                self.assertIn("not editable", output)

    def test_missing_locale_fails_before_the_build(self) -> None:
        code, output = self.run_preflight(self.fake(version_locales=("de-DE",)), UPLOAD_WHATS_NEW="true")
        self.assertEqual(code, 1)
        self.assertIn("version has no en-US localization", output)
        code, output = self.run_preflight(self.fake(app_info_locales=("de-DE",)), UPLOAD_LISTING="true")
        self.assertEqual(code, 1)
        self.assertIn("app info has no en-US localization", output)

    def test_draft_submission_still_takes_text_and_unchanged_screenshots(self) -> None:
        # READY_FOR_REVIEW: listing and What's New can still change, screenshots cannot.
        code, output = self.run_preflight(self.fake(state="READY_FOR_REVIEW"), UPLOAD_LISTING="true",
                                          UPLOAD_WHATS_NEW="true", SUBMIT_IOS_REVIEW="true")
        self.assertEqual(code, 0, output)
        code, output = self.run_preflight(self.fake(state="READY_FOR_REVIEW", screenshot_sums=["old"]),
                                          UPLOAD_SCREENSHOTS="true")
        self.assertEqual(code, 1)
        self.assertIn("screenshots APP_IPHONE_67 (en-US) differs", output)
        self.assertIn("READY_FOR_REVIEW", output)

    def test_unchanged_screenshots_pass_in_a_draft_submission(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            checksum = asc_release.md5_hex(png(Path(tmp) / "a.png", 1260, 2736))
        code, output = self.run_preflight(self.fake(state="READY_FOR_REVIEW", screenshot_sums=[checksum]),
                                          UPLOAD_SCREENSHOTS="true")
        self.assertEqual(code, 0, output)

    def test_stale_whats_new_fails_before_the_build(self) -> None:
        code, output = self.run_preflight(self.fake(live_notes="- New notes"), UPLOAD_WHATS_NEW="true")
        self.assertEqual(code, 1)
        self.assertIn("identical to live version 2.0.1", output)

    def test_pending_products_fail_before_the_build(self) -> None:
        products = [{"id": "S1", "attributes": {"productId": "plus", "state": "READY_TO_SUBMIT"}}]
        code, output = self.run_preflight(self.fake(products=products), SUBMIT_IOS_REVIEW="true")
        self.assertEqual(code, 1)
        self.assertIn("plus", output)

    def test_preflight_does_not_need_a_build(self) -> None:
        code, output = self.run_preflight(self.fake(), SUBMIT_IOS_REVIEW="true", PUBLIC_RELEASE="true")
        self.assertEqual(code, 0, output)

    def test_creative_assets_are_checked_without_writing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            creative = Path(tmp)
            (creative / "header").mkdir()
            (creative / "header" / "header.png").write_bytes(b"header-image")
            args = ("--creative-dir", str(creative))
            # An editable version: images are uploaded and placed by the live run only.
            fake = self.fake()
            code, output = self.run_preflight(fake, *args, UPLOAD_CREATIVE_ASSETS="true")
            self.assertEqual(code, 0, output)
            self.assertFalse([c for c in fake.calls if c[0] == "asset-library"])
            # A version in a draft submission can take no new image: fail before the build.
            code, output = self.run_preflight(self.fake(state="READY_FOR_REVIEW"), *args, UPLOAD_CREATIVE_ASSETS="true")
            self.assertEqual(code, 1)
            self.assertIn("cannot upload the product page header image", output)
            in_review = {"id": "H", "attributes": {"fileName": "header.png", "fileSize": len(b"header-image"),
                                                   "state": "IN_REVIEW", "createdDate": "z"}}
            code, output = self.run_preflight(self.fake(state="READY_FOR_REVIEW", library=[in_review]), *args,
                                              UPLOAD_CREATIVE_ASSETS="true")
            self.assertEqual(code, 0, output)
            code, output = self.run_preflight(self.fake(version_locales=("de-DE",)), *args, UPLOAD_CREATIVE_ASSETS="true")
            self.assertEqual(code, 1)
            self.assertIn("version has no en-US localization", output)


class CreateVersionTests(unittest.TestCase):
    """--create-version (IOS_CREATE_VERSION): add the tag's App Store version only when it is missing."""

    ON = {"CREATE_IOS_VERSION": "true"}

    def create(self, fake: FakeAsc, flags: dict[str, str] | None = None, *args: str) -> tuple[int, str]:
        return run_release(fake, self.ON if flags is None else flags, ["--create-version", *(args or ("--version", VERSION))])

    def test_switch_off_makes_no_calls(self) -> None:
        fake = FakeAsc(versions=[LIVE_VERSION])
        code, output = self.create(fake, {})
        self.assertEqual(code, 0, output)
        self.assertIn("skipped", output)
        self.assertEqual(fake.calls, [])

    def test_existing_version_is_left_alone(self) -> None:
        fake = FakeAsc(versions=[LIVE_VERSION, version_row("V1", VERSION, "READY_FOR_REVIEW")])
        code, output = self.create(fake)
        self.assertEqual(code, 0, output)
        self.assertIn(f"{VERSION} already exists (READY_FOR_REVIEW)", output)
        self.assertEqual(fake.writes(), [])

    def test_missing_version_is_created_for_this_app_and_read_back(self) -> None:
        fake = FakeAsc(versions=[LIVE_VERSION])
        code, output = self.create(fake)
        self.assertEqual(code, 0, output)
        self.assertEqual(fake.writes(), [("versions", "create", "--app", APP, "--version", VERSION, "--platform", "IOS")])
        self.assertEqual(fake.calls[0], ("apps", "view", "--id", APP), "the pinned app is checked first")
        self.assertEqual(fake.calls[-1][:2], ("versions", "list"), "the created version must be read back")
        self.assertIn(f"created App Store version {VERSION} (PREPARE_FOR_SUBMISSION)", output)
        self.assertEqual(fake.modes, [False])

    def test_another_version_on_its_way_blocks_creation(self) -> None:
        for state in ("PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
            with self.subTest(state=state):
                fake = FakeAsc(versions=[version_row("V0", "2.0", "READY_FOR_SALE"), version_row("V1", "2.0.1", state)])
                code, output = self.create(fake)
                self.assertEqual(code, 1)
                self.assertIn(f"is still {state}", output)
                self.assertIn("nothing was changed", output)
                self.assertEqual(fake.writes(), [])

    def test_version_not_newer_than_an_existing_one_is_refused(self) -> None:
        for existing in ("2.1", "2.0.10", "3"):
            with self.subTest(existing=existing):
                fake = FakeAsc(versions=[version_row("V0", existing, "READY_FOR_SALE")])
                code, output = self.create(fake)
                self.assertEqual(code, 1)
                self.assertIn(f"not newer than the existing version {existing}", output)
                self.assertEqual(fake.writes(), [])
        # 2.1 and 2.1.0 are the same version to the App Store.
        fake = FakeAsc(versions=[version_row("V0", "2.1.0", "READY_FOR_SALE")])
        code, output = self.create(fake, None, "--version", "2.1")
        self.assertEqual(code, 1)
        self.assertEqual(fake.writes(), [])

    def test_older_finished_versions_allow_creation(self) -> None:
        fake = FakeAsc(versions=[version_row("V0", "1.0", "REPLACED_WITH_NEW_VERSION"), version_row("V1", "1.1", "REMOVED_FROM_SALE"),
                                 version_row("V2", "1.2", "DEVELOPER_REMOVED_FROM_SALE"), LIVE_VERSION])
        code, output = self.create(fake)
        self.assertEqual(code, 0, output)
        self.assertEqual([c[:2] for c in fake.writes()], [("versions", "create")])

    def test_other_app_or_bad_version_fails_without_writing(self) -> None:
        for fake, message in ((FakeAsc(versions=[LIVE_VERSION], app_id="1234567890"), f"expected {APP}"),
                              (FakeAsc(versions=[LIVE_VERSION], bundle="com.apoorvdarshan.Scowld.widget"),
                               f"expected {BUNDLE}")):
            code, output = self.create(fake)
            with self.subTest(message=message):
                self.assertEqual(code, 1)
                self.assertIn(message, output)
                self.assertEqual(fake.writes(), [])
        for bad in ("2.0.2-beta", "v2.0.2", "2.0.2.1", "٢.٠"):
            with self.subTest(bad=bad):
                fake = FakeAsc(versions=[LIVE_VERSION])
                code, output = self.create(fake, None, "--version", bad)
                self.assertEqual(code, 1)
                self.assertIn("must look like", output)
                self.assertEqual(fake.calls, [])

    def test_needs_a_version_and_dry_run_makes_no_calls(self) -> None:
        fake = FakeAsc(versions=[LIVE_VERSION])
        code, output = self.create(fake, None, "--dry-run")
        self.assertEqual(code, 1)
        self.assertIn("needs --version", output)
        code, output = self.create(fake, None, "--dry-run", "--version", VERSION)
        self.assertEqual(code, 0, output)
        self.assertIn("would create", output)
        self.assertEqual(fake.calls, [])
        self.assertEqual(fake.modes, [], "no asc is even set up")

    def test_dry_run_rejects_a_bad_version_like_a_live_run(self) -> None:
        for bad in ("2.0.2-beta", "v2.0.2", "2.0.2.1"):
            with self.subTest(bad=bad):
                fake = FakeAsc(versions=[LIVE_VERSION])
                code, output = self.create(fake, None, "--dry-run", "--version", bad)
                self.assertEqual(code, 1)
                self.assertIn("must look like", output)
                self.assertEqual((fake.calls, fake.modes), ([], []))

    def test_create_version_never_runs_together_with_the_preflight(self) -> None:
        for flags in (self.ON, {}, {**self.ON, "SUBMIT_IOS_REVIEW": "true", "UPLOAD_LISTING": "true"}):
            with self.subTest(flags=flags):
                fake = FakeAsc(versions=[LIVE_VERSION])
                code, output = self.create(fake, flags, "--preflight", "--version", VERSION)
                self.assertEqual(code, 1)
                self.assertIn("separate steps", output)
                self.assertEqual(fake.calls, [])

    def test_a_created_version_that_does_not_read_back_fails_naming_it(self) -> None:
        for found in (0, 2):  # App Store Connect does not list it yet / lists it twice
            with self.subTest(found=found):
                fake = FakeAsc(versions=[LIVE_VERSION], created_rows=found)
                code, output = self.create(fake)
                self.assertEqual(code, 1)
                self.assertIn(f"created App Store version {VERSION}, but reading it back found {found} records", output)
                self.assertIn("check it in App Store Connect before rerunning", output)
                self.assertNotIn("IOS_CREATE_VERSION", output)
                self.assertEqual([c[:2] for c in fake.writes()], [("versions", "create")])


class MainArgumentTests(unittest.TestCase):
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

    def test_only_the_scowld_bundle_is_supported(self) -> None:
        code, output = self.run_cli({"UPLOAD_LISTING": "true"}, "--bundle-id", "com.example.other")
        self.assertEqual(code, 1)
        self.assertIn("Scowld iOS bundle", output)

    def test_dry_run_never_creates_an_asc(self) -> None:
        # Its own files: the committed ones are checked by @committed_files_test tests.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            png(root / "shots" / "a.png", 1260, 2736)
            meta = write_listing(root, screenshots={"APP_IPHONE_67": ["shots/a.png"]})
            (root / "creative" / "header").mkdir(parents=True)
            (root / "creative" / "header" / "header.png").write_bytes(b"header-image")
            with mock.patch.object(asc_release, "asc_from_environment", side_effect=AssertionError("network")), \
                    mock.patch.object(asc_release, "ROOT", root):
                code, output = self.run_cli({"UPLOAD_LISTING": "true", "UPLOAD_SCREENSHOTS": "true",
                                             "UPLOAD_CREATIVE_ASSETS": "true"},
                                            "--metadata-dir", str(meta), "--creative-dir", str(root / "creative"))
        self.assertEqual(code, 0, output)
        self.assertIn("no asc calls", output)
        self.assertIn("creative=True", output)

    def test_creative_assets_need_an_image(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            meta = write_listing(Path(tmp))
            creative = Path(tmp) / "creative"
            code, output = self.run_cli({"UPLOAD_CREATIVE_ASSETS": "true"}, "--metadata-dir", str(meta),
                                        "--creative-dir", str(creative))
            self.assertEqual(code, 1)
            self.assertIn("no header or search results image", output)
            (creative / "search-results").mkdir(parents=True)
            (creative / "search-results" / "search.png").write_bytes(b"x")
            code, output = self.run_cli({"UPLOAD_CREATIVE_ASSETS": "true"}, "--metadata-dir", str(meta),
                                        "--creative-dir", str(creative))
            self.assertEqual(code, 0, output)


class ExportListingTests(unittest.TestCase):
    def test_export_writes_the_live_listing_with_read_only_asc(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            chat = png(root / "shots" / "chat.png", 1260, 2736)
            known = asc_release.md5_hex(chat)
            text = {"locale": "en-US", "description": "A companion", "keywords": "ai,voice", "whatsNew": "- Fixes"}
            fake = FakeAsc(versions=[version_row("V0", "2.0", "READY_FOR_SALE", "2026-06-09T00:00:00Z"), LIVE_VERSION],
                           version_locs={"VLIVE": [{"id": "LIVE", "attributes": text}]},
                           app_infos=("READY_FOR_DISTRIBUTION",), app_info_text={"AI0": {"name": "Scowld", "subtitle": "AI Voice Chat"}})
            fake.sets = {"LIVE": {"APP_IPHONE_67": [shot(known, "chat.png")], "APP_IPAD_PRO_3GEN_129": [shot("f" * 32, "ipad.png")]}}
            out_dir = root / "out"
            stdout = io.StringIO()
            with mock.patch.object(asc_release, "asc_from_environment", side_effect=fake.connect), \
                    mock.patch.object(asc_release, "ROOT", root), redirect_stdout(stdout):
                self.assertEqual(asc_export_listing.main(["--out", str(out_dir)]), 0)
            loc = out_dir / "en-US"
            self.assertEqual((loc / "name.txt").read_text(), "Scowld\n")
            self.assertEqual((loc / "description.txt").read_text(), "A companion\n")
            self.assertEqual((loc / "whats_new.txt").read_text(), "- Fixes\n")
            self.assertFalse((loc / "privacy_url.txt").exists())
            self.assertEqual(json.loads((loc / "screenshots.json").read_text()), {"APP_IPHONE_67": ["shots/chat.png"]})
            self.assertIn("no identical repository image for live screenshot en-US APP_IPAD_PRO_3GEN_129 ipad.png",
                          stdout.getvalue())
        self.assertEqual(fake.modes, [True])
        self.assertEqual(fake.writes(), [])
        self.assertIn(("localizations", "list", "--version", "VLIVE", "--paginate"), fake.calls, "the newest live version")


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

    def test_creative_assets_switch_is_listed(self) -> None:
        self.assertIn("IOS_UPLOAD_CREATIVE_ASSETS=false (unset)", self.output({}))
        self.assertIn("IOS_UPLOAD_CREATIVE_ASSETS=INVALID", self.output({"IOS_UPLOAD_CREATIVE_ASSETS": "maybe"}))
        self.assertIn("WARNING: one or more live switches are on",
                      self.output({"IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_CREATIVE_ASSETS": "true"}))

    def test_reports_exactly_what_the_gates_parse(self) -> None:
        self.assertEqual(print_gates.TRUE_VALUES, ios_release.TRUE_VALUES)
        self.assertEqual(print_gates.FALSE_VALUES, ios_release.FALSE_VALUES)
        self.assertEqual(print_gates.GATES, (ios_release.MASTER, *(name for name, _ in ios_release.OPERATION_SWITCHES)))


class FindAppTests(unittest.TestCase):
    def test_the_pinned_app_must_carry_the_bundle_id(self) -> None:
        fake = FakeAsc()
        self.assertEqual(quiet(asc_release.find_app, fake, BUNDLE), APP)
        self.assertEqual(fake.calls, [("apps", "view", "--id", APP)])
        self.assertEqual(APP, "6760672848")
        for wrong in (FakeAsc(bundle="com.apoorvdarshan.Scowld.widget"), FakeAsc(app_id="1234567890")):
            with self.subTest(app=wrong.app_id, bundle=wrong.bundle), self.assertRaises(SystemExit):
                quiet(asc_release.find_app, wrong, BUNDLE)

    def test_asc_failures_stop_with_a_readable_error(self) -> None:
        class Broken:
            def run(self, *args: str, **_: object):
                raise asc_cli.AscError(args, 3, "unauthorized")

        err = io.StringIO()
        with redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.find_app(Broken(), BUNDLE)
        self.assertIn("exit 3", err.getvalue())


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
