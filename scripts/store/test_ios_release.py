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

The App Store Connect token test signs a real ES256 token, and the RGB screenshot
tests flatten real images, with the hash-locked store tooling
(requirements-store.txt: PyJWT and Pillow). They are skipped where that tooling is
not installed (a local run, the release's prepare job); store-automation.yml
installs it and sets REQUIRE_STORE_TOOLING=true, so there they fail instead of
skipping.
"""
from __future__ import annotations

import argparse
import datetime as dt
import functools
import hashlib
import http.client
import io
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.parse
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

try:  # Only where the store tooling (requirements-store.txt) is installed.
    import jwt as pyjwt  # noqa: E402
    from cryptography.hazmat.primitives import serialization  # noqa: E402
    from cryptography.hazmat.primitives.asymmetric import ec  # noqa: E402
except ImportError:
    pyjwt = None
# Pillow, from the same lock: the RGB screenshot copies.
PILLOW = asc_release.try_import_pillow()

ROOT = HERE.parents[1]
CHECK_COMMITTED_FILES = os.environ.get("CHECK_COMMITTED_STORE_FILES", "true").strip().lower() not in {
    "0", "false", "no", "off",
}
# store-automation.yml installs the tooling and sets this, so a lock that fails to
# provide PyJWT or Pillow can never turn the token or RGB tests into a silent skip.
STORE_TOOLING_REQUIRED = os.environ.get("REQUIRE_STORE_TOOLING", "").strip().lower() in {"1", "true", "yes", "on"}
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
    "IOS_SUBMIT_REVIEW": "true",
    "IOS_PUBLIC_RELEASE": "true",
}
OPS = ("create_version", "upload_build", "listing", "whats_new", "screenshots", "submit", "public_release")
ASC_FLAGS = ("UPLOAD_LISTING", "UPLOAD_WHATS_NEW", "UPLOAD_SCREENSHOTS", "UPLOAD_CREATIVE_ASSETS", "SUBMIT_IOS_REVIEW",
             "PUBLIC_RELEASE", "CREATE_IOS_VERSION")


@functools.lru_cache(maxsize=None)
def make_png(width: int, height: int, colour_type: int = 2, *, chunks: tuple[tuple[bytes, bytes], ...] = ()) -> bytes:
    """A valid PNG of black pixels (8 bits per sample), built without Pillow.

    chunks are extra (type, data) chunks written before the image data, e.g. tRNS.
    """
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour_type]

    def chunk(kind: bytes, data: bytes) -> bytes:
        return len(data).to_bytes(4, "big") + kind + data + zlib.crc32(kind + data).to_bytes(4, "big")

    header = width.to_bytes(4, "big") + height.to_bytes(4, "big") + bytes([8, colour_type, 0, 0, 0])
    extra = b"".join(chunk(kind, data) for kind, data in chunks)
    palette = chunk(b"PLTE", b"\x00\x00\x00") if colour_type == 3 else b""
    pixels = zlib.compress((b"\x00" + b"\x00" * (width * channels)) * height)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + palette + extra
            + chunk(b"IDAT", pixels) + chunk(b"IEND", b""))


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
        for name in ("IOS_RELEASE_AUTOMATION", "IOS_CREATE_VERSION", "IOS_UPLOAD_BUILD", "IOS_SUBMIT_REVIEW",
                     "IOS_PUBLIC_RELEASE"):
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

    def test_token_is_an_es256_jwt_app_store_connect_accepts(self) -> None:
        # Signs with the real PyJWT/cryptography from requirements-store.txt, so an
        # update that breaks App Store Connect authentication fails here, not in a release.
        if pyjwt is None:
            if STORE_TOOLING_REQUIRED:
                self.fail("REQUIRE_STORE_TOOLING is set, but PyJWT/cryptography are not installed")
            self.skipTest("store tooling not installed (pip install --require-hashes -r requirements-store.txt)")
        key = ec.generate_private_key(ec.SECP256R1())
        pem = key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
        ).decode()
        issuer = "00000000-1111-2222-3333-444444444444"
        token = asc_release.make_asc_token("TESTKEY000", issuer, pem)
        header = pyjwt.get_unverified_header(token)
        self.assertEqual((header["alg"], header["kid"], header["typ"]), ("ES256", "TESTKEY000", "JWT"))
        claims = pyjwt.decode(
            token, key.public_key(), algorithms=["ES256"], audience="appstoreconnect-v1", issuer=issuer
        )
        # App Store Connect rejects tokens that live longer than 20 minutes.
        self.assertEqual(claims["exp"] - claims["iat"], 1200)


# MARK: - Listing, What's New and screenshots


def png(path: Path, width: int, height: int, *, alpha: bool = False, seed: int = 0) -> Path:
    """A real PNG with the given dimensions (the upload path refuses anything else); seed makes contents unique."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(make_png(width, height, 6 if alpha else 2, chunks=((b"tEXt", b"seed\x00%d" % seed),)))
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
        good = png(self.root / "store" / "metadata" / "screenshots" / "a.png", 1260, 2736)
        png(self.root / "store" / "metadata" / "screenshots" / "ipad.png", 2064, 2752, seed=1)
        png(self.root / "store" / "metadata" / "screenshots" / "small.png", 1179, 2556, seed=2)
        png(self.root / "store" / "metadata" / "screenshots" / "alpha.png", 1290, 2796, alpha=True, seed=3)
        manifest = self.loc / "screenshots.json"

        manifest.write_text(json.dumps({"APP_IPHONE_67": ["store/metadata/screenshots/a.png"], "APP_IPAD_PRO_3GEN_129": ["store/metadata/screenshots/ipad.png"]}))
        plan = self.validate(upload_screenshots=True)["en-US"]["screenshots"]
        self.assertEqual(plan["APP_IPHONE_67"], [good.resolve()])
        # A frame that stores alpha is listed like any other: staging uploads an RGB copy of it.
        manifest.write_text(json.dumps({"APP_IPHONE_67": ["store/metadata/screenshots/alpha.png"]}))
        self.assertEqual(len(self.validate(upload_screenshots=True)["en-US"]["screenshots"]["APP_IPHONE_67"]), 1)

        cases = {
            "1179x2556; APP_IPHONE_67 accepts": {"APP_IPHONE_67": ["store/metadata/screenshots/small.png"]},
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
    def test_committed_store_metadata_is_valid(self) -> None:
        plan = quiet(asc_release.validate_local_inputs, upload_listing=True, upload_whats_new=True,
                     upload_screenshots=True, metadata_dir=asc_release.METADATA_DIR)
        self.assertIn("en-US", plan)
        for locale, entry in plan.items():
            with self.subTest(locale=locale):
                self.assertTrue(entry["version"]["description"])
                self.assertTrue(entry["app_info"]["name"])
                self.assertTrue(entry["screenshots"], "every locale lists App Store-ready screenshots")
        committed = {locale: {display: list(files) for display, files in entry["screenshots"].items()}
                     for locale, entry in plan.items()}
        before = {path: path.read_bytes() for sets in committed.values() for files in sets.values() for path in files}
        with tempfile.TemporaryDirectory() as tmp:
            quiet(asc_release.stage_screenshots, plan, Path(tmp))
            for locale, sets in committed.items():
                for display, files in sets.items():
                    for source, staged in zip(files, plan[locale]["screenshots"][display]):
                        with self.subTest(display=display, name=source.name):
                            # The live sets hold these exact files (their checksums match App Store
                            # Connect's), so their RGB copies are byte for byte the same.
                            self.assertEqual(staged.read_bytes(), before[source])
                            self.assertNotEqual(staged, source)
        self.assertEqual({path: path.read_bytes() for path in before}, before, "the committed files are untouched")


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
                 draft_items: list[dict] | None = None, drafts: int = 1, versions: list[str] | None = None,
                 live_by_display: dict[str, list[dict]] | None = None) -> None:
        self.state = state
        self.attached = attached
        self.revert_after_select = revert_after_select
        self.products = products or []
        self.draft_items = draft_items or []
        self.drafts = drafts
        self.versions = versions if versions is not None else [VERSION]
        # display type -> the screenshots its live set holds.
        self.live_by_display = dict(live_by_display or {})
        self.created_sets: list[str] = []
        # (set id, file name, uploaded bytes) of every screenshot uploaded.
        self.uploaded_shots: list[tuple[str, str, bytes]] = []
        self.build_reads = 0
        self.calls: list[tuple[str, str]] = []

    def get(self, path: str) -> dict:
        self.calls.append(("GET", path))
        if path.startswith("/appStoreVersions/V1/appStoreVersionLocalizations"):
            return {"data": [{"id": "LOC1", "attributes": {"locale": "en-US"}}]}
        if path.startswith("/appStoreVersionLocalizations/LOC1/appScreenshotSets"):
            return {"data": [{"id": f"SET-{display}", "attributes": {"screenshotDisplayType": display}}
                             for display in self.live_by_display]}
        if path.startswith("/appScreenshotSets/") and "/appScreenshots" in path:
            # Live sets hold live_by_display; sets created by this run start empty.
            set_id = path.split("/")[2]
            live = self.live_by_display.get(set_id.removeprefix("SET-"), []) if set_id.startswith("SET-") else []
            return {"data": [{"id": f"SHOT{i}", "attributes": shot} for i, shot in enumerate(live)]}
        if path.startswith("/appScreenshots/"):
            return {"data": {"id": path.split("/")[2], "attributes": {"assetDeliveryState": {"state": "COMPLETE"}}}}
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
        if path.startswith("/reviewSubmissions/SUB") and "/items?" in path:
            return {"data": []}  # the other drafts are empty
        raise AssertionError(f"unexpected GET {path}")

    def post(self, path: str, body: dict) -> dict:
        self.calls.append(("POST", path))
        if path == "/appScreenshotSets":
            display = body["data"]["attributes"]["screenshotDisplayType"]
            self.created_sets.append(display)
            return {"data": {"id": f"NEW-{display}"}}
        if path == "/appScreenshots":
            attributes = body["data"]["attributes"]
            shot_id = f"UP{len(self.uploaded_shots)}"
            self.uploaded_shots.append((body["data"]["relationships"]["appScreenshotSet"]["data"]["id"],
                                        attributes["fileName"], b""))
            return {"data": {"id": shot_id, "attributes": {"uploadOperations": [
                {"url": f"https://upload.example/{shot_id}", "method": "PUT", "offset": 0,
                 "length": attributes["fileSize"], "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]}]}}}
        return {"data": {"id": "ITEM"}}

    def patch(self, path: str, body: dict) -> dict:
        self.calls.append(("PATCH", path))
        return {"data": body["data"]}

    def request(self, method: str, path: str, *, body: dict | None = None):
        self.calls.append((method, path))
        if method == "PATCH" and path == "/appStoreVersions/V1/relationships/build":
            self.attached = body["data"]["id"]
        return None

    def delete(self, path: str) -> None:
        self.calls.append(("DELETE", path))

    def upload_bytes(self, url: str, data: bytes, headers: dict, *, method: str = "PUT") -> None:
        self.calls.append(("UPLOAD", url))
        index = int(url.rsplit("/UP", 1)[1])
        set_id, name, _ = self.uploaded_shots[index]
        self.uploaded_shots[index] = (set_id, name, data)


def writes(fake: FakeAsc) -> list[tuple[str, str]]:
    return [call for call in fake.calls if call[0] != "GET"]


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
            # A READY_FOR_REVIEW version sits in its draft, as in App Store Connect.
            f"/apps/{APP}/reviewSubmissions?*": {"data": [{"id": "D1"}] if state == "READY_FOR_REVIEW" else []},
            "/reviewSubmissions/D1/items?*": {"data": [
                {"id": "I1", "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": "V0"}}}}]},
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


class VersionsClient(RouteClient):
    """Fake App Store Connect app with the given iOS versions; POST /appStoreVersions adds one."""

    def __init__(self, versions: list[tuple[str, str]], *, app_id: str = asc_release.DEFAULT_APP_ID) -> None:
        self.rows = [{"id": f"V{i}", "attributes": {"versionString": number, "appStoreState": state}}
                     for i, (number, state) in enumerate(versions)]
        super().__init__({
            "/apps?*": {"data": [{"id": app_id, "attributes": {"bundleId": asc_release.DEFAULT_BUNDLE_ID}}]},
            f"/apps/{app_id}/appStoreVersions?*": lambda _path: {"data": list(self.rows)},
        })

    def post(self, path: str, body: dict) -> dict:
        result = super().post(path, body)
        if path == "/appStoreVersions":
            number = body["data"]["attributes"]["versionString"]
            self.rows.append({"id": result["data"]["id"],
                              "attributes": {"versionString": number, "appStoreState": "PREPARE_FOR_SUBMISSION"}})
        return result


class CreateVersionTests(unittest.TestCase):
    """--create-version (IOS_CREATE_VERSION): add the tag's App Store version only when it is missing."""

    ON = {"CREATE_IOS_VERSION": "true"}
    LIVE = ("2.0.1", "READY_FOR_SALE")

    def create(self, client: RouteClient, flags: dict[str, str] | None = None, *args: str) -> tuple[int, str]:
        env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        env.update(self.ON if flags is None else flags)
        out = io.StringIO()
        code = 0
        argv = ["--create-version", *(args or ("--version", VERSION))]
        with mock.patch.dict(os.environ, env, clear=True), \
                mock.patch.object(asc_release, "client_from_environment", return_value=client), \
                redirect_stdout(out), redirect_stderr(out):
            try:
                asc_release.main(argv)
            except SystemExit as exc:
                code = exc.code if isinstance(exc.code, int) else 1
        return code, out.getvalue()

    def test_switch_off_makes_no_calls(self) -> None:
        client = VersionsClient([self.LIVE])
        code, output = self.create(client, {})
        self.assertEqual(code, 0, output)
        self.assertIn("skipped", output)
        self.assertEqual(client.calls, [])

    def test_existing_version_is_left_alone(self) -> None:
        client = VersionsClient([self.LIVE, (VERSION, "READY_FOR_REVIEW")])
        code, output = self.create(client)
        self.assertEqual(code, 0, output)
        self.assertIn(f"{VERSION} already exists (READY_FOR_REVIEW)", output)
        self.assertEqual(client.writes(), [])

    def test_missing_version_is_created_for_this_app_and_read_back(self) -> None:
        client = VersionsClient([self.LIVE])
        code, output = self.create(client)
        self.assertEqual(code, 0, output)
        self.assertEqual([call[:2] for call in client.writes()], [("POST", "/appStoreVersions")])
        body = client.writes()[0][2]["data"]
        self.assertEqual(body["type"], "appStoreVersions")
        self.assertEqual(body["attributes"], {"platform": "IOS", "versionString": VERSION})
        self.assertEqual(body["relationships"]["app"]["data"], {"type": "apps", "id": asc_release.DEFAULT_APP_ID})
        self.assertEqual(client.calls[-1][0], "GET", "the created version must be read back")
        self.assertIn(f"created App Store version {VERSION} (PREPARE_FOR_SUBMISSION)", output)

    def test_another_version_on_its_way_blocks_creation(self) -> None:
        for state in ("PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
            with self.subTest(state=state):
                client = VersionsClient([("2.0", "READY_FOR_SALE"), ("2.0.1", state)])
                code, output = self.create(client)
                self.assertEqual(code, 1)
                self.assertIn(f"is still {state}", output)
                self.assertIn("nothing was changed", output)
                self.assertEqual(client.writes(), [])

    def test_version_not_newer_than_an_existing_one_is_refused(self) -> None:
        for existing in ("2.1", "2.0.10", "3"):
            with self.subTest(existing=existing):
                client = VersionsClient([(existing, "READY_FOR_SALE")])
                code, output = self.create(client)
                self.assertEqual(code, 1)
                self.assertIn(f"not newer than the existing version {existing}", output)
                self.assertEqual(client.writes(), [])
        # 2.1 and 2.1.0 are the same version to the App Store.
        client = VersionsClient([("2.1.0", "READY_FOR_SALE")])
        code, output = self.create(client, None, "--version", "2.1")
        self.assertEqual(code, 1)
        self.assertEqual(client.writes(), [])

    def test_older_finished_versions_allow_creation(self) -> None:
        client = VersionsClient([("1.0", "REPLACED_WITH_NEW_VERSION"), ("1.1", "REMOVED_FROM_SALE"),
                                 ("1.2", "DEVELOPER_REMOVED_FROM_SALE"), self.LIVE])
        code, output = self.create(client)
        self.assertEqual(code, 0, output)
        self.assertEqual([call[:2] for call in client.writes()], [("POST", "/appStoreVersions")])

    def test_other_app_or_bad_version_fails_without_writing(self) -> None:
        client = VersionsClient([self.LIVE], app_id="1234567890")
        code, output = self.create(client)
        self.assertEqual(code, 1)
        self.assertIn(f"expected {asc_release.DEFAULT_APP_ID}", output)
        self.assertEqual(client.writes(), [])
        for bad in ("2.0.2-beta", "v2.0.2", "2.0.2.1", "٢.٠"):
            with self.subTest(bad=bad):
                client = VersionsClient([self.LIVE])
                code, output = self.create(client, None, "--version", bad)
                self.assertEqual(code, 1)
                self.assertIn("must look like", output)
                self.assertEqual(client.calls, [])

    def test_needs_a_version_and_dry_run_makes_no_calls(self) -> None:
        client = VersionsClient([self.LIVE])
        code, output = self.create(client, None, "--dry-run")
        self.assertEqual(code, 1)
        self.assertIn("needs --version", output)
        code, output = self.create(client, None, "--dry-run", "--version", VERSION)
        self.assertEqual(code, 0, output)
        self.assertIn("would create", output)
        self.assertEqual(client.calls, [])

    def test_dry_run_rejects_a_bad_version_like_a_live_run(self) -> None:
        for bad in ("2.0.2-beta", "v2.0.2", "2.0.2.1"):
            with self.subTest(bad=bad):
                client = VersionsClient([self.LIVE])
                with mock.patch.object(asc_release, "client_from_environment",
                                       side_effect=AssertionError("network")):
                    code, output = self.create(client, None, "--dry-run", "--version", bad)
                self.assertEqual(code, 1)
                self.assertIn("must look like", output)
                self.assertEqual(client.calls, [])

    def test_create_version_never_runs_together_with_the_preflight(self) -> None:
        for flags in (self.ON, {}, {**self.ON, "SUBMIT_IOS_REVIEW": "true", "UPLOAD_LISTING": "true"}):
            with self.subTest(flags=flags):
                client = VersionsClient([self.LIVE])
                code, output = self.create(client, flags, "--preflight", "--version", VERSION)
                self.assertEqual(code, 1)
                self.assertIn("separate steps", output)
                self.assertEqual(client.calls, [])

    def test_a_created_version_that_does_not_read_back_fails_naming_it(self) -> None:
        class Vanishing(VersionsClient):
            def post(self, path: str, body: dict) -> dict:
                result = super().post(path, body)
                self.rows.pop()  # App Store Connect does not list it yet
                return result

        class Doubled(VersionsClient):
            def post(self, path: str, body: dict) -> dict:
                result = super().post(path, body)
                self.rows.append(self.rows[-1])
                return result

        for fake_class, found in ((Vanishing, 0), (Doubled, 2)):
            with self.subTest(found=found):
                client = fake_class([self.LIVE])
                code, output = self.create(client)
                self.assertEqual(code, 1)
                self.assertIn(f"created App Store version {VERSION}, but reading it back found {found} records",
                              output)
                self.assertIn("check it in App Store Connect before rerunning", output)
                self.assertNotIn("IOS_CREATE_VERSION", output)
                self.assertEqual([call[:2] for call in client.writes()], [("POST", "/appStoreVersions")])


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


# MARK: - Header and search results images, the screenshot alpha guard, Apple Watch and RGB copies


class CreativeGateTests(unittest.TestCase):
    """IOS_UPLOAD_CREATIVE_ASSETS follows every switch convention."""

    def test_creative_assets_are_their_own_switch(self) -> None:
        result = gates({"IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_CREATIVE_ASSETS": "true"})
        self.assertTrue(result["creative"])
        self.assertTrue(result["asc"], "the store job runs for creative assets alone")
        self.assertFalse(result["build"])
        for key in OPS:
            self.assertFalse(result[key], key)
        self.assertFalse(gates({**ALL_ON, "IOS_UPLOAD_CREATIVE_ASSETS": "false"})["creative"])

    def test_it_needs_the_master_switch_and_validation_runs_never_use_it(self) -> None:
        result = gates({"IOS_UPLOAD_CREATIVE_ASSETS": "true"})
        self.assertFalse(result["creative"])
        self.assertFalse(result["asc"])
        self.assertTrue(any("IOS_UPLOAD_CREATIVE_ASSETS" in note for note in result["notes"]))
        manual = gates({**ALL_ON, "IOS_UPLOAD_CREATIVE_ASSETS": "true"}, event="workflow_dispatch", ref="main")
        self.assertFalse(manual["creative"])

    def test_invalid_values_fail_even_when_the_master_is_off(self) -> None:
        for env in ({"IOS_UPLOAD_CREATIVE_ASSETS": "maybe"},
                    {"IOS_RELEASE_AUTOMATION": "false", "IOS_UPLOAD_CREATIVE_ASSETS": "2"}):
            with self.subTest(env=env), self.assertRaisesRegex(ReleaseError, "IOS_UPLOAD_CREATIVE_ASSETS"):
                gates(env)

    def test_every_ios_switch_is_printed_and_documented(self) -> None:
        example = (Path(ios_release.ROOT) / "store" / "gates.env.example").read_text()
        self.assertEqual(dict(ios_release.OPERATION_SWITCHES).get("IOS_UPLOAD_CREATIVE_ASSETS"), "creative")
        for name, _ in ios_release.OPERATION_SWITCHES:
            with self.subTest(name=name):
                self.assertIn(name, print_gates.GATES)
                self.assertIn(f"\n{name}=false\n", example)

    def test_preflight_reads_the_switch(self) -> None:
        # On: the images go on the version's localization, so the preflight checks it, and
        # their Asset Library state, without writing. Off: nothing is read.
        with tempfile.TemporaryDirectory() as tmp:
            creative = Path(tmp) / "creative"
            header = creative / "header" / "header.png"
            header.parent.mkdir(parents=True)
            header.write_bytes(make_png(3840, 1646))
            library = [{"id": "HDR", "attributes": {"fileName": header.name, "fileSize": header.stat().st_size,
                                                    "state": "APPROVED"}}]
            placements = {"PL-HDR": {"type": "PRODUCT_PAGE_HEADER_ASSET", "image": "HDR", "loc": "LOC1"}}
            for flags, reads in (({"UPLOAD_CREATIVE_ASSETS": "true"}, True), ({}, False)):
                fake = CreativeFake(library=library, placements=placements)
                env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
                with self.subTest(flags=flags), mock.patch.dict(os.environ, {**env, **flags}, clear=True), \
                        mock.patch.object(asc_release, "client_from_environment", return_value=fake), \
                        redirect_stdout(io.StringIO()):
                    asc_release.main(["--preflight", "--version", VERSION, "--creative-dir", str(creative)])
                    self.assertEqual(bool([c for c in fake.calls if "appStoreVersionLocalizations" in c[1]]), reads)
                    self.assertEqual((("GET", f"/apps/{APP}/assetLibrary") in fake.calls), reads)
                    self.assertEqual(writes(fake), [])

    def test_print_gates_lists_it(self) -> None:
        clean = {k: v for k, v in os.environ.items() if not k.startswith("IOS_")}
        for value, shown in (("true", "IOS_UPLOAD_CREATIVE_ASSETS=true\n"),
                             ("maybe", "IOS_UPLOAD_CREATIVE_ASSETS=INVALID 'maybe'")):
            out = io.StringIO()
            with mock.patch.dict(os.environ, {**clean, "IOS_RELEASE_AUTOMATION": "true",
                                              "IOS_UPLOAD_CREATIVE_ASSETS": value}, clear=True), redirect_stdout(out):
                print_gates.main()
            self.assertIn(shown, out.getvalue())


class ScreenshotAlphaGuardTests(unittest.TestCase):
    """The last guard: a staged file that still stores alpha never reaches App Store Connect."""

    def test_alpha_is_detected_the_way_app_store_connect_refuses_it(self) -> None:
        cases = {
            "rgb": (make_png(2, 2, 2), False),
            "grey": (make_png(2, 2, 0), False),
            "palette": (make_png(2, 2, 3), False),
            "grey + alpha": (make_png(2, 2, 4), True),
            "rgba": (make_png(2, 2, 6), True),
            "rgb + tRNS": (make_png(2, 2, 2, chunks=((b"tRNS", b"\x00\x00\x00\x00\x00\x00"),)), True),
            "palette + tRNS": (make_png(2, 2, 3, chunks=((b"tRNS", b"\x00"),)), True),
        }
        for label, (raw, alpha) in cases.items():
            with self.subTest(label):
                self.assertEqual(asc_release.png_stores_alpha(asc_release.png_chunks(raw)), alpha)

    def test_truncated_or_corrupt_pngs_are_refused(self) -> None:
        good = make_png(8, 8)
        ihdr_end = 8 + 12 + 13
        idat = good.index(b"IDAT") - 4
        corrupt_crc = bytearray(good)
        corrupt_crc[idat + 8] ^= 0xFF  # first byte of the IDAT data; its CRC no longer matches
        cases = {
            "signature and IHDR only": good[:ihdr_end],
            "cut in the image data": good[: idat + 10],
            "no IEND": good[:-12],
            "IEND without its CRC": good[:-4],
            "bad CRC": bytes(corrupt_crc),
            "no IDAT": good[:ihdr_end] + good[-12:],
            "image data is not zlib": make_png(8, 8)[:idat] + self.chunk(b"IDAT", b"not zlib") + good[-12:],
            "image data for another size": make_png(8, 8)[:idat] + make_png(4, 4)[make_png(4, 4).index(b"IDAT") - 4:],
        }
        for label, raw in cases.items():
            with self.subTest(label), self.assertRaises(ValueError):
                asc_release.png_chunks(raw)
        self.assertEqual([kind for kind, _ in asc_release.png_chunks(good)], [b"IHDR", b"IDAT", b"IEND"])
        # Lenient reading (deciding how to copy a screenshot) only needs the header.
        self.assertEqual(asc_release.png_chunks(good[:ihdr_end], strict=False)[0][0], b"IHDR")

    @staticmethod
    def chunk(kind: bytes, data: bytes) -> bytes:
        return len(data).to_bytes(4, "big") + kind + data + zlib.crc32(kind + data).to_bytes(4, "big")

    def test_staged_files_with_alpha_or_not_png_are_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "01-home.png"
            for raw in (make_png(4, 4, 6), make_png(4, 4, 4), make_png(4, 4, 2, chunks=((b"tRNS", b"\x00" * 6),)),
                        b"\x89PNG\r\n\x1a\n" + b"screenshot" * 4, b"GIF89a", make_png(4, 4)[:-12]):
                path.write_bytes(raw)
                with self.subTest(raw=raw[:30]), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    asc_release.staged_png(path, "APP_IPHONE_67")
            path.write_bytes(make_png(4, 4, 2))
            self.assertEqual(asc_release.staged_png(path, "APP_IPHONE_67"), (4, 4))

    def test_a_truncated_or_corrupt_screenshot_fails_before_any_call(self) -> None:
        # Staging copies an RGB file as it is, so the guard is what stops a broken one.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            loc = root / "meta" / "en-US"
            loc.mkdir(parents=True)
            shot = png(root / "shots" / "a.png", 1260, 2736)
            (loc / "screenshots.json").write_text(json.dumps({"APP_IPHONE_67": ["shots/a.png"]}))
            good = shot.read_bytes()
            for raw in (good[:-12], good[: len(good) // 2]):
                shot.write_bytes(raw)
                fake = FakeAsc()
                err = io.StringIO()
                env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
                with self.subTest(size=len(raw)), mock.patch.dict(os.environ, {**env, "UPLOAD_SCREENSHOTS": "true"}, clear=True), \
                        mock.patch.object(asc_release, "client_from_environment", return_value=fake), \
                        mock.patch.object(asc_release, "ROOT", root), redirect_stdout(io.StringIO()), redirect_stderr(err), \
                        self.assertRaises(SystemExit):
                    asc_release.main(["--version", VERSION, "--metadata-dir", str(root / "meta")])
                self.assertIn("not a readable PNG", err.getvalue())
                self.assertEqual(fake.calls, [])


class WatchScreenshotTests(unittest.TestCase):
    """Apple Watch frames are uploaded like the other sets, by the display type their size belongs to."""

    PHONE_SETS = {"APP_IPHONE_67": (1260, 2736), "APP_IPAD_PRO_3GEN_129": (2048, 2732), "APP_IPHONE_DUO": (1398, 2034)}

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.loc = self.root / "meta" / "en-US"
        self.loc.mkdir(parents=True)
        self.shots = self.root / "store" / "metadata" / "screenshots" / "ios"
        self.phone: dict[str, bytes] = {}
        for display, size in self.PHONE_SETS.items():
            self.phone[display] = png(self.shots / display.lower() / "01-home.png", *size).read_bytes()
        self.watch = self.shots / "watch"
        self.watch_png = make_png(416, 496)
        self.watch.mkdir()
        (self.watch / "01-home-glance.png").write_bytes(self.watch_png)
        self.manifest(["01-home-glance.png"])

    def manifest(self, watch: list[str] | None) -> None:
        # "watch" comes first here: the Watch sets still go after the others.
        sets: dict[str, list[str]] = {}
        if watch is not None:
            sets["watch"] = [f"store/metadata/screenshots/ios/watch/{name}" for name in watch]
        for display in self.PHONE_SETS:
            sets[display] = [f"store/metadata/screenshots/ios/{display.lower()}/01-home.png"]
        (self.loc / "screenshots.json").write_text(json.dumps(sets))

    @staticmethod
    def shot(name: str, raw: bytes) -> dict:
        return {"fileName": name, "fileSize": len(raw), "sourceFileChecksum": hashlib.md5(raw).hexdigest()}

    def live(self) -> dict[str, list[dict]]:
        return {display: [self.shot("01-home.png", raw)] for display, raw in self.phone.items()}

    def run_main(self, fake: FakeAsc, env: dict[str, str]) -> int:
        argv = ["--version", VERSION, "--build-id", "B9", "--build-number", "14", "--metadata-dir", str(self.root / "meta")]
        full_env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        full_env.update(env)
        with mock.patch.dict(os.environ, full_env, clear=True), \
                mock.patch.object(asc_release, "client_from_environment", return_value=fake), \
                mock.patch.object(asc_release, "ROOT", self.root), \
                mock.patch.object(asc_release.time, "sleep"), \
                redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            try:
                asc_release.main(argv)
            except SystemExit as exc:
                return exc.code if isinstance(exc.code, int) else 1
        return 0

    def test_each_watch_size_maps_to_its_display_type(self) -> None:
        (self.watch / "02-ultra-3.png").write_bytes(make_png(422, 514))
        (self.watch / "03-ultra.png").write_bytes(make_png(410, 502))
        (self.watch / "04-series-7.png").write_bytes(make_png(396, 484))
        self.manifest(["01-home-glance.png", "02-ultra-3.png", "03-ultra.png", "04-series-7.png"])
        sets = quiet(asc_release.load_screenshot_manifest, self.loc, self.root)
        self.assertEqual(
            [(display, [p.name for p in files]) for display, files in sets.items() if display.startswith("APP_WATCH")],
            [("APP_WATCH_SERIES_10", ["01-home-glance.png"]),
             ("APP_WATCH_ULTRA", ["02-ultra-3.png", "03-ultra.png"]),
             ("APP_WATCH_SERIES_7", ["04-series-7.png"])],
        )
        expected = {(416, 496): "APP_WATCH_SERIES_10", (422, 514): "APP_WATCH_ULTRA", (410, 502): "APP_WATCH_ULTRA",
                    (396, 484): "APP_WATCH_SERIES_7", (368, 448): "APP_WATCH_SERIES_4", (312, 390): "APP_WATCH_SERIES_3"}
        self.assertEqual(asc_release.WATCH_DISPLAY_TYPES, expected)
        # The Watch sets come after the iPhone, iPad and iPhone Duo sets.
        self.assertEqual(list(sets), ["APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129", "APP_IPHONE_DUO",
                                      "APP_WATCH_SERIES_10", "APP_WATCH_ULTRA", "APP_WATCH_SERIES_7"])
        # The iPhone Duo set takes the outer and the inner screen.
        self.assertEqual(asc_release.SCREENSHOT_SIZES["APP_IPHONE_DUO"], {(1398, 2034), (2007, 2853)})

    def test_a_frame_that_is_no_watch_size_or_stores_alpha_fails_before_any_call(self) -> None:
        # Without Pillow an alpha frame is copied as it is, so it is refused; with Pillow it is flattened.
        for name, raw in (("02-phone.png", make_png(1290, 2796)), ("02-alpha.png", make_png(416, 496, 6))):
            (self.watch / name).write_bytes(raw)
            self.manifest(["01-home-glance.png", name])
            fake = FakeAsc()
            with self.subTest(name=name), mock.patch.object(asc_release, "try_import_pillow", return_value=None):
                self.assertEqual(self.run_main(fake, {"UPLOAD_SCREENSHOTS": "true"}), 1)
                self.assertEqual(fake.calls, [])
            (self.watch / name).unlink()

    def test_the_watch_set_is_uploaded_with_its_display_type(self) -> None:
        fake = FakeAsc()
        self.assertEqual(self.run_main(fake, {"UPLOAD_SCREENSHOTS": "true"}), 0)
        self.assertEqual(fake.created_sets, ["APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129", "APP_IPHONE_DUO",
                                             "APP_WATCH_SERIES_10"])
        self.assertEqual(fake.uploaded_shots[-1], ("NEW-APP_WATCH_SERIES_10", "01-home-glance.png", self.watch_png))

    def test_a_watch_set_is_replaced_only_when_it_differs(self) -> None:
        same = {**self.live(), "APP_WATCH_SERIES_10": [self.shot("01-home-glance.png", self.watch_png)]}
        fake = FakeAsc(live_by_display=same)
        self.assertEqual(self.run_main(fake, {"UPLOAD_SCREENSHOTS": "true"}), 0)
        self.assertEqual(writes(fake), [])
        # A different live Watch set is replaced; the others are left alone.
        old = {**self.live(), "APP_WATCH_SERIES_10": [self.shot("01-old.png", b"old")]}
        fake = FakeAsc(live_by_display=old)
        self.assertEqual(self.run_main(fake, {"UPLOAD_SCREENSHOTS": "true"}), 0)
        self.assertEqual([(set_id, name) for set_id, name, _ in fake.uploaded_shots],
                         [("SET-APP_WATCH_SERIES_10", "01-home-glance.png")])
        self.assertEqual([c for c in writes(fake) if c[0] == "DELETE"], [("DELETE", "/appScreenshots/SHOT0")])

    def test_a_locked_version_only_compares_the_watch_set(self) -> None:
        same = {**self.live(), "APP_WATCH_SERIES_10": [self.shot("01-home-glance.png", self.watch_png)]}
        env = {"UPLOAD_SCREENSHOTS": "true", "SUBMIT_IOS_REVIEW": "true"}
        held = [version_item()]
        fake = FakeAsc(state="READY_FOR_REVIEW", live_by_display=same, draft_items=held)
        self.assertEqual(self.run_main(fake, env), 0)
        self.assertFalse([c for c in writes(fake) if "creenshot" in c[1]])
        # A Watch set that differs while the version is in a review submission stops the run before any write.
        fake = FakeAsc(state="READY_FOR_REVIEW", live_by_display=self.live(), draft_items=held)
        self.assertEqual(self.run_main(fake, env), 1)
        self.assertEqual(writes(fake), [])

    def test_without_staged_watch_frames_the_live_watch_sets_are_left_alone(self) -> None:
        self.manifest(None)
        fake = FakeAsc(live_by_display={**self.live(), "APP_WATCH_ULTRA": [self.shot("01-hand.png", b"by hand")]})
        self.assertEqual(self.run_main(fake, {"UPLOAD_SCREENSHOTS": "true"}), 0)
        self.assertEqual(writes(fake), [])
        self.assertEqual(asc_release.watch_sets([]), {})


class StageScreenshotTests(unittest.TestCase):
    """Screenshots are uploaded from copies in a temporary folder; the committed files are only read."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.staging = self.root / "staging"
        self.staging.mkdir()

    def stage(self, sets: dict[str, list[Path]]) -> dict[str, list[Path]]:
        plan = {"en-US": {"screenshots": {display: list(files) for display, files in sets.items()}}}
        quiet(asc_release.stage_screenshots, plan, self.staging)
        return plan["en-US"]["screenshots"]

    def test_rgb_files_are_copied_byte_for_byte(self) -> None:
        # The live sets were uploaded from these exact bytes; a re-encoded copy would no
        # longer match their checksums, and every set would be uploaded again.
        iphone = png(self.root / "iphone-6.9" / "chat.png", 1320, 2868)
        ipad = png(self.root / "ipad-13" / "chat.png", 2064, 2752, seed=1)
        before = {path: path.read_bytes() for path in (iphone, ipad)}
        staged = self.stage({"APP_IPHONE_67": [iphone], "APP_IPAD_PRO_3GEN_129": [ipad]})
        for (display, (copy,)), source in zip(staged.items(), (iphone, ipad)):
            with self.subTest(display=display):
                self.assertEqual(copy.read_bytes(), before[source])
                self.assertEqual(copy.name, source.name, "the copy keeps the file name App Store Connect shows")
                self.assertIn(self.staging, copy.parents)
        self.assertNotEqual(staged["APP_IPHONE_67"][0], staged["APP_IPAD_PRO_3GEN_129"][0], "same name, own copy")
        self.assertEqual({path: path.read_bytes() for path in before}, before, "the committed files are untouched")

    def test_upload_without_pillow_refuses_frames_that_store_alpha(self) -> None:
        cases = {
            "rgba": make_png(1290, 2796, 6),
            "grey + alpha": make_png(1290, 2796, 4),
            "rgb + tRNS": make_png(1290, 2796, 2, chunks=((b"tRNS", b"\x00" * 6),)),
        }
        path = self.root / "02-alpha.png"
        with mock.patch.object(asc_release, "try_import_pillow", return_value=None):
            for label, raw in cases.items():
                path.write_bytes(raw)
                plan = {"en-US": {"screenshots": {"APP_IPHONE_67": [path]}}}
                stderr = io.StringIO()
                with self.subTest(label), self.assertRaises(SystemExit), redirect_stdout(io.StringIO()), \
                        redirect_stderr(stderr):
                    asc_release.stage_screenshots(plan, self.staging)
                self.assertIn("02-alpha.png", stderr.getvalue())
                self.assertIn("install Pillow", stderr.getvalue())
            # An RGB file is copied as it is.
            path.write_bytes(make_png(1290, 2796, 2))
            (copy,) = self.stage({"APP_IPHONE_67": [path]})["APP_IPHONE_67"]
            self.assertEqual(copy.read_bytes(), path.read_bytes())


@unittest.skipIf(PILLOW is None and not STORE_TOOLING_REQUIRED,
                 "store tooling not installed (pip install --require-hashes -r requirements-store.txt)")
class RgbStageTests(unittest.TestCase):
    """With Pillow, every App Store frame is uploaded as an RGB PNG without alpha."""

    OPAQUE = (10, 20, 30, 255)
    HIDDEN_RED = (255, 0, 0, 0)  # fully transparent, with a colour that must never show
    HALF = (200, 100, 50, 128)

    def setUp(self) -> None:
        if PILLOW is None:
            self.fail("REQUIRE_STORE_TOOLING is set, but Pillow is not installed")
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.staging = self.root / "staging"
        self.staging.mkdir()

    def frame(self, name: str, size: tuple[int, int], *, icc: bytes | None = None,
              chunks: tuple[tuple[bytes, bytes], ...] = ()) -> Path:
        from PIL import PngImagePlugin

        img = PILLOW.new("RGBA", size, self.OPAQUE)
        width, height = size
        # The left quarter is transparent; one translucent pixel top right.
        img.paste(self.HIDDEN_RED, (0, 0, width // 4, height))
        img.putpixel((width - 1, 0), self.HALF)
        info = PngImagePlugin.PngInfo()
        for kind, data in chunks:
            info.add(kind, data)
        path = self.root / "frames" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(path, pnginfo=info, **({"icc_profile": icc} if icc else {}))
        return path

    def stage(self, plan: dict[str, dict]) -> None:
        quiet(asc_release.stage_screenshots, plan, self.staging)

    def rgb(self, path: Path):
        raw = path.read_bytes()
        self.assertEqual(raw[25], 2, f"{path.name} is not an RGB PNG (colour type {raw[25]})")
        self.assertNotIn(b"tRNS", [kind for kind, _ in asc_release.png_chunks(raw)])
        img = PILLOW.open(path)
        self.assertEqual(img.mode, "RGB")
        return img

    def test_frames_at_an_accepted_size_keep_their_pixels_over_black(self) -> None:
        source = self.frame("01-a.png", (1290, 2796))
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        plan = {"en-US": {"screenshots": {"APP_IPHONE_67": [source]}}}

        self.stage(plan)

        (staged,) = plan["en-US"]["screenshots"]["APP_IPHONE_67"]
        img = self.rgb(staged)
        self.assertEqual(img.size, (1290, 2796))
        self.assertEqual(img.getpixel((1289, 2795)), self.OPAQUE[:3], "opaque pixels are kept as they are")
        self.assertEqual(img.getpixel((0, 0)), (0, 0, 0), "transparent pixels are laid over black")
        # Translucent pixels are blended over black exactly once.
        for got, value in zip(img.getpixel((1289, 0)), self.HALF[:3]):
            self.assertAlmostEqual(got, value * 128 / 255, delta=1)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before, "the committed file is untouched")

    def test_every_app_store_set_is_staged_without_alpha(self) -> None:
        loc = self.root / "meta" / "en-US"
        loc.mkdir(parents=True)
        frames = {"APP_IPHONE_67": ("01-a.png", (1290, 2796)), "APP_IPAD_PRO_3GEN_129": ("01-i.png", (2064, 2752)),
                  "APP_IPHONE_DUO": ("01-d.png", (2007, 2853)), "watch": ("01-w.png", (416, 496))}
        for name, size in frames.values():
            self.frame(name, size)
        (loc / "screenshots.json").write_text(json.dumps({key: [f"frames/{name}"] for key, (name, _) in frames.items()}))
        plan = quiet(asc_release.validate_local_inputs, upload_listing=False, upload_whats_new=False,
                     upload_screenshots=True, metadata_dir=self.root / "meta", root=self.root)

        self.stage(plan)

        sets = plan["en-US"]["screenshots"]
        self.assertEqual(list(sets), ["APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129", "APP_IPHONE_DUO", "APP_WATCH_SERIES_10"])
        for display, files in sets.items():
            for path in files:
                with self.subTest(set=display, name=path.name):
                    self.rgb(path)

    def test_the_colour_profile_is_kept(self) -> None:
        from PIL import ImageCms

        icc = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
        gamma = (b"gAMA", (45455).to_bytes(4, "big"))
        chroma = (b"cHRM", bytes(range(32)))
        source = self.frame("01-a.png", (1290, 2796), icc=icc, chunks=(gamma, chroma))
        plan = {"en-US": {"screenshots": {"APP_IPHONE_67": [source]}}}

        self.stage(plan)

        (staged,) = plan["en-US"]["screenshots"]["APP_IPHONE_67"]
        self.assertEqual(self.rgb(staged).info.get("icc_profile"), icc)
        kept = {kind: data for kind, data in asc_release.png_chunks(staged.read_bytes())}
        self.assertEqual(kept.get(b"gAMA"), gamma[1])
        self.assertEqual(kept.get(b"cHRM"), chroma[1])

    def test_a_truncated_frame_that_stores_alpha_fails_cleanly(self) -> None:
        # Pillow only ever gets a complete, well-formed file; a broken one stops the run with a message.
        source = self.frame("01-a.png", (1290, 2796))
        good = source.read_bytes()
        for raw in (good[:-12], good[: len(good) // 2]):
            source.write_bytes(raw)
            plan = {"en-US": {"screenshots": {"APP_IPHONE_67": [source]}}}
            err = io.StringIO()
            with self.subTest(size=len(raw)), redirect_stdout(io.StringIO()), redirect_stderr(err), \
                    self.assertRaises(SystemExit):
                asc_release.stage_screenshots(plan, self.staging)
            self.assertIn("01-a.png is not a readable PNG", err.getvalue())

    def test_the_upload_sends_the_rgb_copy_not_the_committed_file(self) -> None:
        loc = self.root / "meta" / "en-US"
        loc.mkdir(parents=True)
        source = self.frame("01-a.png", (1290, 2796))
        committed = source.read_bytes()
        (loc / "screenshots.json").write_text(json.dumps({"APP_IPHONE_67": ["frames/01-a.png"]}))
        fake = FakeAsc()
        env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        with mock.patch.dict(os.environ, {**env, "UPLOAD_SCREENSHOTS": "true"}, clear=True), \
                mock.patch.object(asc_release, "client_from_environment", return_value=fake), \
                mock.patch.object(asc_release, "ROOT", self.root), redirect_stdout(io.StringIO()):
            asc_release.main(["--version", VERSION, "--metadata-dir", str(self.root / "meta")])
        ((set_id, name, sent),) = fake.uploaded_shots
        self.assertEqual((set_id, name), ("NEW-APP_IPHONE_67", "01-a.png"))
        self.assertEqual(sent[25], 2, "an RGB PNG went to App Store Connect")
        self.assertFalse(asc_release.png_stores_alpha(asc_release.png_chunks(sent)))
        self.assertNotEqual(sent, committed)
        self.assertEqual(source.read_bytes(), committed, "the committed file is untouched")


@functools.lru_cache(maxsize=None)
def creative_png(width: int, height: int, colour_type: int = 2) -> bytes:
    return make_png(width, height, colour_type)


def jpeg(width: int, height: int) -> bytes:
    """A JPEG header with a baseline start-of-frame segment (enough to read its size)."""
    app0 = b"\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    sof0 = b"\xff\xc0\x00\x11\x08" + height.to_bytes(2, "big") + width.to_bytes(2, "big") + b"\x03" + b"\x01\x11\x00" * 3
    return b"\xff\xd8" + app0 + sof0 + b"\xff\xd9"


class CreativeFake(FakeAsc):
    """FakeAsc plus the Asset Library, image placements and any number of review drafts."""

    def __init__(self, *, library: list[dict] | None = None, placements: dict[str, dict] | None = None,
                 drafts: list[str] | None = None, draft_items: dict[str, list[dict]] | None = None,
                 processing: dict[str, list[str]] | None = None, **kwargs) -> None:
        super().__init__(**kwargs)
        self.library = [json_copy(image) for image in library or []]
        # placement id -> {"type", "image", "loc", "group", "state"}
        self.placements = {pid: dict(p) for pid, p in (placements or {}).items()}
        self.draft_ids = list(drafts or [])
        self.items = {draft: list(rows) for draft, rows in (draft_items or {}).items()}
        # image id -> the states successive GETs of the image report while Apple processes it
        self.processing = {image_id: list(states) for image_id, states in (processing or {}).items()}
        self.submitted: list[str] = []
        self.placed: list[dict] = []
        self.counter = 0

    def next_id(self, prefix: str) -> str:
        self.counter += 1
        return f"{prefix}{self.counter}"

    def image(self, image_id: str) -> dict:
        return next(image for image in self.library if image["id"] == image_id)

    def get(self, path: str) -> dict:
        parsed = urllib.parse.urlparse(path)
        query = urllib.parse.parse_qs(parsed.query)
        if path == f"/apps/{APP}/assetLibrary":
            self.calls.append(("GET", path))
            return {"data": {"type": "appAssetLibraries", "id": "LIB"}}
        if parsed.path == "/appAssetLibraries/LIB/images":
            self.calls.append(("GET", path))
            assert query.get("filter[category]") == ["CREATIVE_ASSETS"], path
            return {"data": [json_copy(image) for image in self.library]}
        if parsed.path.startswith("/appAssetLibraryImages/") and parsed.path.endswith("/relationships/placements"):
            self.calls.append(("GET", path))
            image_id = parsed.path.split("/")[2]
            return {"data": [{"type": "appAssetLibraryPlacements", "id": pid}
                             for pid, p in self.placements.items() if p["image"] == image_id]}
        if parsed.path.startswith("/appAssetLibraryImages/"):
            self.calls.append(("GET", path))
            image = self.image(parsed.path.split("/")[2])
            states = self.processing.get(image["id"])
            if states:
                image["attributes"]["state"] = states.pop(0)
                if image["attributes"]["state"] == "PREPARE_FOR_SUBMISSION":
                    image["attributes"]["imageAsset"] = {"width": 1, "height": 1}
            return {"data": json_copy(image)}
        if parsed.path == "/appStoreVersionLocalizations/LOC1/placements":
            self.calls.append(("GET", path))
            wanted = (query.get("filter[placementType]") or [""])[0]
            return {"data": [{"type": "appAssetLibraryPlacements", "id": pid,
                              "attributes": {"placementType": p["type"], "placementGroup": p.get("group", "DEFAULT_PROFILE"),
                                             "state": p.get("state", "ACTIVE")}}
                             for pid, p in self.placements.items() if p["loc"] == "LOC1" and p["type"] == wanted]}
        if path.startswith(f"/apps/{APP}/reviewSubmissions"):
            self.calls.append(("GET", path))
            assert query.get("filter[state]") == ["READY_FOR_REVIEW"], path
            return {"data": [{"type": "reviewSubmissions", "id": draft} for draft in self.draft_ids]}
        if parsed.path.startswith("/reviewSubmissions/") and parsed.path.endswith("/items"):
            self.calls.append(("GET", path))
            assert "appAssetLibraryImage" in (query.get("include") or [""])[0], path
            return {"data": [json_copy(item) for item in self.items.get(parsed.path.split("/")[2], [])]}
        return super().get(path)

    def post(self, path: str, body: dict) -> dict:
        data = body["data"]
        if path == "/appAssetLibraryImages":
            self.calls.append(("POST", path))
            image_id = self.next_id("IMG")
            attributes = data["attributes"]
            self.library.append({"id": image_id, "attributes": {**attributes, "state": "AWAITING_UPLOAD",
                                                                 "createdDate": "2026-10-21"}})
            ops = [{"url": f"https://upload.example/{image_id}", "offset": 0, "length": attributes["fileSize"],
                    "method": "PUT", "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]}]
            return {"data": {"type": "appAssetLibraryImages", "id": image_id,
                             "attributes": {"state": "AWAITING_UPLOAD", "uploadOperations": ops}}}
        if path == "/reviewSubmissions":
            self.calls.append(("POST", path))
            draft = self.next_id("DRAFT")
            self.draft_ids.append(draft)
            self.items[draft] = []
            return {"data": {"type": "reviewSubmissions", "id": draft}}
        if path == "/reviewSubmissionItems":
            self.calls.append(("POST", path))
            rels = data["relationships"]
            draft = rels["reviewSubmission"]["data"]["id"]
            (name, related_row), = [(k, v) for k, v in rels.items() if k != "reviewSubmission"]
            self.items.setdefault(draft, []).append(
                {"id": self.next_id("ITEM"), "relationships": {name: {"data": dict(related_row["data"])}}})
            if name == "appAssetLibraryImage":
                self.image(related_row["data"]["id"])["attributes"]["state"] = "READY_FOR_REVIEW"
            return {"data": {"type": "reviewSubmissionItems", "id": "ITEM"}}
        if path == "/appAssetLibraryPlacements":
            self.calls.append(("POST", path))
            self.placed.append(body)
            rels = data["relationships"]
            swap = (rels.get("placementToSwapOut") or {}).get("data")
            if swap:
                del self.placements[swap["id"]]
            self.placements[self.next_id("PL")] = {
                "type": data["attributes"]["placementType"], "image": rels["image"]["data"]["id"],
                "loc": rels["appStoreVersionLocalization"]["data"]["id"],
                "group": data["attributes"]["placementGroup"]}
            return {"data": {"type": "appAssetLibraryPlacements", "id": "PL"}}
        return super().post(path, body)

    def patch(self, path: str, body: dict) -> dict:
        if path.startswith("/appAssetLibraryImages/"):
            self.calls.append(("PATCH", path))
            image = self.image(path.split("/")[2])
            assert body["data"]["attributes"] == {"uploaded": True}
            image["attributes"]["state"] = "UPLOAD_COMPLETE"
            self.processing.setdefault(image["id"], ["UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION"])
            return {"data": body["data"]}
        return super().patch(path, body)

    def request(self, method: str, path: str, *, body: dict | None = None):
        if method == "PATCH" and path.startswith("/reviewSubmissions/"):
            self.calls.append((method, path))
            draft = path.split("/")[2]
            assert body is not None and body["data"]["attributes"] == {"submitted": True}
            self.submitted.append(draft)
            self.draft_ids.remove(draft)
            for item in self.items.get(draft, []):
                image_id = related(item, "appAssetLibraryImage")
                if image_id:
                    self.image(image_id)["attributes"]["state"] = "WAITING_FOR_REVIEW"
            return None
        return super().request(method, path, body=body)

    def upload_bytes(self, url: str, data: bytes, headers: dict, *, method: str = "PUT") -> None:
        if "/IMG" not in url:
            return super().upload_bytes(url, data, headers, method=method)
        self.calls.append(("UPLOAD", url))
        image = self.image(url.rsplit("/", 1)[1])
        assert len(data) == image["attributes"]["fileSize"] and headers == {"Content-Type": "image/png"}
        return None


def json_copy(value):
    return json.loads(json.dumps(value))


def related(item: dict, name: str):
    return ((item.get("relationships") or {}).get(name) or {}).get("data", {}).get("id")


def image_item(image_id: str) -> dict:
    return {"id": f"I-{image_id}", "relationships": {"appAssetLibraryImage": {"data": {"type": "appAssetLibraryImages", "id": image_id}}}}


def version_item(version_id: str = "V1") -> dict:
    return {"id": f"I-{version_id}", "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}


class CreativeAssetTests(unittest.TestCase):
    """Header and search results images: Asset Library upload, their own review, placement."""

    ENV = {"UPLOAD_CREATIVE_ASSETS": "true"}

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name) / "creative"
        self.header = self.dir / "header" / "header.png"
        self.search = self.dir / "search-results" / "search.png"
        for path, raw in ((self.header, creative_png(3840, 1646)), (self.search, creative_png(1920, 1280))):
            path.parent.mkdir(parents=True)
            path.write_bytes(raw)
        sleep = mock.patch.object(asc_release.time, "sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

    def image(self, image_id: str, path: Path, state: str, created: str = "2026-10-20") -> dict:
        return {"id": image_id, "attributes": {"fileName": path.name, "fileSize": path.stat().st_size,
                                               "state": state, "createdDate": created,
                                               "imageAsset": {"width": 1, "height": 1}}}

    def run_main(self, fake: FakeAsc, env: dict[str, str] | None = None, *extra: str,
                 creative_dir: Path | None = None) -> int:
        argv = ["--version", VERSION, "--creative-dir", str(creative_dir or self.dir), *extra]
        full_env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        full_env.update(env if env is not None else self.ENV)
        with mock.patch.dict(os.environ, full_env, clear=True), \
                mock.patch.object(asc_release, "client_from_environment", return_value=fake), \
                redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            try:
                asc_release.main(argv)
            except SystemExit as exc:
                return exc.code if isinstance(exc.code, int) else 1
        return 0

    def submit(self, fake: FakeAsc) -> int:
        return self.run_main(fake, {**self.ENV, "SUBMIT_IOS_REVIEW": "true"},
                             "--build-id", "B9", "--build-number", "14")

    def image_review_drafts(self, fake: CreativeFake) -> set[str]:
        return {draft for draft, items in fake.items.items() if any(related(i, "appAssetLibraryImage") for i in items)}

    def test_new_images_are_uploaded_once_and_reviewed_on_their_own(self) -> None:
        fake = CreativeFake()
        self.assertEqual(self.run_main(fake), 0)
        posts = [c for c in writes(fake) if c == ("POST", "/appAssetLibraryImages")]
        self.assertEqual(len(posts), 2)
        self.assertEqual([c[0] for c in writes(fake) if c[1].startswith(("https://upload", "/appAssetLibraryImages/"))],
                         ["UPLOAD", "PATCH", "UPLOAD", "PATCH"])
        uploaded = {image["attributes"]["fileName"]: image["attributes"] for image in fake.library}
        self.assertEqual(set(uploaded), {"header.png", "search.png"})
        self.assertEqual({a["category"] for a in uploaded.values()}, {"CREATIVE_ASSETS"})
        self.assertEqual(uploaded["header.png"]["fileSize"], self.header.stat().st_size)
        # One submission of their own, holding exactly the two images, submitted.
        self.assertEqual(len(fake.submitted), 1)
        held = [related(item, "appAssetLibraryImage") for item in fake.items[fake.submitted[0]]]
        self.assertEqual(sorted(held), sorted(image["id"] for image in fake.library))
        self.assertEqual(fake.placed, [], "images are placed only once Apple approves them")
        # The next run finds them in review: nothing is uploaded, reviewed or placed again.
        before = len(writes(fake))
        self.assertEqual(self.run_main(fake), 0)
        self.assertEqual(len(writes(fake)), before)

    def test_approved_and_placed_images_are_recognised(self) -> None:
        library = [self.image("HDR", self.header, "APPROVED"), self.image("SRCH", self.search, "APPROVED")]
        placements = {"PL-H": {"type": "PRODUCT_PAGE_HEADER_ASSET", "image": "HDR", "loc": "LOC1"},
                      "PL-S": {"type": "APP_STORE_SEARCH_RESULTS_ASSET", "image": "SRCH", "loc": "LOC1"}}
        fake = CreativeFake(library=library, placements=placements)
        self.assertEqual(self.run_main(fake), 0)
        self.assertEqual(writes(fake), [])
        self.assertIn(("GET", "/appAssetLibraryImages/HDR/relationships/placements?limit=50"), fake.calls)

    def test_approved_images_are_placed_on_the_version(self) -> None:
        fake = CreativeFake(library=[self.image("H", self.header, "APPROVED"), self.image("S", self.search, "APPROVED")],
                            # Placed on another version's localization only.
                            placements={"PL-OLD": {"type": "PRODUCT_PAGE_HEADER_ASSET", "image": "H", "loc": "LOC-201"}})
        self.assertEqual(self.run_main(fake), 0)
        self.assertEqual(fake.placed, [
            {"data": {"type": "appAssetLibraryPlacements",
                      "attributes": {"placementType": placement, "placementGroup": "DEFAULT_PROFILE"},
                      "relationships": {"image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
                                        "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations",
                                                                                 "id": "LOC1"}}}}}
            for placement, image_id in (("PRODUCT_PAGE_HEADER_ASSET", "H"), ("APP_STORE_SEARCH_RESULTS_ASSET", "S"))
        ])
        self.assertNotIn(("POST", "/appAssetLibraryImages"), fake.calls)
        self.assertEqual(fake.submitted, [])
        # A second run finds both placed and writes nothing.
        before = len(writes(fake))
        self.assertEqual(self.run_main(fake), 0)
        self.assertEqual(len(writes(fake)), before)

    def test_another_image_in_the_slot_is_swapped_out_in_one_request(self) -> None:
        fake = CreativeFake(library=[self.image("H", self.header, "APPROVED"), self.image("S", self.search, "IN_REVIEW")],
                            placements={"PL-OLD": {"type": "PRODUCT_PAGE_HEADER_ASSET", "image": "OLDIMG", "loc": "LOC1"}})
        self.assertEqual(self.run_main(fake), 0)
        self.assertEqual(len(fake.placed), 1)
        rels = fake.placed[0]["data"]["relationships"]
        self.assertEqual(rels["placementToSwapOut"], {"data": {"type": "appAssetLibraryPlacements", "id": "PL-OLD"}})
        self.assertEqual(rels["image"]["data"]["id"], "H")
        self.assertNotIn("PL-OLD", fake.placements)

    def test_an_interrupted_upload_is_uploaded_again(self) -> None:
        stale = self.image("STALE", self.header, "AWAITING_UPLOAD", created="2026-10-21")
        fake = CreativeFake(library=[stale, self.image("S", self.search, "APPROVED")])
        self.assertEqual(self.run_main(fake), 0)
        self.assertEqual([c for c in writes(fake) if c == ("POST", "/appAssetLibraryImages")],
                         [("POST", "/appAssetLibraryImages")])
        reviewed = {related(item, "appAssetLibraryImage") for item in fake.items[fake.submitted[0]]}
        self.assertNotIn("STALE", reviewed)
        self.assertEqual(len(reviewed), 1)
        # Failed and archived images do not count either.
        for state in ("FAILED", "ARCHIVED"):
            fake = CreativeFake(library=[self.image("OLD", self.header, state), self.image("S", self.search, "APPROVED")])
            with self.subTest(state=state):
                self.assertEqual(self.run_main(fake), 0)
                self.assertIn(("POST", "/appAssetLibraryImages"), fake.calls)

    def test_an_uploaded_image_still_processing_is_reviewed_once_ready(self) -> None:
        fake = CreativeFake(library=[self.image("H", self.header, "UPLOAD_COMPLETE"), self.image("S", self.search, "APPROVED")],
                            processing={"H": ["UPLOAD_COMPLETE", "COMPLETE", "PREPARE_FOR_SUBMISSION"]})
        self.assertEqual(self.run_main(fake), 0)
        self.assertNotIn(("POST", "/appAssetLibraryImages"), fake.calls)
        self.assertEqual(fake.processing["H"], [], "the run waits until Apple has processed the image")
        self.assertEqual([related(i, "appAssetLibraryImage") for i in fake.items[fake.submitted[0]]], ["H"])

    def test_processing_failure_or_timeout_stops_before_review(self) -> None:
        fake = CreativeFake(library=[self.image("H", self.header, "UPLOAD_COMPLETE")], processing={"H": ["FAILED"]})
        self.assertEqual(self.run_main(fake), 1)
        self.assertEqual(fake.submitted, [])
        self.assertNotIn(("POST", "/reviewSubmissionItems"), fake.calls)
        fake = CreativeFake(library=[self.image("H", self.header, "UPLOAD_COMPLETE")],
                            processing={"H": ["UPLOAD_COMPLETE"] * 5})
        with mock.patch.object(asc_release, "CREATIVE_PROCESSING_TIMEOUT_SECONDS", 0):
            self.assertEqual(self.run_main(fake), 1)
        self.assertNotIn(("POST", "/reviewSubmissionItems"), fake.calls)

    def test_images_in_review_are_neither_uploaded_nor_placed(self) -> None:
        for state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED"):
            fake = CreativeFake(library=[self.image("H", self.header, state), self.image("S", self.search, state)])
            with self.subTest(state=state):
                self.assertEqual(self.run_main(fake), 0)
                self.assertEqual(writes(fake), [])

    def test_a_rejected_image_stops_the_run_before_any_write(self) -> None:
        rejected = self.image("H", self.header, "REJECTED")
        rejected["attributes"]["stateDetails"] = [{"code": "IMAGE_QUALITY"}]
        fake = CreativeFake(library=[rejected, self.image("S", self.search, "PREPARE_FOR_SUBMISSION")])
        self.assertEqual(self.run_main(fake), 1)
        self.assertEqual(writes(fake), [])

    def test_a_locked_version_takes_no_new_images(self) -> None:
        for state, attached in (("WAITING_FOR_REVIEW", "B9"), ("READY_FOR_REVIEW", "B9")):
            for library in ([], [self.image("H", self.header, "PREPARE_FOR_SUBMISSION")]):
                fake = CreativeFake(state=state, attached=attached, library=library)
                with self.subTest(state=state, library=bool(library)):
                    self.assertEqual(self.run_main(fake), 1)
                    self.assertEqual(writes(fake), [])

    def test_an_approved_image_on_a_locked_version_waits_without_failing(self) -> None:
        # Approval can land between a submit and a re-run of the store job.
        fake = CreativeFake(state="WAITING_FOR_REVIEW", attached="B9",
                            library=[self.image("H", self.header, "APPROVED"), self.image("S", self.search, "IN_REVIEW")])
        self.assertEqual(self.run_main(fake), 0)
        self.assertEqual(writes(fake), [])

    def test_images_never_go_into_the_versions_draft(self) -> None:
        # The version's draft is picked (and reserved) before any write; the
        # empty draft goes to the version and the images get their own submission.
        fake = CreativeFake(drafts=["EMPTY"], draft_items={"EMPTY": []})
        self.assertEqual(self.submit(fake), 0)
        self.assertEqual(len(fake.submitted), 2)
        self.assertEqual(fake.submitted[-1], "EMPTY", "the version went out in the reserved draft")
        self.assertEqual([related(i, "appStoreVersion") for i in fake.items["EMPTY"]], ["V1"])
        self.assertEqual(self.image_review_drafts(fake), {fake.submitted[0]})
        self.assertNotIn("EMPTY", self.image_review_drafts(fake))

    def test_a_creative_draft_is_never_used_for_the_version(self) -> None:
        library = [self.image("H", self.header, "WAITING_FOR_REVIEW"), self.image("S", self.search, "APPROVED")]
        placements = {"P": {"type": "APP_STORE_SEARCH_RESULTS_ASSET", "image": "S", "loc": "LOC1"}}
        # A draft holding an image (left by hand or another tool) is not the version's.
        fake = CreativeFake(library=library, placements=placements, drafts=["IMAGES"],
                            draft_items={"IMAGES": [image_item("OTHER")]})
        self.assertEqual(self.submit(fake), 0)
        self.assertEqual(fake.items["IMAGES"], [image_item("OTHER")])
        self.assertEqual(len(fake.submitted), 1)
        self.assertNotEqual(fake.submitted[0], "IMAGES")
        self.assertIn(("POST", "/reviewSubmissions"), fake.calls)

    def test_a_ready_for_review_version_its_draft_does_not_hold_stops_before_any_write(self) -> None:
        # Images that need nothing (one placed, one in review) and images that would need a
        # review: either way the missing draft stops the run first.
        settled = ([self.image("H", self.header, "APPROVED"), self.image("S", self.search, "IN_REVIEW")],
                   {"P": {"type": "PRODUCT_PAGE_HEADER_ASSET", "image": "H", "loc": "LOC1"}})
        for library, placements in (([self.image("H", self.header, "PREPARE_FOR_SUBMISSION")], {}), settled):
            # The only draft holding the version also holds an image, so it is not the version's draft.
            for drafts, items in (([], {}), (["MIXED"], {"MIXED": [version_item(), image_item("X")]})):
                fake = CreativeFake(state="READY_FOR_REVIEW", library=library, placements=placements,
                                    drafts=drafts, draft_items=items)
                with self.subTest(images=len(placements), drafts=drafts):
                    self.assertEqual(self.submit(fake), 1)
                    self.assertEqual(writes(fake), [])

    def test_the_draft_holding_this_version_is_reserved_over_others(self) -> None:
        fake = CreativeFake(state="READY_FOR_REVIEW", drafts=["EMPTY", "MINE"],
                            draft_items={"EMPTY": [], "MINE": [version_item()]},
                            library=[self.image("H", self.header, "APPROVED"), self.image("S", self.search, "IN_REVIEW")],
                            placements={"P": {"type": "PRODUCT_PAGE_HEADER_ASSET", "image": "H", "loc": "LOC1"}})
        self.assertEqual(self.submit(fake), 0)
        self.assertEqual(fake.submitted, ["MINE"])
        self.assertEqual(fake.items["EMPTY"], [])

    def test_a_rerun_finishes_the_draft_an_interrupted_review_left(self) -> None:
        library = [self.image("H", self.header, "READY_FOR_REVIEW"), self.image("S", self.search, "PREPARE_FOR_SUBMISSION")]
        # A draft already holding some of the images is finished before an empty one.
        fake = CreativeFake(library=library, drafts=["EMPTY", "PART"],
                            draft_items={"EMPTY": [], "PART": [image_item("H")]})
        self.assertEqual(self.run_main(fake), 0)
        self.assertNotIn(("POST", "/reviewSubmissions"), fake.calls)
        self.assertEqual(fake.submitted, ["PART"])
        self.assertEqual(sorted(related(i, "appAssetLibraryImage") for i in fake.items["PART"]), ["H", "S"])
        self.assertEqual(fake.items["EMPTY"], [])
        # Else an empty draft (a run stopped before it added the images) is used.
        fake = CreativeFake(library=[self.image("S", self.search, "PREPARE_FOR_SUBMISSION")],
                            drafts=["EMPTY"], draft_items={"EMPTY": []})
        self.assertEqual(self.run_main(fake), 0)
        self.assertNotIn(("POST", "/reviewSubmissions"), fake.calls)
        self.assertEqual(fake.submitted, ["EMPTY"])
        # A draft holding anything else is left alone and a new one is created.
        fake = CreativeFake(library=[self.image("S", self.search, "PREPARE_FOR_SUBMISSION")],
                            drafts=["OTHER"], draft_items={"OTHER": [version_item("V0")]})
        self.assertEqual(self.run_main(fake), 0)
        self.assertIn(("POST", "/reviewSubmissions"), fake.calls)
        self.assertEqual(fake.items["OTHER"], [version_item("V0")])
        self.assertNotIn("OTHER", fake.submitted)

    def test_a_creative_submission_holding_other_items_is_not_submitted(self) -> None:
        class Crowded(CreativeFake):
            def post(self, path: str, body: dict) -> dict:
                result = super().post(path, body)
                if path == "/reviewSubmissions":
                    # Something else lands in the new draft before it is submitted.
                    self.items[result["data"]["id"]].append(version_item("V0"))
                return result

        fake = Crowded(library=[self.image("S", self.search, "PREPARE_FOR_SUBMISSION")])
        self.assertEqual(self.run_main(fake), 1)
        self.assertEqual(fake.submitted, [])

    def test_images_apple_would_refuse_fail_before_any_call(self) -> None:
        cases = [
            (self.header, creative_png(3840, 2160), "header.png"),
            (self.header, creative_png(3840, 1646, 6), "header.png"),
            (self.header, jpeg(3840, 1646), "header.jpg"),
            (self.header, jpeg(3840, 1646), "header.png"),
            (self.search, creative_png(3000, 2001), "search.png"),
            (self.search, creative_png(1800, 1200), "search.png"),
            (self.search, creative_png(3900, 2600), "search.png"),
            (self.search, creative_png(1920, 1280, 4), "search.png"),
            (self.search, make_png(1920, 1280, 2, chunks=((b"tRNS", b"\x00" * 6),)), "search.png"),
            (self.search, jpeg(4000, 2666), "search.jpg"),
            (self.search, b"GIF89a", "search.png"),
            # Truncated or corrupt files with the right header fail too.
            (self.header, creative_png(3840, 1646)[:-12], "header.png"),
            (self.header, creative_png(3840, 1646)[:8 + 25], "header.png"),
            (self.search, creative_png(1920, 1280)[: len(creative_png(1920, 1280)) // 2], "search.png"),
        ]
        for path, raw, name in cases:
            original = path.read_bytes()
            path.unlink()
            (path.parent / name).write_bytes(raw)
            fake = CreativeFake()
            with self.subTest(slot=path.parent.name, name=name, raw=raw[:26]):
                self.assertEqual(self.run_main(fake), 1)
                self.assertEqual(fake.calls, [])
            (path.parent / name).unlink()
            path.write_bytes(original)

    def test_sizes_and_formats_apple_takes_pass(self) -> None:
        for name, raw in (("search.jpg", jpeg(1920, 1280)), ("search.jpeg", jpeg(3840, 2560)),
                          ("search.png", creative_png(3840, 2560)), ("search.png", creative_png(3000, 2000))):
            self.search.unlink()
            (self.search.parent / name).write_bytes(raw)
            with self.subTest(name=name, raw=raw[:26]):
                sources = quiet(asc_release.creative_sources, self.dir)
                self.assertEqual([(p, path.name) for p, _, path in sources],
                                 [("PRODUCT_PAGE_HEADER_ASSET", "header.png"), ("APP_STORE_SEARCH_RESULTS_ASSET", name)])
            (self.search.parent / name).unlink()
            self.search.write_bytes(creative_png(1920, 1280))

    def test_a_slot_takes_one_image_and_at_least_one_slot_needs_one(self) -> None:
        (self.header.parent / "header-2.png").write_bytes(creative_png(3840, 1646))
        fake = CreativeFake()
        self.assertEqual(self.run_main(fake), 1)
        self.assertEqual(fake.calls, [])
        (self.header.parent / "header-2.png").unlink()
        # Other files (notes, .DS_Store) do not count; an empty slot is left alone.
        (self.header.parent / "README.md").write_text("notes")
        self.header.unlink()
        self.assertEqual([p for p, _, _ in quiet(asc_release.creative_sources, self.dir)],
                         ["APP_STORE_SEARCH_RESULTS_ASSET"])
        self.search.unlink()
        fake = CreativeFake()
        self.assertEqual(self.run_main(fake), 1)
        self.assertEqual(fake.calls, [])

    @committed_files_test
    def test_the_repository_images_pass_the_local_checks(self) -> None:
        # Each slot has its folder; no image is committed yet, so the switch has nothing to
        # upload (and fails if turned on). An image added later must pass the local checks.
        directory = asc_release.DEFAULT_CREATIVE_DIR
        images = sorted(path for folder, _, _, _ in asc_release.CREATIVE_SLOTS
                        for path in (directory / folder).iterdir()
                        if path.suffix.lower() in asc_release.CREATIVE_EXTENSIONS)
        self.assertTrue(all((directory / folder).is_dir() for folder, _, _, _ in asc_release.CREATIVE_SLOTS))
        if images:
            sources = quiet(asc_release.creative_sources, directory)
            self.assertEqual(sorted(path for _, _, path in sources), images)
        else:
            with self.assertRaises(SystemExit):
                quiet(asc_release.creative_sources, directory)

    def preflight(self, fake: FakeAsc, *, submit: bool = False) -> None:
        quiet(asc_release.preflight, fake, bundle_id=asc_release.DEFAULT_BUNDLE_ID, version_string=VERSION, plan={},
              do_listing=False, do_whats_new=False, do_screenshots=False, do_submit=submit,
              do_creative=True, creative_dir=self.dir)

    def test_the_preflight_stops_before_the_build_when_the_version_cannot_take_the_images(self) -> None:
        # In a review submission the version takes no new image: found before the build, not after.
        for library in ([], [self.image("H", self.header, "PREPARE_FOR_SUBMISSION")]):
            fake = CreativeFake(state="READY_FOR_REVIEW", library=library,
                                drafts=["MINE"], draft_items={"MINE": [version_item()]})
            with self.subTest(library=bool(library)), self.assertRaises(SystemExit):
                self.preflight(fake)
            self.assertEqual(writes(fake), [])
        # A rejected image stops it in any state.
        rejected = [self.image("H", self.header, "REJECTED"), self.image("S", self.search, "APPROVED")]
        with self.assertRaises(SystemExit):
            self.preflight(CreativeFake(library=rejected))

    def test_the_preflight_passes_what_the_store_step_can_do(self) -> None:
        cases = [
            # An editable version takes new images (uploaded by the store step, not here).
            ("PREPARE_FOR_SUBMISSION", []),
            # Images in review or approved wait for a later run without failing.
            ("READY_FOR_REVIEW", [self.image("H", self.header, "IN_REVIEW"), self.image("S", self.search, "APPROVED")]),
        ]
        for state, library in cases:
            fake = CreativeFake(state=state, library=library, drafts=["MINE"], draft_items={"MINE": [version_item()]})
            with self.subTest(state=state):
                self.preflight(fake, submit=True)
                self.assertEqual(writes(fake), [])

    def test_the_preflight_checks_a_ready_for_review_versions_draft(self) -> None:
        library = [self.image("H", self.header, "APPROVED"), self.image("S", self.search, "IN_REVIEW")]
        placements = {"P": {"type": "PRODUCT_PAGE_HEADER_ASSET", "image": "H", "loc": "LOC1"}}
        for drafts, items in (([], {}), (["MIXED"], {"MIXED": [version_item(), image_item("X")]})):
            fake = CreativeFake(state="READY_FOR_REVIEW", library=library, placements=placements,
                                drafts=drafts, draft_items=items)
            with self.subTest(drafts=drafts), self.assertRaises(SystemExit):
                self.preflight(fake, submit=True)
            self.assertEqual(writes(fake), [])
            # Without review submission the draft does not matter.
            self.preflight(fake, submit=False)

    def test_dry_run_checks_the_images_without_calls(self) -> None:
        out = io.StringIO()
        env = {k: v for k, v in os.environ.items() if k not in ASC_FLAGS}
        with mock.patch.dict(os.environ, {**env, **self.ENV}, clear=True), \
                mock.patch.object(asc_release, "client_from_environment") as client, \
                redirect_stdout(out), redirect_stderr(out):
            asc_release.main(["--dry-run", "--creative-dir", str(self.dir)])
        client.assert_not_called()
        self.assertIn("creative=True", out.getvalue())
        self.header.write_bytes(creative_png(3840, 1646, 6))
        with mock.patch.dict(os.environ, {**env, **self.ENV}, clear=True), \
                redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            asc_release.main(["--dry-run", "--creative-dir", str(self.dir)])


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
