#!/usr/bin/env python3
"""Conservative farm-to-field operation evidence extension for Scout.

This rule pack researches whether a known livestock farm can be tied to one of
Scout's already-ranked pasture candidates. Parcel ownership and proximity remain
supporting context only; automatic bridge corroboration requires an exact numbered
candidate property-address match plus explicit operation/lease/management/grazing/
pasture-use language. Source media remains transient.
"""
from __future__ import annotations

import re
import time

import scout_document_evidence_runner as runner

base = runner.base
RULE_PACK = "farm_field_operation_v1"

runner.SUPPORTED_RULE_PACKS.add(RULE_PACK)
runner.NEW_RULE_PACKS.add(RULE_PACK)

_ORIGINAL_ANALYZE = runner.analyze_page_extended
_ORIGINAL_SEARCH_QUERIES = runner._search_queries

OPERATE_RE = re.compile(r"\b(?:operates?|operating|operation\s+at|operated\s+by)\b", re.I)
LEASE_RE = re.compile(r"\b(?:leases?|leased|leasing|rents?|rented|renting)\b", re.I)
MANAGE_RE = re.compile(r"\b(?:manages?|managed|managing)\b", re.I)
GRAZE_RE = re.compile(r"\b(?:grazes?|grazed|grazing)\b", re.I)
PASTURE_USE_RE = re.compile(
    r"\b(?:uses?|using|maintains?|keeps?|runs?|raises?)\b.{0,100}\b(?:pasture|pastures|grazing\s+land)\b|"
    r"\b(?:pastures?|grazing\s+land)\b.{0,100}\b(?:cattle|cows?|calves?|heifers?|horses?|livestock|herd)\b|"
    r"\b(?:cattle|cows?|calves?|heifers?|horses?|livestock|herd)\b.{0,100}\b(?:pasture|pastures|grazing\s+land)\b",
    re.I | re.S,
)
OWN_RE = re.compile(r"\b(?:owns?|owned|ownership|property\s+of|land\s+owned\s+by)\b", re.I)

_SUFFIX = {
    "road": "rd", "rd": "rd", "street": "st", "st": "st",
    "lane": "ln", "ln": "ln", "drive": "dr", "dr": "dr",
    "highway": "hwy", "hwy": "hwy", "avenue": "ave", "ave": "ave",
    "boulevard": "blvd", "blvd": "blvd", "court": "ct", "ct": "ct",
    "circle": "cir", "cir": "cir", "parkway": "pkwy", "pkwy": "pkwy",
    "route": "rte", "rte": "rte",
}
_ROUTE_HINTS = {"us", "state", "ky", "in", "oh", "sr", "rte"}


def _canonical_tokens(value: object) -> list[str]:
    tokens = base.norm(value).split()
    return [_SUFFIX.get(token, token) for token in tokens]


def _has_numbered_property_address(value: object) -> bool:
    """Require a plausible street number, not merely a numbered highway/route name."""
    tokens = _canonical_tokens(value)
    if not tokens:
        return False
    if tokens[0].isdigit() and 1 <= len(tokens[0]) <= 6:
        return True
    if len(tokens) >= 3 and tokens[-1].isdigit() and 1 <= len(tokens[-1]) <= 6:
        if any(token in _ROUTE_HINTS for token in tokens[:-1]) or tokens[-2] == "hwy":
            return False
        return tokens[-2] in {"rd", "st", "ln", "dr", "ave", "blvd", "ct", "cir", "pkwy", "pl"}
    return False


def _address_variants(value: object) -> list[str]:
    tokens = _canonical_tokens(value)
    if not tokens:
        return []
    variants = [" ".join(tokens)]
    # Some assessor feeds expose "DOVER ROAD 8729" while ordinary documents use
    # "8729 Dover Road". Reorder only when the terminal token is clearly a street number.
    if len(tokens) >= 3 and tokens[-1].isdigit() and not tokens[0].isdigit():
        variants.append(" ".join([tokens[-1]] + tokens[:-1]))
    return list(dict.fromkeys(variants))


def _exact_address_in_text(value: object, text: str) -> tuple[bool, str | None]:
    ntext = " " + " ".join(_canonical_tokens(text)) + " "
    for variant in _address_variants(value):
        if len(variant) >= 7 and f" {variant} " in ntext:
            return True, variant
    return False, None


def _exact_phrase_in_text(value: object, text: str) -> bool:
    phrase = base.norm(value)
    return len(phrase) >= 5 and f" {phrase} " in (" " + base.norm(text) + " ")


def _farm_identity(job: dict, text: str, source_url: str) -> float:
    identity = base.buyer_identity_confidence(job, text, source_url)
    name = base.norm(job.get("display_name"))
    tokens = [t for t in name.split() if t]
    generic = len(name) < 14 or len(tokens) <= 2
    if identity < 0.95 or not generic:
        return identity
    if base.official_domain_for_job(job, source_url):
        return identity

    ntext = " " + base.norm(text) + " "
    ctx = job.get("context") or {}
    for address in ctx.get("addresses") or []:
        naddr = base.norm(address)
        if len(naddr) >= 8 and f" {naddr} " in ntext:
            return identity
    county = base.norm(ctx.get("county_name"))
    if county and f" {county} " in ntext:
        return identity

    # Generic farm names are too collision-prone to accept on an unrelated domain.
    return min(identity, 0.90)


def _operation_codes(text: str) -> tuple[list[str], list[re.Pattern[str]]]:
    codes: list[str] = []
    patterns: list[re.Pattern[str]] = []
    for code, pattern in (
        ("field.explicit_operates", OPERATE_RE),
        ("field.explicit_leases", LEASE_RE),
        ("field.explicit_manages", MANAGE_RE),
        ("field.explicit_grazes", GRAZE_RE),
        ("field.explicit_pasture_use", PASTURE_USE_RE),
    ):
        if pattern.search(text):
            codes.append(code)
            patterns.append(pattern)
    return codes, patterns


def _field_matches(job: dict, text: str) -> list[dict[str, object]]:
    ctx = job.get("context") or {}
    matches: list[dict[str, object]] = []
    for raw in ctx.get("candidate_fields") or []:
        if not isinstance(raw, dict) or not raw.get("field_id"):
            continue
        property_match = None
        property_variant = None
        for address in raw.get("property_addresses") or []:
            # Road-name-only assessor records are useful context but are never exact
            # field-attribution anchors.
            if not _has_numbered_property_address(address):
                continue
            matched, variant = _exact_address_in_text(address, text)
            if matched:
                property_match = str(address)
                property_variant = variant
                break
        owner_match = next(
            (str(owner) for owner in (raw.get("parcel_owner_names") or []) if _exact_phrase_in_text(owner, text)),
            None,
        )
        mailing_match = None
        for address in raw.get("parcel_mailing_addresses") or []:
            matched, _ = _exact_address_in_text(address, text)
            if matched:
                mailing_match = str(address)
                break
        if property_match or owner_match or mailing_match:
            matches.append({
                "field": raw,
                "property_match": property_match,
                "property_variant": property_variant,
                "owner_match": owner_match,
                "mailing_match": mailing_match,
            })
    return matches


def _best_field_match(job: dict, text: str) -> dict[str, object] | None:
    matches = _field_matches(job, text)
    if not matches:
        return None

    def key(item: dict[str, object]) -> tuple[int, int, int]:
        field = item["field"]
        assert isinstance(field, dict)
        specificity = 0 if item.get("property_match") else (1 if item.get("owner_match") else 2)
        rank = int(field.get("candidate_rank") or 999)
        distance = int(field.get("distance_m") or 999999)
        return specificity, rank, distance

    return sorted(matches, key=key)[0]


def analyze_page_extended(
    job: dict,
    text: str,
    source_url: str,
    source_sha: str,
    page_number: int | None,
    title: str | None,
) -> dict | None:
    if job.get("rule_pack") != RULE_PACK:
        return _ORIGINAL_ANALYZE(job, text, source_url, source_sha, page_number, title)

    identity = _farm_identity(job, text, source_url)
    if identity < 0.90:
        return None

    field_match = _best_field_match(job, text)
    if field_match is None:
        return None
    field = field_match["field"]
    assert isinstance(field, dict)

    operation_codes, operation_patterns = _operation_codes(text)
    ownership = bool(OWN_RE.search(text))
    if not operation_codes and not ownership:
        return None

    codes = list(operation_codes)
    patterns: list[re.Pattern[str]] = list(operation_patterns)
    matched_property = field_match.get("property_match")
    matched_owner = field_match.get("owner_match")
    matched_mailing = field_match.get("mailing_match")

    if matched_property:
        codes.append("property.address_exact_candidate")
        patterns.append(re.compile(re.escape(str(matched_property)), re.I))
    if matched_owner:
        codes.append("parcel.owner_exact_candidate")
        patterns.append(re.compile(re.escape(str(matched_owner)), re.I))
    if matched_mailing:
        codes.append("parcel.mailing_address_exact_candidate")
    if ownership:
        codes.append("property.explicit_owned_by_farm")
        patterns.append(OWN_RE)

    codes = sorted(set(codes))
    direct_operation = bool(operation_codes)
    exact_property = bool(matched_property)

    if exact_property and direct_operation and identity >= 0.98:
        confidence = 0.985
        decision_state = "documented"
        auto_apply = True
    elif exact_property and direct_operation and identity >= 0.95:
        confidence = 0.95
        decision_state = "documented"
        auto_apply = False
    elif exact_property and ownership and identity >= 0.95:
        confidence = 0.90
        decision_state = "documented"
        auto_apply = False
    else:
        confidence = 0.80 if direct_operation else 0.72
        decision_state = "signal_to_investigate"
        auto_apply = False

    excerpt = base.excerpt_around(text, patterns, 1100)
    if not excerpt:
        return None

    extracted = {
        "field_id": str(field.get("field_id")),
        "candidate_rank": field.get("candidate_rank"),
        "distance_m": field.get("distance_m"),
        "profile_class": field.get("profile_class"),
        "grazing_relevance": field.get("grazing_relevance"),
        "matched_property_address": matched_property,
        "matched_property_address_variant": field_match.get("property_variant"),
        "matched_parcel_owner": matched_owner,
        "matched_parcel_mailing_address": matched_mailing,
        "field_specificity": "exact_numbered_property_address" if exact_property else "parcel_context_only",
        "operation_semantics": operation_codes,
        "ownership_language_present": ownership,
        "ownership_alone_never_establishes_operation": True,
        "road_name_only_never_establishes_operation": True,
        "source_media_retention": "transient_only",
    }

    return {
        "fingerprint": base.finding_fingerprint(str(job["id"]), source_url, page_number, codes, excerpt),
        "source_url": source_url,
        "source_authority": base.document_authority(source_url),
        "source_kind": "public_document" if page_number else "public_web_page",
        "document_title": title,
        "page_number": page_number,
        "evidence_excerpt": excerpt[:4000],
        "evidence_codes": codes,
        "extracted_values": extracted,
        "confidence": confidence,
        "identity_confidence": identity,
        "decision_state": decision_state,
        "source_sha256": source_sha,
        "observed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "auto_apply": auto_apply,
    }


def _search_queries(job: dict) -> list[str]:
    if job.get("rule_pack") != RULE_PACK:
        return _ORIGINAL_SEARCH_QUERIES(job)
    ctx = job.get("context") or {}
    name = str(job.get("display_name") or "").strip()
    county = str(ctx.get("county_name") or "").strip()
    state = str(ctx.get("state_code") or "").strip()
    fields = [x for x in (ctx.get("candidate_fields") or []) if isinstance(x, dict)]
    fields.sort(key=lambda x: (0 if any(_has_numbered_property_address(a) for a in (x.get("property_addresses") or [])) else 1, int(x.get("candidate_rank") or 999)))

    property_address = ""
    owner = ""
    if fields:
        addresses = [str(a).strip() for a in (fields[0].get("property_addresses") or []) if _has_numbered_property_address(a)]
        owners = fields[0].get("parcel_owner_names") or []
        property_address = addresses[0] if addresses else ""
        owner = str(owners[0]).strip() if owners else ""

    best_address = str((ctx.get("addresses") or [""])[0] or "").strip()
    queries = [
        f'"{name}" "{property_address}" operates leases manages grazes pasture farm acreage' if property_address else
        f'"{name}" "{best_address}" operates leases manages grazes pasture farm acreage',
        f'"{name}" "{owner}" {county} {state} farm lease pasture property acreage' if owner else
        f'"{name}" {county} {state} farm property acreage pasture grazing lease',
    ]
    return [q for q in queries if q.strip()][:2]


runner.analyze_page_extended = analyze_page_extended
base.analyze_page = analyze_page_extended
runner._search_queries = _search_queries


def self_test() -> None:
    field_id = "00000000-0000-0000-0000-000000000301"
    job = {
        "id": "00000000-0000-0000-0000-000000000302",
        "rule_pack": RULE_PACK,
        "display_name": "Example Cattle Farm",
        "organization_name": "Example Cattle Farm",
        "source_roots": ["https://example.com/"],
        "context": {
            "known_parties": ["Example Cattle Farm"],
            "addresses": ["100 Farm Road, Example, KY 40000"],
            "county_name": "Example County",
            "state_code": "KY",
            "candidate_fields": [{
                "field_id": field_id,
                "candidate_rank": 1,
                "distance_m": 80,
                "profile_class": "persistent_pasture",
                "grazing_relevance": "high",
                "property_addresses": ["500 Pasture Road Example KY 40000"],
                "parcel_owner_names": ["Example Land LLC"],
                "parcel_mailing_addresses": ["10 Owner Lane Example KY 40000"],
            }],
        },
    }

    strong = analyze_page_extended(
        job,
        "Example Cattle Farm operates and grazes cattle on the pasture at 500 Pasture Road Example KY 40000.",
        "https://example.com/our-farm",
        "abc",
        None,
        "Our Farm",
    )
    assert strong is not None
    assert strong["extracted_values"]["field_id"] == field_id
    assert "property.address_exact_candidate" in strong["evidence_codes"]
    assert "field.explicit_operates" in strong["evidence_codes"]
    assert "field.explicit_grazes" in strong["evidence_codes"]
    assert strong["auto_apply"] is True

    ownership = analyze_page_extended(
        job,
        "Example Cattle Farm owns the property at 500 Pasture Road Example KY 40000.",
        "https://example.com/property",
        "def",
        None,
        "Property",
    )
    assert ownership is not None
    assert "property.explicit_owned_by_farm" in ownership["evidence_codes"]
    assert ownership["auto_apply"] is False

    unrelated = analyze_page_extended(
        job,
        "Example Cattle Farm operates pasture at 999 Other Road Example KY 40000.",
        "https://example.com/other",
        "ghi",
        None,
        "Other",
    )
    assert unrelated is None

    reversed_address_job = dict(job)
    reversed_address_job["context"] = dict(job["context"])
    reversed_address_job["context"]["candidate_fields"] = [dict(job["context"]["candidate_fields"][0])]
    reversed_address_job["context"]["candidate_fields"][0]["property_addresses"] = ["PASTURE ROAD 500"]
    reversed_match = analyze_page_extended(
        reversed_address_job,
        "Example Cattle Farm grazes livestock on pasture at 500 Pasture Road.",
        "https://example.com/grazing",
        "jkl",
        None,
        "Grazing",
    )
    assert reversed_match is not None and "property.address_exact_candidate" in reversed_match["evidence_codes"]

    road_only_job = dict(job)
    road_only_job["context"] = dict(job["context"])
    road_only_job["context"]["candidate_fields"] = [dict(job["context"]["candidate_fields"][0])]
    road_only_job["context"]["candidate_fields"][0]["property_addresses"] = ["Pasture Road"]
    road_only_job["context"]["candidate_fields"][0]["parcel_owner_names"] = []
    road_only_job["context"]["candidate_fields"][0]["parcel_mailing_addresses"] = []
    road_only = analyze_page_extended(
        road_only_job,
        "Example Cattle Farm operates pasture along Pasture Road.",
        "https://example.com/road-only",
        "pqr",
        None,
        "Road-only",
    )
    assert road_only is None

    generic = {
        "id": "00000000-0000-0000-0000-000000000303",
        "rule_pack": RULE_PACK,
        "display_name": "Green Farm",
        "organization_name": "Green Farm",
        "source_roots": [],
        "context": {
            "known_parties": ["Green Farm"],
            "county_name": "Example County",
            "candidate_fields": [{
                "field_id": field_id,
                "candidate_rank": 1,
                "distance_m": 40,
                "property_addresses": ["500 Pasture Road"],
                "parcel_owner_names": [],
                "parcel_mailing_addresses": [],
            }],
        },
    }
    weak = analyze_page_extended(
        generic,
        "Green Farm operates pasture at 500 Pasture Road.",
        "https://unrelated.example.org/page",
        "mno",
        None,
        None,
    )
    assert weak is not None
    assert weak["decision_state"] == "signal_to_investigate"
    assert weak["auto_apply"] is False

    print("farm field-operation evidence extension self-test passed")
