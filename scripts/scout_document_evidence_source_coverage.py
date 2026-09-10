#!/usr/bin/env python3
"""Bounded source-coverage extensions for Scout's document evidence workers.

This module is intentionally a discovery-layer patch rather than a replacement for
Scout's evidence extractors. It preserves existing identity thresholds, robots.txt
behavior, transient source-media handling, and canonical auto-application contracts.

Coverage improvements:
- Prefer each queue job's curated ``search_query`` instead of silently ignoring it.
- Add bounded public-web discovery for facade and water-tank rule packs.
- Bias search results toward official/public documents without forbidding useful
  lower-authority pages as evidence leads.
- Keep search-discovered facade/tank evidence non-auto-applying unless it comes from
  an official job domain or an authoritative .gov source.
- Give buyer/contact jobs the same queue-aware search behavior, including agriculture.
"""
from __future__ import annotations

from pathlib import Path
import tempfile
import time
from urllib.parse import parse_qs, unquote, urlparse

import scout_document_evidence_runner as runner

base = runner.base

_ORIGINAL_SEARCH_QUERIES = runner._search_queries
_ORIGINAL_PROCESS_JOB = runner.process_job
_ORIGINAL_RUNNER_SELF_TEST = runner.self_test

SEARCHABLE_BASE_PACKS = {"water_tank_morphology_v1", "facade_material_glazing_v1"}
SOCIAL_HOST_SUFFIXES = (
    "facebook.com",
    "instagram.com",
    "linkedin.com",
    "pinterest.com",
    "tiktok.com",
    "x.com",
    "twitter.com",
)
LOWER_AUTHORITY_HOST_SUFFIXES = (
    "bizapedia.com",
    "crexi.com",
    "govwin.com",
    "iq.govwin.com",
    "loopnet.com",
    "starbridge.ai",
)


def _unique_nonempty(values: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for raw in values:
        value = " ".join(str(raw or "").split()).strip()
        if not value or value in seen:
            continue
        seen.add(value)
        out.append(value)
    return out


def _search_queries(job: dict) -> list[str]:
    """Return at most two high-information queries, preferring the seeded query."""
    pack = str(job.get("rule_pack") or "")
    ctx = job.get("context") or {}
    seeded = str(job.get("search_query") or "").strip()
    name = str(job.get("display_name") or "").strip()
    org = str(job.get("organization_name") or ctx.get("organization_name") or "").strip()
    address = str(
        ctx.get("address_text")
        or ctx.get("site_address_text")
        or ctx.get("historic_address_text")
        or ((ctx.get("addresses") or [""])[0] if isinstance(ctx.get("addresses"), list) else "")
        or ""
    ).strip()

    if pack == "water_tank_morphology_v1":
        project_numbers = " ".join(str(x) for x in (ctx.get("project_numbers") or [])[:4])
        fallback = (
            f'"{name}" "{org}" {project_numbers} water tank engineering plans specifications bid '
            "rehabilitation pedesphere composite multi-column multi-leg cross bracing filetype:pdf"
        )
        return _unique_nonempty([seeded, fallback])[:2]

    if pack == "facade_material_glazing_v1":
        historic_names = " ".join(str(x) for x in (ctx.get("historic_resource_names") or [])[:3])
        historic_ref = str(ctx.get("historic_reference_number") or "").strip()
        if historic_names or historic_ref or ctx.get("historic_address_text"):
            fallback = (
                f'"{name}" "{address}" {historic_names} {historic_ref} National Register historic survey '
                "architectural description exterior materials facade glazing filetype:pdf"
            )
        else:
            county = str(ctx.get("county_name") or "").strip()
            state = str(ctx.get("state_code") or "").strip()
            fallback = (
                f'"{name}" "{address}" {county} {state} architectural drawings exterior elevations '
                "facade material glazing curtain wall renovation specification filetype:pdf"
            )
        return _unique_nonempty([seeded, fallback])[:2]

    if pack == "surface_work_condition_v1":
        fallback = (
            f'"{name}" "{address}" {org} bid specifications scope of work exterior cleaning painting '
            "coating facade masonry restoration rehabilitation surface preparation filetype:pdf"
        )
        return _unique_nonempty([seeded, fallback] + _ORIGINAL_SEARCH_QUERIES(job))[:2]

    if pack == "account_portfolio_context_v1":
        fallback = (
            f'"{name}" portfolio projects locations facilities operations supplier procurement vendor '
            "prequalification service area"
        )
        return _unique_nonempty([seeded, fallback] + _ORIGINAL_SEARCH_QUERIES(job))[:2]

    # Livestock and any future extension retain their pack-specific query generator,
    # but the queue's curated query gets first use when present.
    return _unique_nonempty([seeded] + _ORIGINAL_SEARCH_QUERIES(job))[:2]


def _host(url: str) -> str:
    return (urlparse(url).hostname or "").lower().removeprefix("www.")


def _is_social(url: str) -> bool:
    host = _host(url)
    return any(host == suffix or host.endswith("." + suffix) for suffix in SOCIAL_HOST_SUFFIXES)


def _result_quality(url: str, job: dict) -> int:
    """Stable source-priority score; identity/extraction rules remain authoritative."""
    host = _host(url)
    path = (urlparse(url).path or "").lower()
    score = 0
    if base.official_domain_for_job(job, url):
        score += 50
    if host.endswith(".gov") or host.endswith("ky.gov") or host.endswith("kentucky.gov"):
        score += 40
    elif host.endswith(".edu"):
        score += 18
    if path.endswith(".pdf") or ".pdf" in path:
        score += 16
    if any(token in path for token in ("bid", "bids", "spec", "plan", "project", "contract", "procurement", "historic", "register", "survey")):
        score += 10
    if any(host == suffix or host.endswith("." + suffix) for suffix in LOWER_AUTHORITY_HOST_SUFFIXES):
        score -= 20
    return score


def _search_urls(job: dict, queries: list[str] | None = None, result_limit: int | None = None) -> list[str]:
    queries = queries if queries is not None else _search_queries(job)
    max_results = result_limit or max(8, runner.EXEMPLAR_MAX_PAGES * 2)
    ranked: list[tuple[int, int, str]] = []
    ordinal = 0
    for query in queries[:2]:
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
                if parsed.scheme not in {"http", "https"} or not parsed.hostname:
                    continue
                if "duckduckgo.com" in parsed.hostname or _is_social(href):
                    continue
                clean = href.split("#", 1)[0]
                ranked.append((_result_quality(clean, job), ordinal, clean))
                ordinal += 1
                if ordinal >= max_results * 3:
                    break
        except Exception as exc:
            print(f"coverage search failed: {type(exc).__name__}: {exc}", flush=True)
        time.sleep(0.4)

    best: dict[str, tuple[int, int]] = {}
    for score, order, url in ranked:
        previous = best.get(url)
        if previous is None or score > previous[0]:
            best[url] = (score, order)
    ordered = sorted(best.items(), key=lambda item: (-item[1][0], item[1][1], item[0]))
    return [url for url, _ in ordered[:max_results]]


def _queue_aware_buyer_search_results(job: dict) -> list[str]:
    """Bound buyer discovery to the stored query plus one context-specific fallback."""
    ctx = job.get("context") or {}
    seeded = str(job.get("search_query") or "").strip()
    org = str(job.get("organization_name") or ctx.get("organization_name") or "").strip()
    addresses = ctx.get("addresses") or []
    address = str(addresses[0] if isinstance(addresses, list) and addresses else "").strip()

    if ctx.get("research_domain") == "agriculture":
        bridge_name = ""
        for candidate in ctx.get("agriculture_operator_bridge_candidates") or []:
            if isinstance(candidate, dict) and candidate.get("search_hint_only") is True:
                bridge_name = str(candidate.get("operator_name") or "").strip()
                if bridge_name:
                    break
        if bridge_name and address:
            fallback = f'"{bridge_name}" "{address}" farm agriculture contact'
        elif org:
            fallback = f'"{org}" farm agriculture contact phone website operator'
        else:
            fallback = f'"{address}" farm operator agriculture contact'
    else:
        if org:
            fallback = f'"{org}" facilities procurement purchasing vendor supplier contact'
        else:
            fallback = f'"{address}" owner property manager facilities procurement'

    queries = _unique_nonempty([seeded, fallback])[: max(0, base.BUYER_MAX_SEARCHES)]
    if not queries:
        return []
    return _search_urls(job, queries=queries, result_limit=max(8, base.BUYER_MAX_PAGES * 2))


def _trusted_search_source(job: dict, source_url: str) -> bool:
    """Search discovery alone never upgrades a commercial/aggregator page to auto-apply."""
    if base.official_domain_for_job(job, source_url):
        return True
    host = _host(source_url)
    return host.endswith(".gov") or host.endswith("ky.gov") or host.endswith("kentucky.gov")


def _process_urls(job: dict, urls: list[str], prefix: str) -> tuple[list[dict], list[str]]:
    findings: list[dict] = []
    errors: list[str] = []
    with tempfile.TemporaryDirectory(prefix=prefix) as temp_dir:
        root_dir = Path(temp_dir)
        for index, url in enumerate(urls):
            work = root_dir / str(index)
            work.mkdir()
            result, error = base.process_document(job, url, work)
            findings.extend(result)
            if error:
                errors.append(f"{url}: {error}")
            time.sleep(0.15)
    return findings, errors


def _process_searchable_base_job(job: dict) -> tuple[str, list[dict], str | None]:
    """Preserve base-pack semantics, adding search only when primary sources do not close it."""
    primary_urls: list[str] = []
    errors: list[str] = []
    for root in job.get("source_roots") or []:
        if not isinstance(root, str) or not root.startswith(("http://", "https://")):
            continue
        try:
            primary_urls.extend(base.discover_from_root(root, job))
        except Exception as exc:
            errors.append(f"root {root}: {exc}")

    if job.get("rule_pack") == "water_tank_morphology_v1":
        try:
            primary_urls.extend(base.discover_psc_documents(job))
        except Exception as exc:
            errors.append(f"PSC discovery: {exc}")

    attempt = int(job.get("attempt_count") or 1)
    primary_limit = 18 if attempt <= 1 else 30
    primary_urls = list(dict.fromkeys(primary_urls))[:primary_limit]
    primary_findings, primary_errors = _process_urls(
        job, primary_urls, "scout-document-evidence-primary-"
    )
    errors.extend(primary_errors)

    # Keep the mature canonical closure behavior exactly as-is for seeded roots/PSC.
    auto, conflict = base.aggregate_auto_candidate(job, primary_findings)
    if conflict:
        return "needs_review", primary_findings, "conflicting direct document evidence"
    if auto:
        findings = [f for f in primary_findings if f["fingerprint"] != auto["fingerprint"]]
        findings.append(auto)
        return "completed", findings, None

    # Search is fallback coverage, not a replacement for authoritative primary paths.
    search_limit = 6 if attempt <= 1 else 10
    search_urls = [u for u in _search_urls(job, result_limit=search_limit * 2) if u not in set(primary_urls)]
    search_urls = search_urls[:search_limit]
    search_findings, search_errors = _process_urls(
        job, search_urls, "scout-document-evidence-search-"
    )
    errors.extend(search_errors)

    for finding in search_findings:
        values = dict(finding.get("extracted_values") or {})
        values["discovery_basis"] = "bounded_public_web_search"
        finding["extracted_values"] = values
        if not _trusted_search_source(job, str(finding.get("source_url") or "")):
            finding["auto_apply"] = False

    all_findings = primary_findings + search_findings
    trusted_search_findings = [
        f for f in search_findings if _trusted_search_source(job, str(f.get("source_url") or ""))
    ]
    auto, conflict = base.aggregate_auto_candidate(job, primary_findings + trusted_search_findings)
    if conflict:
        return "needs_review", all_findings, "conflicting direct document evidence"
    if auto:
        all_findings = [f for f in all_findings if f["fingerprint"] != auto["fingerprint"]]
        all_findings.append(auto)
        return "completed", all_findings, None
    if all_findings:
        return "no_evidence", all_findings, None
    attempted_urls = primary_urls + search_urls
    if attempted_urls and errors and len(errors) >= len(attempted_urls):
        return "failed", [], "; ".join(errors[:8])
    return "no_evidence", [], None


def process_job(job: dict) -> tuple[str, list[dict], str | None]:
    if job.get("rule_pack") in SEARCHABLE_BASE_PACKS:
        return _process_searchable_base_job(job)
    return _ORIGINAL_PROCESS_JOB(job)


def self_test() -> None:
    _ORIGINAL_RUNNER_SELF_TEST()

    water = {
        "rule_pack": "water_tank_morphology_v1",
        "display_name": "Example Tank",
        "organization_name": "Example Water District",
        "search_query": "SEEDED WATER QUERY",
        "context": {"project_numbers": ["2026-001"], "addresses": []},
    }
    water_queries = _search_queries(water)
    assert water_queries[0] == "SEEDED WATER QUERY"
    assert "specifications" in water_queries[1] and "multi-leg" in water_queries[1]

    facade = {
        "rule_pack": "facade_material_glazing_v1",
        "display_name": "Example Historic Hall",
        "search_query": "SEEDED FACADE QUERY",
        "context": {
            "historic_reference_number": "NR-123",
            "historic_address_text": "100 Main Street",
            "historic_resource_names": ["Example Hall"],
        },
    }
    facade_queries = _search_queries(facade)
    assert facade_queries[0] == "SEEDED FACADE QUERY"
    assert "National Register" in facade_queries[1]

    buyer = {
        "rule_pack": "buyer_organization_contact_v1",
        "organization_name": "Example University",
        "search_query": "SEEDED BUYER QUERY",
        "context": {"addresses": ["100 Campus Drive"]},
    }
    assert _unique_nonempty([buyer["search_query"], buyer["search_query"]]) == ["SEEDED BUYER QUERY"]
    print("source coverage self-test passed")


# Monkey-patch only discovery/orchestration seams. Extractors and evidence thresholds
# remain owned by the existing worker/runner modules.
runner._search_queries = _search_queries
runner._search_results = lambda job: _search_urls(job)
base.discover_buyer_search_results = _queue_aware_buyer_search_results
runner.process_job = process_job
runner.self_test = self_test
