#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="verify"
ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-}"

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
  echo "Usage: $0 /absolute/path/to/App.xcarchive" >&2
  echo "       IOS_ARCHIVE_PATH=/absolute/path/to/App.xcarchive $0" >&2
  echo "       $0 --self-test" >&2
  exit 2
fi

if [ "$MODE" = "verify" ] && [ -z "$ARCHIVE_PATH" ]; then
  echo "FAIL archive input — supply a real .xcarchive path as the first argument or IOS_ARCHIVE_PATH." >&2
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
SOURCE_MAIN_PRIVACY = ROOT / "GTAFreeSTEM" / "Resources" / "PrivacyInfo.xcprivacy"
SOURCE_WATCH_PRIVACY = ROOT / "GTAFreeSTEMWatch" / "PrivacyInfo.xcprivacy"
EXPECTED_MAIN_BUNDLE_ID = "com.rupayonhaldar.gtafreestem"
EXPECTED_WATCH_BUNDLE_ID = "com.rupayonhaldar.gtafreestem.watchkitapp"


class InspectionError(Exception):
    pass


def source_setting(name):
    try:
        text = PROJECT_FILE.read_text(encoding="utf-8")
    except OSError as error:
        raise SystemExit("Unable to read {}: {}".format(PROJECT_FILE, error))
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


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_plist_file(path):
    with path.open("rb") as stream:
        value = plistlib.load(stream)
    if not isinstance(value, dict):
        raise ValueError("root object is not a dictionary")
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


class LiveInspector:
    @staticmethod
    def run(command):
        try:
            completed = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        except OSError as error:
            raise InspectionError("unable to run {}: {}".format(command[0], error))
        return completed

    def signature(self, bundle):
        verification = self.run(
            ["/usr/bin/codesign", "--verify", "--strict", "--verbose=4", str(bundle)]
        )
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
        completed = self.run(
            ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)]
        )
        payload = completed.stdout + completed.stderr
        if completed.returncode != 0:
            detail = payload.decode("utf-8", "replace").strip()
            raise InspectionError("unable to inspect entitlements: {}".format(detail or "no detail"))
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
        output = completed.stdout + completed.stderr
        if completed.returncode != 0:
            detail = output.decode("utf-8", "replace").strip()
            raise InspectionError("dwarfdump failed: {}".format(detail or "no detail"))
        pairs = set()
        for match in re.finditer(
            rb"^UUID:\s*([0-9A-Fa-f-]{36})\s*\(([^)]+)\)",
            output,
            re.MULTILINE,
        ):
            pairs.add((match.group(1).decode("ascii").upper(), match.group(2).decode("utf-8")))
        if not pairs:
            raise InspectionError("dwarfdump emitted no Mach-O UUIDs")
        return pairs


class FixtureInspector:
    def __init__(self, broken_security=False):
        self.broken_security = broken_security

    def signature(self, bundle):
        if self.broken_security:
            return {"authority": "Apple Development: Fixture ({})".format(EXPECTED_TEAM), "team": EXPECTED_TEAM}
        return {"authority": "Apple Distribution: Fixture ({})".format(EXPECTED_TEAM), "team": EXPECTED_TEAM}

    def entitlements(self, bundle):
        info = read_plist_file(bundle / "Info.plist")
        return {
            "application-identifier": "{}.{}".format(EXPECTED_TEAM, info["CFBundleIdentifier"]),
            "com.apple.developer.team-identifier": EXPECTED_TEAM,
            "get-task-allow": True if self.broken_security else False,
        }

    def profile(self, path):
        bundle = path.parent
        info = read_plist_file(bundle / "Info.plist")
        profile = {
            "Name": "Fixture App Store Profile",
            "UUID": "00000000-0000-0000-0000-000000000000",
            "TeamIdentifier": [EXPECTED_TEAM],
            "ExpirationDate": dt.datetime(2099, 1, 1),
            "Entitlements": {
                "application-identifier": "{}.{}".format(EXPECTED_TEAM, info["CFBundleIdentifier"]),
                "beta-reports-active": True,
                "get-task-allow": False,
            },
        }
        if self.broken_security:
            profile["ProvisionedDevices"] = ["fixture-device"]
            profile["Entitlements"]["get-task-allow"] = True
            profile["Entitlements"].pop("beta-reports-active", None)
        return profile

    def uuids(self, path):
        if "Watch" in str(path):
            return {("22222222-2222-2222-2222-222222222222", "arm64_32")}
        return {("11111111-1111-1111-1111-111111111111", "arm64")}


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
        value = read_plist_file(path)
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


def check_signature(label, bundle, inspector, reporter):
    try:
        signature = inspector.signature(bundle)
    except InspectionError as error:
        reporter.fail(label + " code signature", str(error))
        return ""
    authority = signature.get("authority", "")
    team = signature.get("team", "")
    reporter.expect(
        authority.startswith("Apple Distribution:"),
        label + " code signature",
        "{}; TeamIdentifier={}".format(authority, team or "missing"),
        "expected Apple Distribution, observed {}".format(authority or "no authority"),
    )
    reporter.expect(
        team == EXPECTED_TEAM,
        label + " signing team",
        team,
        "expected {}, observed {}".format(EXPECTED_TEAM, team or "missing"),
    )
    return team


def check_entitlements(label, bundle, bundle_id, inspector, reporter):
    try:
        entitlements = inspector.entitlements(bundle)
    except InspectionError as error:
        reporter.fail(label + " entitlements", str(error))
        return
    reporter.expect(
        entitlements.get("get-task-allow") is False,
        label + " get-task-allow",
        "false",
        "must be explicitly false, observed {!r}".format(entitlements.get("get-task-allow")),
    )
    expected_application_id = "{}.{}".format(EXPECTED_TEAM, bundle_id)
    reporter.expect(
        entitlements.get("application-identifier") == expected_application_id,
        label + " application identifier entitlement",
        expected_application_id,
        "expected {}, observed {!r}".format(
            expected_application_id, entitlements.get("application-identifier")
        ),
    )


def check_profile(label, bundle, bundle_id, inspector, reporter):
    profile_path = bundle / "embedded.mobileprovision"
    if not profile_path.is_file():
        reporter.fail(label + " App Store provisioning", "missing {}".format(profile_path))
        return
    try:
        profile = inspector.profile(profile_path)
    except InspectionError as error:
        reporter.fail(label + " App Store provisioning", str(error))
        return

    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        reporter.fail(label + " App Store provisioning", "profile Entitlements dictionary is missing")
        return
    expected_application_id = "{}.{}".format(EXPECTED_TEAM, bundle_id)
    issues = []
    if entitlements.get("get-task-allow") is not False:
        issues.append("profile get-task-allow is not false")
    if entitlements.get("beta-reports-active") is not True:
        issues.append("beta-reports-active is not true")
    if "ProvisionedDevices" in profile:
        issues.append("ProvisionedDevices is present (development/ad-hoc profile)")
    if profile.get("ProvisionsAllDevices") is True:
        issues.append("ProvisionsAllDevices is true (enterprise profile)")
    if entitlements.get("application-identifier") != expected_application_id:
        issues.append(
            "application-identifier expected {}, observed {!r}".format(
                expected_application_id, entitlements.get("application-identifier")
            )
        )
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
        reporter.fail(label + " App Store provisioning", "; ".join(issues))
    else:
        reporter.pass_(
            label + " App Store provisioning",
            "{}; UUID={}; expires={}".format(
                profile.get("Name", "unnamed profile"),
                profile.get("UUID", "missing"),
                expiration.isoformat(),
            ),
        )


def find_dsym(archive, bundle_id, reporter, label):
    dsym_root = archive / "dSYMs"
    if not dsym_root.is_dir():
        reporter.fail(label + " dSYM", "missing {}".format(dsym_root))
        return None
    matches = []
    for candidate in sorted(dsym_root.glob("*.dSYM")):
        info_path = candidate / "Contents" / "Info.plist"
        if not info_path.is_file():
            continue
        try:
            info = read_plist_file(info_path)
        except Exception:
            continue
        if info.get("CFBundleIdentifier") == "com.apple.xcode.dsym.{}".format(bundle_id):
            matches.append(candidate)
    if len(matches) != 1:
        reporter.fail(
            label + " dSYM",
            "expected exactly one dSYM for {}, found {}".format(bundle_id, len(matches)),
        )
        return None
    reporter.pass_(label + " dSYM", str(matches[0]))
    return matches[0]


def check_uuid_coverage(label, executable, dsym, inspector, reporter):
    if not executable.is_file():
        reporter.fail(label + " executable UUIDs", "missing {}".format(executable))
        return
    if dsym is None:
        return
    try:
        executable_uuids = inspector.uuids(executable)
        dsym_uuids = inspector.uuids(dsym)
    except InspectionError as error:
        reporter.fail(label + " executable/dSYM UUID coverage", str(error))
        return
    missing = executable_uuids - dsym_uuids
    extra = dsym_uuids - executable_uuids
    evidence = ", ".join("{} ({})".format(uuid, arch) for uuid, arch in sorted(executable_uuids))
    reporter.expect(
        not missing and not extra,
        label + " executable/dSYM UUID coverage",
        evidence,
        "missing={} extra={}".format(sorted(missing), sorted(extra)),
    )


def verify_archive(archive, inspector, emit=True):
    reporter = Reporter(emit=emit)
    archive = archive.resolve()
    reporter.expect(
        archive.name.endswith(".xcarchive"),
        "archive suffix",
        archive.name,
        "expected a .xcarchive directory, observed {}".format(archive.name),
    )
    reporter.expect(
        archive.is_dir(),
        "archive directory",
        str(archive),
        "path does not exist as a directory: {}".format(archive),
    )
    if not archive.is_dir():
        return reporter

    archive_info = load_plist(archive / "Info.plist", "archive Info.plist", reporter)
    applications = archive / "Products" / "Applications"
    app_candidates = sorted(path for path in applications.glob("*.app") if path.is_dir()) if applications.is_dir() else []
    reporter.expect(
        len(app_candidates) == 1,
        "archive application layout",
        str(app_candidates[0]) if len(app_candidates) == 1 else "",
        "expected exactly one Products/Applications/*.app, found {}".format(len(app_candidates)),
    )
    if len(app_candidates) != 1:
        return reporter
    app = app_candidates[0]
    reporter.expect(
        app.name == "GTAFreeSTEM.app",
        "main application name",
        app.name,
        "expected GTAFreeSTEM.app, observed {}".format(app.name),
    )

    if archive_info:
        reporter.expect(
            archive_info.get("ArchiveVersion") == 2,
            "archive format version",
            "ArchiveVersion=2",
            "expected ArchiveVersion=2, observed {!r}".format(archive_info.get("ArchiveVersion")),
        )
        properties = archive_info.get("ApplicationProperties")
        if not isinstance(properties, dict):
            reporter.fail("archive application properties", "ApplicationProperties dictionary is missing")
        else:
            expected_relative_path = "Applications/{}".format(app.name)
            reporter.expect(
                properties.get("ApplicationPath") == expected_relative_path,
                "archive application path",
                expected_relative_path,
                "expected {}, observed {!r}".format(expected_relative_path, properties.get("ApplicationPath")),
            )
            reporter.expect(
                properties.get("CFBundleIdentifier") == EXPECTED_MAIN_BUNDLE_ID,
                "archive bundle identifier",
                EXPECTED_MAIN_BUNDLE_ID,
                "expected {}, observed {!r}".format(
                    EXPECTED_MAIN_BUNDLE_ID, properties.get("CFBundleIdentifier")
                ),
            )
            reporter.expect(
                str(properties.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION,
                "archive version metadata",
                EXPECTED_VERSION,
                "expected {}, observed {!r}".format(
                    EXPECTED_VERSION, properties.get("CFBundleShortVersionString")
                ),
            )
            reporter.expect(
                str(properties.get("CFBundleVersion", "")) == EXPECTED_BUILD,
                "archive build metadata",
                EXPECTED_BUILD,
                "expected {}, observed {!r}".format(EXPECTED_BUILD, properties.get("CFBundleVersion")),
            )
            signing_identity = properties.get("SigningIdentity", "")
            reporter.expect(
                isinstance(signing_identity, str) and signing_identity.startswith("Apple Distribution:"),
                "archive signing identity",
                signing_identity,
                "expected Apple Distribution, observed {!r}".format(signing_identity),
            )

    main_info = load_plist(app / "Info.plist", "main Info.plist", reporter)
    watch_root = app / "Watch"
    watch_candidates = sorted(path for path in watch_root.glob("*.app") if path.is_dir()) if watch_root.is_dir() else []
    reporter.expect(
        len(watch_candidates) == 1,
        "embedded Watch application layout",
        str(watch_candidates[0]) if len(watch_candidates) == 1 else "",
        "expected exactly one Watch/*.app, found {}".format(len(watch_candidates)),
    )
    watch = watch_candidates[0] if len(watch_candidates) == 1 else None
    watch_info = load_plist(watch / "Info.plist", "Watch Info.plist", reporter) if watch else None

    if main_info:
        reporter.expect(
            main_info.get("CFBundlePackageType") == "APPL",
            "main runnable package type",
            "APPL",
            "expected APPL, observed {!r}".format(main_info.get("CFBundlePackageType")),
        )
        reporter.expect(
            main_info.get("CFBundleIdentifier") == EXPECTED_MAIN_BUNDLE_ID,
            "main bundle identifier",
            EXPECTED_MAIN_BUNDLE_ID,
            "expected {}, observed {!r}".format(EXPECTED_MAIN_BUNDLE_ID, main_info.get("CFBundleIdentifier")),
        )
        reporter.expect(
            str(main_info.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION,
            "main version",
            EXPECTED_VERSION,
            "expected {}, observed {!r}".format(EXPECTED_VERSION, main_info.get("CFBundleShortVersionString")),
        )
        reporter.expect(
            str(main_info.get("CFBundleVersion", "")) == EXPECTED_BUILD,
            "main build",
            EXPECTED_BUILD,
            "expected {}, observed {!r}".format(EXPECTED_BUILD, main_info.get("CFBundleVersion")),
        )
        family = main_info.get("UIDeviceFamily")
        normalized_family = set(family) if isinstance(family, list) else set()
        reporter.expect(
            normalized_family == {1, 2},
            "iPhone and iPad device family",
            "UIDeviceFamily=[1, 2]",
            "expected exactly [1, 2], observed {!r}".format(family),
        )
        reporter.expect(
            main_info.get("ITSAppUsesNonExemptEncryption") is False,
            "main export encryption declaration",
            "ITSAppUsesNonExemptEncryption=false",
            "must be explicitly false, observed {!r}".format(main_info.get("ITSAppUsesNonExemptEncryption")),
        )

    if watch_info:
        reporter.expect(
            watch_info.get("CFBundlePackageType") == "APPL",
            "Watch runnable package type",
            "APPL",
            "expected APPL, observed {!r}".format(watch_info.get("CFBundlePackageType")),
        )
        reporter.expect(
            watch_info.get("CFBundleIdentifier") == EXPECTED_WATCH_BUNDLE_ID,
            "Watch bundle identifier",
            EXPECTED_WATCH_BUNDLE_ID,
            "expected {}, observed {!r}".format(EXPECTED_WATCH_BUNDLE_ID, watch_info.get("CFBundleIdentifier")),
        )
        reporter.expect(
            str(watch_info.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION,
            "Watch version",
            EXPECTED_VERSION,
            "expected {}, observed {!r}".format(EXPECTED_VERSION, watch_info.get("CFBundleShortVersionString")),
        )
        reporter.expect(
            str(watch_info.get("CFBundleVersion", "")) == EXPECTED_BUILD,
            "Watch build",
            EXPECTED_BUILD,
            "expected {}, observed {!r}".format(EXPECTED_BUILD, watch_info.get("CFBundleVersion")),
        )
        reporter.expect(
            watch_info.get("WKApplication") is True,
            "Watch runnable target",
            "WKApplication=true",
            "WKApplication must be true, observed {!r}".format(watch_info.get("WKApplication")),
        )
        reporter.expect(
            watch_info.get("WKCompanionAppBundleIdentifier") == EXPECTED_MAIN_BUNDLE_ID,
            "Watch companion identifier",
            EXPECTED_MAIN_BUNDLE_ID,
            "expected {}, observed {!r}".format(
                EXPECTED_MAIN_BUNDLE_ID, watch_info.get("WKCompanionAppBundleIdentifier")
            ),
        )
        reporter.expect(
            watch_info.get("ITSAppUsesNonExemptEncryption") is False,
            "Watch export encryption declaration",
            "ITSAppUsesNonExemptEncryption=false",
            "must be explicitly false, observed {!r}".format(watch_info.get("ITSAppUsesNonExemptEncryption")),
        )

    main_privacy = load_plist(app / "PrivacyInfo.xcprivacy", "main privacy manifest", reporter)
    if main_privacy is not None:
        check_hash("main privacy manifest SHA", app / "PrivacyInfo.xcprivacy", SOURCE_MAIN_PRIVACY, reporter)
    if watch:
        watch_privacy = load_plist(watch / "PrivacyInfo.xcprivacy", "Watch privacy manifest", reporter)
        if watch_privacy is not None:
            check_hash("Watch privacy manifest SHA", watch / "PrivacyInfo.xcprivacy", SOURCE_WATCH_PRIVACY, reporter)

    check_hash("main bundled opportunities SHA", app / "opportunities.json", SOURCE_OPPORTUNITIES, reporter)

    if main_info:
        check_signature("main", app, inspector, reporter)
        check_entitlements("main", app, EXPECTED_MAIN_BUNDLE_ID, inspector, reporter)
        check_profile("main", app, EXPECTED_MAIN_BUNDLE_ID, inspector, reporter)
        executable_name = main_info.get("CFBundleExecutable")
        if not isinstance(executable_name, str) or not executable_name:
            reporter.fail("main executable", "CFBundleExecutable is missing")
        else:
            main_dsym = find_dsym(archive, EXPECTED_MAIN_BUNDLE_ID, reporter, "main")
            check_uuid_coverage("main", app / executable_name, main_dsym, inspector, reporter)

    if watch and watch_info:
        check_signature("Watch", watch, inspector, reporter)
        check_entitlements("Watch", watch, EXPECTED_WATCH_BUNDLE_ID, inspector, reporter)
        check_profile("Watch", watch, EXPECTED_WATCH_BUNDLE_ID, inspector, reporter)
        executable_name = watch_info.get("CFBundleExecutable")
        if not isinstance(executable_name, str) or not executable_name:
            reporter.fail("Watch executable", "CFBundleExecutable is missing")
        else:
            watch_dsym = find_dsym(archive, EXPECTED_WATCH_BUNDLE_ID, reporter, "Watch")
            check_uuid_coverage("Watch", watch / executable_name, watch_dsym, inspector, reporter)

    return reporter


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        plistlib.dump(value, stream, fmt=plistlib.FMT_XML, sort_keys=True)


def build_fixture(base):
    archive = base / "Fixture.xcarchive"
    app = archive / "Products" / "Applications" / "GTAFreeSTEM.app"
    watch = app / "Watch" / "GTAFreeSTEMWatch.app"
    app.mkdir(parents=True)
    watch.mkdir(parents=True)
    write_plist(
        archive / "Info.plist",
        {
            "ArchiveVersion": 2,
            "ApplicationProperties": {
                "ApplicationPath": "Applications/GTAFreeSTEM.app",
                "CFBundleIdentifier": EXPECTED_MAIN_BUNDLE_ID,
                "CFBundleShortVersionString": EXPECTED_VERSION,
                "CFBundleVersion": EXPECTED_BUILD,
                "SigningIdentity": "Apple Distribution: Fixture ({})".format(EXPECTED_TEAM),
                "Team": EXPECTED_TEAM,
            },
        },
    )
    write_plist(
        app / "Info.plist",
        {
            "CFBundleExecutable": "GTAFreeSTEM",
            "CFBundleIdentifier": EXPECTED_MAIN_BUNDLE_ID,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": EXPECTED_VERSION,
            "CFBundleVersion": EXPECTED_BUILD,
            "ITSAppUsesNonExemptEncryption": False,
            "UIDeviceFamily": [1, 2],
        },
    )
    write_plist(
        watch / "Info.plist",
        {
            "CFBundleExecutable": "GTAFreeSTEMWatch",
            "CFBundleIdentifier": EXPECTED_WATCH_BUNDLE_ID,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": EXPECTED_VERSION,
            "CFBundleVersion": EXPECTED_BUILD,
            "ITSAppUsesNonExemptEncryption": False,
            "WKApplication": True,
            "WKCompanionAppBundleIdentifier": EXPECTED_MAIN_BUNDLE_ID,
        },
    )
    shutil.copyfile(SOURCE_MAIN_PRIVACY, app / "PrivacyInfo.xcprivacy")
    shutil.copyfile(SOURCE_WATCH_PRIVACY, watch / "PrivacyInfo.xcprivacy")
    shutil.copyfile(SOURCE_OPPORTUNITIES, app / "opportunities.json")
    (app / "GTAFreeSTEM").write_bytes(b"fixture-main-mach-o")
    (watch / "GTAFreeSTEMWatch").write_bytes(b"fixture-watch-mach-o")
    (app / "embedded.mobileprovision").write_bytes(b"fixture-main-profile")
    (watch / "embedded.mobileprovision").write_bytes(b"fixture-watch-profile")
    write_plist(
        archive / "dSYMs" / "GTAFreeSTEM.app.dSYM" / "Contents" / "Info.plist",
        {"CFBundleIdentifier": "com.apple.xcode.dsym.{}".format(EXPECTED_MAIN_BUNDLE_ID)},
    )
    write_plist(
        archive / "dSYMs" / "GTAFreeSTEMWatch.app.dSYM" / "Contents" / "Info.plist",
        {"CFBundleIdentifier": "com.apple.xcode.dsym.{}".format(EXPECTED_WATCH_BUNDLE_ID)},
    )
    return archive


def run_self_test():
    if not SOURCE_OPPORTUNITIES.is_file() or not SOURCE_MAIN_PRIVACY.is_file() or not SOURCE_WATCH_PRIVACY.is_file():
        raise SystemExit("Self-test requires the current source resources.")
    with tempfile.TemporaryDirectory(prefix="gtafreestem-archive-verifier-") as temporary:
        archive = build_fixture(Path(temporary))

        passing = verify_archive(archive, FixtureInspector(), emit=False)
        if passing.failures:
            print("Archive verifier self-test failed: valid fixture was rejected.", file=sys.stderr)
            for failure in passing.failures:
                print(failure, file=sys.stderr)
            return 1

        watch_info_path = (
            archive
            / "Products"
            / "Applications"
            / "GTAFreeSTEM.app"
            / "Watch"
            / "GTAFreeSTEMWatch.app"
            / "Info.plist"
        )
        watch_info = read_plist_file(watch_info_path)
        watch_info["CFBundleVersion"] = "999"
        write_plist(watch_info_path, watch_info)
        stale_build = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(line.startswith("FAIL Watch build") for line in stale_build.failures):
            print("Archive verifier self-test failed: stale Watch build was not rejected.", file=sys.stderr)
            return 1
        watch_info["CFBundleVersion"] = EXPECTED_BUILD
        write_plist(watch_info_path, watch_info)

        app_opportunities = archive / "Products" / "Applications" / "GTAFreeSTEM.app" / "opportunities.json"
        app_opportunities.write_bytes(app_opportunities.read_bytes() + b"\n")
        stale_data = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(line.startswith("FAIL main bundled opportunities SHA") for line in stale_data.failures):
            print("Archive verifier self-test failed: stale bundled feed was not rejected.", file=sys.stderr)
            return 1
        shutil.copyfile(SOURCE_OPPORTUNITIES, app_opportunities)

        unsafe = verify_archive(archive, FixtureInspector(broken_security=True), emit=False)
        required_security_failures = [
            "FAIL main code signature",
            "FAIL main get-task-allow",
            "FAIL main App Store provisioning",
            "FAIL Watch code signature",
            "FAIL Watch get-task-allow",
            "FAIL Watch App Store provisioning",
        ]
        for prefix in required_security_failures:
            if not any(line.startswith(prefix) for line in unsafe.failures):
                print("Archive verifier self-test failed: missing rejection {}.".format(prefix), file=sys.stderr)
                return 1

    print("Archive verifier self-test passed (valid fixture plus stale-build, stale-data, and signing failures).")
    return 0


if MODE == "self-test":
    raise SystemExit(run_self_test())

archive_path = Path(os.path.expanduser(ARCHIVE_ARGUMENT))
if not archive_path.is_absolute():
    archive_path = (Path.cwd() / archive_path).resolve()
report = verify_archive(archive_path, LiveInspector(), emit=True)
if report.failures:
    print("RESULT FAIL — {} check(s) failed; {} passed.".format(len(report.failures), len(report.passes)))
    raise SystemExit(1)
print("RESULT PASS — {} strict App Store archive checks passed for {} {} ({}).".format(
    len(report.passes), EXPECTED_MAIN_BUNDLE_ID, EXPECTED_VERSION, EXPECTED_BUILD
))
PY
