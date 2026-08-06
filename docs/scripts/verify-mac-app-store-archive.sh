#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="verify"
ARCHIVE_PATH="${MAC_ARCHIVE_PATH:-}"

if [ "${1:-}" = "--self-test" ]; then
  if [ "$#" -ne 1 ]; then
    echo "Usage: $0 --self-test" >&2
    exit 2
  fi
  MODE="self-test"
  ARCHIVE_PATH=""
elif [ "$#" -eq 1 ]; then
  ARCHIVE_PATH="$1"
elif [ "$#" -ne 0 ]; then
  echo "Usage: $0 /absolute/path/to/Mac-App.xcarchive" >&2
  echo "       MAC_ARCHIVE_PATH=/absolute/path/to/Mac-App.xcarchive $0" >&2
  echo "       $0 --self-test" >&2
  exit 2
fi

if [ "$MODE" = "verify" ] && [ -z "$ARCHIVE_PATH" ]; then
  echo "FAIL Mac archive input — supply a real .xcarchive path or MAC_ARCHIVE_PATH." >&2
  exit 2
fi

/usr/bin/python3 - "$ROOT_DIR" "$MODE" "$ARCHIVE_PATH" <<'PY'
import datetime as dt
import hashlib
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(sys.argv[1]).resolve()
MODE = sys.argv[2]
ARCHIVE_ARGUMENT = sys.argv[3]
PROJECT_FILE = ROOT / "project.yml"
SOURCE_OPPORTUNITIES = ROOT / "GTAFreeSTEM" / "Resources" / "opportunities.json"
SOURCE_PRIVACY = ROOT / "GTAFreeSTEM" / "Resources" / "PrivacyInfo.xcprivacy"
EXPECTED_BUNDLE_ID = "com.rupayonhaldar.gtafreestem.maccatalyst"


class InspectionError(Exception):
    pass


def source_setting(name):
    text = PROJECT_FILE.read_text(encoding="utf-8")
    match = re.search(
        r"^\s*{}:\s*[\"']?([^\"'\n#]+)".format(re.escape(name)),
        text,
        re.MULTILINE,
    )
    if not match:
        raise SystemExit("Unable to resolve {} from {}".format(name, PROJECT_FILE))
    return match.group(1).strip()


EXPECTED_VERSION = source_setting("MARKETING_VERSION")
EXPECTED_BUILD = source_setting("CURRENT_PROJECT_VERSION")
EXPECTED_TEAM = source_setting("DEVELOPMENT_TEAM")
EXPECTED_MINIMUM_SYSTEM = source_setting("macOS")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_plist(path):
    with path.open("rb") as stream:
        value = plistlib.load(stream)
    if not isinstance(value, dict):
        raise ValueError("property-list root is not a dictionary")
    return value


def extract_xml_plist(payload):
    start = payload.find(b"<?xml")
    end_marker = b"</plist>"
    end = payload.rfind(end_marker)
    if start < 0 or end < start:
        raise InspectionError("command did not emit an XML property list")
    try:
        value = plistlib.loads(payload[start : end + len(end_marker)])
    except Exception as error:
        raise InspectionError("unable to parse property list: {}".format(error))
    if not isinstance(value, dict):
        raise InspectionError("property-list root is not a dictionary")
    return value


def application_identifier(entitlements):
    return entitlements.get("com.apple.application-identifier") or entitlements.get("application-identifier")


def debug_entitlement(entitlements):
    return entitlements.get("com.apple.security.get-task-allow", entitlements.get("get-task-allow"))


class LiveInspector:
    @staticmethod
    def run(command):
        try:
            return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        except OSError as error:
            raise InspectionError("unable to run {}: {}".format(command[0], error))

    def signature(self, bundle):
        verification = self.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=4", str(bundle)])
        if verification.returncode != 0:
            detail = (verification.stderr or verification.stdout).decode("utf-8", "replace").strip()
            raise InspectionError("codesign verification failed: {}".format(detail or "no detail"))
        details = self.run(["/usr/bin/codesign", "-d", "--verbose=4", str(bundle)])
        payload = details.stdout + details.stderr
        text = payload.decode("utf-8", "replace")
        if details.returncode != 0:
            raise InspectionError("unable to inspect code signature: {}".format(text.strip()))
        if re.search(r"^Signature=adhoc$", text, re.MULTILINE):
            raise InspectionError("ad-hoc code signature")
        authorities = re.findall(r"^Authority=(.+)$", text, re.MULTILINE)
        team_match = re.search(r"^TeamIdentifier=(.+)$", text, re.MULTILINE)
        if not authorities:
            raise InspectionError("signature has no certificate authority")
        return {
            "authority": authorities[0].strip(),
            "team": team_match.group(1).strip() if team_match else "",
        }

    def entitlements(self, bundle):
        completed = self.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)])
        payload = completed.stdout + completed.stderr
        if completed.returncode != 0:
            raise InspectionError("unable to inspect entitlements: {}".format(payload.decode("utf-8", "replace").strip()))
        return extract_xml_plist(payload)

    def profile(self, path):
        completed = self.run(["/usr/bin/security", "cms", "-D", "-i", str(path)])
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).decode("utf-8", "replace").strip()
            raise InspectionError("unable to decode provisioning profile: {}".format(detail or "no detail"))
        try:
            value = plistlib.loads(completed.stdout)
        except Exception as error:
            raise InspectionError("unable to parse provisioning profile: {}".format(error))
        if not isinstance(value, dict):
            raise InspectionError("provisioning profile root is not a dictionary")
        return value

    def uuids(self, path):
        completed = self.run(["/usr/bin/xcrun", "dwarfdump", "--uuid", str(path)])
        payload = completed.stdout + completed.stderr
        if completed.returncode != 0:
            raise InspectionError("dwarfdump failed: {}".format(payload.decode("utf-8", "replace").strip()))
        pairs = set()
        for match in re.finditer(rb"^UUID:\s*([0-9A-Fa-f-]{36})\s*\(([^)]+)\)", payload, re.MULTILINE):
            pairs.add((match.group(1).decode("ascii").upper(), match.group(2).decode("utf-8")))
        if not pairs:
            raise InspectionError("dwarfdump emitted no Mach-O UUIDs")
        return pairs


class FixtureInspector:
    def __init__(self, broken_security=False):
        self.broken_security = broken_security

    def signature(self, bundle):
        authority = "Apple Development: Fixture ({})" if self.broken_security else "Apple Distribution: Fixture ({})"
        return {"authority": authority.format(EXPECTED_TEAM), "team": EXPECTED_TEAM}

    def entitlements(self, bundle):
        return {
            "com.apple.application-identifier": "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID),
            "com.apple.developer.team-identifier": EXPECTED_TEAM,
            "com.apple.security.app-sandbox": not self.broken_security,
            "com.apple.security.network.client": True,
            "com.apple.security.personal-information.location": True,
            "com.apple.security.get-task-allow": self.broken_security,
        }

    def profile(self, path):
        entitlements = {
            "com.apple.application-identifier": "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID),
            "com.apple.developer.team-identifier": EXPECTED_TEAM,
            "get-task-allow": self.broken_security,
            "beta-reports-active": not self.broken_security,
        }
        profile = {
            "Name": "Fixture Mac App Store Profile",
            "UUID": "00000000-0000-0000-0000-000000000000",
            "TeamIdentifier": [EXPECTED_TEAM],
            "ExpirationDate": dt.datetime(2099, 1, 1),
            "Entitlements": entitlements,
        }
        if self.broken_security:
            profile["ProvisionedDevices"] = ["fixture-device"]
        return profile

    def uuids(self, path):
        return {("33333333-3333-3333-3333-333333333333", "arm64")}


class Reporter:
    def __init__(self, emit=True):
        self.emit = emit
        self.passes = []
        self.failures = []

    def pass_(self, label, evidence):
        line = "PASS {} — {}".format(label, evidence)
        self.passes.append(line)
        if self.emit:
            print(line)

    def fail(self, label, evidence):
        line = "FAIL {} — {}".format(label, evidence)
        self.failures.append(line)
        if self.emit:
            print(line)

    def expect(self, condition, label, pass_evidence, fail_evidence):
        if condition:
            self.pass_(label, pass_evidence)
        else:
            self.fail(label, fail_evidence)


def load_plist(path, label, reporter):
    if not path.is_file():
        reporter.fail(label, "missing {}".format(path))
        return None
    try:
        value = read_plist(path)
    except Exception as error:
        reporter.fail(label, "invalid property list at {}: {}".format(path, error))
        return None
    reporter.pass_(label, "valid property list at {}".format(path))
    return value


def check_hash(label, archived_path, source_path, reporter):
    if not archived_path.is_file():
        reporter.fail(label, "missing {}".format(archived_path))
        return
    if not source_path.is_file():
        reporter.fail(label, "current source resource is missing: {}".format(source_path))
        return
    archived_hash = sha256(archived_path)
    source_hash = sha256(source_path)
    reporter.expect(
        archived_hash == source_hash,
        label,
        "sha256={} matches {}".format(archived_hash, source_path.relative_to(ROOT)),
        "archive sha256={} but current source sha256={}".format(archived_hash, source_hash),
    )


def distribution_authority(value):
    return value.startswith("Apple Distribution:") or value.startswith("3rd Party Mac Developer Application:")


def check_signature(app, inspector, reporter):
    try:
        signature = inspector.signature(app)
    except InspectionError as error:
        reporter.fail("Mac code signature", str(error))
        return
    authority = signature.get("authority", "")
    team = signature.get("team", "")
    reporter.expect(
        distribution_authority(authority),
        "Mac code signature",
        "{}; TeamIdentifier={}".format(authority, team or "missing"),
        "expected Apple Distribution/Mac App Store authority, observed {}".format(authority or "none"),
    )
    reporter.expect(team == EXPECTED_TEAM, "Mac signing team", team, "expected {}, observed {}".format(EXPECTED_TEAM, team or "missing"))


def check_entitlements(app, inspector, reporter):
    try:
        entitlements = inspector.entitlements(app)
    except InspectionError as error:
        reporter.fail("Mac entitlements", str(error))
        return
    expected_identifier = "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID)
    reporter.expect(debug_entitlement(entitlements) is not True, "Mac get-task-allow", "false or absent", "debug entitlement is true")
    reporter.expect(entitlements.get("com.apple.security.app-sandbox") is True, "Mac App Sandbox", "enabled", "com.apple.security.app-sandbox must be true")
    reporter.expect(entitlements.get("com.apple.security.network.client") is True, "Mac outbound network entitlement", "enabled", "com.apple.security.network.client must be true")
    reporter.expect(entitlements.get("com.apple.security.personal-information.location") is True, "Mac location entitlement", "enabled", "location entitlement must be true")
    reporter.expect(application_identifier(entitlements) == expected_identifier, "Mac application identifier entitlement", expected_identifier, "expected {}, observed {!r}".format(expected_identifier, application_identifier(entitlements)))
    reporter.expect(entitlements.get("com.apple.developer.team-identifier") == EXPECTED_TEAM, "Mac team entitlement", EXPECTED_TEAM, "expected {}, observed {!r}".format(EXPECTED_TEAM, entitlements.get("com.apple.developer.team-identifier")))


def profile_path(app):
    candidates = [
        app / "Contents" / "embedded.provisionprofile",
        app / "embedded.provisionprofile",
        app / "Contents" / "embedded.mobileprovision",
        app / "embedded.mobileprovision",
    ]
    return next((candidate for candidate in candidates if candidate.is_file()), None)


def check_profile(app, inspector, reporter):
    path = profile_path(app)
    if path is None:
        reporter.fail("Mac App Store provisioning", "missing embedded provisioning profile")
        return
    try:
        profile = inspector.profile(path)
    except InspectionError as error:
        reporter.fail("Mac App Store provisioning", str(error))
        return
    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        reporter.fail("Mac App Store provisioning", "profile Entitlements dictionary is missing")
        return
    expected_identifier = "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID)
    issues = []
    if debug_entitlement(entitlements) is not False:
        issues.append("profile get-task-allow is not false")
    if entitlements.get("beta-reports-active") is not True:
        issues.append("beta-reports-active is not true")
    if application_identifier(entitlements) != expected_identifier:
        issues.append("application identifier expected {}, observed {!r}".format(expected_identifier, application_identifier(entitlements)))
    if "ProvisionedDevices" in profile:
        issues.append("ProvisionedDevices is present")
    if profile.get("ProvisionsAllDevices") is True:
        issues.append("ProvisionsAllDevices is true")
    teams = profile.get("TeamIdentifier")
    if not isinstance(teams, list) or EXPECTED_TEAM not in teams:
        issues.append("TeamIdentifier does not include {}".format(EXPECTED_TEAM))
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        issues.append("ExpirationDate is missing or invalid")
    else:
        now = dt.datetime.now(dt.timezone.utc) if expiration.tzinfo else dt.datetime.utcnow()
        if expiration <= now:
            issues.append("profile expired at {}".format(expiration.isoformat()))
    if issues:
        reporter.fail("Mac App Store provisioning", "; ".join(issues))
    else:
        reporter.pass_("Mac App Store provisioning", "{}; expires={}".format(profile.get("Name", "unnamed profile"), expiration.isoformat()))


def find_dsym(archive, reporter):
    root = archive / "dSYMs"
    candidates = sorted(root.glob("*.dSYM")) if root.is_dir() else []
    matches = []
    for candidate in candidates:
        info_path = candidate / "Contents" / "Info.plist"
        if not info_path.is_file():
            continue
        try:
            identifier = read_plist(info_path).get("CFBundleIdentifier", "")
        except Exception:
            continue
        if identifier in {"com.apple.xcode.dsym.{}".format(EXPECTED_BUNDLE_ID), "com.apple.xcode.dsym.GTAFreeSTEM"}:
            matches.append(candidate)
    if len(matches) != 1:
        reporter.fail("Mac dSYM", "expected exactly one GTAFreeSTEM dSYM, found {}".format(len(matches)))
        return None
    reporter.pass_("Mac dSYM", str(matches[0]))
    return matches[0]


def check_uuid_coverage(executable, dsym, inspector, reporter):
    if not executable.is_file():
        reporter.fail("Mac executable UUIDs", "missing {}".format(executable))
        return
    if dsym is None:
        return
    try:
        executable_uuids = inspector.uuids(executable)
        dsym_uuids = inspector.uuids(dsym)
    except InspectionError as error:
        reporter.fail("Mac executable/dSYM UUID coverage", str(error))
        return
    reporter.expect(
        executable_uuids == dsym_uuids,
        "Mac executable/dSYM UUID coverage",
        ", ".join("{} ({})".format(uuid, arch) for uuid, arch in sorted(executable_uuids)),
        "executable={} dSYM={}".format(sorted(executable_uuids), sorted(dsym_uuids)),
    )


def verify_archive(archive, inspector, emit=True):
    reporter = Reporter(emit=emit)
    archive = archive.resolve()
    reporter.expect(archive.name.endswith(".xcarchive"), "Mac archive suffix", archive.name, "expected a .xcarchive directory")
    reporter.expect(archive.is_dir(), "Mac archive directory", str(archive), "path does not exist: {}".format(archive))
    if not archive.is_dir():
        return reporter

    archive_info = load_plist(archive / "Info.plist", "Mac archive Info.plist", reporter)
    applications = archive / "Products" / "Applications"
    candidates = sorted(path for path in applications.glob("*.app") if path.is_dir()) if applications.is_dir() else []
    reporter.expect(len(candidates) == 1, "Mac archive application layout", str(candidates[0]) if len(candidates) == 1 else "", "expected one Products/Applications/*.app, found {}".format(len(candidates)))
    if len(candidates) != 1:
        return reporter
    app = candidates[0]
    contents = app / "Contents"

    if archive_info:
        reporter.expect(archive_info.get("ArchiveVersion") == 2, "Mac archive format version", "ArchiveVersion=2", "expected 2, observed {!r}".format(archive_info.get("ArchiveVersion")))
        properties = archive_info.get("ApplicationProperties")
        if not isinstance(properties, dict):
            reporter.fail("Mac archive application properties", "ApplicationProperties dictionary is missing")
        else:
            reporter.expect(properties.get("ApplicationPath") == "Applications/{}".format(app.name), "Mac archive application path", "Applications/{}".format(app.name), "unexpected ApplicationPath {!r}".format(properties.get("ApplicationPath")))
            reporter.expect(properties.get("CFBundleIdentifier") == EXPECTED_BUNDLE_ID, "Mac archive bundle identifier", EXPECTED_BUNDLE_ID, "expected {}, observed {!r}".format(EXPECTED_BUNDLE_ID, properties.get("CFBundleIdentifier")))
            reporter.expect(str(properties.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION, "Mac archive version metadata", EXPECTED_VERSION, "unexpected version {!r}".format(properties.get("CFBundleShortVersionString")))
            reporter.expect(str(properties.get("CFBundleVersion", "")) == EXPECTED_BUILD, "Mac archive build metadata", EXPECTED_BUILD, "unexpected build {!r}".format(properties.get("CFBundleVersion")))
            identity = str(properties.get("SigningIdentity", ""))
            reporter.expect(distribution_authority(identity), "Mac archive signing identity", identity, "expected Apple Distribution/Mac App Store identity, observed {!r}".format(identity))

    info = load_plist(contents / "Info.plist", "Mac Info.plist", reporter)
    if info:
        reporter.expect(info.get("CFBundlePackageType") == "APPL", "Mac runnable package type", "APPL", "expected APPL")
        reporter.expect(info.get("CFBundleIdentifier") == EXPECTED_BUNDLE_ID, "Mac bundle identifier", EXPECTED_BUNDLE_ID, "expected {}, observed {!r}".format(EXPECTED_BUNDLE_ID, info.get("CFBundleIdentifier")))
        reporter.expect(str(info.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION, "Mac version", EXPECTED_VERSION, "unexpected version {!r}".format(info.get("CFBundleShortVersionString")))
        reporter.expect(str(info.get("CFBundleVersion", "")) == EXPECTED_BUILD, "Mac build", EXPECTED_BUILD, "unexpected build {!r}".format(info.get("CFBundleVersion")))
        reporter.expect(info.get("DTPlatformName") == "macosx", "Mac platform metadata", "macosx", "expected macosx, observed {!r}".format(info.get("DTPlatformName")))
        supported = info.get("CFBundleSupportedPlatforms")
        reporter.expect(isinstance(supported, list) and "MacOSX" in supported, "Mac supported platform", "MacOSX", "CFBundleSupportedPlatforms must include MacOSX")
        reporter.expect(str(info.get("LSMinimumSystemVersion", "")) == EXPECTED_MINIMUM_SYSTEM, "Mac minimum system version", EXPECTED_MINIMUM_SYSTEM, "expected {}, observed {!r}".format(EXPECTED_MINIMUM_SYSTEM, info.get("LSMinimumSystemVersion")))
        reporter.expect(info.get("ITSAppUsesNonExemptEncryption") is False, "Mac export encryption declaration", "false", "must be explicitly false")

    reporter.expect(not (app / "Watch").exists() and not (contents / "Watch").exists(), "Mac archive excludes Watch bundle", "no embedded Watch app", "Mac Catalyst archive must not embed an iOS Watch companion")
    resources = contents / "Resources"
    privacy = load_plist(resources / "PrivacyInfo.xcprivacy", "Mac privacy manifest", reporter)
    if privacy is not None:
        check_hash("Mac privacy manifest SHA", resources / "PrivacyInfo.xcprivacy", SOURCE_PRIVACY, reporter)
    check_hash("Mac bundled opportunities SHA", resources / "opportunities.json", SOURCE_OPPORTUNITIES, reporter)

    check_signature(app, inspector, reporter)
    check_entitlements(app, inspector, reporter)
    check_profile(app, inspector, reporter)
    if info:
        executable_name = info.get("CFBundleExecutable")
        if not isinstance(executable_name, str) or not executable_name:
            reporter.fail("Mac executable", "CFBundleExecutable is missing")
        else:
            dsym = find_dsym(archive, reporter)
            check_uuid_coverage(contents / "MacOS" / executable_name, dsym, inspector, reporter)
    return reporter


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        plistlib.dump(value, stream, fmt=plistlib.FMT_XML, sort_keys=True)


def build_fixture(base):
    archive = base / "MacFixture.xcarchive"
    app = archive / "Products" / "Applications" / "GTAFreeSTEM.app"
    contents = app / "Contents"
    resources = contents / "Resources"
    resources.mkdir(parents=True)
    write_plist(archive / "Info.plist", {
        "ArchiveVersion": 2,
        "ApplicationProperties": {
            "ApplicationPath": "Applications/GTAFreeSTEM.app",
            "CFBundleIdentifier": EXPECTED_BUNDLE_ID,
            "CFBundleShortVersionString": EXPECTED_VERSION,
            "CFBundleVersion": EXPECTED_BUILD,
            "SigningIdentity": "Apple Distribution: Fixture ({})".format(EXPECTED_TEAM),
            "Team": EXPECTED_TEAM,
        },
    })
    write_plist(contents / "Info.plist", {
        "CFBundleExecutable": "GTAFreeSTEM",
        "CFBundleIdentifier": EXPECTED_BUNDLE_ID,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": EXPECTED_VERSION,
        "CFBundleVersion": EXPECTED_BUILD,
        "CFBundleSupportedPlatforms": ["MacOSX"],
        "DTPlatformName": "macosx",
        "ITSAppUsesNonExemptEncryption": False,
        "LSMinimumSystemVersion": EXPECTED_MINIMUM_SYSTEM,
    })
    shutil.copyfile(SOURCE_PRIVACY, resources / "PrivacyInfo.xcprivacy")
    shutil.copyfile(SOURCE_OPPORTUNITIES, resources / "opportunities.json")
    (contents / "MacOS").mkdir(parents=True)
    (contents / "MacOS" / "GTAFreeSTEM").write_bytes(b"fixture-mac-mach-o")
    (contents / "embedded.provisionprofile").write_bytes(b"fixture-profile")
    write_plist(
        archive / "dSYMs" / "GTAFreeSTEM.app.dSYM" / "Contents" / "Info.plist",
        {"CFBundleIdentifier": "com.apple.xcode.dsym.{}".format(EXPECTED_BUNDLE_ID)},
    )
    return archive


def run_self_test():
    if not SOURCE_OPPORTUNITIES.is_file() or not SOURCE_PRIVACY.is_file():
        raise SystemExit("Mac verifier self-test requires current source resources")
    with tempfile.TemporaryDirectory(prefix="gtafreestem-mac-archive-verifier-") as temporary:
        archive = build_fixture(Path(temporary))
        passing = verify_archive(archive, FixtureInspector(), emit=False)
        if passing.failures:
            print("Mac archive verifier self-test failed: valid fixture was rejected.", file=sys.stderr)
            for failure in passing.failures:
                print(failure, file=sys.stderr)
            return 1

        info_path = archive / "Products" / "Applications" / "GTAFreeSTEM.app" / "Contents" / "Info.plist"
        info = read_plist(info_path)
        info["CFBundleVersion"] = "999"
        write_plist(info_path, info)
        stale_build = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(line.startswith("FAIL Mac build") for line in stale_build.failures):
            print("Mac archive verifier self-test failed: stale build was not rejected.", file=sys.stderr)
            return 1
        info["CFBundleVersion"] = EXPECTED_BUILD
        write_plist(info_path, info)

        feed_path = archive / "Products" / "Applications" / "GTAFreeSTEM.app" / "Contents" / "Resources" / "opportunities.json"
        feed_path.write_bytes(feed_path.read_bytes() + b"\n")
        stale_feed = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(line.startswith("FAIL Mac bundled opportunities SHA") for line in stale_feed.failures):
            print("Mac archive verifier self-test failed: stale feed was not rejected.", file=sys.stderr)
            return 1
        shutil.copyfile(SOURCE_OPPORTUNITIES, feed_path)

        unsafe = verify_archive(archive, FixtureInspector(broken_security=True), emit=False)
        for prefix in ["FAIL Mac code signature", "FAIL Mac get-task-allow", "FAIL Mac App Sandbox", "FAIL Mac App Store provisioning"]:
            if not any(line.startswith(prefix) for line in unsafe.failures):
                print("Mac archive verifier self-test failed: missing rejection {}.".format(prefix), file=sys.stderr)
                return 1

    print("Mac archive verifier self-test passed (valid fixture plus stale-build, stale-feed, and signing failures).")
    return 0


if MODE == "self-test":
    raise SystemExit(run_self_test())

archive_path = Path(os.path.expanduser(ARCHIVE_ARGUMENT))
if not archive_path.is_absolute():
    archive_path = (Path.cwd() / archive_path).resolve()
report = verify_archive(archive_path, LiveInspector(), emit=True)
if report.failures:
    print("RESULT FAIL — {} Mac archive check(s) failed; {} passed.".format(len(report.failures), len(report.passes)))
    raise SystemExit(1)
print("RESULT PASS — {} strict Mac App Store archive checks passed for {} {} ({}).".format(len(report.passes), EXPECTED_BUNDLE_ID, EXPECTED_VERSION, EXPECTED_BUILD))
PY
