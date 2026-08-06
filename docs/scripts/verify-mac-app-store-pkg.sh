#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="verify"
PKG_PATH="${MAC_PKG_PATH:-}"
ARCHIVE_PATH="${MAC_ARCHIVE_PATH:-}"

if [ "${1:-}" = "--self-test" ]; then
  if [ "$#" -ne 1 ]; then
    echo "Usage: $0 --self-test" >&2
    exit 2
  fi
  MODE="self-test"
  PKG_PATH=""
  ARCHIVE_PATH=""
elif [ "$#" -eq 1 ]; then
  PKG_PATH="$1"
elif [ "$#" -eq 2 ]; then
  PKG_PATH="$1"
  ARCHIVE_PATH="$2"
elif [ "$#" -ne 0 ]; then
  echo "Usage: $0 /absolute/path/to/App.pkg [/absolute/path/to/source.xcarchive]" >&2
  echo "       MAC_PKG_PATH=/absolute/path/to/App.pkg MAC_ARCHIVE_PATH=/absolute/path/to/source.xcarchive $0" >&2
  echo "       $0 --self-test" >&2
  exit 2
fi

if [ "$MODE" = "verify" ] && [ -z "$PKG_PATH" ]; then
  echo "FAIL Mac package input — supply a real exported .pkg path as the first argument or MAC_PKG_PATH." >&2
  exit 2
fi

/usr/bin/python3 - "$ROOT_DIR" "$MODE" "$PKG_PATH" "$ARCHIVE_PATH" <<'PY'
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
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath


ROOT = Path(sys.argv[1]).resolve()
MODE = sys.argv[2]
PKG_ARGUMENT = sys.argv[3]
ARCHIVE_ARGUMENT = sys.argv[4]
PROJECT_FILE = ROOT / "project.yml"
SOURCE_OPPORTUNITIES = ROOT / "GTAFreeSTEM" / "Resources" / "opportunities.json"
SOURCE_PRIVACY = ROOT / "GTAFreeSTEM" / "Resources" / "PrivacyInfo.xcprivacy"
SOURCE_STRINGS = ROOT / "GTAFreeSTEM" / "Resources" / "app_strings.json"
EXPECTED_BUNDLE_ID = "com.rupayonhaldar.gtafreestem.maccatalyst"
EXPECTED_COMPONENT_NAME = EXPECTED_BUNDLE_ID + ".pkg"
SOURCE_COMMIT_KEY = "GTAReleaseSourceCommit"
FIXTURE_SOURCE_COMMIT = "0123456789abcdef0123456789abcdef01234567"
MAX_PACKAGE_ENTRIES = 200000
MAX_EXPANDED_BYTES = 2 * 1024 * 1024 * 1024


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
EXPECTED_MINIMUM_SYSTEM = source_setting("macOS")
EXPECTED_APPLICATION_IDENTIFIER = "{}.{}".format(EXPECTED_TEAM, EXPECTED_BUNDLE_ID)
EXPECTED_ARCHITECTURES = {"arm64", "x86_64"}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def utc_now_for(value):
    if isinstance(value, dt.datetime) and value.tzinfo:
        return dt.datetime.now(dt.timezone.utc)
    return dt.datetime.utcnow()


def read_plist(path):
    with path.open("rb") as stream:
        value = plistlib.load(stream)
    if not isinstance(value, dict):
        raise ValueError("property-list root is not a dictionary")
    return value


def valid_source_commit(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value) is not None


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


def parse_installer_signature(output):
    status_match = re.search(r"^\s*Status:\s*(.+)$", output, re.MULTILINE)
    leaf_match = re.search(r"^\s*1\.\s+(.+)$", output, re.MULTILINE)
    if not status_match or not leaf_match:
        raise InspectionError("pkgutil signature output is incomplete")
    leaf_start = leaf_match.end()
    next_certificate = re.search(r"^\s*2\.\s+", output[leaf_start:], re.MULTILINE)
    leaf_end = leaf_start + next_certificate.start() if next_certificate else len(output)
    leaf_block = output[leaf_start:leaf_end]
    expiration_match = re.search(r"^\s*Expires:\s*(.+)$", leaf_block, re.MULTILINE)
    fingerprint_match = re.search(
        r"SHA256 Fingerprint:\s*([0-9A-Fa-f\s]+?)(?:\n\s*-{5,}|\Z)",
        leaf_block,
        re.MULTILINE,
    )
    if not expiration_match or not fingerprint_match:
        raise InspectionError("installer certificate metadata is incomplete")
    try:
        expiration = dt.datetime.strptime(
            re.sub(r"\s+", " ", expiration_match.group(1).strip()),
            "%Y-%m-%d %H:%M:%S %z",
        )
    except ValueError as error:
        raise InspectionError("unable to parse installer certificate expiration: {}".format(error))
    fingerprint = re.sub(r"[^0-9A-Fa-f]", "", fingerprint_match.group(1)).upper()
    common_name = leaf_match.group(1).strip()
    team_match = re.search(r"\(([A-Z0-9]{10})\)$", common_name)
    return {
        "status": status_match.group(1).strip(),
        "common_name": common_name,
        "team": team_match.group(1) if team_match else "",
        "expiration": expiration,
        "fingerprint": fingerprint,
        "trusted_chain": (
            "Apple Worldwide Developer Relations Certification Authority" in output
            and "Apple Root CA" in output
        ),
    }


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


class LiveInspector:
    def package_signature(self, package):
        completed = run_command(["/usr/sbin/pkgutil", "--check-signature", str(package)])
        payload = completed.stdout + completed.stderr
        text = payload.decode("utf-8", "replace")
        if completed.returncode != 0:
            raise InspectionError("pkgutil signature verification failed: {}".format(text.strip()))
        return parse_installer_signature(text)

    def expand(self, package, destination):
        listing = run_command(["/usr/bin/xar", "-tf", str(package)])
        if listing.returncode != 0:
            detail = (listing.stderr or listing.stdout).decode("utf-8", "replace").strip()
            raise InspectionError("unable to inspect package XAR: {}".format(detail))
        names = listing.stdout.decode("utf-8", "replace").splitlines()
        issues = []
        seen = set()
        for name in names:
            path = PurePosixPath(name)
            if name in seen:
                issues.append("duplicate XAR entry {}".format(name))
            seen.add(name)
            if not name or "\\" in name or path.is_absolute() or ".." in path.parts:
                issues.append("unsafe XAR path {}".format(name or "<blank>"))
        if len(names) > MAX_PACKAGE_ENTRIES:
            issues.append("too many XAR entries ({})".format(len(names)))
        if issues:
            raise InspectionError("; ".join(issues[:12]))
        completed = run_command(
            ["/usr/sbin/pkgutil", "--expand-full", str(package), str(destination)]
        )
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).decode("utf-8", "replace").strip()
            raise InspectionError("pkgutil expansion failed: {}".format(detail))

    def signature(self, bundle):
        verification = run_command(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=4", str(bundle)]
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
        with tempfile.TemporaryDirectory(prefix="gtafreestem-mac-pkg-cert-") as temporary:
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
            raise InspectionError(
                "unable to inspect entitlements: {}".format(payload.decode("utf-8", "replace").strip())
            )
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
        payload = completed.stdout + completed.stderr
        if completed.returncode != 0:
            raise InspectionError("dwarfdump failed: {}".format(payload.decode("utf-8", "replace").strip()))
        pairs = set()
        for match in re.finditer(
            rb"^UUID:\s*([0-9A-Fa-f-]{36})\s*\(([^)]+)\)",
            payload,
            re.MULTILINE,
        ):
            pairs.add((match.group(1).decode("ascii").upper(), match.group(2).decode("utf-8")))
        if not pairs:
            raise InspectionError("dwarfdump emitted no Mach-O UUIDs")
        return pairs


class FixtureInspector:
    def __init__(
        self,
        expanded,
        installer_common_name=None,
        installer_team=EXPECTED_TEAM,
        installer_expiration=None,
        installer_fingerprint="A" * 64,
        installer_trusted_chain=True,
        app_authority=None,
        app_team=EXPECTED_TEAM,
        app_identifier=EXPECTED_BUNDLE_ID,
        app_certificate_expiration=None,
        app_certificate_fingerprint="B" * 40,
        entitlements=None,
        profile_identifier=EXPECTED_APPLICATION_IDENTIFIER,
        profile_team=None,
        profile_expiration=None,
        profile_has_devices=False,
        profile_enterprise=False,
        profile_platform=None,
        profile_certificate_fingerprint="B" * 40,
        archive_uuid_mismatch=False,
    ):
        self.expanded = expanded
        self.installer_common_name = installer_common_name or (
            "3rd Party Mac Developer Installer: Fixture ({})".format(installer_team)
        )
        self.installer_team = installer_team
        self.installer_expiration = installer_expiration or dt.datetime(2099, 1, 1, tzinfo=dt.timezone.utc)
        self.installer_fingerprint = installer_fingerprint
        self.installer_trusted_chain = installer_trusted_chain
        self.app_authority = app_authority or "Apple Distribution: Fixture ({})".format(app_team)
        self.app_team = app_team
        self.app_identifier = app_identifier
        self.app_certificate_expiration = app_certificate_expiration or dt.datetime(2099, 1, 1)
        self.app_certificate_fingerprint = app_certificate_fingerprint
        self.entitlements_value = entitlements or {
            "application-identifier": EXPECTED_APPLICATION_IDENTIFIER,
            "com.apple.application-identifier": EXPECTED_APPLICATION_IDENTIFIER,
            "com.apple.developer.team-identifier": EXPECTED_TEAM,
            "com.apple.security.app-sandbox": True,
            "com.apple.security.network.client": True,
            "com.apple.security.personal-information.location": True,
            "get-task-allow": False,
        }
        self.profile_identifier = profile_identifier
        self.profile_team = profile_team if profile_team is not None else [EXPECTED_TEAM]
        self.profile_expiration = profile_expiration or dt.datetime(2099, 1, 1)
        self.profile_has_devices = profile_has_devices
        self.profile_enterprise = profile_enterprise
        self.profile_platform = profile_platform if profile_platform is not None else ["OSX"]
        self.profile_certificate_fingerprint = profile_certificate_fingerprint
        self.archive_uuid_mismatch = archive_uuid_mismatch

    def package_signature(self, package):
        return {
            "status": "signed by a developer certificate issued by Apple (Development)",
            "common_name": self.installer_common_name,
            "team": self.installer_team,
            "expiration": self.installer_expiration,
            "fingerprint": self.installer_fingerprint,
            "trusted_chain": self.installer_trusted_chain,
        }

    def expand(self, package, destination):
        # Preserve hostile links so the verifier can reject them. Following a
        # fixture link would copy data outside the fixture and defeat the test.
        shutil.copytree(self.expanded, destination, symlinks=True)

    def signature(self, bundle):
        return {
            "authority": self.app_authority,
            "team": self.app_team,
            "identifier": self.app_identifier,
            "certificate_common_name": self.app_authority,
            "certificate_expiration": self.app_certificate_expiration,
            "certificate_fingerprint": self.app_certificate_fingerprint,
        }

    def entitlements(self, bundle):
        return dict(self.entitlements_value)

    def profile(self, path):
        profile = {
            "ApplicationIdentifierPrefix": [EXPECTED_TEAM],
            "Entitlements": {
                "application-identifier": self.profile_identifier,
                "com.apple.application-identifier": self.profile_identifier,
                "com.apple.developer.team-identifier": EXPECTED_TEAM,
                "get-task-allow": False,
            },
            "ExpirationDate": self.profile_expiration,
            "Name": "Fixture Mac App Store Profile",
            "Platform": self.profile_platform,
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
        if self.archive_uuid_mismatch and ".xcarchive" in str(path):
            return {("33333333-3333-3333-3333-333333333333", "arm64")}
        return {
            ("11111111-1111-1111-1111-111111111111", "arm64"),
            ("22222222-2222-2222-2222-222222222222", "x86_64"),
        }


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


def check_hash(label, packaged_path, source_path, reporter):
    if not packaged_path.is_file():
        reporter.fail(label, "missing {}".format(packaged_path))
        return
    if not source_path.is_file():
        reporter.fail(label, "current source resource is missing: {}".format(source_path))
        return
    packaged_hash = sha256(packaged_path)
    source_hash = sha256(source_path)
    reporter.expect(
        packaged_hash == source_hash,
        label,
        "sha256={} matches {}".format(packaged_hash, source_path.relative_to(ROOT)),
        "package sha256={} but current source sha256={}".format(packaged_hash, source_hash),
    )


def check_installer_signature(package, inspector, reporter):
    try:
        signature = inspector.package_signature(package)
    except InspectionError as error:
        reporter.fail("Mac installer package signature", str(error))
        return
    common_name = signature.get("common_name", "")
    team = signature.get("team", "")
    expiration = signature.get("expiration")
    fingerprint = signature.get("fingerprint", "")
    expected_pattern = r"^3rd Party Mac Developer Installer: .+ \({}\)$".format(
        re.escape(EXPECTED_TEAM)
    )
    reporter.expect(
        re.fullmatch(expected_pattern, common_name) is not None,
        "Mac installer certificate identity",
        common_name,
        "expected 3rd Party Mac Developer Installer for team {}, observed {!r}".format(
            EXPECTED_TEAM, common_name
        ),
    )
    reporter.expect(
        team == EXPECTED_TEAM,
        "Mac installer certificate team",
        team,
        "expected {}, observed {}".format(EXPECTED_TEAM, team or "missing"),
    )
    certificate_issues = []
    if not re.fullmatch(r"[0-9A-F]{64}", fingerprint):
        certificate_issues.append("SHA-256 fingerprint is missing or invalid")
    if not isinstance(expiration, dt.datetime):
        certificate_issues.append("expiration is missing")
    elif expiration <= utc_now_for(expiration):
        certificate_issues.append("certificate expired at {}".format(expiration.isoformat()))
    if signature.get("trusted_chain") is not True:
        certificate_issues.append("Apple installer certificate chain is incomplete")
    reporter.expect(
        not certificate_issues,
        "Mac installer certificate trust",
        "sha256={}; expires={}; Apple chain verified".format(
            fingerprint, expiration.isoformat() if isinstance(expiration, dt.datetime) else "missing"
        ),
        "; ".join(certificate_issues),
    )


def check_expanded_tree(root, reporter):
    issues = []
    count = 0
    total_size = 0
    resolved_root = root.resolve()
    for candidate in root.rglob("*"):
        count += 1
        try:
            metadata = candidate.lstat()
        except OSError as error:
            issues.append("unable to inspect {}: {}".format(candidate, error))
            continue
        try:
            resolved = candidate.resolve()
            resolved.relative_to(resolved_root)
        except (OSError, ValueError):
            issues.append("path escapes expansion root: {}".format(candidate))
        if stat.S_ISLNK(metadata.st_mode):
            issues.append("symbolic link is not allowed: {}".format(candidate.relative_to(root)))
        if metadata.st_mode & (stat.S_ISUID | stat.S_ISGID):
            issues.append("setuid/setgid mode is not allowed: {}".format(candidate.relative_to(root)))
        if metadata.st_mode & stat.S_IWOTH:
            issues.append("world-writable mode is not allowed: {}".format(candidate.relative_to(root)))
        if stat.S_ISREG(metadata.st_mode):
            total_size += metadata.st_size
    if count > MAX_PACKAGE_ENTRIES:
        issues.append("too many expanded entries ({})".format(count))
    if total_size > MAX_EXPANDED_BYTES:
        issues.append("expanded size exceeds {} bytes".format(MAX_EXPANDED_BYTES))
    reporter.expect(
        not issues,
        "Mac package expanded-tree safety",
        "{} entries; {} bytes; no links, escapes, setuid, or world-writable files".format(
            count, total_size
        ),
        "; ".join(issues[:12]),
    )


def normalized_version(value):
    text = str(value)
    parts = text.split(".")
    if not all(part.isdigit() for part in parts):
        return None
    numbers = [int(part) for part in parts]
    while len(numbers) > 1 and numbers[-1] == 0:
        numbers.pop()
    return tuple(numbers)


def xml_local_name(element):
    return element.tag.rsplit("}", 1)[-1]


def check_distribution(path, reporter):
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError) as error:
        reporter.fail("Mac package Distribution", "unable to parse {}: {}".format(path, error))
        return
    reporter.expect(
        xml_local_name(root) == "installer-gui-script",
        "Mac package Distribution root",
        "installer-gui-script",
        "unexpected root {}".format(xml_local_name(root)),
    )
    forbidden = [
        xml_local_name(element)
        for element in root.iter()
        if xml_local_name(element) in {"script", "installation-check", "conclusion"}
    ]
    reporter.expect(
        not forbidden,
        "Mac package Distribution scripts",
        "no executable installer script hooks",
        "forbidden elements: {}".format(", ".join(forbidden)),
    )
    products = [element for element in root.iter() if xml_local_name(element) == "product"]
    product_ok = (
        len(products) == 1
        and products[0].get("id") == EXPECTED_BUNDLE_ID
        and str(products[0].get("version", "")) == EXPECTED_VERSION
    )
    reporter.expect(
        product_ok,
        "Mac package product identity",
        "{} {}".format(EXPECTED_BUNDLE_ID, EXPECTED_VERSION),
        "expected one product {} {}, observed {}".format(
            EXPECTED_BUNDLE_ID,
            EXPECTED_VERSION,
            [(item.get("id"), item.get("version")) for item in products],
        ),
    )
    options = [element for element in root.iter() if xml_local_name(element) == "options"]
    options_ok = (
        len(options) == 1
        and options[0].get("customize") == "never"
        and options[0].get("require-scripts") == "false"
        and set((options[0].get("hostArchitectures") or "").split(",")) == EXPECTED_ARCHITECTURES
    )
    reporter.expect(
        options_ok,
        "Mac package installer options",
        "customize=never; require-scripts=false; arm64,x86_64",
        "unexpected installer options {}".format(options[0].attrib if options else "missing"),
    )
    os_versions = [
        element.get("min")
        for element in root.iter()
        if xml_local_name(element) == "os-version"
    ]
    reporter.expect(
        os_versions == [EXPECTED_MINIMUM_SYSTEM],
        "Mac package minimum system",
        EXPECTED_MINIMUM_SYSTEM,
        "expected [{}], observed {!r}".format(EXPECTED_MINIMUM_SYSTEM, os_versions),
    )
    locations = [
        element.get("customLocation")
        for element in root.iter()
        if xml_local_name(element) == "choice" and element.get("customLocation") is not None
    ]
    reporter.expect(
        locations == ["/Applications"],
        "Mac package install choice",
        "/Applications",
        "expected one /Applications choice, observed {!r}".format(locations),
    )
    refs = [element for element in root.iter() if xml_local_name(element) == "pkg-ref"]
    ref_ids = {element.get("id") for element in refs}
    external_refs = [
        (element.text or "").strip()
        for element in refs
        if (element.text or "").strip() and (element.text or "").strip() != "#" + EXPECTED_COMPONENT_NAME
    ]
    reporter.expect(
        ref_ids == {EXPECTED_BUNDLE_ID} and not external_refs,
        "Mac package component references",
        "only #{}".format(EXPECTED_COMPONENT_NAME),
        "unexpected ids={!r} external refs={!r}".format(ref_ids, external_refs),
    )


def check_package_info(path, reporter):
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError) as error:
        reporter.fail("Mac component PackageInfo", "unable to parse {}: {}".format(path, error))
        return
    attributes = root.attrib
    root_ok = (
        xml_local_name(root) == "pkg-info"
        and attributes.get("identifier") == EXPECTED_BUNDLE_ID
        and attributes.get("install-location") == "/Applications"
        and attributes.get("auth") == "root"
        and attributes.get("relocatable") == "false"
        and attributes.get("postinstall-action") == "none"
        and normalized_version(attributes.get("version", "")) == normalized_version(EXPECTED_VERSION)
    )
    reporter.expect(
        root_ok,
        "Mac component package identity",
        "{} {} installs only to /Applications without scripts".format(
            EXPECTED_BUNDLE_ID, attributes.get("version", "")
        ),
        "unexpected pkg-info attributes {!r}".format(attributes),
    )
    bundles = [element for element in root if xml_local_name(element) == "bundle"]
    bundle_ok = (
        len(bundles) == 1
        and bundles[0].get("path") == "./GTAFreeSTEM.app"
        and bundles[0].get("id") == EXPECTED_BUNDLE_ID
        and bundles[0].get("CFBundleShortVersionString") == EXPECTED_VERSION
        and bundles[0].get("CFBundleVersion") == EXPECTED_BUILD
    )
    reporter.expect(
        bundle_ok,
        "Mac component bundle metadata",
        "GTAFreeSTEM.app {} ({})".format(EXPECTED_VERSION, EXPECTED_BUILD),
        "unexpected bundle metadata {}".format(bundles[0].attrib if bundles else "missing"),
    )


def check_app_metadata(info, reporter):
    checks = [
        (info.get("CFBundlePackageType") == "APPL", "Mac package runnable type", "APPL", repr(info.get("CFBundlePackageType"))),
        (info.get("CFBundleIdentifier") == EXPECTED_BUNDLE_ID, "Mac package bundle identifier", EXPECTED_BUNDLE_ID, repr(info.get("CFBundleIdentifier"))),
        (str(info.get("CFBundleShortVersionString", "")) == EXPECTED_VERSION, "Mac package version", EXPECTED_VERSION, repr(info.get("CFBundleShortVersionString"))),
        (str(info.get("CFBundleVersion", "")) == EXPECTED_BUILD, "Mac package build", EXPECTED_BUILD, repr(info.get("CFBundleVersion"))),
        (info.get("DTPlatformName") == "macosx", "Mac package platform", "macosx", repr(info.get("DTPlatformName"))),
        (isinstance(info.get("CFBundleSupportedPlatforms"), list) and info.get("CFBundleSupportedPlatforms") == ["MacOSX"], "Mac package supported platform", "MacOSX", repr(info.get("CFBundleSupportedPlatforms"))),
        (str(info.get("LSMinimumSystemVersion", "")) == EXPECTED_MINIMUM_SYSTEM, "Mac package minimum OS", EXPECTED_MINIMUM_SYSTEM, repr(info.get("LSMinimumSystemVersion"))),
        (info.get("ITSAppUsesNonExemptEncryption") is False, "Mac package encryption declaration", "false", repr(info.get("ITSAppUsesNonExemptEncryption"))),
        (info.get("UIDeviceFamily") == [2], "Mac Catalyst device family", "[2]", repr(info.get("UIDeviceFamily"))),
    ]
    for condition, label, success, failure in checks:
        reporter.expect(condition, label, success, "unexpected value {}".format(failure))
    source_commit = info.get(SOURCE_COMMIT_KEY)
    reporter.expect(
        valid_source_commit(source_commit),
        "Mac package signed source commit provenance",
        "{}={}".format(SOURCE_COMMIT_KEY, source_commit),
        "{} must be a full lowercase 40-hex Git commit, observed {!r}".format(
            SOURCE_COMMIT_KEY,
            source_commit,
        ),
    )


def check_app_signature(app, inspector, reporter):
    try:
        signature = inspector.signature(app)
    except InspectionError as error:
        reporter.fail("Mac package app distribution signature", str(error))
        return None
    authority = signature.get("authority", "")
    team = signature.get("team", "")
    identifier = signature.get("identifier", "")
    common_name = signature.get("certificate_common_name", "")
    expiration = signature.get("certificate_expiration")
    fingerprint = signature.get("certificate_fingerprint", "")
    reporter.expect(
        authority.startswith("Apple Distribution:"),
        "Mac package app distribution signature",
        authority,
        "expected Apple Distribution, observed {}".format(authority or "missing"),
    )
    reporter.expect(
        team == EXPECTED_TEAM,
        "Mac package app signing team",
        team,
        "expected {}, observed {}".format(EXPECTED_TEAM, team or "missing"),
    )
    reporter.expect(
        identifier == EXPECTED_BUNDLE_ID,
        "Mac package app signed identifier",
        EXPECTED_BUNDLE_ID,
        "expected {}, observed {!r}".format(EXPECTED_BUNDLE_ID, identifier),
    )
    certificate_issues = []
    if common_name != authority:
        certificate_issues.append("leaf common name does not match codesign authority")
    if not re.fullmatch(r"[0-9A-F]{40}", fingerprint):
        certificate_issues.append("leaf SHA-1 fingerprint is missing or invalid")
    if not isinstance(expiration, dt.datetime):
        certificate_issues.append("leaf expiration is missing")
    elif expiration <= utc_now_for(expiration):
        certificate_issues.append("leaf certificate expired at {}".format(expiration.isoformat()))
    reporter.expect(
        not certificate_issues,
        "Mac package app signing certificate",
        "sha1={}; expires={}".format(
            fingerprint, expiration.isoformat() if isinstance(expiration, dt.datetime) else "missing"
        ),
        "; ".join(certificate_issues),
    )
    return signature


def check_app_entitlements(app, inspector, reporter):
    try:
        entitlements = inspector.entitlements(app)
    except InspectionError as error:
        reporter.fail("Mac package app entitlements", str(error))
        return
    expected = {
        "application-identifier": EXPECTED_APPLICATION_IDENTIFIER,
        "com.apple.application-identifier": EXPECTED_APPLICATION_IDENTIFIER,
        "com.apple.developer.team-identifier": EXPECTED_TEAM,
        "com.apple.security.app-sandbox": True,
        "com.apple.security.network.client": True,
        "com.apple.security.personal-information.location": True,
        "get-task-allow": False,
    }
    reporter.expect(
        entitlements == expected,
        "Mac package app release entitlements",
        "exact sandboxed release entitlement set",
        "expected {!r}, observed {!r}".format(expected, entitlements),
    )


def check_app_profile(app, signature, inspector, reporter):
    profile_path = app / "Contents" / "embedded.provisionprofile"
    if not profile_path.is_file():
        reporter.fail("Mac package App Store provisioning", "missing {}".format(profile_path))
        return
    try:
        profile = inspector.profile(profile_path)
    except InspectionError as error:
        reporter.fail("Mac package App Store provisioning", str(error))
        return
    entitlements = profile.get("Entitlements")
    issues = []
    if not isinstance(entitlements, dict):
        issues.append("profile Entitlements dictionary is missing")
        entitlements = {}
    for key in ("application-identifier", "com.apple.application-identifier"):
        if entitlements.get(key) != EXPECTED_APPLICATION_IDENTIFIER:
            issues.append("{} expected {}, observed {!r}".format(key, EXPECTED_APPLICATION_IDENTIFIER, entitlements.get(key)))
    if entitlements.get("com.apple.developer.team-identifier") != EXPECTED_TEAM:
        issues.append("entitlement team expected {}, observed {!r}".format(EXPECTED_TEAM, entitlements.get("com.apple.developer.team-identifier")))
    if entitlements.get("get-task-allow") is not False:
        issues.append("get-task-allow is not false")
    if profile.get("TeamIdentifier") != [EXPECTED_TEAM]:
        issues.append("TeamIdentifier expected [{}], observed {!r}".format(EXPECTED_TEAM, profile.get("TeamIdentifier")))
    if profile.get("ApplicationIdentifierPrefix") != [EXPECTED_TEAM]:
        issues.append("ApplicationIdentifierPrefix expected [{}], observed {!r}".format(EXPECTED_TEAM, profile.get("ApplicationIdentifierPrefix")))
    if profile.get("Platform") != ["OSX"]:
        issues.append("Platform expected [OSX], observed {!r}".format(profile.get("Platform")))
    if profile.get("ProvisionedDevices"):
        issues.append("ProvisionedDevices must be absent for App Store distribution")
    if profile.get("ProvisionsAllDevices") is True:
        issues.append("ProvisionsAllDevices is true (enterprise profile)")
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        issues.append("ExpirationDate is missing or invalid")
    elif expiration <= utc_now_for(expiration):
        issues.append("profile expired at {}".format(expiration.isoformat()))
    profile_fingerprints = {
        certificate.get("fingerprint")
        for certificate in profile.get("_DecodedDeveloperCertificates", [])
        if isinstance(certificate, dict) and certificate.get("fingerprint")
    }
    signature_fingerprint = signature.get("certificate_fingerprint", "") if signature else ""
    if not signature_fingerprint or signature_fingerprint not in profile_fingerprints:
        issues.append("profile does not authorize the leaf signing certificate")
    if issues:
        reporter.fail("Mac package App Store provisioning", "; ".join(issues))
    else:
        reporter.pass_(
            "Mac package App Store provisioning",
            "{}; UUID={}; expires={}; exact app/team/certificate".format(
                profile.get("Name", "unnamed profile"),
                profile.get("UUID", "missing"),
                expiration.isoformat(),
            ),
        )


def find_archive_app(archive, reporter):
    reporter.expect(
        archive.name.endswith(".xcarchive"),
        "Mac source archive suffix",
        archive.name,
        "expected .xcarchive, observed {}".format(archive.name),
    )
    applications = archive / "Products" / "Applications"
    candidates = sorted(path for path in applications.glob("*.app") if path.is_dir()) if applications.is_dir() else []
    reporter.expect(
        len(candidates) == 1,
        "Mac source archive application layout",
        str(candidates[0]) if len(candidates) == 1 else "",
        "expected one Products/Applications/*.app, found {}".format(len(candidates)),
    )
    return candidates[0] if len(candidates) == 1 else None


def relative_file_manifest(app, executable_relative):
    ignored_roots = {
        "Contents/_CodeSignature",
    }
    ignored_files = {
        "Contents/embedded.provisionprofile",
        executable_relative,
    }
    manifest = {}
    for candidate in sorted(app.rglob("*")):
        if not candidate.is_file():
            continue
        relative = candidate.relative_to(app).as_posix()
        if relative in ignored_files or any(relative == root or relative.startswith(root + "/") for root in ignored_roots):
            continue
        manifest[relative] = sha256(candidate)
    return manifest


def check_archive_provenance(package_app, archive, info, inspector, reporter, symbolication):
    if archive is None:
        reporter.fail("Mac archive-to-package provenance", "source .xcarchive path is required")
        return
    if not archive.is_dir():
        reporter.fail("Mac archive-to-package provenance", "archive does not exist: {}".format(archive))
        return
    archive_app = find_archive_app(archive, reporter)
    if archive_app is None:
        return
    archive_info_path = archive_app / "Contents" / "Info.plist"
    try:
        archive_info = read_plist(archive_info_path)
    except Exception as error:
        reporter.fail(
            "Mac archive-to-package source commit provenance",
            "unable to read {}: {}".format(archive_info_path, error),
        )
        archive_info = {}
    package_source_commit = info.get(SOURCE_COMMIT_KEY) if isinstance(info, dict) else None
    archive_source_commit = archive_info.get(SOURCE_COMMIT_KEY)
    reporter.expect(
        valid_source_commit(package_source_commit)
        and valid_source_commit(archive_source_commit)
        and package_source_commit == archive_source_commit,
        "Mac archive-to-package source commit provenance",
        "{}={} matches source archive".format(SOURCE_COMMIT_KEY, package_source_commit),
        "package {}={!r}; archive {}={!r}; both must be the same full lowercase 40-hex Git commit".format(
            SOURCE_COMMIT_KEY,
            package_source_commit,
            SOURCE_COMMIT_KEY,
            archive_source_commit,
        ),
    )
    executable_name = info.get("CFBundleExecutable") if isinstance(info, dict) else None
    if not isinstance(executable_name, str) or not executable_name:
        reporter.fail("Mac archive-to-package provenance", "CFBundleExecutable is missing")
        return
    executable_relative = "Contents/MacOS/{}".format(executable_name)
    package_executable = package_app / executable_relative
    archive_executable = archive_app / executable_relative
    try:
        package_uuids = inspector.uuids(package_executable)
        archive_uuids = inspector.uuids(archive_executable)
    except InspectionError as error:
        reporter.fail("Mac archive-to-package executable UUID provenance", str(error))
        return
    reporter.expect(
        package_uuids == archive_uuids,
        "Mac archive-to-package executable UUID provenance",
        ", ".join("{} ({})".format(uuid, arch) for uuid, arch in sorted(package_uuids)),
        "package UUIDs={} archive UUIDs={}".format(sorted(package_uuids), sorted(archive_uuids)),
    )
    observed_architectures = {arch for _, arch in package_uuids}
    reporter.expect(
        observed_architectures == EXPECTED_ARCHITECTURES,
        "Mac package executable architectures",
        "arm64,x86_64",
        "expected {}, observed {}".format(sorted(EXPECTED_ARCHITECTURES), sorted(observed_architectures)),
    )
    package_manifest = relative_file_manifest(package_app, executable_relative)
    archive_manifest = relative_file_manifest(archive_app, executable_relative)
    reporter.expect(
        package_manifest == archive_manifest,
        "Mac archive-to-package non-signing content provenance",
        "{} files byte-match source archive".format(len(package_manifest)),
        "package-only={} archive-only={} changed={}".format(
            sorted(set(package_manifest) - set(archive_manifest))[:8],
            sorted(set(archive_manifest) - set(package_manifest))[:8],
            sorted(
                key
                for key in set(package_manifest) & set(archive_manifest)
                if package_manifest[key] != archive_manifest[key]
            )[:8],
        ),
    )
    expected_symbol_names = {"{}.symbols".format(uuid) for uuid, _ in package_uuids}
    symbol_names = {
        candidate.name
        for candidate in symbolication.iterdir()
        if candidate.is_file()
    } if symbolication.is_dir() else set()
    reporter.expect(
        symbol_names == expected_symbol_names,
        "Mac package symbolication provenance",
        ", ".join(sorted(symbol_names)),
        "expected {}, observed {}".format(sorted(expected_symbol_names), sorted(symbol_names)),
    )


def verify_expanded(expanded, archive, inspector, reporter):
    check_expanded_tree(expanded, reporter)
    top_level = {candidate.name for candidate in expanded.iterdir()} if expanded.is_dir() else set()
    expected_top_level = {"Distribution", EXPECTED_COMPONENT_NAME, "Symbolication"}
    reporter.expect(
        top_level == expected_top_level,
        "Mac package top-level layout",
        ", ".join(sorted(top_level)),
        "expected {}, observed {}".format(sorted(expected_top_level), sorted(top_level)),
    )
    check_distribution(expanded / "Distribution", reporter)
    component = expanded / EXPECTED_COMPONENT_NAME
    component_entries = {candidate.name for candidate in component.iterdir()} if component.is_dir() else set()
    reporter.expect(
        component_entries == {"Bom", "PackageInfo", "Payload"},
        "Mac component package layout",
        "Bom, PackageInfo, Payload; no installer scripts",
        "expected Bom, PackageInfo, Payload only; observed {}".format(sorted(component_entries)),
    )
    check_package_info(component / "PackageInfo", reporter)
    payload = component / "Payload"
    payload_entries = sorted(payload.iterdir()) if payload.is_dir() else []
    reporter.expect(
        len(payload_entries) == 1 and payload_entries[0].name == "GTAFreeSTEM.app" and payload_entries[0].is_dir(),
        "Mac package payload layout",
        "one GTAFreeSTEM.app at /Applications",
        "expected one GTAFreeSTEM.app, observed {}".format([item.name for item in payload_entries]),
    )
    if len(payload_entries) != 1 or not payload_entries[0].is_dir():
        return
    app = payload_entries[0]
    contents = app / "Contents"
    info = load_plist(contents / "Info.plist", "Mac package app Info.plist", reporter)
    if info:
        check_app_metadata(info, reporter)
    reporter.expect(
        not (app / "Watch").exists() and not (contents / "Watch").exists(),
        "Mac package excludes Watch bundle",
        "no embedded Watch app",
        "Mac Catalyst package must not embed an iOS Watch companion",
    )
    resources = contents / "Resources"
    check_hash("Mac package privacy manifest SHA", resources / "PrivacyInfo.xcprivacy", SOURCE_PRIVACY, reporter)
    check_hash("Mac package opportunities SHA", resources / "opportunities.json", SOURCE_OPPORTUNITIES, reporter)
    check_hash("Mac package localization catalog SHA", resources / "app_strings.json", SOURCE_STRINGS, reporter)
    signature = check_app_signature(app, inspector, reporter)
    check_app_entitlements(app, inspector, reporter)
    check_app_profile(app, signature, inspector, reporter)
    if info:
        check_archive_provenance(
            app,
            archive,
            info,
            inspector,
            reporter,
            expanded / "Symbolication",
        )


def verify_package(package, archive, inspector, emit=True):
    reporter = Reporter(emit=emit)
    package = package.resolve()
    reporter.expect(
        package.suffix.lower() == ".pkg",
        "Mac package suffix",
        package.name,
        "expected .pkg, observed {}".format(package.name),
    )
    reporter.expect(
        package.is_file(),
        "Mac package file",
        str(package),
        "path does not exist as a file: {}".format(package),
    )
    if not package.is_file():
        return reporter
    reporter.pass_("Mac package SHA-256", sha256(package))
    check_installer_signature(package, inspector, reporter)
    with tempfile.TemporaryDirectory(prefix="gtafreestem-mac-pkg-verifier-") as temporary:
        expanded = Path(temporary) / "expanded"
        try:
            inspector.expand(package, expanded)
        except InspectionError as error:
            reporter.fail("Mac package safe expansion", str(error))
            return reporter
        reporter.pass_("Mac package safe expansion", str(expanded))
        verify_expanded(expanded, archive, inspector, reporter)
    return reporter


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        plistlib.dump(value, stream, fmt=plistlib.FMT_XML, sort_keys=True)


def write_distribution(path):
    path.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <pkg-ref id="{bundle}"><bundle-version><bundle CFBundleShortVersionString="{version}" CFBundleVersion="{build}" id="{bundle}" path="GTAFreeSTEM.app"/></bundle-version></pkg-ref>
  <product id="{bundle}" version="{version}"/>
  <title>GTA FREE STEM</title>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <volume-check><allowed-os-versions><os-version min="{minimum}"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="default"><line choice="{bundle}"/></line></choices-outline>
  <choice id="default" title="GTA FREE STEM" versStr="{version}"/>
  <choice id="{bundle}" title="GTA FREE STEM" visible="false" customLocation="/Applications"><pkg-ref id="{bundle}"/></choice>
  <pkg-ref id="{bundle}" version="{version}.0" onConclusion="none" installKBytes="1" updateKBytes="0">#{component}</pkg-ref>
</installer-gui-script>
""".format(
            bundle=EXPECTED_BUNDLE_ID,
            component=EXPECTED_COMPONENT_NAME,
            version=EXPECTED_VERSION,
            build=EXPECTED_BUILD,
            minimum=EXPECTED_MINIMUM_SYSTEM,
        ),
        encoding="utf-8",
    )


def write_package_info(path):
    path.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<pkg-info overwrite-permissions="true" relocatable="false" identifier="{bundle}" postinstall-action="none" version="{version}.0" format-version="2" install-location="/Applications" auth="root">
  <payload numberOfFiles="1" installKBytes="1"/>
  <bundle path="./GTAFreeSTEM.app" id="{bundle}" CFBundleShortVersionString="{version}" CFBundleVersion="{build}"/>
  <bundle-version><bundle id="{bundle}"/></bundle-version>
  <upgrade-bundle><bundle id="{bundle}"/></upgrade-bundle>
  <strict-identifier><bundle id="{bundle}"/></strict-identifier>
</pkg-info>
""".format(bundle=EXPECTED_BUNDLE_ID, version=EXPECTED_VERSION, build=EXPECTED_BUILD),
        encoding="utf-8",
    )


def build_fixture(base):
    package = base / "Fixture.pkg"
    package.write_bytes(b"fixture-package")
    expanded = base / "expanded-fixture"
    component = expanded / EXPECTED_COMPONENT_NAME
    payload = component / "Payload"
    app = payload / "GTAFreeSTEM.app"
    contents = app / "Contents"
    resources = contents / "Resources"
    resources.mkdir(parents=True)
    write_distribution(expanded / "Distribution")
    (component / "Bom").write_bytes(b"fixture-bom")
    write_package_info(component / "PackageInfo")
    write_plist(
        contents / "Info.plist",
        {
            "CFBundleExecutable": "GTAFreeSTEM",
            "CFBundleIdentifier": EXPECTED_BUNDLE_ID,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": EXPECTED_VERSION,
            "CFBundleSupportedPlatforms": ["MacOSX"],
            "CFBundleVersion": EXPECTED_BUILD,
            "DTPlatformName": "macosx",
            SOURCE_COMMIT_KEY: FIXTURE_SOURCE_COMMIT,
            "ITSAppUsesNonExemptEncryption": False,
            "LSMinimumSystemVersion": EXPECTED_MINIMUM_SYSTEM,
            "UIDeviceFamily": [2],
        },
    )
    shutil.copyfile(SOURCE_PRIVACY, resources / "PrivacyInfo.xcprivacy")
    shutil.copyfile(SOURCE_OPPORTUNITIES, resources / "opportunities.json")
    shutil.copyfile(SOURCE_STRINGS, resources / "app_strings.json")
    (contents / "MacOS").mkdir(parents=True)
    (contents / "MacOS" / "GTAFreeSTEM").write_bytes(b"fixture-mac-mach-o")
    (contents / "embedded.provisionprofile").write_bytes(b"fixture-profile")
    symbols = expanded / "Symbolication"
    symbols.mkdir()
    (symbols / "11111111-1111-1111-1111-111111111111.symbols").write_bytes(b"fixture-symbols")
    (symbols / "22222222-2222-2222-2222-222222222222.symbols").write_bytes(b"fixture-symbols")
    archive = base / "Fixture.xcarchive"
    archive_app = archive / "Products" / "Applications" / "GTAFreeSTEM.app"
    shutil.copytree(app, archive_app)
    return package, expanded, archive


def require_failure(report, prefix, fragment=""):
    return any(
        line.startswith(prefix) and (not fragment or fragment in line)
        for line in report.failures
    )


def run_self_test():
    required_sources = [SOURCE_OPPORTUNITIES, SOURCE_PRIVACY, SOURCE_STRINGS]
    if not all(path.is_file() for path in required_sources):
        raise SystemExit("Mac package verifier self-test requires current source resources")
    sample_signature = """Package \"Fixture.pkg\":
   Status: signed by a developer certificate issued by Apple (Development)
   Certificate Chain:
    1. 3rd Party Mac Developer Installer: Fixture ({team})
       Expires: 2099-01-01 00:00:00 +0000
       SHA256 Fingerprint:
           AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA
           AA AA AA AA AA AA AA AA AA AA
       ------------------------------------------------------------------------
    2. Apple Worldwide Developer Relations Certification Authority
       Expires: 2099-01-01 00:00:00 +0000
       ------------------------------------------------------------------------
    3. Apple Root CA
       Expires: 2099-01-01 00:00:00 +0000
""".format(team=EXPECTED_TEAM)
    parsed = parse_installer_signature(sample_signature)
    if parsed["team"] != EXPECTED_TEAM or len(parsed["fingerprint"]) != 64 or not parsed["trusted_chain"]:
        print("Mac package verifier self-test failed: valid pkgutil signature output was not parsed.", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="gtafreestem-mac-pkg-self-test-") as temporary:
        base = Path(temporary)
        package, expanded, archive = build_fixture(base)
        passing = verify_package(package, archive, FixtureInspector(expanded), emit=False)
        if passing.failures:
            print("Mac package verifier self-test failed: valid fixture was rejected.", file=sys.stderr)
            for failure in passing.failures:
                print(failure, file=sys.stderr)
            return 1

        package_info_path = (
            expanded
            / EXPECTED_COMPONENT_NAME
            / "Payload"
            / "GTAFreeSTEM.app"
            / "Contents"
            / "Info.plist"
        )
        package_info = read_plist(package_info_path)
        del package_info[SOURCE_COMMIT_KEY]
        write_plist(package_info_path, package_info)
        missing_source_commit = verify_package(
            package,
            archive,
            FixtureInspector(expanded),
            emit=False,
        )
        if not require_failure(
            missing_source_commit,
            "FAIL Mac package signed source commit provenance",
            "observed None",
        ):
            print("Mac package verifier self-test failed: missing source commit was not rejected.", file=sys.stderr)
            return 1

        package_info[SOURCE_COMMIT_KEY] = FIXTURE_SOURCE_COMMIT.upper()
        write_plist(package_info_path, package_info)
        malformed_source_commit = verify_package(
            package,
            archive,
            FixtureInspector(expanded),
            emit=False,
        )
        if not require_failure(
            malformed_source_commit,
            "FAIL Mac package signed source commit provenance",
            "lowercase 40-hex",
        ):
            print("Mac package verifier self-test failed: malformed source commit was not rejected.", file=sys.stderr)
            return 1

        package_info[SOURCE_COMMIT_KEY] = FIXTURE_SOURCE_COMMIT
        write_plist(package_info_path, package_info)

        archive_info_path = archive / "Products" / "Applications" / "GTAFreeSTEM.app" / "Contents" / "Info.plist"
        archive_info = read_plist(archive_info_path)
        archive_info[SOURCE_COMMIT_KEY] = "89abcdef0123456789abcdef0123456789abcdef"
        write_plist(archive_info_path, archive_info)
        mismatched_source_commit = verify_package(
            package,
            archive,
            FixtureInspector(expanded),
            emit=False,
        )
        if not require_failure(
            mismatched_source_commit,
            "FAIL Mac archive-to-package source commit provenance",
            "both must be the same",
        ):
            print("Mac package verifier self-test failed: archive/package source commit mismatch was not rejected.", file=sys.stderr)
            return 1
        archive_info[SOURCE_COMMIT_KEY] = FIXTURE_SOURCE_COMMIT
        write_plist(archive_info_path, archive_info)

        bad_entitlements = {
            "application-identifier": EXPECTED_APPLICATION_IDENTIFIER,
            "com.apple.application-identifier": EXPECTED_APPLICATION_IDENTIFIER,
            "com.apple.developer.team-identifier": EXPECTED_TEAM,
            "com.apple.security.app-sandbox": True,
            "com.apple.security.network.client": True,
            "com.apple.security.personal-information.location": True,
            "com.apple.security.network.server": True,
            "get-task-allow": False,
        }
        cases = [
            (
                "wrong installer identity",
                FixtureInspector(expanded, installer_common_name="Developer ID Installer: Fixture ({})".format(EXPECTED_TEAM)),
                "FAIL Mac installer certificate identity",
                "3rd Party",
            ),
            (
                "wrong installer team",
                FixtureInspector(expanded, installer_team="WRONGTEAM1"),
                "FAIL Mac installer certificate team",
                "expected",
            ),
            (
                "expired installer certificate",
                FixtureInspector(expanded, installer_expiration=dt.datetime(2000, 1, 1, tzinfo=dt.timezone.utc)),
                "FAIL Mac installer certificate trust",
                "expired",
            ),
            (
                "untrusted installer chain",
                FixtureInspector(expanded, installer_trusted_chain=False),
                "FAIL Mac installer certificate trust",
                "chain",
            ),
            (
                "development app signature",
                FixtureInspector(expanded, app_authority="Apple Development: Fixture ({})".format(EXPECTED_TEAM)),
                "FAIL Mac package app distribution signature",
                "Apple Distribution",
            ),
            (
                "wrong app team",
                FixtureInspector(expanded, app_team="WRONGTEAM1"),
                "FAIL Mac package app signing team",
                EXPECTED_TEAM,
            ),
            (
                "wrong signed app identifier",
                FixtureInspector(expanded, app_identifier="com.example.wrong"),
                "FAIL Mac package app signed identifier",
                "com.example.wrong",
            ),
            (
                "expired app certificate",
                FixtureInspector(expanded, app_certificate_expiration=dt.datetime(2000, 1, 1)),
                "FAIL Mac package app signing certificate",
                "expired",
            ),
            (
                "unexpected entitlement",
                FixtureInspector(expanded, entitlements=bad_entitlements),
                "FAIL Mac package app release entitlements",
                "network.server",
            ),
            (
                "wildcard profile",
                FixtureInspector(expanded, profile_identifier="{}.*".format(EXPECTED_TEAM)),
                "FAIL Mac package App Store provisioning",
                "application-identifier expected",
            ),
            (
                "wrong profile team",
                FixtureInspector(expanded, profile_team=["WRONGTEAM1"]),
                "FAIL Mac package App Store provisioning",
                "TeamIdentifier expected",
            ),
            (
                "expired profile",
                FixtureInspector(expanded, profile_expiration=dt.datetime(2000, 1, 1)),
                "FAIL Mac package App Store provisioning",
                "profile expired",
            ),
            (
                "device profile",
                FixtureInspector(expanded, profile_has_devices=True),
                "FAIL Mac package App Store provisioning",
                "ProvisionedDevices",
            ),
            (
                "enterprise profile",
                FixtureInspector(expanded, profile_enterprise=True),
                "FAIL Mac package App Store provisioning",
                "enterprise",
            ),
            (
                "wrong profile platform",
                FixtureInspector(expanded, profile_platform=["iOS"]),
                "FAIL Mac package App Store provisioning",
                "Platform expected",
            ),
            (
                "profile certificate mismatch",
                FixtureInspector(expanded, profile_certificate_fingerprint="C" * 40),
                "FAIL Mac package App Store provisioning",
                "does not authorize",
            ),
            (
                "archive UUID mismatch",
                FixtureInspector(expanded, archive_uuid_mismatch=True),
                "FAIL Mac archive-to-package executable UUID provenance",
                "archive UUIDs",
            ),
        ]
        for name, inspector, prefix, fragment in cases:
            report = verify_package(package, archive, inspector, emit=False)
            if not require_failure(report, prefix, fragment):
                print(
                    "Mac package verifier self-test failed: {} was not rejected with {} containing {!r}.".format(
                        name, prefix, fragment
                    ),
                    file=sys.stderr,
                )
                for failure in report.failures:
                    print(failure, file=sys.stderr)
                return 1

        feed_path = expanded / EXPECTED_COMPONENT_NAME / "Payload" / "GTAFreeSTEM.app" / "Contents" / "Resources" / "opportunities.json"
        original_feed = feed_path.read_bytes()
        feed_path.write_bytes(original_feed + b"\n")
        stale_feed = verify_package(package, archive, FixtureInspector(expanded), emit=False)
        if not require_failure(stale_feed, "FAIL Mac package opportunities SHA"):
            print("Mac package verifier self-test failed: stale feed was not rejected.", file=sys.stderr)
            return 1
        feed_path.write_bytes(original_feed)

        scripts = expanded / EXPECTED_COMPONENT_NAME / "Scripts"
        scripts.mkdir()
        (scripts / "postinstall").write_text("#!/bin/sh\n", encoding="utf-8")
        scripted = verify_package(package, archive, FixtureInspector(expanded), emit=False)
        if not require_failure(scripted, "FAIL Mac component package layout", "Scripts"):
            print("Mac package verifier self-test failed: installer scripts were not rejected.", file=sys.stderr)
            return 1
        shutil.rmtree(scripts)

        extra_payload = expanded / EXPECTED_COMPONENT_NAME / "Payload" / "unexpected.txt"
        extra_payload.write_text("unexpected", encoding="utf-8")
        extra = verify_package(package, archive, FixtureInspector(expanded), emit=False)
        if not require_failure(extra, "FAIL Mac package payload layout", "unexpected.txt"):
            print("Mac package verifier self-test failed: extra payload was not rejected.", file=sys.stderr)
            return 1
        extra_payload.unlink()

        distribution = expanded / "Distribution"
        original_distribution = distribution.read_text(encoding="utf-8")
        distribution.write_text(
            original_distribution.replace(
                '<product id="{}"'.format(EXPECTED_BUNDLE_ID),
                '<product id="com.example.wrong"',
                1,
            ),
            encoding="utf-8",
        )
        wrong_product = verify_package(package, archive, FixtureInspector(expanded), emit=False)
        if not require_failure(wrong_product, "FAIL Mac package product identity"):
            print("Mac package verifier self-test failed: wrong product identifier was not rejected.", file=sys.stderr)
            return 1
        distribution.write_text(original_distribution, encoding="utf-8")

        symlink = expanded / EXPECTED_COMPONENT_NAME / "Payload" / "GTAFreeSTEM.app" / "Contents" / "Resources" / "unsafe-link"
        symlink.symlink_to("/tmp")
        unsafe = verify_package(package, archive, FixtureInspector(expanded), emit=False)
        if not require_failure(unsafe, "FAIL Mac package expanded-tree safety", "symbolic link"):
            print("Mac package verifier self-test failed: symbolic-link payload was not rejected.", file=sys.stderr)
            return 1
        symlink.unlink()

    print(
        "Mac package verifier self-test passed "
        "(installer/app signatures, exact entitlements/profile, layout/script/link safety, "
        "current resources, and archive source-commit/UUID/content provenance)."
    )
    return 0


if MODE == "self-test":
    raise SystemExit(run_self_test())

package_path = Path(os.path.expanduser(PKG_ARGUMENT))
if not package_path.is_absolute():
    package_path = (Path.cwd() / package_path).resolve()
archive_path = None
if ARCHIVE_ARGUMENT:
    archive_path = Path(os.path.expanduser(ARCHIVE_ARGUMENT))
    if not archive_path.is_absolute():
        archive_path = (Path.cwd() / archive_path).resolve()

report = verify_package(package_path, archive_path, LiveInspector(), emit=True)
if report.failures:
    print("RESULT FAIL — {} Mac package check(s) failed; {} passed.".format(len(report.failures), len(report.passes)))
    raise SystemExit(1)
print(
    "RESULT PASS — {} strict exported Mac App Store package checks passed for {} {} ({}).".format(
        len(report.passes), EXPECTED_BUNDLE_ID, EXPECTED_VERSION, EXPECTED_BUILD
    )
)
if archive_path is None:
    print(
        "NOTE — Package signing is valid, but archive-to-package provenance was not checked; "
        "supply the source .xcarchive as the second argument for release signoff."
    )
PY
