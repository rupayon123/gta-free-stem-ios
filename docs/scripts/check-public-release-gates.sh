#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

RUN_RELEASE_AUDIT="${RUN_RELEASE_AUDIT:-1}"
CHECK_APP_STORE_SCREENSHOTS="${CHECK_APP_STORE_SCREENSHOTS:-1}"
SIGNOFF_PATH="${SIGNOFF_PATH:-docs/TESTFLIGHT_REAL_DEVICE_SIGNOFF.md}"
EXPECTED_BUILD="1.0 (12)"
IOS_ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-}"
IOS_IPA_PATH="${IOS_IPA_PATH:-}"
MAC_ARCHIVE_PATH="${MAC_ARCHIVE_PATH:-}"
MAC_PKG_PATH="${MAC_PKG_PATH:-}"
# The metadata fixture suite sets this together with RUN_RELEASE_AUDIT=0. It is
# never a valid public-release signoff mode.
PUBLIC_GATE_TEST_FIXTURE_ONLY="${PUBLIC_GATE_TEST_FIXTURE_ONLY:-0}"
# This deliberately has no default. The release owner must state which product
# platforms are actually being enabled for public distribution.
PUBLIC_RELEASE_PLATFORMS="${PUBLIC_RELEASE_PLATFORMS:-}"
SCREENSHOT_ROOT="build/app-store-screenshots/final"
VISUAL_QA_MANIFEST_PATH="$SCREENSHOT_ROOT/FINAL_VISUAL_QA.md"
CAPTURE_RECEIPT_PATH="$SCREENSHOT_ROOT/CAPTURE_RECEIPT.json"

if [ "$PUBLIC_GATE_TEST_FIXTURE_ONLY" = "1" ]; then
  if [ "$RUN_RELEASE_AUDIT" != "0" ]; then
    echo "PUBLIC_GATE_TEST_FIXTURE_ONLY=1 requires RUN_RELEASE_AUDIT=0 and cannot be used for release signoff."
    exit 1
  fi
  SCREENSHOT_ROOT="${PUBLIC_GATE_TEST_SCREENSHOT_ROOT:-$SCREENSHOT_ROOT}"
  VISUAL_QA_MANIFEST_PATH="${PUBLIC_GATE_TEST_VISUAL_QA_MANIFEST:-$SCREENSHOT_ROOT/FINAL_VISUAL_QA.md}"
  CAPTURE_RECEIPT_PATH="${PUBLIC_GATE_TEST_CAPTURE_RECEIPT:-$SCREENSHOT_ROOT/CAPTURE_RECEIPT.json}"
else
  if [ "$RUN_RELEASE_AUDIT" != "1" ]; then
    echo "RUN_RELEASE_AUDIT must be 1 for public release signoff; only explicit metadata-fixture mode may disable it."
    exit 1
  fi
  if [ "$CHECK_APP_STORE_SCREENSHOTS" != "1" ]; then
    echo "CHECK_APP_STORE_SCREENSHOTS must be 1 for public release signoff; only explicit metadata-fixture mode may skip screenshot-file checks."
    exit 1
  fi
fi

NORMALIZED_PUBLIC_PLATFORMS="$(printf '%s' "$PUBLIC_RELEASE_PLATFORMS" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
MAC_SELECTED=0
case ",$NORMALIZED_PUBLIC_PLATFORMS," in
  *,mac,*|*,maccatalyst,*) MAC_SELECTED=1 ;;
esac

if [ -z "$IOS_ARCHIVE_PATH" ]; then
  echo "IOS_ARCHIVE_PATH is required for public App Store signoff and must point to the signed pre-export .xcarchive."
  exit 1
fi
if [ -z "$IOS_IPA_PATH" ]; then
  echo "IOS_IPA_PATH is required for public App Store signoff and must point to the distribution-signed IPA exported from IOS_ARCHIVE_PATH."
  exit 1
fi
if [ "$MAC_SELECTED" = "1" ] && [ -z "$MAC_ARCHIVE_PATH" ]; then
  echo "MAC_ARCHIVE_PATH is required when mac is selected and must point to the signed Mac Catalyst .xcarchive."
  exit 1
fi
if [ "$MAC_SELECTED" = "1" ] && [ -z "$MAC_PKG_PATH" ]; then
  echo "MAC_PKG_PATH is required when mac is selected and must point to the exported Mac App Store .pkg."
  exit 1
fi

if [ "$PUBLIC_GATE_TEST_FIXTURE_ONLY" = "1" ]; then
  echo "Skipping binary signing verification in explicit metadata-fixture mode; evidence binding remains active."
else
  echo
  echo "=== Strict iOS/iPadOS/watchOS pre-export archive verification ==="
  bash docs/scripts/verify-app-store-archive.sh "$IOS_ARCHIVE_PATH"
  echo
  echo "=== Strict exported iOS/iPadOS/watchOS App Store IPA verification ==="
  bash docs/scripts/verify-app-store-ipa.sh "$IOS_IPA_PATH" "$IOS_ARCHIVE_PATH"
  if [ "$MAC_SELECTED" = "1" ]; then
    echo
    echo "=== Strict Mac Catalyst App Store archive verification ==="
    bash docs/scripts/verify-mac-app-store-archive.sh "$MAC_ARCHIVE_PATH"
    echo
    echo "=== Strict exported Mac Catalyst App Store package verification ==="
    bash docs/scripts/verify-mac-app-store-pkg.sh "$MAC_PKG_PATH" "$MAC_ARCHIVE_PATH"
  fi
fi

if [ "$RUN_RELEASE_AUDIT" != "0" ]; then
  STRICT_TRANSLATION_CHECK=1 CHECK_APP_STORE_SCREENSHOTS=1 bash docs/scripts/check-release-readiness.sh
fi

SCREENSHOT_PACKAGE_TEST_FIXTURE_ONLY="$PUBLIC_GATE_TEST_FIXTURE_ONLY" \
  SCREENSHOT_PACKAGE_TEST_SOURCE_COMMIT="${PUBLIC_GATE_TEST_SCREENSHOT_SOURCE_COMMIT:-}" \
  SCREENSHOT_PACKAGE_TEST_SOURCE_TREE_SHA256="${PUBLIC_GATE_TEST_SCREENSHOT_SOURCE_TREE_SHA256:-}" \
  SCREENSHOT_ROOT="$SCREENSHOT_ROOT" \
  VISUAL_QA_MANIFEST_PATH="$VISUAL_QA_MANIFEST_PATH" \
  CAPTURE_RECEIPT_PATH="$CAPTURE_RECEIPT_PATH" \
  MAC_CAPTURE_SESSION_PATH="$SCREENSHOT_ROOT/MAC_CAPTURE_SESSION.json" \
  bash docs/scripts/verify-screenshot-package.sh

/usr/bin/python3 - \
  "$SIGNOFF_PATH" \
  "$EXPECTED_BUILD" \
  "$PUBLIC_RELEASE_PLATFORMS" \
  "$IOS_ARCHIVE_PATH" \
  "$IOS_IPA_PATH" \
  "$MAC_ARCHIVE_PATH" \
  "$MAC_PKG_PATH" \
  "$PUBLIC_GATE_TEST_FIXTURE_ONLY" \
  "$SCREENSHOT_ROOT" \
  "$VISUAL_QA_MANIFEST_PATH" <<'PY'
import datetime as dt
import hashlib
import os
import plistlib
import re
import stat
import subprocess
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected_build = sys.argv[2]
configured_platforms_raw = sys.argv[3]
ios_archive_argument = sys.argv[4]
ios_ipa_argument = sys.argv[5]
mac_archive_argument = sys.argv[6]
mac_pkg_argument = sys.argv[7]
fixture_only = sys.argv[8] == "1"
screenshot_root_argument = sys.argv[9]
visual_qa_manifest_argument = sys.argv[10]
if not path.exists():
    raise SystemExit(f"Missing {path}")
text = path.read_text(encoding="utf-8")
not_ready = []

def clean(value):
    return value.strip().replace(r"\`", "`").strip(chr(96)).strip()

FIELD_SECTIONS = {
    "Version/build": "Build Under Test",
    "iOS Delivery UUID": "Build Under Test",
    "Mac Delivery UUID": "Build Under Test",
    "iOS App Store Connect status": "Build Under Test",
    "iOS BuildBetaDetail.internalBuildState": "Build Under Test",
    "Mac App Store Connect status": "Build Under Test",
    "Mac BuildBetaDetail.internalBuildState": "Build Under Test",
    "Public distribution platforms": "Build Under Test",
    "Artifact binding status": "Verified Artifact Binding",
    "Published commit": "Verified Artifact Binding",
    "Artifact verification date": "Verified Artifact Binding",
    "iOS archive path": "Verified Artifact Binding",
    "iOS archive SHA-256": "Verified Artifact Binding",
    "iOS IPA path": "Verified Artifact Binding",
    "iOS IPA SHA-256": "Verified Artifact Binding",
    "Mac archive path": "Verified Artifact Binding",
    "Mac archive SHA-256": "Verified Artifact Binding",
    "Mac package path": "Verified Artifact Binding",
    "Mac package SHA-256": "Verified Artifact Binding",
    "Tester": "Tester And Device",
    "Date": "Tester And Device",
    "Install source": "Tester And Device",
    "Network conditions tested": "Tester And Device",
    "Accessibility settings tested": "Tester And Device",
    "Languages tested": "Tester And Device",
    "Overall status": "Release Owner Decision",
    "Accepted risks": "Release Owner Decision",
    "Must-fix blockers": "Release Owner Decision",
    "iOS App Store Connect build selected": "Release Owner Decision",
    "Mac App Store Connect build selected": "Release Owner Decision",
    "Archive provenance verified": "Release Owner Decision",
    "Screenshot visual QA": "Release Owner Decision",
    "Visual QA manifest SHA-256": "Release Owner Decision",
    "Screenshots uploaded": "Release Owner Decision",
    "Metadata/privacy/age rating entered": "Release Owner Decision",
    "Support contact verified": "Release Owner Decision",
    "Production legal/support truthfulness verified": "Release Owner Decision",
    "App Review contact verified": "Release Owner Decision",
    "Copyright entered": "Release Owner Decision",
    "Platform record decision": "Release Owner Decision",
    "Primary language verified": "Release Owner Decision",
    "Availability and DSA verified": "Release Owner Decision",
    "Submitted for App Review": "Release Owner Decision",
}

section_cache = {}
field_cache = {}


def section_contents(heading):
    if heading in section_cache:
        return section_cache[heading]
    matches = list(re.finditer(
        rf"^## {re.escape(heading)}\s*$\n?(.*?)(?=^## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    ))
    if len(matches) != 1:
        not_ready.append(f"{heading}: expected exactly one section, found {len(matches)}")
        value = matches[0].group(1) if matches else ""
    else:
        value = matches[0].group(1)
    section_cache[heading] = value
    return value


def field_value(label):
    if label in field_cache:
        return field_cache[label]
    heading = FIELD_SECTIONS.get(label)
    if heading is None:
        not_ready.append(f"Gate configuration: no owning section declared for field {label}")
        field_cache[label] = ""
        return ""
    section = section_contents(heading)
    matches = re.findall(
        rf"^- {re.escape(label)}:[ \t]*(.*)$",
        section,
        re.MULTILINE,
    )
    if len(matches) != 1:
        not_ready.append(
            f"{heading}: expected exactly one '{label}' field, found {len(matches)}"
        )
        value = ""
    else:
        value = clean(matches[0])
    field_cache[label] = value
    return value

def is_pending(value):
    normalized = clean(value).lower()
    return normalized in {
        "", "pending", "pending upload", "not uploaded", "not submitted",
        "no", "not yet", "todo", "tbd", "n/a", "na",
    } or normalized.startswith(("include ", "record ", "enter ", "confirm "))


def run(command):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_sha256(path):
    """Hash a directory's names, types, modes, links, and file bytes deterministically."""
    digest = hashlib.sha256()
    digest.update(b"GTA-FREE-STEM-RELEASE-TREE-SHA256-v1\0")
    for candidate in sorted(path.rglob("*"), key=lambda item: item.relative_to(path).as_posix()):
        relative = candidate.relative_to(path).as_posix().encode("utf-8")
        metadata = candidate.lstat()
        mode = stat.S_IMODE(metadata.st_mode)
        if stat.S_ISLNK(metadata.st_mode):
            digest.update(b"L\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
            digest.update(os.readlink(candidate).encode("utf-8") + b"\0")
        elif stat.S_ISDIR(metadata.st_mode):
            digest.update(b"D\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
        elif stat.S_ISREG(metadata.st_mode):
            digest.update(b"F\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
            digest.update(str(metadata.st_size).encode("ascii") + b"\0")
            with candidate.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest.update(b"\0")
        else:
            digest.update(b"O\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
    return digest.hexdigest()


def resolve_artifact(argument, label, expected_kind, problems):
    raw = Path(os.path.expanduser(argument))
    if not raw.is_absolute():
        problems.append(f"{label}: gate input must be an absolute path")
    try:
        resolved = raw.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        problems.append(f"{label}: unable to resolve artifact: {error}")
        return None
    if expected_kind == "directory" and not resolved.is_dir():
        problems.append(f"{label}: expected a directory, observed {resolved}")
        return None
    if expected_kind == "file" and not resolved.is_file():
        problems.append(f"{label}: expected a file, observed {resolved}")
        return None
    return resolved

PLATFORM_ORDER = ("iphone", "ipad", "watch", "mac")
PLATFORM_LABELS = {
    "iphone": "iPhone",
    "ipad": "iPad",
    "watch": "Apple Watch",
    "mac": "Mac",
}
PLATFORM_ALIASES = {
    "iphone": "iphone",
    "ipad": "ipad",
    "watch": "watch",
    "apple watch": "watch",
    "mac": "mac",
    "mac catalyst": "mac",
}


def parse_platforms(value, source):
    raw = clean(value)
    if not raw:
        return set(), [
            f"{source}: set an explicit comma-separated selection using iphone,ipad,watch,mac"
        ]
    if is_pending(raw):
        return set(), [f"{source}: blank or pending"]

    platforms = set()
    problems = []
    for token in raw.split(","):
        candidate = token.strip().lower()
        canonical = PLATFORM_ALIASES.get(candidate)
        if not canonical:
            problems.append(
                f"{source}: unsupported platform {token.strip() or 'blank'} "
                "(use iphone,ipad,watch,mac)"
            )
            continue
        if canonical in platforms:
            problems.append(f"{source}: duplicate platform {canonical}")
            continue
        platforms.add(canonical)
    if not platforms and not problems:
        problems.append(
            f"{source}: set an explicit comma-separated selection using iphone,ipad,watch,mac"
        )
    return platforms, problems


def table_rows(section, expected_columns, header):
    for line in section.splitlines():
        if not line.startswith("|") or "---" in line:
            continue
        cells = [clean(cell) for cell in line.strip("|").split("|")]
        if len(cells) < expected_columns or cells[0].lower() == header.lower():
            continue
        yield cells[:expected_columns]


recorded_commit = field_value("Published commit")
if not re.fullmatch(r"[0-9a-f]{40}", recorded_commit):
    not_ready.append("Published commit: record the full 40-character published source commit")

selected_platforms, platform_errors = parse_platforms(
    configured_platforms_raw,
    "PUBLIC_RELEASE_PLATFORMS",
)
not_ready.extend(platform_errors)

ios_archive_path = resolve_artifact(
    ios_archive_argument,
    "iOS archive path",
    "directory",
    not_ready,
)
ios_ipa_path = resolve_artifact(
    ios_ipa_argument,
    "iOS IPA path",
    "file",
    not_ready,
)
mac_archive_path = None
mac_pkg_path = None
if "mac" in selected_platforms:
    mac_archive_path = resolve_artifact(
        mac_archive_argument,
        "Mac archive path",
        "directory",
        not_ready,
    )
    mac_pkg_path = resolve_artifact(
        mac_pkg_argument,
        "Mac package path",
        "file",
        not_ready,
    )

artifact_evidence = {}
for label, artifact, hasher in [
    ("iOS archive", ios_archive_path, tree_sha256),
    ("iOS IPA", ios_ipa_path, file_sha256),
    ("Mac archive", mac_archive_path, tree_sha256),
    ("Mac package", mac_pkg_path, file_sha256),
]:
    if artifact is None:
        continue
    try:
        artifact_evidence[label] = {
            "path": str(artifact),
            "sha256": hasher(artifact),
        }
    except (OSError, RuntimeError) as error:
        not_ready.append(f"{label}: unable to hash exact artifact: {error}")


def archive_source_commit(archive, relative_info_path, label):
    info_path = archive / relative_info_path
    try:
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        not_ready.append(f"{label} source commit: unable to read signed Info.plist: {error}")
        return ""
    value = info.get("GTAReleaseSourceCommit") if isinstance(info, dict) else None
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}", value):
        not_ready.append(
            f"{label} source commit: signed artifact must embed a full lowercase 40-character commit"
        )
        return ""
    return value


if fixture_only:
    fixture_artifact_commit = os.environ.get(
        "PUBLIC_GATE_TEST_ARTIFACT_SOURCE_COMMIT",
        recorded_commit,
    ).lower()
    artifact_source_commits = {"iOS archive": fixture_artifact_commit}
    if "mac" in selected_platforms:
        artifact_source_commits["Mac archive"] = fixture_artifact_commit
else:
    artifact_source_commits = {}
    if ios_archive_path is not None:
        artifact_source_commits["iOS archive"] = archive_source_commit(
            ios_archive_path,
            Path("Products/Applications/GTAFreeSTEM.app/Info.plist"),
            "iOS archive",
        )
    if mac_archive_path is not None:
        artifact_source_commits["Mac archive"] = archive_source_commit(
            mac_archive_path,
            Path("Products/Applications/GTAFreeSTEM.app/Contents/Info.plist"),
            "Mac archive",
        )

for artifact_label, artifact_commit in artifact_source_commits.items():
    if artifact_commit and artifact_commit != recorded_commit:
        not_ready.append(
            f"{artifact_label} source commit: signed artifact embeds {artifact_commit}, "
            f"but signoff records {recorded_commit or 'blank'}"
        )

source_paths = [
    "GTAFreeSTEM",
    "GTAFreeSTEMWatch",
    "GTAFreeSTEM.xcodeproj",
    "project.yml",
]
if fixture_only:
    live_main_commit = os.environ.get("PUBLIC_GATE_TEST_LIVE_MAIN_COMMIT", "c" * 40).lower()
    verification_date = os.environ.get("PUBLIC_GATE_TEST_TODAY", "2026-08-06")
    recorded_reachable_from_live = (
        os.environ.get("PUBLIC_GATE_TEST_RECORDED_REACHABLE_FROM_LIVE", "1") == "1"
    )
    recorded_matches_live_source = (
        os.environ.get("PUBLIC_GATE_TEST_RECORDED_MATCHES_LIVE_SOURCE", "1") == "1"
    )
    local_matches_recorded_source = (
        os.environ.get("PUBLIC_GATE_TEST_LOCAL_MATCHES_RECORDED_SOURCE", "1") == "1"
    )
else:
    remote_result = run(["git", "ls-remote", "--exit-code", "origin", "refs/heads/main"])
    remote_tokens = remote_result.stdout.strip().split()
    live_main_commit = remote_tokens[0].lower() if remote_result.returncode == 0 and remote_tokens else ""
    if not re.fullmatch(r"[0-9a-f]{40}", live_main_commit):
        detail = (remote_result.stderr or remote_result.stdout).strip()
        not_ready.append(
            "Published source: unable to verify live origin/main{}".format(
                ": " + detail if detail else ""
            )
        )

    recorded_reachable_from_live = None
    recorded_matches_live_source = None
    local_matches_recorded_source = None
    live_main_available = False
    recorded_commit_available = False

    if re.fullmatch(r"[0-9a-f]{40}", live_main_commit):
        live_object_check = run(["git", "cat-file", "-e", live_main_commit + "^{commit}"])
        live_main_available = live_object_check.returncode == 0
        if not live_main_available:
            not_ready.append(
                "Published source: origin/main commit is not available locally; fetch it before signoff"
            )

    if re.fullmatch(r"[0-9a-f]{40}", recorded_commit):
        recorded_object_check = run(["git", "cat-file", "-e", recorded_commit + "^{commit}"])
        recorded_commit_available = recorded_object_check.returncode == 0
        if not recorded_commit_available:
            not_ready.append(
                "Published commit: recorded source commit is not available locally; fetch it before signoff"
            )

    if live_main_available and recorded_commit_available:
        recorded_reachable_from_live = (
            run(["git", "merge-base", "--is-ancestor", recorded_commit, live_main_commit]).returncode
            == 0
        )
        recorded_matches_live_source = (
            run(
                ["git", "diff", "--quiet", recorded_commit, live_main_commit, "--"]
                + source_paths
            ).returncode
            == 0
        )
        source_status = run(
            ["git", "status", "--porcelain=v1", "--untracked-files=all", "--"]
            + source_paths
        )
        local_source_diff = run(
            ["git", "diff", "--quiet", recorded_commit, "--"] + source_paths
        )
        local_matches_recorded_source = (
            source_status.returncode == 0
            and not source_status.stdout.strip()
            and local_source_diff.returncode == 0
        )
    verification_date = dt.date.today().isoformat()

if recorded_reachable_from_live is False:
    not_ready.append(
        "Published commit: recorded source commit {} is not reachable from live origin/main {}".format(
            recorded_commit or "blank",
            live_main_commit or "unknown",
        )
    )
if recorded_matches_live_source is False:
    not_ready.append(
        "Published source: recorded source commit app, Watch, and Xcode project inputs "
        "must byte-match live origin/main"
    )
if local_matches_recorded_source is False:
    not_ready.append(
        "Published source: current local app, Watch, and Xcode project inputs must "
        "byte-match the recorded published source commit"
    )

project_path = Path("project.yml")
project_text = project_path.read_text(encoding="utf-8") if project_path.exists() else ""
required_platforms = set()
device_family_match = re.search(r'^\s*TARGETED_DEVICE_FAMILY:\s*["\']?([^"\'\n#]+)', project_text, re.MULTILINE)
device_families = {
    token.strip()
    for token in (device_family_match.group(1).split(",") if device_family_match else [])
}
if "1" in device_families:
    required_platforms.add("iphone")
if "2" in device_families:
    required_platforms.add("ipad")
if re.search(r"^\s*-\s*target:\s*GTAFreeSTEMWatch\s*$", project_text, re.MULTILINE):
    required_platforms.add("watch")
if re.search(
    r"^\s*SUPPORTS_MACCATALYST:\s*(?:true|yes|1)\s*$",
    project_text,
    re.MULTILINE | re.IGNORECASE,
):
    required_platforms.add("mac")

missing_required_platforms = required_platforms - selected_platforms
if missing_required_platforms:
    missing = ",".join(platform for platform in PLATFORM_ORDER if platform in missing_required_platforms)
    not_ready.append(
        "PUBLIC_RELEASE_PLATFORMS: current binary requires "
        f"{missing}; change the binary before omitting an enabled platform"
    )

recorded_platforms = field_value("Public distribution platforms")
if is_pending(recorded_platforms):
    not_ready.append("Public distribution platforms: blank or pending")
elif selected_platforms:
    recorded_set, recorded_errors = parse_platforms(
        recorded_platforms,
        "Public distribution platforms",
    )
    not_ready.extend(recorded_errors)
    if not recorded_errors and recorded_set != selected_platforms:
        expected = ",".join(platform for platform in PLATFORM_ORDER if platform in selected_platforms)
        observed = ",".join(platform for platform in PLATFORM_ORDER if platform in recorded_set)
        not_ready.append(
            "Public distribution platforms: signoff must match "
            f"PUBLIC_RELEASE_PLATFORMS ({expected}; recorded {observed})"
        )

required_build_facts = {
    "Version/build": expected_build,
    "iOS App Store Connect status": "VALID",
    "iOS BuildBetaDetail.internalBuildState": "IN_BETA_TESTING",
}
if "mac" in selected_platforms:
    required_build_facts.update({
        "Mac App Store Connect status": "VALID",
        "Mac BuildBetaDetail.internalBuildState": "IN_BETA_TESTING",
    })
for label, required in required_build_facts.items():
    value = field_value(label)
    if value != required:
        not_ready.append(f"{label}: expected exact value {required}, got {value or 'blank'}")

uuid_pattern = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
ios_delivery = field_value("iOS Delivery UUID")
if not re.fullmatch(uuid_pattern, ios_delivery):
    not_ready.append("iOS Delivery UUID: real build-12 Apple delivery UUID required")

recorded_verification_date = field_value("Artifact verification date")
if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", recorded_verification_date):
    not_ready.append("Artifact verification date: use YYYY-MM-DD")
elif recorded_verification_date != verification_date:
    not_ready.append(
        "Artifact verification date: exact artifacts were verified today ({}), recorded {}".format(
            verification_date, recorded_verification_date
        )
    )


def require_artifact_binding(evidence_name, field_prefix):
    evidence = artifact_evidence.get(evidence_name)
    recorded_path = field_value(field_prefix + " path")
    recorded_hash = field_value(field_prefix + " SHA-256")
    if evidence is None:
        return
    if recorded_path != evidence["path"]:
        not_ready.append(
            "{} path: signoff must equal verified artifact {} (recorded {})".format(
                field_prefix,
                evidence["path"],
                recorded_path or "blank",
            )
        )
    if not re.fullmatch(r"[0-9a-f]{64}", recorded_hash):
        not_ready.append("{} SHA-256: record the full lowercase digest".format(field_prefix))
    elif recorded_hash != evidence["sha256"]:
        not_ready.append(
            "{} SHA-256: verified {} but signoff records {}".format(
                field_prefix,
                evidence["sha256"],
                recorded_hash,
            )
        )


require_artifact_binding("iOS archive", "iOS archive")
require_artifact_binding("iOS IPA", "iOS IPA")
if "mac" in selected_platforms:
    require_artifact_binding("Mac archive", "Mac archive")
    require_artifact_binding("Mac package", "Mac package")
    mac_delivery = field_value("Mac Delivery UUID")
    if not re.fullmatch(uuid_pattern, mac_delivery):
        not_ready.append("Mac Delivery UUID: separate real Apple delivery UUID required")
    elif mac_delivery.lower() == ios_delivery.lower():
        not_ready.append("Mac Delivery UUID: must be separate from the iOS delivery UUID")

for label in ["Tester", "Date"]:
    if is_pending(field_value(label)):
        not_ready.append(f"{label}: blank or pending")

date = field_value("Date")
if date and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
    not_ready.append("Date: use YYYY-MM-DD")
required_test_context = {
    "Install source": "TestFlight",
    "Network conditions tested": "WI_FI_AND_OFFLINE_FALLBACK",
    "Accessibility settings tested": "VOICEOVER_LARGE_TEXT_DARK_MODE",
    "Languages tested": "ENGLISH_FRENCH_SPANISH_ARABIC_RTL",
}
for label, required in required_test_context.items():
    value = field_value(label)
    if value != required:
        not_ready.append(f"{label}: expected exact value {required}, got {value or 'blank'}")

allowed = {"Pass", "Accepted Risk"}
accepted_rows = []
REQUIRED_PASS_AREAS = (
    "Install and launch",
    "Warm launch experience",
    "Live feed",
    "Search keywords",
    "Search translations",
    "Filters and sorting",
    "Map/list consistency",
    "Details and external links",
    "Local saves",
    "Local profile deletion",
    "Manual refresh",
    "Cache fallback",
    "Bundled fallback",
    "State restore",
    "Location",
    "Notifications",
    "Localization and RTL",
    "Accessibility",
    "Support privacy",
    "App Store URLs",
)


def validate_status(area, status, notes):
    if status not in allowed:
        not_ready.append(f"{area}: {status or 'blank'}")
    elif status == "Accepted Risk":
        accepted_rows.append(area)
        if is_pending(notes):
            not_ready.append(f"{area}: Accepted Risk needs notes")


required_passes = section_contents("Required Passes")
if not required_passes:
    not_ready.append("Required Passes: missing section")
else:
    required_rows = list(table_rows(required_passes, 4, "Area"))
    if len(required_rows) != len(REQUIRED_PASS_AREAS):
        not_ready.append(
            "Required Passes: expected exactly {} canonical rows, found {}".format(
                len(REQUIRED_PASS_AREAS),
                len(required_rows),
            )
        )
    observed_areas = set()
    for area, _, status, notes in required_rows:
        if area in observed_areas:
            not_ready.append(f"Required Passes: duplicate area {area or 'blank'}")
        else:
            observed_areas.add(area)
        if area not in REQUIRED_PASS_AREAS:
            not_ready.append(f"Required Passes: unexpected area {area or 'blank'}")
        validate_status(area, status, notes)
    for area in REQUIRED_PASS_AREAS:
        if area not in observed_areas:
            not_ready.append(f"Required Passes: missing required area {area}")

platform_evidence = {}
platform_section = section_contents("Platform-Specific Evidence")
if selected_platforms and not platform_section:
    not_ready.append("Platform-Specific Evidence: missing section")
elif platform_section:
    for platform_name, _, device, os_version, status, notes in table_rows(
        platform_section,
        6,
        "Platform",
    ):
        platform = PLATFORM_ALIASES.get(platform_name.lower())
        if not platform:
            not_ready.append(
                f"Platform-Specific Evidence: unsupported platform {platform_name or 'blank'}"
            )
            continue
        if platform in platform_evidence:
            not_ready.append(f"Platform-Specific Evidence: duplicate {PLATFORM_LABELS[platform]} row")
            continue
        platform_evidence[platform] = (device, os_version, status, notes)

for platform in PLATFORM_ORDER:
    if platform not in selected_platforms:
        continue
    label = PLATFORM_LABELS[platform]
    evidence = platform_evidence.get(platform)
    if not evidence:
        not_ready.append(f"{label}: missing platform-specific evidence")
        continue
    device, os_version, status, notes = evidence
    if is_pending(device):
        not_ready.append(f"{label} device model: blank or pending")
    if is_pending(os_version):
        not_ready.append(f"{label} OS version: blank or pending")
    validate_status(label, status, notes)

overall = field_value("Overall status")
if overall not in allowed:
    not_ready.append(f"Overall status: {overall or 'blank'}")

accepted_risks = field_value("Accepted risks")
if accepted_rows or overall == "Accepted Risk":
    if is_pending(accepted_risks):
        not_ready.append("Accepted risks: required when any risk is accepted")
elif accepted_risks.lower() not in {"none", "no accepted risks"}:
    not_ready.append("Accepted risks: write None when no risk is accepted")

required_owner_fields = [
    "iOS App Store Connect build selected", "Archive provenance verified",
    "Screenshot visual QA", "Visual QA manifest SHA-256", "Screenshots uploaded",
    "Metadata/privacy/age rating entered",
    "Support contact verified", "App Review contact verified",
    "Copyright entered", "Production legal/support truthfulness verified",
    "Primary language verified", "Availability and DSA verified",
]
if "mac" in selected_platforms:
    required_owner_fields.append("Mac App Store Connect build selected")
for label in required_owner_fields:
    if is_pending(field_value(label)):
        not_ready.append(f"{label}: blank or pending")
if "mac" in selected_platforms and is_pending(field_value("Platform record decision")):
    not_ready.append("Platform record decision: blank or pending")

must_fix = field_value("Must-fix blockers").lower()
if must_fix not in {"none", "no known blockers"}:
    not_ready.append("Must-fix blockers: write None only after all must-fix issues are resolved")

selected_build_fields = ["iOS App Store Connect build selected"]
if "mac" in selected_platforms:
    selected_build_fields.append("Mac App Store Connect build selected")
for label in selected_build_fields:
    value = field_value(label)
    if value != expected_build:
        not_ready.append(f"{label}: expected exact value {expected_build}, got {value or 'blank'}")

artifact_binding_status = field_value("Artifact binding status")
if artifact_binding_status != "CURRENT_AND_VERIFIED":
    not_ready.append(
        "Artifact binding status: expected exact value CURRENT_AND_VERIFIED after the exact source is rebuilt and rebound"
    )

expected_screenshot_count = sum(
    {"iphone": 4, "ipad": 4, "watch": 1, "mac": 4}[platform]
    for platform in selected_platforms
)
expected_upload_status = "UPLOADED_{}_{}".format(
    expected_screenshot_count,
    "_".join(platform.upper() for platform in PLATFORM_ORDER if platform in selected_platforms),
)
screenshots = field_value("Screenshots uploaded")
if screenshots != expected_upload_status:
    not_ready.append(
        f"Screenshots uploaded: expected exact value {expected_upload_status}, got {screenshots or 'blank'}"
    )

screenshot_visual_qa = field_value("Screenshot visual QA")
if screenshot_visual_qa != "PASS":
    not_ready.append(
        f"Screenshot visual QA: expected exact value PASS, got {screenshot_visual_qa or 'blank'}"
    )

EXPECTED_SCREENSHOT_PATHS = (
    "iphone-6.9/01-home.jpg",
    "iphone-6.9/02-opportunities.jpg",
    "iphone-6.9/03-high-school.jpg",
    "iphone-6.9/04-profile.jpg",
    "ipad-13/01-home.jpg",
    "ipad-13/02-opportunities.jpg",
    "ipad-13/03-high-school.jpg",
    "ipad-13/04-profile.jpg",
    "mac/01-home.jpg",
    "mac/02-opportunities.jpg",
    "mac/03-high-school.jpg",
    "mac/04-profile.jpg",
    "watch-series-11/01-home.jpg",
)


def validate_visual_qa_manifest():
    manifest = Path(visual_qa_manifest_argument)
    screenshot_root = Path(screenshot_root_argument)
    recorded_manifest_hash = field_value("Visual QA manifest SHA-256")
    if not re.fullmatch(r"[0-9a-f]{64}", recorded_manifest_hash):
        not_ready.append("Visual QA manifest SHA-256: record the full lowercase digest")

    if not manifest.exists():
        not_ready.append(f"Visual QA manifest: missing {manifest}")
        return
    if manifest.is_symlink() or not manifest.is_file():
        not_ready.append(f"Visual QA manifest: expected a regular non-symlink file at {manifest}")
        return
    if not screenshot_root.exists() or not screenshot_root.is_dir():
        not_ready.append(f"Visual QA screenshot root: missing directory {screenshot_root}")
        return

    try:
        manifest_bytes = manifest.read_bytes()
        actual_manifest_hash = hashlib.sha256(manifest_bytes).hexdigest()
        manifest_text = manifest_bytes.decode("utf-8")
    except (OSError, UnicodeError) as error:
        not_ready.append(f"Visual QA manifest: unable to read {manifest}: {error}")
        return
    if recorded_manifest_hash != actual_manifest_hash:
        not_ready.append(
            "Visual QA manifest SHA-256: verified {} but signoff records {}".format(
                actual_manifest_hash,
                recorded_manifest_hash or "blank",
            )
        )

    manifest_sections = {}

    def manifest_section(heading):
        if heading in manifest_sections:
            return manifest_sections[heading]
        matches = list(re.finditer(
            rf"^## {re.escape(heading)}\s*$\n?(.*?)(?=^## |\Z)",
            manifest_text,
            re.MULTILINE | re.DOTALL,
        ))
        if len(matches) != 1:
            not_ready.append(
                f"Visual QA manifest {heading}: expected exactly one section, found {len(matches)}"
            )
            value = matches[0].group(1) if matches else ""
        else:
            value = matches[0].group(1)
        manifest_sections[heading] = value
        return value

    approval = manifest_section("Approval")
    manifest_field_cache = {}

    def manifest_field(label):
        if label in manifest_field_cache:
            return manifest_field_cache[label]
        matches = re.findall(
            rf"^- {re.escape(label)}:[ \t]*(.*)$",
            approval,
            re.MULTILINE,
        )
        if len(matches) != 1:
            not_ready.append(
                f"Visual QA manifest Approval: expected exactly one '{label}' field, found {len(matches)}"
            )
            value = ""
        else:
            value = clean(matches[0])
        manifest_field_cache[label] = value
        return value

    exact_manifest_fields = {
        "Manifest schema": "GTA-FREE-STEM-FINAL-VISUAL-QA-v1",
        "Approval status": "PASS",
        "Review scope": "FULL_SIZE_ALL_13_NO_KNOWN_DEFECTS",
        "Version/build": expected_build,
        "Published commit": recorded_commit,
        "Screenshot count": str(len(EXPECTED_SCREENSHOT_PATHS)),
    }
    for label, required in exact_manifest_fields.items():
        value = manifest_field(label)
        if value != required:
            not_ready.append(
                f"Visual QA manifest {label}: expected exact value {required}, got {value or 'blank'}"
            )

    capture_receipt_hash = manifest_field("Capture receipt SHA-256")
    if not re.fullmatch(r"[0-9a-f]{64}", capture_receipt_hash):
        not_ready.append(
            "Visual QA manifest Capture receipt SHA-256: record a full lowercase digest"
        )

    reviewer = manifest_field("Reviewer")
    reviewer_normalized = reviewer.lower()
    if is_pending(reviewer) or re.match(
        r"^(?:no|not|none|unreviewed|unknown|nobody)\b",
        reviewer_normalized,
    ):
        not_ready.append("Visual QA manifest Reviewer: blank or pending")
    reviewed_on = manifest_field("Reviewed on")
    try:
        reviewed_date = dt.date.fromisoformat(reviewed_on)
    except ValueError:
        not_ready.append("Visual QA manifest Reviewed on: use YYYY-MM-DD")
    else:
        if reviewed_date > dt.date.fromisoformat(verification_date):
            not_ready.append("Visual QA manifest Reviewed on: date cannot be in the future")

    approved_files = manifest_section("Approved Files")
    rows = list(table_rows(approved_files, 2, "Relative path"))
    if len(rows) != len(EXPECTED_SCREENSHOT_PATHS):
        not_ready.append(
            "Visual QA manifest Approved Files: expected exactly {} rows, found {}".format(
                len(EXPECTED_SCREENSHOT_PATHS),
                len(rows),
            )
        )
    observed_paths = set()
    recorded_hashes = {}
    for relative_path, recorded_hash in rows:
        if relative_path in observed_paths:
            not_ready.append(f"Visual QA manifest Approved Files: duplicate path {relative_path}")
            continue
        observed_paths.add(relative_path)
        recorded_hashes[relative_path] = recorded_hash
        if relative_path not in EXPECTED_SCREENSHOT_PATHS:
            not_ready.append(
                f"Visual QA manifest Approved Files: unexpected path {relative_path or 'blank'}"
            )
            continue
        if not re.fullmatch(r"[0-9a-f]{64}", recorded_hash):
            not_ready.append(
                f"Visual QA screenshot {relative_path}: record a full lowercase SHA-256 digest"
            )
            continue
        screenshot = screenshot_root / relative_path
        if screenshot.is_symlink() or not screenshot.is_file():
            not_ready.append(
                f"Visual QA screenshot {relative_path}: missing regular non-symlink file"
            )
            continue
        try:
            actual_hash = file_sha256(screenshot)
        except OSError as error:
            not_ready.append(f"Visual QA screenshot {relative_path}: unable to hash: {error}")
            continue
        if actual_hash != recorded_hash:
            not_ready.append(
                f"Visual QA screenshot {relative_path}: SHA-256 mismatch; "
                f"manifest records {recorded_hash}, current file is {actual_hash}"
            )
    for relative_path in EXPECTED_SCREENSHOT_PATHS:
        if relative_path not in observed_paths:
            not_ready.append(
                f"Visual QA manifest Approved Files: missing required path {relative_path}"
            )

    canonical_lines = [
        "# Final Screenshot Visual QA",
        "",
        "## Approval",
        "",
        "- Manifest schema: `GTA-FREE-STEM-FINAL-VISUAL-QA-v1`",
        "- Approval status: `PASS`",
        "- Review scope: `FULL_SIZE_ALL_13_NO_KNOWN_DEFECTS`",
        f"- Version/build: `{expected_build}`",
        f"- Published commit: `{recorded_commit}`",
        f"- Capture receipt SHA-256: `{capture_receipt_hash}`",
        f"- Reviewer: `{reviewer}`",
        f"- Reviewed on: `{reviewed_on}`",
        f"- Screenshot count: `{len(EXPECTED_SCREENSHOT_PATHS)}`",
        "",
        "## Approved Files",
        "",
        "| Relative path | SHA-256 |",
        "| --- | --- |",
    ]
    for relative_path in EXPECTED_SCREENSHOT_PATHS:
        canonical_lines.append(
            f"| {relative_path} | {recorded_hashes.get(relative_path, '')} |"
        )
    canonical_manifest = "\n".join(canonical_lines) + "\n"
    if manifest_text != canonical_manifest:
        not_ready.append(
            "Visual QA manifest: content must match the canonical schema and row order exactly"
        )


validate_visual_qa_manifest()

expected_metadata_status = (
    "ENTERED_METADATA_PRIVACY_AGE_RATING_KIDS_NO_EXPORT_COMPLIANCE_REVIEW_NOTES"
)
metadata = field_value("Metadata/privacy/age rating entered")
if metadata != expected_metadata_status:
    not_ready.append(
        "Metadata/privacy/age rating entered: expected exact value "
        f"{expected_metadata_status}, got {metadata or 'blank'}"
    )

build_token = re.sub(r"[^A-Za-z0-9]+", "_", expected_build).strip("_").upper()
archive_platform_tokens = []
if selected_platforms & {"iphone", "ipad"}:
    archive_platform_tokens.append("IOS")
if "watch" in selected_platforms:
    archive_platform_tokens.append("WATCH")
if "mac" in selected_platforms:
    archive_platform_tokens.append("MAC")
expected_archive_status = "VERIFIED_SIGNED_BUILD_{}_{}".format(
    build_token,
    "_".join(archive_platform_tokens),
)
archive = field_value("Archive provenance verified")
if archive != expected_archive_status:
    not_ready.append(
        "Archive provenance verified: expected exact value "
        f"{expected_archive_status}, got {archive or 'blank'}"
    )

expected_support_status = (
    "VERIFIED: https://gta-free-stem.vercel.app/support/ | "
    "GITHUB_ISSUES | MONITORED_DIRECT_CONTACT"
)
support = field_value("Support contact verified")
if support != expected_support_status:
    not_ready.append(
        f"Support contact verified: expected exact value {expected_support_status}, "
        f"got {support or 'blank'}"
    )

expected_production_truthfulness = (
    "VERIFIED_MATCH_BUILD: https://gta-free-stem.vercel.app/support/ | "
    "https://gta-free-stem.vercel.app/privacy/ | "
    "https://gta-free-stem.vercel.app/terms/"
)
production_support_privacy = field_value("Production legal/support truthfulness verified")
if production_support_privacy != expected_production_truthfulness:
    not_ready.append(
        "Production legal/support truthfulness verified: expected exact value "
        f"{expected_production_truthfulness}, got {production_support_privacy or 'blank'}"
    )

expected_portal_verification = f"VERIFIED_APP_STORE_CONNECT_{verification_date}"
review_contact = field_value("App Review contact verified")
if review_contact != expected_portal_verification:
    not_ready.append(
        f"App Review contact verified: expected exact value {expected_portal_verification}, "
        f"got {review_contact or 'blank'}"
    )

primary_language = field_value("Primary language verified")
primary_language_pattern = re.compile(
    rf"{re.escape(expected_portal_verification)}: primary_language=[a-z]{{2}}(?:-[A-Z]{{2}})?"
)
if not primary_language_pattern.fullmatch(primary_language):
    not_ready.append(
        "Primary language verified: expected exact format "
        f"{expected_portal_verification}: primary_language=<locale>, "
        f"got {primary_language or 'blank'}"
    )

availability_dsa = field_value("Availability and DSA verified")
if availability_dsa != expected_portal_verification:
    not_ready.append(
        f"Availability and DSA verified: expected exact value {expected_portal_verification}, "
        f"got {availability_dsa or 'blank'}"
    )

copyright = field_value("Copyright entered")
copyright_match = re.fullmatch(
    r"ENTERED_APP_STORE_CONNECT_(20\d{2}): ([A-Za-z][A-Za-z0-9 .,'&-]{3,})",
    copyright,
)
copyright_holder = copyright_match.group(2).strip().lower() if copyright_match else ""
copyright_placeholders = {
    "legal rights owner", "rights holder", "copyright owner", "unknown", "none",
}
if (
    not copyright_match
    or copyright_holder in copyright_placeholders
    or re.match(r"^(?:no|not|none|unknown)\b", copyright_holder)
):
    not_ready.append(
        "Copyright entered: expected exact format "
        "ENTERED_APP_STORE_CONNECT_<year>: <confirmed legal-rights holder>"
    )

ios_bundle_match = re.search(r"^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*([^\s#]+)", project_text, re.MULTILINE)
mac_bundle_match = re.search(
    r'^\s*["\']?PRODUCT_BUNDLE_IDENTIFIER\[sdk=macosx\*\]["\']?:\s*([^\s#]+)',
    project_text,
    re.MULTILINE,
)
ios_bundle = ios_bundle_match.group(1).strip('"\'') if ios_bundle_match else ""
mac_bundle = mac_bundle_match.group(1).strip('"\'') if mac_bundle_match else ios_bundle
platform_decision = field_value("Platform record decision")
if "mac" in selected_platforms:
    platform_match = re.fullmatch(
        r"VERIFIED_SEPARATE_MAC_RECORD: app_id=([0-9]{10}); "
        r"sku=([A-Za-z0-9._-]+); "
        r"bundle_id=com\.rupayonhaldar\.gtafreestem\.maccatalyst",
        platform_decision,
    )
    if not platform_match:
        not_ready.append(
            "Platform record decision: expected exact format VERIFIED_SEPARATE_MAC_RECORD: "
            "app_id=<numeric App ID>; sku=<SKU>; "
            "bundle_id=com.rupayonhaldar.gtafreestem.maccatalyst"
        )
    if mac_bundle != "com.rupayonhaldar.gtafreestem.maccatalyst":
        not_ready.append("Platform record decision: separate path requires the configured Catalyst bundle ID")

submitted = field_value("Submitted for App Review")
if is_pending(submitted):
    print("Submitted for App Review is pending; that is acceptable until the final release decision.")

if not_ready:
    print("Public release gates are not complete:")
    for item in not_ready:
        print(f"- {item}")
    raise SystemExit(1)

if fixture_only:
    print("PUBLIC_GATE_FIXTURE_PASS_NOT_RELEASE_SIGNOFF")
else:
    print(f"Public release gates are complete for build {expected_build}.")
PY
