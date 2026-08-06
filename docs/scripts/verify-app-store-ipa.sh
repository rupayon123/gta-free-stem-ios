#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="verify"
IPA_PATH="${IOS_IPA_PATH:-}"
ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-}"

if [ "${1:-}" = "--self-test" ]; then
  if [ "$#" -ne 1 ]; then
    echo "Usage: $0 --self-test" >&2
    exit 2
  fi
  MODE="self-test"
  IPA_PATH=""
  ARCHIVE_PATH=""
elif [ "$#" -eq 1 ]; then
  IPA_PATH="$1"
elif [ "$#" -eq 2 ]; then
  IPA_PATH="$1"
  ARCHIVE_PATH="$2"
elif [ "$#" -ne 0 ]; then
  echo "Usage: $0 /absolute/path/to/App.ipa [/absolute/path/to/source.xcarchive]" >&2
  echo "       IOS_IPA_PATH=/absolute/path/to/App.ipa IOS_ARCHIVE_PATH=/absolute/path/to/source.xcarchive $0" >&2
  echo "       $0 --self-test" >&2
  exit 2
fi

if [ "$MODE" = "verify" ] && [ -z "$IPA_PATH" ]; then
  echo "FAIL IPA input — supply a real exported .ipa path as the first argument or IOS_IPA_PATH." >&2
  exit 2
fi

/usr/bin/python3 - "$ROOT_DIR" "$MODE" "$IPA_PATH" "$ARCHIVE_PATH" <<'PY'
import datetime as dt
import hashlib
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


ROOT = Path(sys.argv[1]).resolve()
MODE = sys.argv[2]
IPA_ARGUMENT = sys.argv[3]
ARCHIVE_ARGUMENT = sys.argv[4]
PROJECT_FILE = ROOT / "project.yml"
SOURCE_OPPORTUNITIES = ROOT / "GTAFreeSTEM" / "Resources" / "opportunities.json"
SOURCE_MAIN_PRIVACY = ROOT / "GTAFreeSTEM" / "Resources" / "PrivacyInfo.xcprivacy"
SOURCE_WATCH_PRIVACY = ROOT / "GTAFreeSTEMWatch" / "PrivacyInfo.xcprivacy"
EXPECTED_MAIN_BUNDLE_ID = "com.rupayonhaldar.gtafreestem"
EXPECTED_WATCH_BUNDLE_ID = "com.rupayonhaldar.gtafreestem.watchkitapp"
SOURCE_COMMIT_KEY = "GTAReleaseSourceCommit"
FIXTURE_SOURCE_COMMIT = "0123456789abcdef0123456789abcdef01234567"
MAX_IPA_ENTRIES = 200000
MAX_IPA_UNCOMPRESSED_BYTES = 2 * 1024 * 1024 * 1024


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


def check_release_source_commits(main_info, watch_info, reporter, label_prefix=""):
    main_commit = main_info.get(SOURCE_COMMIT_KEY)
    watch_commit = watch_info.get(SOURCE_COMMIT_KEY)
    main_valid = isinstance(main_commit, str) and re.fullmatch(r"[0-9a-f]{40}", main_commit) is not None
    watch_valid = isinstance(watch_commit, str) and re.fullmatch(r"[0-9a-f]{40}", watch_commit) is not None
    reporter.expect(
        main_valid,
        label_prefix + "main release source commit",
        main_commit if main_valid else "",
        "expected {} as a full lowercase 40-hex SHA, observed {!r}".format(
            SOURCE_COMMIT_KEY,
            main_commit,
        ),
    )
    reporter.expect(
        watch_valid,
        label_prefix + "Watch release source commit",
        watch_commit if watch_valid else "",
        "expected {} as a full lowercase 40-hex SHA, observed {!r}".format(
            SOURCE_COMMIT_KEY,
            watch_commit,
        ),
    )
    reporter.expect(
        main_valid and watch_valid and main_commit == watch_commit,
        label_prefix + "release source commit agreement",
        main_commit if main_valid and watch_valid and main_commit == watch_commit else "",
        "main={!r}; Watch={!r}; expected identical valid source commits".format(
            main_commit,
            watch_commit,
        ),
    )
    if main_valid and watch_valid and main_commit == watch_commit:
        return main_commit
    return None


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


def utc_now_for(value):
    if isinstance(value, dt.datetime) and value.tzinfo:
        return dt.datetime.now(dt.timezone.utc)
    return dt.datetime.utcnow()


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


def run_command(command, input_data=None):
    try:
        return subprocess.run(
            command,
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise InspectionError("unable to run {}: {}".format(command[0], error))


def decode_certificate(certificate_bytes):
    completed = run_command(
        [
            "/usr/bin/openssl",
            "x509",
            "-inform",
            "DER",
            "-noout",
            "-subject",
            "-enddate",
            "-fingerprint",
            "-sha1",
        ],
        input_data=certificate_bytes,
    )
    payload = completed.stdout + completed.stderr
    text = payload.decode("utf-8", "replace")
    if completed.returncode != 0:
        raise InspectionError("unable to inspect signing certificate: {}".format(text.strip()))
    subject_match = re.search(r"^subject=\s*(.+)$", text, re.MULTILINE)
    expiration_match = re.search(r"^notAfter=(.+)$", text, re.MULTILINE)
    fingerprint_match = re.search(r"^sha1 Fingerprint=(.+)$", text, re.MULTILINE | re.IGNORECASE)
    if not subject_match or not expiration_match or not fingerprint_match:
        raise InspectionError("certificate metadata is incomplete")
    subject = subject_match.group(1).strip()
    common_name_match = re.search(r"(?:^|/)CN=([^/]+)", subject)
    if not common_name_match:
        common_name_match = re.search(r"(?:^|,)\s*CN\s*=\s*([^,]+)", subject)
    try:
        expiration = dt.datetime.strptime(
            re.sub(r"\s+", " ", expiration_match.group(1).strip()),
            "%b %d %H:%M:%S %Y %Z",
        )
    except ValueError as error:
        raise InspectionError("unable to parse certificate expiration: {}".format(error))
    return {
        "common_name": common_name_match.group(1).strip() if common_name_match else "",
        "expiration": expiration,
        "fingerprint": fingerprint_match.group(1).replace(":", "").strip().upper(),
    }


class LiveInspector:
    def signature(self, bundle):
        verification = run_command(
            ["/usr/bin/codesign", "--verify", "--strict", "--verbose=4", str(bundle)]
        )
        if verification.returncode != 0:
            detail = (verification.stderr or verification.stdout).decode("utf-8", "replace").strip()
            raise InspectionError("codesign verification failed: {}".format(detail or "no detail"))

        details = run_command(["/usr/bin/codesign", "-d", "--verbose=4", str(bundle)])
        payload = details.stdout + details.stderr
        text = payload.decode("utf-8", "replace")
        if details.returncode != 0:
            raise InspectionError("unable to inspect code signature: {}".format(text.strip()))
        if re.search(r"^Signature=adhoc$", text, re.MULTILINE):
            raise InspectionError("ad-hoc code signature")
        authorities = re.findall(r"^Authority=(.+)$", text, re.MULTILINE)
        team_match = re.search(r"^TeamIdentifier=(.+)$", text, re.MULTILINE)
        identifier_match = re.search(r"^Identifier=(.+)$", text, re.MULTILINE)
        if not authorities:
            raise InspectionError("signature has no certificate authority")

        with tempfile.TemporaryDirectory(prefix="gtafreestem-signing-cert-") as temporary:
            prefix = Path(temporary) / "certificate"
            extraction = run_command(
                [
                    "/usr/bin/codesign",
                    "-d",
                    "--extract-certificates={}".format(prefix),
                    str(bundle),
                ]
            )
            if extraction.returncode != 0:
                detail = (extraction.stderr or extraction.stdout).decode("utf-8", "replace").strip()
                raise InspectionError("unable to extract signing certificate: {}".format(detail))
            leaf_path = Path("{}0".format(prefix))
            if not leaf_path.is_file():
                raise InspectionError("codesign did not extract a leaf signing certificate")
            certificate = decode_certificate(leaf_path.read_bytes())

        return {
            "authority": authorities[0].strip(),
            "team": team_match.group(1).strip() if team_match else "",
            "identifier": identifier_match.group(1).strip() if identifier_match else "",
            "certificate_common_name": certificate["common_name"],
            "certificate_expiration": certificate["expiration"],
            "certificate_fingerprint": certificate["fingerprint"],
        }

    def entitlements(self, bundle):
        completed = run_command(
            ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)]
        )
        payload = completed.stdout + completed.stderr
        if completed.returncode != 0:
            detail = payload.decode("utf-8", "replace").strip()
            raise InspectionError("unable to inspect entitlements: {}".format(detail or "no detail"))
        return extract_xml_plist(payload)

    def profile(self, path):
        completed = run_command(["/usr/bin/security", "cms", "-D", "-i", str(path)])
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).decode("utf-8", "replace").strip()
            raise InspectionError("unable to decode provisioning profile: {}".format(detail or "no detail"))
        try:
            value = plistlib.loads(completed.stdout)
        except Exception as error:
            raise InspectionError("unable to parse provisioning profile: {}".format(error))
        if not isinstance(value, dict):
            raise InspectionError("provisioning profile root is not a dictionary")
        decoded_certificates = []
        certificates = value.get("DeveloperCertificates")
        if isinstance(certificates, list):
            for certificate in certificates:
                if isinstance(certificate, bytes):
                    decoded_certificates.append(decode_certificate(certificate))
        value["_DecodedDeveloperCertificates"] = decoded_certificates
        return value

    def uuids(self, path):
        completed = run_command(["/usr/bin/xcrun", "dwarfdump", "--uuid", str(path)])
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
    def __init__(
        self,
        signing_mode="distribution",
        signature_team=EXPECTED_TEAM,
        signature_identifier_overrides=None,
        certificate_expiration=None,
        entitlement_application_id_overrides=None,
        entitlement_team=None,
        entitlement_get_task_allow=False,
        profile_application_id_overrides=None,
        profile_team=None,
        profile_expiration=None,
        profile_get_task_allow=False,
        profile_beta_reports_active=True,
        profile_has_devices=False,
        profile_enterprise=False,
        profile_certificate_fingerprint="A" * 40,
        archive_uuid_mismatch=False,
    ):
        self.signing_mode = signing_mode
        self.signature_team = signature_team
        self.signature_identifier_overrides = signature_identifier_overrides or {}
        self.certificate_expiration = certificate_expiration or dt.datetime(2099, 1, 1)
        self.entitlement_application_id_overrides = entitlement_application_id_overrides or {}
        self.entitlement_team = entitlement_team if entitlement_team is not None else EXPECTED_TEAM
        self.entitlement_get_task_allow = entitlement_get_task_allow
        self.profile_application_id_overrides = profile_application_id_overrides or {}
        self.profile_team = profile_team if profile_team is not None else [EXPECTED_TEAM]
        self.profile_expiration = profile_expiration or dt.datetime(2099, 1, 1)
        self.profile_get_task_allow = profile_get_task_allow
        self.profile_beta_reports_active = profile_beta_reports_active
        self.profile_has_devices = profile_has_devices
        self.profile_enterprise = profile_enterprise
        self.profile_certificate_fingerprint = profile_certificate_fingerprint
        self.archive_uuid_mismatch = archive_uuid_mismatch

    def signature(self, bundle):
        info = read_plist_file(bundle / "Info.plist")
        bundle_id = info["CFBundleIdentifier"]
        authority_prefix = "Apple Distribution" if self.signing_mode == "distribution" else "Apple Development"
        authority = "{}: Fixture ({})".format(authority_prefix, self.signature_team)
        return {
            "authority": authority,
            "team": self.signature_team,
            "identifier": self.signature_identifier_overrides.get(bundle_id, bundle_id),
            "certificate_common_name": authority,
            "certificate_expiration": self.certificate_expiration,
            "certificate_fingerprint": "A" * 40,
        }

    def entitlements(self, bundle):
        info = read_plist_file(bundle / "Info.plist")
        bundle_id = info["CFBundleIdentifier"]
        return {
            "application-identifier": self.entitlement_application_id_overrides.get(
                bundle_id,
                "{}.{}".format(EXPECTED_TEAM, bundle_id),
            ),
            "beta-reports-active": True,
            "com.apple.developer.team-identifier": self.entitlement_team,
            "get-task-allow": self.entitlement_get_task_allow,
        }

    def profile(self, path):
        bundle = path.parent
        info = read_plist_file(bundle / "Info.plist")
        bundle_id = info["CFBundleIdentifier"]
        profile = {
            "ApplicationIdentifierPrefix": [EXPECTED_TEAM],
            "DeveloperCertificates": [b"fixture"],
            "Entitlements": {
                "application-identifier": self.profile_application_id_overrides.get(
                    bundle_id,
                    "{}.{}".format(EXPECTED_TEAM, bundle_id),
                ),
                "beta-reports-active": self.profile_beta_reports_active,
                "com.apple.developer.team-identifier": EXPECTED_TEAM,
                "get-task-allow": self.profile_get_task_allow,
            },
            "ExpirationDate": self.profile_expiration,
            "Name": "Fixture App Store Profile",
            "Platform": ["iOS"],
            "TeamIdentifier": self.profile_team,
            "UUID": "00000000-0000-0000-0000-000000000000",
            "_DecodedDeveloperCertificates": [
                {
                    "common_name": "Apple Distribution: Fixture ({})".format(EXPECTED_TEAM),
                    "expiration": dt.datetime(2099, 1, 1),
                    "fingerprint": self.profile_certificate_fingerprint,
                }
            ],
        }
        if self.profile_has_devices:
            profile["ProvisionedDevices"] = ["fixture-device"]
        if self.profile_enterprise:
            profile["ProvisionsAllDevices"] = True
        return profile

    def uuids(self, path):
        is_watch = "Watch" in str(path)
        if self.archive_uuid_mismatch and ".xcarchive" in str(path):
            return {("33333333-3333-3333-3333-333333333333", "arm64")}
        if is_watch:
            return {
                ("22222222-2222-2222-2222-222222222222", "arm64"),
                ("44444444-4444-4444-4444-444444444444", "arm64_32"),
            }
        return {("11111111-1111-1111-1111-111111111111", "arm64")}


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


def check_hash(label, exported_path, source_path, reporter):
    if not exported_path.is_file():
        reporter.fail(label, "missing {}".format(exported_path))
        return
    if not source_path.is_file():
        reporter.fail(label, "current source resource is missing: {}".format(source_path))
        return
    exported_hash = sha256(exported_path)
    source_hash = sha256(source_path)
    reporter.expect(
        exported_hash == source_hash,
        label,
        "sha256={} matches {}".format(exported_hash, source_path.relative_to(ROOT)),
        "exported sha256={} but current source sha256={}".format(exported_hash, source_hash),
    )


def safe_extract_ipa(ipa_path, destination, reporter):
    reporter.expect(
        ipa_path.suffix.lower() == ".ipa",
        "IPA suffix",
        ipa_path.name,
        "expected a .ipa file, observed {}".format(ipa_path.name),
    )
    reporter.expect(
        ipa_path.is_file(),
        "IPA file",
        str(ipa_path),
        "path does not exist as a file: {}".format(ipa_path),
    )
    if not ipa_path.is_file():
        return False
    try:
        archive = zipfile.ZipFile(str(ipa_path), "r")
    except (OSError, zipfile.BadZipFile) as error:
        reporter.fail("IPA ZIP container", "unable to open {}: {}".format(ipa_path, error))
        return False

    with archive:
        infos = archive.infolist()
        issues = []
        names = set()
        total_size = 0
        for info in infos:
            name = info.filename
            total_size += info.file_size
            if name in names:
                issues.append("duplicate entry {}".format(name))
            names.add(name)
            path = PurePosixPath(name)
            if "\\" in name or path.is_absolute() or ".." in path.parts:
                issues.append("unsafe path {}".format(name))
            file_type = (info.external_attr >> 16) & 0o170000
            if file_type and stat.S_ISLNK(file_type):
                issues.append("symbolic link entry {}".format(name))
        if len(infos) > MAX_IPA_ENTRIES:
            issues.append("too many ZIP entries ({})".format(len(infos)))
        if total_size > MAX_IPA_UNCOMPRESSED_BYTES:
            issues.append("uncompressed size exceeds {} bytes".format(MAX_IPA_UNCOMPRESSED_BYTES))
        reporter.expect(
            not issues,
            "IPA ZIP safety",
            "{} unique non-link entries; {} uncompressed bytes".format(len(infos), total_size),
            "; ".join(issues[:12]),
        )
        if issues:
            return False
        try:
            archive.extractall(str(destination))
            for info in infos:
                permissions = (info.external_attr >> 16) & 0o777
                extracted = destination.joinpath(*PurePosixPath(info.filename).parts)
                if permissions and extracted.exists():
                    os.chmod(str(extracted), permissions)
        except (OSError, zipfile.BadZipFile) as error:
            reporter.fail("IPA ZIP extraction", str(error))
            return False
    reporter.pass_("IPA ZIP extraction", str(destination))
    return True


def check_bundle_metadata(label, info, expected_bundle_id, reporter, is_watch=False):
    reporter.expect(
        info.get("CFBundlePackageType") == "APPL",
        label + " runnable package type",
        "APPL",
        "expected APPL, observed {!r}".format(info.get("CFBundlePackageType")),
    )
    reporter.expect(
        info.get("CFBundleIdentifier") == expected_bundle_id,
        label + " bundle identifier",
        expected_bundle_id,
        "expected {}, observed {!r}".format(expected_bundle_id, info.get("CFBundleIdentifier")),
    )
    reporter.expect(
        str(info.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION,
        label + " version",
        EXPECTED_VERSION,
        "expected {}, observed {!r}".format(EXPECTED_VERSION, info.get("CFBundleShortVersionString")),
    )
    reporter.expect(
        str(info.get("CFBundleVersion", "")) == EXPECTED_BUILD,
        label + " build",
        EXPECTED_BUILD,
        "expected {}, observed {!r}".format(EXPECTED_BUILD, info.get("CFBundleVersion")),
    )
    reporter.expect(
        info.get("ITSAppUsesNonExemptEncryption") is False,
        label + " export encryption declaration",
        "ITSAppUsesNonExemptEncryption=false",
        "must be explicitly false, observed {!r}".format(info.get("ITSAppUsesNonExemptEncryption")),
    )
    if is_watch:
        reporter.expect(
            info.get("WKApplication") is True,
            "Watch runnable target",
            "WKApplication=true",
            "WKApplication must be true, observed {!r}".format(info.get("WKApplication")),
        )
        reporter.expect(
            info.get("WKCompanionAppBundleIdentifier") == EXPECTED_MAIN_BUNDLE_ID,
            "Watch companion identifier",
            EXPECTED_MAIN_BUNDLE_ID,
            "expected {}, observed {!r}".format(
                EXPECTED_MAIN_BUNDLE_ID,
                info.get("WKCompanionAppBundleIdentifier"),
            ),
        )
    else:
        family = info.get("UIDeviceFamily")
        normalized_family = set(family) if isinstance(family, list) else set()
        reporter.expect(
            normalized_family == {1, 2},
            "iPhone and iPad device family",
            "UIDeviceFamily=[1, 2]",
            "expected exactly [1, 2], observed {!r}".format(family),
        )


def check_distribution_signature(label, bundle, bundle_id, inspector, reporter):
    try:
        signature = inspector.signature(bundle)
    except InspectionError as error:
        reporter.fail(label + " distribution signature", str(error))
        return None
    authority = signature.get("authority", "")
    team = signature.get("team", "")
    identifier = signature.get("identifier", "")
    common_name = signature.get("certificate_common_name", "")
    expiration = signature.get("certificate_expiration")
    fingerprint = signature.get("certificate_fingerprint", "")
    reporter.expect(
        authority.startswith("Apple Distribution:"),
        label + " distribution signature",
        authority,
        "expected Apple Distribution, observed {}".format(authority or "no authority"),
    )
    reporter.expect(
        team == EXPECTED_TEAM,
        label + " signing team",
        team,
        "expected {}, observed {}".format(EXPECTED_TEAM, team or "missing"),
    )
    reporter.expect(
        identifier == bundle_id,
        label + " signed identifier",
        bundle_id,
        "expected {}, observed {!r}".format(bundle_id, identifier),
    )
    certificate_issues = []
    if common_name != authority:
        certificate_issues.append(
            "leaf certificate common name {!r} does not match authority {!r}".format(
                common_name,
                authority,
            )
        )
    if not re.fullmatch(r"[0-9A-F]{40}", fingerprint):
        certificate_issues.append("leaf certificate SHA-1 fingerprint is missing or invalid")
    if not isinstance(expiration, dt.datetime):
        certificate_issues.append("leaf certificate expiration is missing")
    elif expiration <= utc_now_for(expiration):
        certificate_issues.append("leaf certificate expired at {}".format(expiration.isoformat()))
    reporter.expect(
        not certificate_issues,
        label + " signing certificate",
        "sha1={}; expires={}".format(fingerprint, expiration.isoformat()),
        "; ".join(certificate_issues),
    )
    return signature


def check_distribution_entitlements(label, bundle, bundle_id, inspector, reporter):
    try:
        entitlements = inspector.entitlements(bundle)
    except InspectionError as error:
        reporter.fail(label + " distribution entitlements", str(error))
        return None
    expected_application_id = "{}.{}".format(EXPECTED_TEAM, bundle_id)
    reporter.expect(
        entitlements.get("get-task-allow") is False,
        label + " get-task-allow",
        "false",
        "must be explicitly false, observed {!r}".format(entitlements.get("get-task-allow")),
    )
    reporter.expect(
        entitlements.get("beta-reports-active") is True,
        label + " beta reports entitlement",
        "true",
        "must be explicitly true, observed {!r}".format(entitlements.get("beta-reports-active")),
    )
    reporter.expect(
        entitlements.get("application-identifier") == expected_application_id,
        label + " application identifier entitlement",
        expected_application_id,
        "expected {}, observed {!r}".format(
            expected_application_id,
            entitlements.get("application-identifier"),
        ),
    )
    reporter.expect(
        entitlements.get("com.apple.developer.team-identifier") == EXPECTED_TEAM,
        label + " team identifier entitlement",
        EXPECTED_TEAM,
        "expected {}, observed {!r}".format(
            EXPECTED_TEAM,
            entitlements.get("com.apple.developer.team-identifier"),
        ),
    )
    return entitlements


def check_app_store_profile(label, bundle, bundle_id, signature, inspector, reporter):
    path = bundle / "embedded.mobileprovision"
    if not path.is_file():
        reporter.fail(label + " App Store provisioning", "missing {}".format(path))
        return
    try:
        profile = inspector.profile(path)
    except InspectionError as error:
        reporter.fail(label + " App Store provisioning", str(error))
        return
    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        reporter.fail(label + " App Store provisioning", "profile Entitlements dictionary is missing")
        return

    expected_application_id = "{}.{}".format(EXPECTED_TEAM, bundle_id)
    issues = []
    if entitlements.get("application-identifier") != expected_application_id:
        issues.append(
            "application-identifier expected {}, observed {!r}".format(
                expected_application_id,
                entitlements.get("application-identifier"),
            )
        )
    if entitlements.get("com.apple.developer.team-identifier") != EXPECTED_TEAM:
        issues.append(
            "entitlement team identifier expected {}, observed {!r}".format(
                EXPECTED_TEAM,
                entitlements.get("com.apple.developer.team-identifier"),
            )
        )
    if entitlements.get("get-task-allow") is not False:
        issues.append("profile get-task-allow is not false")
    if entitlements.get("beta-reports-active") is not True:
        issues.append("beta-reports-active is not true")
    if "ProvisionedDevices" in profile:
        issues.append("ProvisionedDevices is present (development/ad-hoc profile)")
    if profile.get("ProvisionsAllDevices") is True:
        issues.append("ProvisionsAllDevices is true (enterprise profile)")
    if profile.get("TeamIdentifier") != [EXPECTED_TEAM]:
        issues.append(
            "TeamIdentifier expected [{}], observed {!r}".format(
                EXPECTED_TEAM,
                profile.get("TeamIdentifier"),
            )
        )
    if profile.get("ApplicationIdentifierPrefix") != [EXPECTED_TEAM]:
        issues.append(
            "ApplicationIdentifierPrefix expected [{}], observed {!r}".format(
                EXPECTED_TEAM,
                profile.get("ApplicationIdentifierPrefix"),
            )
        )
    platforms = profile.get("Platform")
    if not isinstance(platforms, list) or "iOS" not in platforms:
        issues.append("profile Platform does not include iOS")
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        issues.append("ExpirationDate is missing or invalid")
    elif expiration <= utc_now_for(expiration):
        issues.append("profile expired at {}".format(expiration.isoformat()))

    certificates = profile.get("_DecodedDeveloperCertificates")
    certificate_fingerprints = {
        certificate.get("fingerprint")
        for certificate in certificates
        if isinstance(certificate, dict) and certificate.get("fingerprint")
    } if isinstance(certificates, list) else set()
    signature_fingerprint = signature.get("certificate_fingerprint", "") if signature else ""
    if not signature_fingerprint or signature_fingerprint not in certificate_fingerprints:
        issues.append("profile does not authorize the leaf signing certificate")

    if issues:
        reporter.fail(label + " App Store provisioning", "; ".join(issues))
    else:
        reporter.pass_(
            label + " App Store provisioning",
            "{}; exact-id={}; UUID={}; expires={}".format(
                profile.get("Name", "unnamed profile"),
                expected_application_id,
                profile.get("UUID", "missing"),
                expiration.isoformat(),
            ),
        )


def executable_uuids(label, executable, inspector, reporter):
    if not executable.is_file():
        reporter.fail(label + " executable UUIDs", "missing {}".format(executable))
        return None
    try:
        uuids = inspector.uuids(executable)
    except InspectionError as error:
        reporter.fail(label + " executable UUIDs", str(error))
        return None
    evidence = ", ".join("{} ({})".format(uuid, arch) for uuid, arch in sorted(uuids))
    reporter.pass_(label + " executable UUIDs", evidence)
    return uuids


def check_archive_provenance(
    archive,
    main_executable_name,
    watch_executable_name,
    exported_source_commit,
    main_exported_uuids,
    watch_exported_uuids,
    inspector,
    reporter,
):
    reporter.expect(
        archive.name.endswith(".xcarchive") and archive.is_dir(),
        "source archive provenance input",
        str(archive),
        "expected an existing .xcarchive directory, observed {}".format(archive),
    )
    if not archive.name.endswith(".xcarchive") or not archive.is_dir():
        return
    main = archive / "Products" / "Applications" / "GTAFreeSTEM.app"
    watch = main / "Watch" / "GTAFreeSTEMWatch.app"
    archive_main_info = load_plist(
        main / "Info.plist",
        "source archive main Info.plist",
        reporter,
    )
    archive_watch_info = load_plist(
        watch / "Info.plist",
        "source archive Watch Info.plist",
        reporter,
    )
    archive_source_commit = check_release_source_commits(
        archive_main_info or {},
        archive_watch_info or {},
        reporter,
        label_prefix="source archive ",
    )
    reporter.expect(
        exported_source_commit is not None
        and archive_source_commit is not None
        and exported_source_commit == archive_source_commit,
        "archive-to-IPA source commit provenance",
        exported_source_commit if exported_source_commit == archive_source_commit else "",
        "source archive={!r}; exported IPA={!r}; expected identical valid source commits".format(
            archive_source_commit,
            exported_source_commit,
        ),
    )
    pairs = [
        ("main", main / main_executable_name, main_exported_uuids),
        ("Watch", watch / watch_executable_name, watch_exported_uuids),
    ]
    for label, executable, exported_uuids in pairs:
        if exported_uuids is None:
            continue
        try:
            archived_uuids = inspector.uuids(executable)
        except InspectionError as error:
            reporter.fail(label + " archive-to-IPA UUID provenance", str(error))
            continue
        reporter.expect(
            archived_uuids == exported_uuids,
            label + " archive-to-IPA UUID provenance",
            ", ".join("{} ({})".format(uuid, arch) for uuid, arch in sorted(exported_uuids)),
            "archive UUIDs={} exported UUIDs={}".format(
                sorted(archived_uuids),
                sorted(exported_uuids),
            ),
        )


def verify_payload(payload, inspector, reporter, archive=None):
    app_candidates = sorted(path for path in payload.glob("*.app") if path.is_dir()) if payload.is_dir() else []
    reporter.expect(
        len(app_candidates) == 1,
        "IPA application layout",
        str(app_candidates[0]) if len(app_candidates) == 1 else "",
        "expected exactly one Payload/*.app, found {}".format(len(app_candidates)),
    )
    if len(app_candidates) != 1:
        return
    app = app_candidates[0]
    reporter.expect(
        app.name == "GTAFreeSTEM.app",
        "main application name",
        app.name,
        "expected GTAFreeSTEM.app, observed {}".format(app.name),
    )
    watch_candidates = sorted(
        path for path in (app / "Watch").glob("*.app") if path.is_dir()
    ) if (app / "Watch").is_dir() else []
    reporter.expect(
        len(watch_candidates) == 1,
        "embedded Watch application layout",
        str(watch_candidates[0]) if len(watch_candidates) == 1 else "",
        "expected exactly one Watch/*.app, found {}".format(len(watch_candidates)),
    )
    if len(watch_candidates) != 1:
        return
    watch = watch_candidates[0]
    reporter.expect(
        watch.name == "GTAFreeSTEMWatch.app",
        "Watch application name",
        watch.name,
        "expected GTAFreeSTEMWatch.app, observed {}".format(watch.name),
    )

    unexpected_apps = sorted(
        path for path in app.rglob("*.app") if path not in {app, watch}
    )
    unexpected_extensions = sorted(app.rglob("*.appex"))
    reporter.expect(
        not unexpected_apps and not unexpected_extensions,
        "embedded executable bundle allowlist",
        "main app plus one Watch app",
        "unexpected apps={} extensions={}".format(unexpected_apps, unexpected_extensions),
    )

    main_info = load_plist(app / "Info.plist", "main Info.plist", reporter)
    watch_info = load_plist(watch / "Info.plist", "Watch Info.plist", reporter)
    if main_info is None or watch_info is None:
        return
    exported_source_commit = check_release_source_commits(main_info, watch_info, reporter)
    check_bundle_metadata("main", main_info, EXPECTED_MAIN_BUNDLE_ID, reporter)
    check_bundle_metadata("Watch", watch_info, EXPECTED_WATCH_BUNDLE_ID, reporter, is_watch=True)

    main_privacy = load_plist(app / "PrivacyInfo.xcprivacy", "main privacy manifest", reporter)
    if main_privacy is not None:
        check_hash("main privacy manifest SHA", app / "PrivacyInfo.xcprivacy", SOURCE_MAIN_PRIVACY, reporter)
    watch_privacy = load_plist(watch / "PrivacyInfo.xcprivacy", "Watch privacy manifest", reporter)
    if watch_privacy is not None:
        check_hash("Watch privacy manifest SHA", watch / "PrivacyInfo.xcprivacy", SOURCE_WATCH_PRIVACY, reporter)
    check_hash("main bundled opportunities SHA", app / "opportunities.json", SOURCE_OPPORTUNITIES, reporter)

    main_signature = check_distribution_signature(
        "main",
        app,
        EXPECTED_MAIN_BUNDLE_ID,
        inspector,
        reporter,
    )
    check_distribution_entitlements(
        "main",
        app,
        EXPECTED_MAIN_BUNDLE_ID,
        inspector,
        reporter,
    )
    check_app_store_profile(
        "main",
        app,
        EXPECTED_MAIN_BUNDLE_ID,
        main_signature,
        inspector,
        reporter,
    )
    watch_signature = check_distribution_signature(
        "Watch",
        watch,
        EXPECTED_WATCH_BUNDLE_ID,
        inspector,
        reporter,
    )
    check_distribution_entitlements(
        "Watch",
        watch,
        EXPECTED_WATCH_BUNDLE_ID,
        inspector,
        reporter,
    )
    check_app_store_profile(
        "Watch",
        watch,
        EXPECTED_WATCH_BUNDLE_ID,
        watch_signature,
        inspector,
        reporter,
    )

    main_executable_name = main_info.get("CFBundleExecutable")
    watch_executable_name = watch_info.get("CFBundleExecutable")
    if not isinstance(main_executable_name, str) or not main_executable_name:
        reporter.fail("main executable", "CFBundleExecutable is missing")
        main_exported_uuids = None
    else:
        main_exported_uuids = executable_uuids(
            "main",
            app / main_executable_name,
            inspector,
            reporter,
        )
    if not isinstance(watch_executable_name, str) or not watch_executable_name:
        reporter.fail("Watch executable", "CFBundleExecutable is missing")
        watch_exported_uuids = None
    else:
        watch_exported_uuids = executable_uuids(
            "Watch",
            watch / watch_executable_name,
            inspector,
            reporter,
        )

    if archive is not None and isinstance(main_executable_name, str) and isinstance(watch_executable_name, str):
        check_archive_provenance(
            archive,
            main_executable_name,
            watch_executable_name,
            exported_source_commit,
            main_exported_uuids,
            watch_exported_uuids,
            inspector,
            reporter,
        )


def verify_ipa(ipa_path, inspector, emit=True, archive=None):
    reporter = Reporter(emit=emit)
    ipa_path = ipa_path.resolve()
    reporter.pass_("IPA SHA-256", sha256(ipa_path)) if ipa_path.is_file() else None
    with tempfile.TemporaryDirectory(prefix="gtafreestem-ipa-verifier-") as temporary:
        extraction = Path(temporary)
        if safe_extract_ipa(ipa_path, extraction, reporter):
            verify_payload(extraction / "Payload", inspector, reporter, archive=archive)
    return reporter


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        plistlib.dump(value, stream, fmt=plistlib.FMT_XML, sort_keys=True)


def build_payload_fixture(base):
    payload = base / "Payload"
    app = payload / "GTAFreeSTEM.app"
    watch = app / "Watch" / "GTAFreeSTEMWatch.app"
    app.mkdir(parents=True)
    watch.mkdir(parents=True)
    write_plist(
        app / "Info.plist",
        {
            "CFBundleExecutable": "GTAFreeSTEM",
            "CFBundleIdentifier": EXPECTED_MAIN_BUNDLE_ID,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": EXPECTED_VERSION,
            "CFBundleVersion": EXPECTED_BUILD,
            SOURCE_COMMIT_KEY: FIXTURE_SOURCE_COMMIT,
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
            SOURCE_COMMIT_KEY: FIXTURE_SOURCE_COMMIT,
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
    return payload


def build_archive_fixture(base, payload):
    archive = base / "Fixture.xcarchive"
    destination = archive / "Products" / "Applications" / "GTAFreeSTEM.app"
    shutil.copytree(payload / "GTAFreeSTEM.app", destination)
    return archive


def write_ipa_fixture(path, payload):
    with zipfile.ZipFile(str(path), "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for candidate in sorted(payload.parent.rglob("*")):
            relative = candidate.relative_to(payload.parent).as_posix()
            if candidate.is_dir():
                archive.writestr(relative + "/", b"")
            else:
                archive.write(str(candidate), relative)


def require_failure(report, prefix, fragment=""):
    return any(
        line.startswith(prefix) and (not fragment or fragment in line)
        for line in report.failures
    )


def run_self_test():
    required_sources = [SOURCE_OPPORTUNITIES, SOURCE_MAIN_PRIVACY, SOURCE_WATCH_PRIVACY]
    if not all(path.is_file() for path in required_sources):
        raise SystemExit("Self-test requires the current source resources.")
    with tempfile.TemporaryDirectory(prefix="gtafreestem-ipa-verifier-self-test-") as temporary:
        base = Path(temporary)
        fixture_root = base / "fixture-root"
        payload = build_payload_fixture(fixture_root)
        archive = build_archive_fixture(base, payload)
        ipa = base / "Fixture.ipa"
        write_ipa_fixture(ipa, payload)

        passing = verify_ipa(ipa, FixtureInspector(), emit=False, archive=archive)
        if passing.failures:
            print("IPA verifier self-test failed: valid App Store fixture was rejected.", file=sys.stderr)
            for failure in passing.failures:
                print(failure, file=sys.stderr)
            return 1

        source_commit_cases = (
            ("missing-main", "main", None, "FAIL main release source commit"),
            ("missing-watch", "watch", None, "FAIL Watch release source commit"),
            ("malformed-main", "main", "A" * 40, "FAIL main release source commit"),
            ("malformed-watch", "watch", "1234", "FAIL Watch release source commit"),
        )
        for name, target, replacement, expected_failure in source_commit_cases:
            case_payload = build_payload_fixture(base / name)
            if target == "main":
                info_path = case_payload / "GTAFreeSTEM.app" / "Info.plist"
            else:
                info_path = (
                    case_payload
                    / "GTAFreeSTEM.app"
                    / "Watch"
                    / "GTAFreeSTEMWatch.app"
                    / "Info.plist"
                )
            info = read_plist_file(info_path)
            if replacement is None:
                info.pop(SOURCE_COMMIT_KEY, None)
            else:
                info[SOURCE_COMMIT_KEY] = replacement
            write_plist(info_path, info)
            case_ipa = base / "{}.ipa".format(name)
            write_ipa_fixture(case_ipa, case_payload)
            rejected = verify_ipa(case_ipa, FixtureInspector(), emit=False)
            if not require_failure(rejected, expected_failure):
                print(
                    "IPA verifier self-test failed: {} source commit was not rejected.".format(name),
                    file=sys.stderr,
                )
                return 1

        mismatched_payload = build_payload_fixture(base / "mismatched-source-commits")
        mismatched_watch_info_path = (
            mismatched_payload
            / "GTAFreeSTEM.app"
            / "Watch"
            / "GTAFreeSTEMWatch.app"
            / "Info.plist"
        )
        mismatched_watch_info = read_plist_file(mismatched_watch_info_path)
        mismatched_watch_info[SOURCE_COMMIT_KEY] = "f" * 40
        write_plist(mismatched_watch_info_path, mismatched_watch_info)
        mismatched_source_ipa = base / "MismatchedSourceCommit.ipa"
        write_ipa_fixture(mismatched_source_ipa, mismatched_payload)
        mismatched_source = verify_ipa(mismatched_source_ipa, FixtureInspector(), emit=False)
        if not require_failure(mismatched_source, "FAIL release source commit agreement"):
            print("IPA verifier self-test failed: mismatched exported source commits were not rejected.", file=sys.stderr)
            return 1

        different_archive = build_archive_fixture(base / "different-source-archive", payload)
        different_archive_main_info_path = (
            different_archive / "Products" / "Applications" / "GTAFreeSTEM.app" / "Info.plist"
        )
        different_archive_watch_info_path = (
            different_archive_main_info_path.parent
            / "Watch"
            / "GTAFreeSTEMWatch.app"
            / "Info.plist"
        )
        for info_path in (different_archive_main_info_path, different_archive_watch_info_path):
            info = read_plist_file(info_path)
            info[SOURCE_COMMIT_KEY] = "f" * 40
            write_plist(info_path, info)
        different_archive_source = verify_ipa(
            ipa,
            FixtureInspector(),
            emit=False,
            archive=different_archive,
        )
        if not require_failure(
            different_archive_source,
            "FAIL archive-to-IPA source commit provenance",
            "expected identical valid source commits",
        ):
            print(
                "IPA verifier self-test failed: archive-to-IPA source commit mismatch was not rejected.",
                file=sys.stderr,
            )
            return 1

        cases = [
            (
                "development signing",
                FixtureInspector(signing_mode="development"),
                "FAIL main distribution signature",
                "Apple Development",
            ),
            (
                "wildcard Watch profile",
                FixtureInspector(
                    profile_application_id_overrides={
                        EXPECTED_WATCH_BUNDLE_ID: "{}.*".format(EXPECTED_TEAM),
                    }
                ),
                "FAIL Watch App Store provisioning",
                "application-identifier expected",
            ),
            (
                "wrong signing team",
                FixtureInspector(signature_team="WRONGTEAM1"),
                "FAIL main signing team",
                "expected {}".format(EXPECTED_TEAM),
            ),
            (
                "wrong entitlement team",
                FixtureInspector(entitlement_team="WRONGTEAM1"),
                "FAIL main team identifier entitlement",
                "WRONGTEAM1",
            ),
            (
                "wrong profile team",
                FixtureInspector(profile_team=["WRONGTEAM1"]),
                "FAIL main App Store provisioning",
                "TeamIdentifier expected",
            ),
            (
                "wrong signed bundle identifier",
                FixtureInspector(
                    signature_identifier_overrides={
                        EXPECTED_MAIN_BUNDLE_ID: "com.example.wrong",
                    }
                ),
                "FAIL main signed identifier",
                "com.example.wrong",
            ),
            (
                "expired signing certificate",
                FixtureInspector(certificate_expiration=dt.datetime(2000, 1, 1)),
                "FAIL main signing certificate",
                "expired",
            ),
            (
                "expired profile",
                FixtureInspector(profile_expiration=dt.datetime(2000, 1, 1)),
                "FAIL main App Store provisioning",
                "profile expired",
            ),
            (
                "debug entitlement",
                FixtureInspector(
                    entitlement_get_task_allow=True,
                    profile_get_task_allow=True,
                ),
                "FAIL main get-task-allow",
                "observed True",
            ),
            (
                "mismatched signed application identifier",
                FixtureInspector(
                    entitlement_application_id_overrides={
                        EXPECTED_MAIN_BUNDLE_ID: "{}.com.example.wrong".format(EXPECTED_TEAM),
                    }
                ),
                "FAIL main application identifier entitlement",
                "com.example.wrong",
            ),
            (
                "mismatched profile certificate",
                FixtureInspector(profile_certificate_fingerprint="B" * 40),
                "FAIL main App Store provisioning",
                "does not authorize",
            ),
            (
                "development device profile",
                FixtureInspector(profile_has_devices=True),
                "FAIL main App Store provisioning",
                "ProvisionedDevices",
            ),
            (
                "enterprise profile",
                FixtureInspector(profile_enterprise=True),
                "FAIL main App Store provisioning",
                "ProvisionsAllDevices",
            ),
            (
                "archive provenance mismatch",
                FixtureInspector(archive_uuid_mismatch=True),
                "FAIL main archive-to-IPA UUID provenance",
                "archive UUIDs",
            ),
        ]
        for name, inspector, prefix, fragment in cases:
            report = verify_ipa(ipa, inspector, emit=False, archive=archive)
            if not require_failure(report, prefix, fragment):
                print(
                    "IPA verifier self-test failed: {} was not rejected with {} containing {!r}.".format(
                        name,
                        prefix,
                        fragment,
                    ),
                    file=sys.stderr,
                )
                for failure in report.failures:
                    print(failure, file=sys.stderr)
                return 1

        unsafe_ipa = base / "Unsafe.ipa"
        with zipfile.ZipFile(str(unsafe_ipa), "w") as unsafe:
            unsafe.writestr("../outside.txt", b"unsafe")
        unsafe_report = verify_ipa(unsafe_ipa, FixtureInspector(), emit=False)
        if not require_failure(unsafe_report, "FAIL IPA ZIP safety", "unsafe path"):
            print("IPA verifier self-test failed: unsafe ZIP path was not rejected.", file=sys.stderr)
            return 1

        main_info_path = payload / "GTAFreeSTEM.app" / "Info.plist"
        main_info = read_plist_file(main_info_path)
        main_info["CFBundleIdentifier"] = "com.example.wrong"
        write_plist(main_info_path, main_info)
        mismatched_ipa = base / "MismatchedIdentifier.ipa"
        write_ipa_fixture(mismatched_ipa, payload)
        mismatched = verify_ipa(mismatched_ipa, FixtureInspector(), emit=False)
        if not require_failure(mismatched, "FAIL main bundle identifier", "com.example.wrong"):
            print("IPA verifier self-test failed: mismatched Info.plist identifier was not rejected.", file=sys.stderr)
            return 1

    print(
        "IPA verifier self-test passed "
        "(valid distribution/source-commit/provenance fixture plus missing/malformed/mismatched source-commit, "
        "development, wildcard, wrong-team, "
        "signed/profile identifier, expired, debug, certificate, device/enterprise, UUID, "
        "and ZIP-safety failures)."
    )
    return 0


if MODE == "self-test":
    raise SystemExit(run_self_test())

ipa_path = Path(os.path.expanduser(IPA_ARGUMENT))
if not ipa_path.is_absolute():
    ipa_path = (Path.cwd() / ipa_path).resolve()
archive_path = None
if ARCHIVE_ARGUMENT:
    archive_path = Path(os.path.expanduser(ARCHIVE_ARGUMENT))
    if not archive_path.is_absolute():
        archive_path = (Path.cwd() / archive_path).resolve()

report = verify_ipa(ipa_path, LiveInspector(), emit=True, archive=archive_path)
if report.failures:
    print("RESULT FAIL — {} check(s) failed; {} passed.".format(len(report.failures), len(report.passes)))
    raise SystemExit(1)
print(
    "RESULT PASS — {} strict exported App Store IPA checks passed for {} {} ({}).".format(
        len(report.passes),
        EXPECTED_MAIN_BUNDLE_ID,
        EXPECTED_VERSION,
        EXPECTED_BUILD,
    )
)
if archive_path is None:
    print(
        "NOTE — Distribution signing is valid, but archive-to-IPA UUID provenance was not checked; "
        "supply the source .xcarchive as the second argument for release signoff."
    )
PY
