#!/usr/bin/env python3
"""Unified Scout document-evidence runner.

This runner keeps the original conservative Document Evidence Worker contracts while
adding evidence-only rule packs for the dynamic demo-exemplar bench. Source PDFs,
images, and other media remain transient and are never uploaded as artifacts.

Supported rule packs:
- water_tank_morphology_v1
- facade_material_glazing_v1
- buyer_organization_contact_v1
- surface_work_condition_v1
- account_portfolio_context_v1
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import tempfile
import time
from urllib.parse import parse_qs, unquote, urlparse

import scout_document_evidence_worker as base

SUPPORTED_RULE_PACKS = {
    "water_tank_morphology_v1",
    "facade_material_glazing_v1",
    "buyer_organization_contact_v1",
    "surface_work_condition_v1",
    "account_portfolio_context_v1",
}
NEW_RULE_PACKS = {"surface_work_condition_v1", "account_portfolio_context_v1"}
EXEMPLAR_MAX_SEARCHES = 2
EXEMPLAR_MAX_PAGES = 10

_ORIGINAL_ANALYZE_PAGE = base.analyze_page

SURFACE_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("cleaning.explicit.exterior", re.compile(r"\b(?:exterior|facade|fa[cç]ade|building)\s+(?:clean(?:ing|ed)?|wash(?:ing|ed)?|pressure\s+wash(?:ing|ed)?|soft\s*wash(?:ing|ed)?)\b|\b(?:clean|wash|pressure\s+wash|soft\s*wash)\s+(?:the\s+)?(?:exterior|facade|fa[cç]ade)\b", re.I)),
    ("cleaning.explicit.brick", re.compile(r"\b(?:clean|wash|pressure\s+wash|soft\s*wash)(?:ing|ed)?\s+(?:the\s+)?brick\b|\bbrick\s+(?:cleaning|washing)\b", re.I)),
    ("cleaning.explicit.eifs", re.compile(r"\b(?:clean|wash)(?:ing|ed)?\s+(?:the\s+)?EIFS\b|\bEIFS\s+(?:cleaning|washing)\b", re.I)),
    ("cleaning.explicit.window_glass", re.compile(r"\b(?:window|glass|glazing)\s+(?:cleaning|washing)\b|\b(?:clean|wash)(?:ing|ed)?\s+(?:the\s+)?(?:windows?|glass|glazing)\b", re.I)),
    ("cleaning.explicit.limestone", re.compile(r"\b(?:clean|wash)(?:ing|ed)?\s+(?:the\s+)?limestone\b|\blimestone\s+(?:cleaning|washing)\b", re.I)),
    ("cleaning.explicit.masonry", re.compile(r"\b(?:clean|wash)(?:ing|ed)?\s+(?:the\s+)?masonry\b|\bmasonry\s+(?:cleaning|washing)\b", re.I)),
    ("condition.organic_growth", re.compile(r"\b(?:algae|mold|mould|mildew|moss|lichen|biological\s+growth|organic\s+growth|microbial\s+growth)\b", re.I)),
    ("condition.staining_soiling", re.compile(r"\b(?:stain(?:ing|ed)?|soiling|discoloration|discolouration|dirt(?:y)?|grime|blackening|black\s+staining)\b", re.I)),
    ("condition.efflorescence", re.compile(r"\befflorescen(?:ce|t)\b", re.I)),
    ("condition.corrosion", re.compile(r"\b(?:corrosion|corroded|rust(?:ing|ed)?|coating\s+failure|paint\s+failure|peeling|flaking)\b", re.I)),
    ("surface_work.paint", re.compile(r"\b(?:exterior\s+)?paint(?:ing|ed)?\b|\brepaint(?:ing|ed)?\b", re.I)),
    ("surface_work.coating", re.compile(r"\b(?:exterior\s+)?coating(?:s)?\b|\brecoat(?:ing|ed)?\b", re.I)),
    ("surface_work.surface_prep", re.compile(r"\b(?:surface\s+preparation|surface\s+prep|prepare\s+(?:the\s+)?surface|pressure\s+wash\s+prior\s+to\s+paint|clean\s+prior\s+to\s+(?:paint|coating))\b", re.I)),
    ("surface_work.tuckpointing", re.compile(r"\b(?:tuck\s*point(?:ing)?|repoint(?:ing)?)\b", re.I)),
    ("surface_work.restoration_rehab", re.compile(r"\b(?:facade|fa[cç]ade|exterior|masonry|tank)\s+(?:restoration|rehabilitation|rehab|renovation)\b", re.I)),
    ("surface_work.sealant", re.compile(r"\b(?:exterior\s+)?sealant(?:s)?\b|\breseal(?:ing|ed)?\b", re.I)),
]

ACCOUNT_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("account.portfolio_language", re.compile(r"\b(?:our\s+)?portfolio\b|\bproperties\b|\bcommunities\b|\bprojects\b|\blocations\b", re.I)),
    ("account.operations_facilities", re.compile(r"\b(?:facilities|facility\s+management|property\s+management|operations|maintenance)\b", re.I)),
    ("account.procurement_vendor", re.compile(r"\b(?:procurement|purchasing|vendor|supplier|subcontractor|trade\s+partner|prequalification|pre-qualification)\b", re.I)),
    ("account.service_area", re.compile(r"\b(?:service\s+area|markets?|regions?|kentucky|indiana|ohio|louisville|lexington|cincinnati)\b", re.I)),
    ("account.project_roster", re.compile(r"\b(?:selected\s+projects|featured\s+projects|project\s+portfolio|project\s+list|our\s+projects)\b", re.I)),
]
PORTFOLIO_COUNT_RE = re.compile(
    r"\b(?P<count>\d{1,4})\s+(?P<unit>properties|communities|hotels|facilities|locations|projects|buildings|sites)\b",
    re.I,
)
YEAR_RE = re.compile(r"\b20(?:2[4-9]|3[0-2])\b")


def _surface_identity(job: dict, text: str) -> float:
    identity = base.identity_confidence(job, text)
    ntext = " " + base.norm(text) + " "
    ctx = job.get("context") or {}
    for value in (ctx.get("address_text"), ctx.get("site_address_text")):
        nvalue = base.norm(value)
        if len(nvalue) >= 6 and f" {nvalue} " in ntext:
            identity = max(identity, 0.96)
    return identity


def analyze_page_extended(
    job: dict,
    text: str,
    source_url: str,
    source_sha: str,
    page_number: int | None,
    title: str | None,
) -> dict | None:
    rule_pack = job.get("rule_pack")
    if rule_pack not in NEW_RULE_PACKS:
        return _ORIGINAL_ANALYZE_PAGE(job, text, source_url, source_sha, page_number, title)

    if rule_pack == "surface_work_condition_v1":
        matches = [(code, pattern) for code, pattern in SURFACE_PATTERNS if pattern.search(text)]
        if not matches:
            return None
        identity = _surface_identity(job, text)
        if identity < 0.90:
            return None
        patterns = [pattern for _, pattern in matches]
        excerpt = base.excerpt_around(text, patterns, 700)
        if not excerpt:
            return None
        codes = sorted({code for code, _ in matches})
        years = sorted({int(y) for y in YEAR_RE.findall(excerpt)})
        extracted: dict[str, object] = {}
        if years:
            extracted["mentioned_years"] = years
        extracted["scope_is_textual_evidence_only"] = True
        confidence = min(0.995, 0.90 + 0.08 * max(0.0, identity - 0.90) / 0.10)
    else:
        matches = [(code, pattern) for code, pattern in ACCOUNT_PATTERNS if pattern.search(text)]
        counts = list(PORTFOLIO_COUNT_RE.finditer(text))
        if not matches and not counts:
            return None
        identity = base.buyer_identity_confidence(job, text, source_url)
        if identity < 0.90:
            return None
        patterns = [pattern for _, pattern in matches]
        if counts:
            patterns.append(PORTFOLIO_COUNT_RE)
        excerpt = base.excerpt_around(text, patterns, 800)
        if not excerpt:
            return None
        codes = sorted({code for code, _ in matches})
        extracted_counts: list[dict[str, object]] = []
        for match in counts[:12]:
            extracted_counts.append({"count": int(match.group("count")), "unit": match.group("unit").lower()})
        if extracted_counts:
            codes.append("account.explicit_portfolio_count")
        codes = sorted(set(codes))
        extracted = {"portfolio_counts": extracted_counts, "account_evidence_only": True}
        confidence = min(0.995, 0.88 + 0.10 * max(0.0, identity - 0.90) / 0.10)

    return {
        "fingerprint": base.finding_fingerprint(str(job["id"]), source_url, page_number, codes, excerpt),
        "source_url": source_url,
        "source_authority": base.document_authority(source_url),
        "source_kind": "public_document" if page_number else "public_web_page",
        "document_title": title,
        "page_number": page_number,
        "evidence_excerpt": excerpt,
        "evidence_codes": codes,
        "extracted_values": extracted,
        "confidence": confidence,
        "identity_confidence": identity,
        "decision_state": "documented" if identity >= 0.95 else "signal_to_investigate",
        "source_sha256": source_sha,
        "observed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "auto_apply": False,
    }


# base.process_document resolves this global at runtime, so extending it here keeps
# acquisition, PDF extraction, hashing, and media-retention behavior centralized.
base.analyze_page = analyze_page_extended


def _search_queries(job: dict) -> list[str]:
    ctx = job.get("context") or {}
    name = str(job.get("display_name") or "").strip()
    org = str(job.get("organization_name") or ctx.get("organization_name") or "").strip()
    address = str(ctx.get("address_text") or ctx.get("site_address_text") or "").strip()
    if job.get("rule_pack") == "surface_work_condition_v1":
        queries = [
            f'"{name}" {org} exterior cleaning facade wash paint coating rehabilitation restoration',
            f'"{address}" cleaning facade brick EIFS limestone window staining algae mold paint coating' if address else "",
        ]
    else:
        queries = [
            f'"{name}" portfolio properties projects facilities procurement vendor',
            f'"{name}" locations service area projects suppliers subcontractors',
        ]
    return [q for q in queries if q.strip()][:EXEMPLAR_MAX_SEARCHES]


def _search_results(job: dict) -> list[str]:
    results: list[str] = []
    for query in _search_queries(job):
        try:
            response = base.SESSION.get(
                "https://html.duckduckgo.com/html/",
                params={"q": query},
                timeout=(12, 30),
                allow_redirects=True,
            )
            response.raise_for_status()
            parser = base.parse_html(response.content)
            for href, _ in parser.links:
                if href.startswith("//duckduckgo.com/l/?"):
                    href = "https:" + href
                if "duckduckgo.com/l/" in href:
                    href = unquote(parse_qs(urlparse(href).query).get("uddg", [""])[0])
                parsed = urlparse(href)
                if parsed.scheme in {"http", "https"} and parsed.hostname and "duckduckgo.com" not in parsed.hostname:
                    results.append(href.split("#", 1)[0])
                if len(results) >= EXEMPLAR_MAX_PAGES * 2:
                    break
        except Exception as exc:
            print(f"exemplar search failed: {type(exc).__name__}: {exc}", flush=True)
        time.sleep(0.4)
    return list(dict.fromkeys(results))


def process_exemplar_job(job: dict) -> tuple[str, list[dict], str | None]:
    urls: list[str] = []
    errors: list[str] = []
    for root in job.get("source_roots") or []:
        if not isinstance(root, str) or not root.startswith(("http://", "https://")):
            continue
        urls.append(root)
        try:
            urls.extend(base.discover_from_root(root, job))
        except Exception as exc:
            errors.append(f"root {root}: {exc}")
    urls.extend(_search_results(job))
    attempt = int(job.get("attempt_count") or 1)
    doc_limit = EXEMPLAR_MAX_PAGES if attempt <= 1 else min(20, EXEMPLAR_MAX_PAGES + 6)
    urls = list(dict.fromkeys(urls))[:doc_limit]

    findings: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="scout-exemplar-evidence-") as temp_dir:
        root_dir = Path(temp_dir)
        for index, url in enumerate(urls):
            work = root_dir / str(index)
            work.mkdir()
            result, error = base.process_document(job, url, work)
            findings.extend(result)
            if error:
                errors.append(f"{url}: {error}")
            time.sleep(0.15)

    # These packs are evidence-only. Direct canonical writes remain limited to the
    # original server-side rule packs. A documented finding is still a completed
    # research job because it materially closes or narrows a missing evidence bit.
    if findings:
        return "completed", findings, None
    if urls and errors and len(errors) >= len(urls):
        return "failed", [], "; ".join(errors[:8])
    return "no_evidence", [], None


def process_job(job: dict) -> tuple[str, list[dict], str | None]:
    if job.get("rule_pack") in NEW_RULE_PACKS:
        return process_exemplar_job(job)
    return base.process_job(job)


def self_test() -> None:
    surface = {
        "id": "00000000-0000-0000-0000-000000000101",
        "rule_pack": "surface_work_condition_v1",
        "display_name": "Lafayette High School",
        "organization_name": "Fayette County Public Schools",
        "context": {},
    }
    text = "Lafayette High School. Exterior walls: clean brick and tuck pointing. Prepare surfaces before exterior coating in 2026."
    finding = analyze_page_extended(surface, text, "https://example.gov/facilities.pdf", "abc", 12, "Facility Plan")
    assert finding and "cleaning.explicit.brick" in finding["evidence_codes"]
    assert "surface_work.tuckpointing" in finding["evidence_codes"]
    assert finding["auto_apply"] is False

    account = {
        "id": "00000000-0000-0000-0000-000000000102",
        "rule_pack": "account_portfolio_context_v1",
        "display_name": "Example Property Management",
        "organization_name": "Example Property Management",
        "source_roots": ["https://example.com/"],
        "context": {},
    }
    text2 = "Example Property Management operates 24 properties across Kentucky and Indiana. Vendors should visit our procurement page."
    finding2 = analyze_page_extended(account, text2, "https://example.com/portfolio", "def", None, "Portfolio")
    assert finding2 and "account.explicit_portfolio_count" in finding2["evidence_codes"]
    assert finding2["extracted_values"]["portfolio_counts"][0]["count"] == 24
    print("exemplar self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        base.self_test()
        self_test()
        return

    if not base.SUPABASE_URL or not base.SERVICE_KEY:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    if not 1 <= base.BATCH_SIZE <= 50:
        raise SystemExit("SCOUT_DOCUMENT_BATCH_SIZE must be between 1 and 50")
    if base.RULE_PACK and base.RULE_PACK not in SUPPORTED_RULE_PACKS:
        raise SystemExit(f"unsupported SCOUT_DOCUMENT_RULE_PACK: {base.RULE_PACK}")

    base.require_poppler()
    seed = base.rpc("internal_seed_exemplar_document_evidence_jobs")
    print(f"exemplar_seed={json.dumps(seed, sort_keys=True)}", flush=True)

    jobs = base.rpc(
        "internal_claim_document_evidence_jobs",
        {"p_limit": base.BATCH_SIZE, "p_rule_pack": base.RULE_PACK},
    )
    print(f"claimed={len(jobs)}", flush=True)
    for job in jobs:
        pack = job.get("rule_pack")
        if pack not in SUPPORTED_RULE_PACKS:
            outcome, findings, error = "failed", [], f"unsupported claimed rule pack: {pack}"
        else:
            print(f"job {job['id']} {pack} {job['display_name']} attempt={job['attempt_count']}", flush=True)
            try:
                outcome, findings, error = process_job(job)
            except Exception as exc:
                outcome, findings, error = "failed", [], f"unhandled worker error: {type(exc).__name__}: {exc}"

        completion_rpc = (
            "internal_complete_buyer_document_evidence_job"
            if pack == "buyer_organization_contact_v1"
            else "internal_complete_document_evidence_job"
        )
        result = base.rpc(
            completion_rpc,
            {"p_job_id": job["id"], "p_outcome": outcome, "p_findings": findings, "p_error": error},
        )
        print(f"complete={json.dumps(result, sort_keys=True)}", flush=True)


if __name__ == "__main__":
    main()
