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
SOURCE_COMMIT_KEY = "GTAReleaseSourceCommit"
FIXTURE_SOURCE_COMMIT = "0123456789abcdef0123456789abcdef01234567"
SIGNING_DEVELOPMENT = "development"
SIGNING_DISTRIBUTION = "distribution"
TRUSTED_SIGNING_MODES = {SIGNING_DEVELOPMENT, SIGNING_DISTRIBUTION}


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


def valid_source_commit(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value) is not None


def signing_mode(authority):
    if not isinstance(authority, str):
        return ""
    if authority.startswith("Apple Development:"):
        return SIGNING_DEVELOPMENT
    if authority.startswith("Apple Distribution:"):
        return SIGNING_DISTRIBUTION
    return ""


def signing_mode_label(mode):
    if mode == SIGNING_DEVELOPMENT:
        return "Apple Development"
    if mode == SIGNING_DISTRIBUTION:
        return "Apple Distribution"
    return "unknown"


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
    def __init__(
        self,
        broken_security=False,
        signing_mode=SIGNING_DISTRIBUTION,
        signed_identifier=None,
        profile_identifier=None,
        profile_team_identifiers=None,
        profile_expiration=None,
        provisions_all_devices=False,
        bad_dsym=False,
        ad_hoc=False,
        get_task_allow_override=None,
    ):
        self.broken_security = broken_security
        self.signing_mode = signing_mode
        self.signed_identifier = signed_identifier
        self.profile_identifier = profile_identifier
        self.profile_team_identifiers = profile_team_identifiers
        self.profile_expiration = profile_expiration
        self.provisions_all_devices = provisions_all_devices
        self.bad_dsym = bad_dsym
        self.ad_hoc = ad_hoc
        self.get_task_allow_override = get_task_allow_override

    def signature(self, bundle):
        if self.ad_hoc:
            raise InspectionError("ad-hoc code signature")
        development_signed = self.broken_security or self.signing_mode == SIGNING_DEVELOPMENT
        authority = "Apple Development: Fixture ({})" if development_signed else "Apple Distribution: Fixture ({})"
        return {"authority": authority.format(EXPECTED_TEAM), "team": EXPECTED_TEAM}

    def entitlements(self, bundle):
        development_signed = self.broken_security or self.signing_mode == SIGNING_DEVELOPMENT
        entitlements = {
            "com.apple.security.app-sandbox": not self.broken_security,
            "com.apple.security.network.client": True,
            "com.apple.security.personal-information.location": True,
        }
        if self.signing_mode == SIGNING_DISTRIBUTION or self.broken_security:
            entitlements.update({
                "com.apple.application-identifier": self.signed_identifier or "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID),
                "com.apple.developer.team-identifier": EXPECTED_TEAM,
                "com.apple.security.get-task-allow": development_signed,
            })
        if self.get_task_allow_override is not None:
            entitlements["com.apple.security.get-task-allow"] = self.get_task_allow_override
        return entitlements

    def profile(self, path):
        development_profile = self.broken_security or self.signing_mode == SIGNING_DEVELOPMENT
        entitlements = {
            "com.apple.application-identifier": self.profile_identifier or "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID),
            "com.apple.developer.team-identifier": EXPECTED_TEAM,
            "get-task-allow": development_profile,
        }
        if not development_profile:
            entitlements["beta-reports-active"] = True
        profile = {
            "Name": "Fixture Mac Development Profile" if development_profile else "Fixture Mac App Store Profile",
            "UUID": "00000000-0000-0000-0000-000000000000",
            "TeamIdentifier": self.profile_team_identifiers or [EXPECTED_TEAM],
            "ExpirationDate": self.profile_expiration or dt.datetime(2099, 1, 1),
            "Entitlements": entitlements,
        }
        if development_profile:
            profile["ProvisionedDevices"] = ["fixture-device"]
        if self.provisions_all_devices:
            profile["ProvisionsAllDevices"] = True
        return profile

    def uuids(self, path):
        if self.bad_dsym and path.name.endswith(".dSYM"):
            return {("44444444-4444-4444-4444-444444444444", "arm64")}
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


def check_signature(app, inspector, reporter, expected_signing_mode=""):
    try:
        signature = inspector.signature(app)
    except InspectionError as error:
        reporter.fail("Mac code signature", str(error))
        return ""
    authority = signature.get("authority", "")
    team = signature.get("team", "")
    observed_signing_mode = signing_mode(authority)
    trusted_mode = observed_signing_mode in TRUSTED_SIGNING_MODES
    matches_archive = not expected_signing_mode or observed_signing_mode == expected_signing_mode
    if not trusted_mode:
        failure = "expected trusted Apple Development or Apple Distribution, observed {}".format(authority or "none")
    elif not matches_archive:
        failure = "expected {} to match archive, observed {}".format(
            signing_mode_label(expected_signing_mode),
            authority,
        )
    else:
        failure = ""
    reporter.expect(
        trusted_mode and matches_archive,
        "Mac code signature",
        "{}; mode={}; TeamIdentifier={}".format(authority, observed_signing_mode, team or "missing"),
        failure,
    )
    reporter.expect(team == EXPECTED_TEAM, "Mac signing team", team, "expected {}, observed {}".format(EXPECTED_TEAM, team or "missing"))
    return observed_signing_mode


def check_entitlements(app, signing_mode_value, inspector, reporter):
    try:
        entitlements = inspector.entitlements(app)
    except InspectionError as error:
        reporter.fail("Mac entitlements", str(error))
        return
    expected_identifier = "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID)
    observed_get_task_allow = debug_entitlement(entitlements)
    if signing_mode_value == SIGNING_DEVELOPMENT:
        get_task_allow_valid = observed_get_task_allow in {None, False, True}
        get_task_allow_policy = "true, false, or absent for a trusted development archive"
    elif signing_mode_value == SIGNING_DISTRIBUTION:
        get_task_allow_valid = observed_get_task_allow in {None, False}
        get_task_allow_policy = "false or absent for a trusted distribution archive"
    else:
        get_task_allow_valid = False
        get_task_allow_policy = "a known trusted signing mode"
    reporter.expect(
        get_task_allow_valid,
        "Mac get-task-allow",
        "{!r} accepted in {} mode".format(observed_get_task_allow, signing_mode_value),
        "expected {}, observed {!r} in {} mode".format(
            get_task_allow_policy,
            observed_get_task_allow,
            signing_mode_value or "unknown",
        ),
    )
    reporter.expect(entitlements.get("com.apple.security.app-sandbox") is True, "Mac App Sandbox", "enabled", "com.apple.security.app-sandbox must be true")
    reporter.expect(entitlements.get("com.apple.security.network.client") is True, "Mac outbound network entitlement", "enabled", "com.apple.security.network.client must be true")
    reporter.expect(entitlements.get("com.apple.security.personal-information.location") is True, "Mac location entitlement", "enabled", "location entitlement must be true")
    observed_identifier = application_identifier(entitlements)
    observed_team = entitlements.get("com.apple.developer.team-identifier")
    identifiers_optional = signing_mode_value == SIGNING_DEVELOPMENT
    reporter.expect(
        observed_identifier == expected_identifier or (identifiers_optional and observed_identifier is None),
        "Mac application identifier entitlement",
        expected_identifier if observed_identifier else "absent in development archive; certificate and archive metadata validated",
        "expected {}{}, observed {!r}".format(
            expected_identifier,
            " or absence in development mode" if identifiers_optional else "",
            observed_identifier,
        ),
    )
    reporter.expect(
        observed_team == EXPECTED_TEAM or (identifiers_optional and observed_team is None),
        "Mac team entitlement",
        EXPECTED_TEAM if observed_team else "absent in development archive; certificate and archive metadata validated",
        "expected {}{}, observed {!r}".format(
            EXPECTED_TEAM,
            " or absence in development mode" if identifiers_optional else "",
            observed_team,
        ),
    )


def profile_path(app):
    candidates = [
        app / "Contents" / "embedded.provisionprofile",
        app / "embedded.provisionprofile",
        app / "Contents" / "embedded.mobileprovision",
        app / "embedded.mobileprovision",
    ]
    return next((candidate for candidate in candidates if candidate.is_file()), None)


def check_profile(app, signing_mode_value, inspector, reporter):
    if signing_mode_value == SIGNING_DEVELOPMENT:
        profile_kind = "development"
    elif signing_mode_value == SIGNING_DISTRIBUTION:
        profile_kind = "App Store"
    else:
        profile_kind = "unknown-mode"
    report_label = "Mac {} provisioning".format(profile_kind)
    path = profile_path(app)
    if path is None:
        if signing_mode_value == SIGNING_DEVELOPMENT:
            reporter.pass_(
                report_label,
                "no embedded profile; valid for certificate-signed Mac Catalyst development archive",
            )
            return
        reporter.fail(report_label, "missing embedded provisioning profile")
        return
    try:
        profile = inspector.profile(path)
    except InspectionError as error:
        reporter.fail(report_label, str(error))
        return
    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        reporter.fail(report_label, "profile Entitlements dictionary is missing")
        return
    expected_identifier = "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID)
    issues = []
    provisioned_devices = profile.get("ProvisionedDevices")
    if signing_mode_value == SIGNING_DEVELOPMENT:
        if debug_entitlement(entitlements) is not True:
            issues.append("profile get-task-allow is not true for development signing")
        if not isinstance(provisioned_devices, list) or not provisioned_devices:
            issues.append("ProvisionedDevices is missing or empty for development signing")
        if entitlements.get("beta-reports-active") is True:
            issues.append("beta-reports-active is true on a development profile")
    elif signing_mode_value == SIGNING_DISTRIBUTION:
        if debug_entitlement(entitlements) is not False:
            issues.append("profile get-task-allow is not false")
        if entitlements.get("beta-reports-active") is not True:
            issues.append("beta-reports-active is not true")
        if "ProvisionedDevices" in profile:
            issues.append("ProvisionedDevices is present (development/ad-hoc profile)")
    else:
        issues.append("unable to determine development or distribution signing mode")
    if application_identifier(entitlements) != expected_identifier:
        issues.append("application identifier expected {}, observed {!r}".format(expected_identifier, application_identifier(entitlements)))
    if entitlements.get("com.apple.developer.team-identifier") != EXPECTED_TEAM:
        issues.append("profile team entitlement expected {}, observed {!r}".format(EXPECTED_TEAM, entitlements.get("com.apple.developer.team-identifier")))
    if profile.get("ProvisionsAllDevices") is True:
        issues.append("ProvisionsAllDevices is true (enterprise profile)")
    teams = profile.get("TeamIdentifier")
    if not isinstance(teams, list) or teams != [EXPECTED_TEAM]:
        issues.append("TeamIdentifier expected [{}], observed {!r}".format(EXPECTED_TEAM, teams))
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        issues.append("ExpirationDate is missing or invalid")
    else:
        now = dt.datetime.now(dt.timezone.utc) if expiration.tzinfo else dt.datetime.utcnow()
        if expiration <= now:
            issues.append("profile expired at {}".format(expiration.isoformat()))
    if issues:
        reporter.fail(report_label, "; ".join(issues))
    else:
        reporter.pass_(
            report_label,
            "{}; mode={}; UUID={}; expires={}".format(
                profile.get("Name", "unnamed profile"),
                signing_mode_value,
                profile.get("UUID", "missing"),
                expiration.isoformat(),
            ),
        )


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
    archive_signing_mode = ""
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
            archive_signing_mode = signing_mode(identity)
            reporter.expect(
                archive_signing_mode in TRUSTED_SIGNING_MODES,
                "Mac archive signing identity",
                "{}; pre-export mode={}".format(identity, archive_signing_mode),
                "expected trusted Apple Development or Apple Distribution, observed {!r}".format(identity),
            )
            reporter.expect(
                properties.get("Team") == EXPECTED_TEAM,
                "Mac archive signing team",
                EXPECTED_TEAM,
                "expected {}, observed {!r}".format(EXPECTED_TEAM, properties.get("Team")),
            )

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
        source_commit = info.get(SOURCE_COMMIT_KEY)
        reporter.expect(
            valid_source_commit(source_commit),
            "Mac signed source commit provenance",
            "{}={}".format(SOURCE_COMMIT_KEY, source_commit),
            "{} must be a full lowercase 40-hex Git commit, observed {!r}".format(
                SOURCE_COMMIT_KEY,
                source_commit,
            ),
        )

    reporter.expect(not (app / "Watch").exists() and not (contents / "Watch").exists(), "Mac archive excludes Watch bundle", "no embedded Watch app", "Mac Catalyst archive must not embed an iOS Watch companion")
    resources = contents / "Resources"
    privacy = load_plist(resources / "PrivacyInfo.xcprivacy", "Mac privacy manifest", reporter)
    if privacy is not None:
        check_hash("Mac privacy manifest SHA", resources / "PrivacyInfo.xcprivacy", SOURCE_PRIVACY, reporter)
    check_hash("Mac bundled opportunities SHA", resources / "opportunities.json", SOURCE_OPPORTUNITIES, reporter)

    observed_signing_mode = check_signature(
        app,
        inspector,
        reporter,
        expected_signing_mode=archive_signing_mode,
    )
    verification_mode = archive_signing_mode or observed_signing_mode
    check_entitlements(app, verification_mode, inspector, reporter)
    check_profile(app, verification_mode, inspector, reporter)
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


def build_fixture(base, signing_mode=SIGNING_DISTRIBUTION, name="MacFixture.xcarchive"):
    archive = base / name
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
            "SigningIdentity": "Apple {}: Fixture ({})".format(
                "Development" if signing_mode == SIGNING_DEVELOPMENT else "Distribution",
                EXPECTED_TEAM,
            ),
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
        SOURCE_COMMIT_KEY: FIXTURE_SOURCE_COMMIT,
        "ITSAppUsesNonExemptEncryption": False,
        "LSMinimumSystemVersion": EXPECTED_MINIMUM_SYSTEM,
    })
    shutil.copyfile(SOURCE_PRIVACY, resources / "PrivacyInfo.xcprivacy")
    shutil.copyfile(SOURCE_OPPORTUNITIES, resources / "opportunities.json")
    (contents / "MacOS").mkdir(parents=True)
    (contents / "MacOS" / "GTAFreeSTEM").write_bytes(b"fixture-mac-mach-o")
    if signing_mode == SIGNING_DISTRIBUTION:
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

        development_archive = build_fixture(
            Path(temporary),
            signing_mode=SIGNING_DEVELOPMENT,
            name="MacDevelopmentFixture.xcarchive",
        )
        development_signed = verify_archive(
            development_archive,
            FixtureInspector(signing_mode=SIGNING_DEVELOPMENT),
            emit=False,
        )
        if development_signed.failures:
            print("Mac archive verifier self-test failed: valid development-signed fixture was rejected.", file=sys.stderr)
            for failure in development_signed.failures:
                print(failure, file=sys.stderr)
            return 1

        development_with_debug_entitlement = verify_archive(
            development_archive,
            FixtureInspector(
                signing_mode=SIGNING_DEVELOPMENT,
                get_task_allow_override=True,
            ),
            emit=False,
        )
        if development_with_debug_entitlement.failures:
            print(
                "Mac archive verifier self-test failed: valid development get-task-allow entitlement was rejected.",
                file=sys.stderr,
            )
            for failure in development_with_debug_entitlement.failures:
                print(failure, file=sys.stderr)
            return 1

        distribution_with_debug_entitlement = verify_archive(
            archive,
            FixtureInspector(
                signing_mode=SIGNING_DISTRIBUTION,
                get_task_allow_override=True,
            ),
            emit=False,
        )
        if not any(
            line.startswith("FAIL Mac get-task-allow")
            for line in distribution_with_debug_entitlement.failures
        ):
            print(
                "Mac archive verifier self-test failed: distribution get-task-allow entitlement was not rejected.",
                file=sys.stderr,
            )
            return 1

        info_path = archive / "Products" / "Applications" / "GTAFreeSTEM.app" / "Contents" / "Info.plist"
        info = read_plist(info_path)

        del info[SOURCE_COMMIT_KEY]
        write_plist(info_path, info)
        missing_source_commit = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(
            line.startswith("FAIL Mac signed source commit provenance")
            and "observed None" in line
            for line in missing_source_commit.failures
        ):
            print("Mac archive verifier self-test failed: missing source commit was not rejected.", file=sys.stderr)
            return 1

        info[SOURCE_COMMIT_KEY] = FIXTURE_SOURCE_COMMIT.upper()
        write_plist(info_path, info)
        malformed_source_commit = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(
            line.startswith("FAIL Mac signed source commit provenance")
            and "lowercase 40-hex" in line
            for line in malformed_source_commit.failures
        ):
            print("Mac archive verifier self-test failed: malformed source commit was not rejected.", file=sys.stderr)
            return 1

        info[SOURCE_COMMIT_KEY] = FIXTURE_SOURCE_COMMIT
        write_plist(info_path, info)

        info["CFBundleVersion"] = "999"
        write_plist(info_path, info)
        stale_build = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(line.startswith("FAIL Mac build") for line in stale_build.failures):
            print("Mac archive verifier self-test failed: stale build was not rejected.", file=sys.stderr)
            return 1
        info["CFBundleVersion"] = EXPECTED_BUILD
        write_plist(info_path, info)

        info["CFBundleIdentifier"] = "com.example.wrong"
        write_plist(info_path, info)
        wrong_bundle = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(line.startswith("FAIL Mac bundle identifier") for line in wrong_bundle.failures):
            print("Mac archive verifier self-test failed: wrong Mac Catalyst bundle ID was not rejected.", file=sys.stderr)
            return 1
        info["CFBundleIdentifier"] = EXPECTED_BUNDLE_ID
        write_plist(info_path, info)

        archive_info_path = archive / "Info.plist"
        archive_info = read_plist(archive_info_path)
        archive_info["ApplicationProperties"]["Team"] = "WRONGTEAM1"
        write_plist(archive_info_path, archive_info)
        wrong_archive_team = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(line.startswith("FAIL Mac archive signing team") for line in wrong_archive_team.failures):
            print("Mac archive verifier self-test failed: wrong archive team was not rejected.", file=sys.stderr)
            return 1
        archive_info["ApplicationProperties"]["Team"] = EXPECTED_TEAM
        write_plist(archive_info_path, archive_info)

        feed_path = archive / "Products" / "Applications" / "GTAFreeSTEM.app" / "Contents" / "Resources" / "opportunities.json"
        feed_path.write_bytes(feed_path.read_bytes() + b"\n")
        stale_feed = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(line.startswith("FAIL Mac bundled opportunities SHA") for line in stale_feed.failures):
            print("Mac archive verifier self-test failed: stale feed was not rejected.", file=sys.stderr)
            return 1
        shutil.copyfile(SOURCE_OPPORTUNITIES, feed_path)

        wildcard_profile = verify_archive(
            archive,
            FixtureInspector(profile_identifier="{}.*".format(EXPECTED_TEAM)),
            emit=False,
        )
        if not any(
            line.startswith("FAIL Mac App Store provisioning")
            and "application identifier expected" in line
            for line in wildcard_profile.failures
        ):
            print("Mac archive verifier self-test failed: wildcard profile was not rejected.", file=sys.stderr)
            return 1

        wrong_signed_identifier = verify_archive(
            archive,
            FixtureInspector(signed_identifier="{}.com.example.wrong".format(EXPECTED_TEAM)),
            emit=False,
        )
        if not any(
            line.startswith("FAIL Mac application identifier entitlement")
            for line in wrong_signed_identifier.failures
        ):
            print("Mac archive verifier self-test failed: wrong signed application identifier was not rejected.", file=sys.stderr)
            return 1

        wrong_profile_team = verify_archive(
            archive,
            FixtureInspector(profile_team_identifiers=[EXPECTED_TEAM, "WRONGTEAM1"]),
            emit=False,
        )
        if not any(
            line.startswith("FAIL Mac App Store provisioning")
            and "TeamIdentifier expected" in line
            for line in wrong_profile_team.failures
        ):
            print("Mac archive verifier self-test failed: non-exact profile team was not rejected.", file=sys.stderr)
            return 1

        expired_profile = verify_archive(
            archive,
            FixtureInspector(profile_expiration=dt.datetime(2000, 1, 1)),
            emit=False,
        )
        if not any(
            line.startswith("FAIL Mac App Store provisioning")
            and "profile expired" in line
            for line in expired_profile.failures
        ):
            print("Mac archive verifier self-test failed: expired profile was not rejected.", file=sys.stderr)
            return 1

        enterprise_profile = verify_archive(
            archive,
            FixtureInspector(provisions_all_devices=True),
            emit=False,
        )
        if not any(
            line.startswith("FAIL Mac App Store provisioning")
            and "enterprise profile" in line
            for line in enterprise_profile.failures
        ):
            print("Mac archive verifier self-test failed: enterprise profile was not rejected.", file=sys.stderr)
            return 1

        distribution_profile_path = (
            archive
            / "Products"
            / "Applications"
            / "GTAFreeSTEM.app"
            / "Contents"
            / "embedded.provisionprofile"
        )
        distribution_profile_path.unlink()
        missing_distribution_profile = verify_archive(archive, FixtureInspector(), emit=False)
        if not any(
            line.startswith("FAIL Mac App Store provisioning")
            and "missing embedded provisioning profile" in line
            for line in missing_distribution_profile.failures
        ):
            print("Mac archive verifier self-test failed: missing distribution profile was not rejected.", file=sys.stderr)
            return 1
        distribution_profile_path.write_bytes(b"fixture-profile")

        ad_hoc = verify_archive(archive, FixtureInspector(ad_hoc=True), emit=False)
        if not any(
            line.startswith("FAIL Mac code signature") and "ad-hoc" in line
            for line in ad_hoc.failures
        ):
            print("Mac archive verifier self-test failed: ad-hoc signature was not rejected.", file=sys.stderr)
            return 1

        bad_dsym = verify_archive(archive, FixtureInspector(bad_dsym=True), emit=False)
        if not any(
            line.startswith("FAIL Mac executable/dSYM UUID coverage")
            for line in bad_dsym.failures
        ):
            print("Mac archive verifier self-test failed: mismatched dSYM was not rejected.", file=sys.stderr)
            return 1

        unsafe = verify_archive(archive, FixtureInspector(broken_security=True), emit=False)
        for prefix in ["FAIL Mac code signature", "FAIL Mac get-task-allow", "FAIL Mac App Sandbox", "FAIL Mac App Store provisioning"]:
            if not any(line.startswith(prefix) for line in unsafe.failures):
                print("Mac archive verifier self-test failed: missing rejection {}.".format(prefix), file=sys.stderr)
                return 1

    print(
        "Mac archive verifier self-test passed "
        "(development/distribution fixtures plus source-commit, stale-content, identifier/team/expiry, "
        "ad-hoc/enterprise, dSYM, and security failures)."
    )
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
