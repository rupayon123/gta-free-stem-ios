#!/usr/bin/env python3
"""Validate release-feed content-rights evidence and per-extract source links."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


TERMS_DIGEST_VERSION = "bibliocommons-relevant-sections-v1"
TERMS_CONDITIONS = (
    "Automated access uses the provider's RSS/XML event feed.",
    "Every displayed extract links to its original BiblioCommons event page.",
    "GTA FREE STEM is free and does not monetize provider content.",
)
APPROVED_TERMS_EVIDENCE = {
    ("Markham Public Library", "markham.bibliocommons.com"): {
        "basisUrl": "https://markham.bibliocommons.com/info/terms/",
        "termsVersion": "2018-09-19",
        "termsSectionDigest": "sha256:451e63466c801166653f47336e236d05f9a50a3df45a917fa603e92bcd11c8a0",
    },
    ("Toronto Public Library", "tpl.bibliocommons.com"): {
        "basisUrl": "https://tpl.bibliocommons.com/info/terms/",
        "termsVersion": "2018-09-19",
        "termsSectionDigest": "sha256:c9b14cbd531afa09533e844274bb9f07f8042883e12b5a3990be3100ca5d4b43",
    },
}

# Original reviewed factual summaries are a separate policy, not a claim of a
# provider agreement. Values mirror the native binary's exact record binding.
REVIEWED_FACTUAL_RECORDS = {
    ("Ontario Science Centre", "www.ontariosciencecentre.ca"): {
        "id": "ontario-science-centre-pride-in-stem-2026", "title": "Pride in STEM 2026",
        "sourceUrl": "https://www.ontariosciencecentre.ca/whats-on/pop-ups-plus-events/pride-in-stem-2026",
        "descriptionHash": "86ae9b3d83e925c6a0553f3e8219b4cdf6c2fc74c24bdcdf920c10b904c50d99",
        "startDate": "2026-11-21T09:00:00-05:00", "endDate": "2026-11-21T15:00:00-05:00",
        "city": "Toronto", "region": "Toronto", "address": "Evergreen Brick Works, 550 Bayview Avenue, Toronto, ON M4W 3X8",
    },
    ("Autism Ontario", "www.autismontario.com"): {
        "id": "autism-ontario-newmarket-quiet-santa-2026-11-22", "title": "Quiet Time with Santa — Newmarket",
        "sourceUrl": "https://www.autismontario.com/civicrm/event/info?id=13084",
        "descriptionHash": "a067b94bbaed7caeb9d5b00bc8f2e4a02ffb27e7616085b24c2fc1d1da77f0c4",
        "startDate": "2026-11-22T08:30:00-05:00", "endDate": "2026-11-22T10:30:00-05:00",
        "city": "Newmarket", "region": "York", "address": "Upper Canada Mall, 17600 Yonge Street, Newmarket, ON L3Y 4Z1",
    },
}


OWNER_PERMISSION = {
    "confirmationID": "gta-library-content-2026-10-25",
    "confirmedAt": "2026-10-25",
    "scope": ["display-event-listings", "translate-event-listings"],
}

def parsed_date(value: object, label: str) -> date:
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"Content-rights evidence is missing {label}.")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        try:
            return date.fromisoformat(value)
        except ValueError as error:
            raise SystemExit(f"Content-rights evidence has invalid {label}: {value}") from error


def https_host(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise SystemExit(f"Content-rights evidence is missing {label}.")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname:
        raise SystemExit(f"Content-rights {label} must be an absolute HTTPS URL: {value}")
    return parsed.hostname.lower()


def validate(path: Path) -> tuple[int, int]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Cannot read a valid JSON feed for content-rights validation: {error}") from error

    items = payload.get("opportunities") or payload.get("data") or []
    if not isinstance(items, list) or not items:
        raise SystemExit("Content-rights validation requires a non-empty opportunity feed.")

    updated = parsed_date(payload.get("lastDataChange") or (payload.get("meta") or {}).get("lastUpdated"), "feed update date")
    rights = payload.get("contentRights")
    if not isinstance(rights, dict):
        raise SystemExit("Canonical public feed must contain contentRights evidence.")
    if "checkedAt" in rights or "reviewedAt" in rights:
        raise SystemExit("Canonical public feed uses a deprecated or misleading rights-verification field.")
    terms_verified_at = parsed_date(rights.get("termsVerifiedAt"), "termsVerifiedAt")
    age = (datetime.now(timezone.utc).date() - terms_verified_at).days
    if age < 0 or age > 14:
        raise SystemExit(f"Content-rights evidence is not current: {terms_verified_at.isoformat()} ({age} days old).")
    if terms_verified_at < updated:
        raise SystemExit("Content-rights evidence predates the feed update and cannot authorize the current extracts.")

    restricted_ids = rights.get("restrictedOpportunityIds")
    if not isinstance(restricted_ids, list) or not all(
        isinstance(value, str) and value.strip() for value in restricted_ids
    ):
        raise SystemExit("Canonical public feed contentRights must declare restrictedOpportunityIds as non-empty strings.")
    if len(restricted_ids) != len(set(restricted_ids)):
        raise SystemExit("Content-rights restrictedOpportunityIds contains duplicates.")

    source_entries = rights.get("sources")
    if not isinstance(source_entries, list) or not source_entries:
        raise SystemExit("Canonical public feed contentRights must contain source entries.")

    evidence_by_key: dict[tuple[str, str], dict] = {}
    for index, source in enumerate(source_entries):
        if not isinstance(source, dict):
            raise SystemExit(f"Content-rights source entry {index} is malformed.")
        organization = source.get("organization")
        source_host = source.get("sourceHost")
        status = source.get("status")
        records = source.get("records")
        if not isinstance(organization, str) or not organization.strip():
            raise SystemExit(f"Content-rights source entry {index} is missing organization.")
        if not isinstance(source_host, str) or not source_host.strip():
            raise SystemExit(f"Content-rights source entry {index} is missing sourceHost.")
        source_host = source_host.lower()
        if not isinstance(records, int) or isinstance(records, bool) or records <= 0:
            raise SystemExit(f"Content-rights source {organization} has an invalid record count.")
        key = (organization, source_host)
        if key in evidence_by_key:
            raise SystemExit(f"Duplicate content-rights evidence for {organization} at {source_host}.")
        approved = APPROVED_TERMS_EVIDENCE.get(key)
        if status == "original-factual-summary":
            if (key not in REVIEWED_FACTUAL_RECORDS or records != 1 or source.get("ownerPermission") is not None
                    or source.get("basisUrl", "") != "" or source.get("conditions", []) != []
                    or any(source.get(field, "") != "" for field in ("termsVerifiedAt", "termsVersion", "termsDigestVersion", "termsSectionDigest"))):
                raise SystemExit(f"Factual-summary policy for {organization} is not the reviewed record.")
        elif status == "owner-confirmed-permission":
            # The owner confirmed permission on this date. This is not a claim
            # that a written agreement or newly reviewed provider terms exist.
            if approved is None or source.get("ownerPermission") != OWNER_PERMISSION:
                raise SystemExit(f"Content-rights owner confirmation for {organization} is not approved.")
        elif status == "terms-permitted":
            if approved is None:
                raise SystemExit(f"Content-rights source {organization} at {source_host} is not in the binary-approved allowlist.")
            basis_host = https_host(source.get("basisUrl"), f"basisUrl for {organization}")
            if basis_host != source_host:
                raise SystemExit(f"Content-rights basis for {organization} does not match source host {source_host}.")
            if "checkedAt" in source or "reviewedAt" in source:
                raise SystemExit(
                    f"Content-rights source {organization} uses a deprecated or misleading verification field."
                )
            source_verified_at = parsed_date(
                source.get("termsVerifiedAt"), f"termsVerifiedAt for {organization}"
            )
            if source_verified_at < updated or source_verified_at != terms_verified_at:
                raise SystemExit(
                    f"Content-rights terms verification for {organization} does not bind the current feed."
                )
            conditions = source.get("conditions")
            if not isinstance(conditions, list) or tuple(conditions) != TERMS_CONDITIONS:
                raise SystemExit(
                    f"Content-rights source {organization} does not declare the exact approved publication conditions."
                )
            if source.get("basisUrl") != approved["basisUrl"]:
                raise SystemExit(f"Content-rights source {organization} has an unapproved terms URL.")
            if source.get("termsVersion") != approved["termsVersion"]:
                raise SystemExit(f"Content-rights source {organization} has an unreviewed terms version.")
            if source.get("termsDigestVersion") != TERMS_DIGEST_VERSION:
                raise SystemExit(f"Content-rights source {organization} has an unreviewed digest version.")
            digest = source.get("termsSectionDigest")
            if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
                raise SystemExit(f"Content-rights source {organization} has an invalid terms-section digest.")
            if digest != approved["termsSectionDigest"]:
                raise SystemExit(f"Content-rights source {organization} has an unreviewed terms-section digest.")
        else:
            raise SystemExit(f"Content-rights source {organization} has no binary-approved evidence type: {status}")
        evidence_by_key[key] = source

    observed_counts: dict[tuple[str, str], int] = {}
    public_ids: set[str] = set()
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise SystemExit(f"Opportunity {index} is malformed.")
        organization = item.get("organization")
        opportunity_id = item.get("id")
        if not isinstance(opportunity_id, str) or not opportunity_id.strip():
            raise SystemExit(f"Opportunity {index} is missing id.")
        public_ids.add(opportunity_id)
        source_url = item.get("sourceUrl")
        registration_url = item.get("registrationUrl")
        if not isinstance(organization, str) or not organization.strip():
            raise SystemExit(f"Opportunity {index} is missing organization.")
        source_host = https_host(source_url, f"sourceUrl for opportunity {index}")
        if registration_url != source_url:
            raise SystemExit(f"Opportunity {index} registrationUrl must link to its original source extract.")
        sources = item.get("sources")
        if not isinstance(sources, list) or not any(
            isinstance(source, dict) and source.get("url") == source_url for source in sources
        ):
            raise SystemExit(f"Opportunity {index} does not preserve its original source link in sources.")
        key = (organization, source_host)
        if key not in evidence_by_key:
            raise SystemExit(f"Opportunity {index} has no release-ready content-rights evidence for {organization} at {source_host}.")
        if evidence_by_key[key]["status"] == "original-factual-summary":
            expected = REVIEWED_FACTUAL_RECORDS[key]
            fields = ("id", "title", "sourceUrl", "startDate", "endDate", "city", "region", "address")
            description = item.get("description")
            if (any(item.get(field) != expected[field] for field in fields)
                    or not isinstance(description, str)
                    or hashlib.sha256(description.encode("utf-8")).hexdigest() != expected["descriptionHash"]
                    or type(item.get("ageMin")) is not int or item["ageMin"] != 0
                    or item.get("ageMax") is not None or "ages" in item
                    or item.get("cost") != "Free to join" or item.get("virtual") is not False):
                raise SystemExit(f"Opportunity {index} differs from the reviewed factual record.")
        observed_counts[key] = observed_counts.get(key, 0) + 1

    overlap = public_ids.intersection(restricted_ids)
    if overlap:
        raise SystemExit("Content-rights restricted IDs must not also appear publicly: " + ", ".join(sorted(overlap)))

    expected_counts = {key: source["records"] for key, source in evidence_by_key.items()}
    if observed_counts != expected_counts:
        raise SystemExit(
            "Content-rights source counts do not match feed records: "
            f"expected {expected_counts}, observed {observed_counts}"
        )
    return len(items), len(source_entries)


if len(sys.argv) != 2:
    raise SystemExit("Usage: validate-feed-content-rights.py /absolute/or/relative/opportunities.json")

count, sources = validate(Path(sys.argv[1]))
print(f"Verified content-rights evidence for {count} linked extracts across {sources} sources.")
