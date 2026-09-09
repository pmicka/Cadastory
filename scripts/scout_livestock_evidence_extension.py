#!/usr/bin/env python3
"""Evidence-only livestock type/count extension for Scout's Document Evidence Worker."""
from __future__ import annotations

import re
import time

import scout_document_evidence_runner as runner

base = runner.base
RULE_PACK = "livestock_inventory_v1"

runner.SUPPORTED_RULE_PACKS.add(RULE_PACK)
runner.NEW_RULE_PACKS.add(RULE_PACK)

_ORIGINAL_ANALYZE = runner.analyze_page_extended
_ORIGINAL_SEARCH_QUERIES = runner._search_queries

ANIMAL_TERMS = (
    r"beef\s+cattle|dairy\s+cattle|cattle|cows?|calves?|heifers?|steers?|bulls?|"
    r"horses?|mares?|stallions?|ponies|goats?|sheep|lambs?|"
    r"hogs?|pigs?|swine|sows?|boars?|"
    r"chickens?|hens?|broilers?|layers?|pullets?|turkeys?|poults?|ducks?|"
    r"alpacas?|llamas?|bison"
)
ANIMAL_RE = re.compile(rf"\b(?P<animal>{ANIMAL_TERMS})\b", re.I)
COUNT_FIRST_RE = re.compile(
    rf"\b(?P<count>\d{{1,3}}(?:,\d{{3}})*|\d{{1,7}})\s+"
    rf"(?:head(?:\s+of)?\s+)?(?P<animal>{ANIMAL_TERMS})\b",
    re.I,
)
ANIMAL_FIRST_RE = re.compile(
    rf"\b(?P<animal>{ANIMAL_TERMS})\b\s*"
    rf"(?:[:=]|[-–—]|\b(?:count|number|capacity|maximum|max|inventory)\b)\s*"
    rf"(?P<count>\d{{1,3}}(?:,\d{{3}})*|\d{{1,7}})\b",
    re.I,
)
HERD_FLOCK_RE = re.compile(
    rf"\b(?:herd|flock)\s+of\s+(?P<count>\d{{1,3}}(?:,\d{{3}})*|\d{{1,7}})\s+"
    rf"(?P<animal>{ANIMAL_TERMS})\b",
    re.I,
)


def _normalize_animal(raw: str) -> str:
    value = base.norm(raw)
    if "dairy" in value:
        return "dairy_cattle"
    if "beef" in value:
        return "beef_cattle"
    if any(t in value.split() for t in ("cattle", "cow", "cows", "calf", "calves", "heifer", "heifers", "steer", "steers", "bull", "bulls")):
        return "cattle"
    if any(t in value.split() for t in ("horse", "horses", "mare", "mares", "stallion", "stallions", "ponies")):
        return "horses"
    if "goat" in value or "goats" in value:
        return "goats"
    if any(t in value.split() for t in ("sheep", "lamb", "lambs")):
        return "sheep"
    if any(t in value.split() for t in ("hog", "hogs", "pig", "pigs", "swine", "sow", "sows", "boar", "boars")):
        return "swine"
    if any(t in value.split() for t in ("chicken", "chickens", "hen", "hens", "broiler", "broilers", "layer", "layers", "pullet", "pullets")):
        return "chickens"
    if any(t in value.split() for t in ("turkey", "turkeys", "poult", "poults")):
        return "turkeys"
    if "duck" in value or "ducks" in value:
        return "ducks"
    if "alpaca" in value or "alpacas" in value:
        return "alpacas"
    if "llama" in value or "llamas" in value:
        return "llamas"
    if "bison" in value:
        return "bison"
    return value.replace(" ", "_") or "unknown"


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

    # A common farm name on an unrelated search result is not enough for documented identity.
    return min(identity, 0.90)


def _extract_counts(text: str) -> list[dict[str, object]]:
    found: list[dict[str, object]] = []
    seen: set[tuple[str, int, str]] = set()
    for pattern, basis in (
        (HERD_FLOCK_RE, "explicit_herd_or_flock_count"),
        (COUNT_FIRST_RE, "explicit_number_adjacent_to_animal"),
        (ANIMAL_FIRST_RE, "explicit_labeled_animal_count"),
    ):
        for match in pattern.finditer(text):
            count = int(match.group("count").replace(",", ""))
            if count <= 0 or count > 20_000_000:
                continue
            animal_raw = match.group("animal")
            animal_class = _normalize_animal(animal_raw)
            key = (animal_class, count, basis)
            if key in seen:
                continue
            seen.add(key)
            found.append({
                "animal_class": animal_class,
                "animal_term": animal_raw,
                "count": count,
                "count_basis": basis,
                "count_is_live_inventory": False,
            })
    return found[:40]


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

    animal_matches = list(ANIMAL_RE.finditer(text))
    if not animal_matches:
        return None

    identity = _farm_identity(job, text, source_url)
    if identity < 0.90:
        return None

    counts = _extract_counts(text)
    animal_types = sorted({_normalize_animal(m.group("animal")) for m in animal_matches})
    codes = [f"livestock.type.{animal}" for animal in animal_types]
    if counts:
        codes.append("livestock.count.explicit")
    codes = sorted(set(codes))

    patterns = [ANIMAL_RE]
    if counts:
        patterns.extend([COUNT_FIRST_RE, ANIMAL_FIRST_RE, HERD_FLOCK_RE])
    excerpt = base.excerpt_around(text, patterns, 900)
    if not excerpt:
        return None

    extracted = {
        "animal_types": animal_types,
        "animal_counts": counts,
        "count_semantics": "explicit textual evidence only; source may describe capacity, maximum, herd size, or another reported count; never assume live on-the-ground inventory without source wording",
        "auto_apply_disabled": True,
    }
    confidence = 0.985 if counts and identity >= 0.95 else (0.95 if identity >= 0.95 else 0.72)

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
        "decision_state": "documented" if identity >= 0.95 else "signal_to_investigate",
        "source_sha256": source_sha,
        "observed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "auto_apply": False,
    }


def _search_queries(job: dict) -> list[str]:
    if job.get("rule_pack") != RULE_PACK:
        return _ORIGINAL_SEARCH_QUERIES(job)
    ctx = job.get("context") or {}
    name = str(job.get("display_name") or "").strip()
    addresses = [str(a).strip() for a in (ctx.get("addresses") or []) if str(a).strip()]
    address = addresses[0] if addresses else ""
    kinds = " ".join(str(k) for k in (ctx.get("known_enterprise_kinds") or []))
    queries = [
        f'"{name}" {kinds} livestock herd flock cattle cows calves horses goats sheep pigs poultry animal count head',
        f'"{name}" "{address}" farm livestock herd cattle cows horses goats pigs poultry' if address else "",
    ]
    return [q for q in queries if q.strip()][:2]


runner.analyze_page_extended = analyze_page_extended
base.analyze_page = analyze_page_extended
runner._search_queries = _search_queries


def self_test() -> None:
    job = {
        "id": "00000000-0000-0000-0000-000000000201",
        "rule_pack": RULE_PACK,
        "display_name": "Example Cattle Farm",
        "organization_name": "Example Cattle Farm",
        "source_roots": ["https://example.com/"],
        "context": {
            "known_parties": ["Example Cattle Farm"],
            "addresses": ["100 Farm Road, Example, KY 40000"],
            "known_enterprise_kinds": ["beef"],
        },
    }
    text = "Example Cattle Farm at 100 Farm Road, Example, KY 40000 maintains a herd of 240 cattle and 18 horses."
    finding = analyze_page_extended(job, text, "https://example.com/herd", "abc", None, "Our Herd")
    assert finding is not None
    pairs = {(x["animal_class"], x["count"]) for x in finding["extracted_values"]["animal_counts"]}
    assert ("cattle", 240) in pairs
    assert ("horses", 18) in pairs
    assert finding["auto_apply"] is False
    assert finding["decision_state"] == "documented"

    generic = {
        "id": "00000000-0000-0000-0000-000000000202",
        "rule_pack": RULE_PACK,
        "display_name": "Green Farm",
        "organization_name": "Green Farm",
        "source_roots": [],
        "context": {"known_parties": ["Green Farm"], "addresses": []},
    }
    weak = analyze_page_extended(generic, "Green Farm raises 300 cattle.", "https://unrelated.example.org/page", "def", None, None)
    assert weak is not None and weak["decision_state"] == "signal_to_investigate"
    print("livestock evidence extension self-test passed")
