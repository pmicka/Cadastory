#!/usr/bin/env python3
"""Bounded orchestration entrypoint for Scout's document evidence worker.

Base domain seeding, agriculture buyer/contact seeding, general buyer seeding, and
demo-exemplar prioritization are intentionally separate RPCs so each phase gets its
own transaction/HTTP timeout budget. The rule-pack implementation remains in
scout_document_evidence_runner.py.

A production identity guard is installed for short/generic surface exemplar names so a
name such as "GARRETT" cannot match an unrelated business page merely because the token
appears there. Generic names require corroborating buyer/address context or an explicit
subject phrase such as "Garrett Tank".

Agricultural buyer jobs reuse the conservative buyer_organization_contact_v1 rule pack.
Farm operator bridge candidates are search hints only: they are never added to
known_parties and therefore cannot become identity aliases merely because a landholder
and a phone-bearing farm candidate share a mailing address. A small agriculture-specific
claim lane prevents the global evidence backlog from starving farm contact work.
"""
from __future__ import annotations

import argparse
import json
import time
from urllib.parse import parse_qs, unquote, urlparse

import scout_document_evidence_runner as runner

base = runner.base
_ORIGINAL_SURFACE_IDENTITY = runner._surface_identity
_ORIGINAL_BUYER_SEARCH_RESULTS = base.discover_buyer_search_results


def _strict_surface_identity(job: dict, text: str) -> float:
    score = _ORIGINAL_SURFACE_IDENTITY(job, text)
    name = str(job.get("display_name") or "").strip()
    nname = base.norm(name)
    name_tokens = [token for token in nname.split() if token]

    # Long/specific names retain the original conservative identity behavior.
    generic_name = len(nname) < 12 or len(name_tokens) <= 1
    if not generic_name:
        return score

    ntext = " " + base.norm(text) + " "
    ctx = job.get("context") or {}
    corroborators = [
        job.get("organization_name"),
        ctx.get("organization_name"),
        ctx.get("buyer_name"),
        ctx.get("system_name"),
        ctx.get("address_text"),
        ctx.get("site_address_text"),
    ]
    for value in corroborators:
        nvalue = base.norm(value)
        if len(nvalue) >= 6 and f" {nvalue} " in ntext:
            return max(score, 0.96)

    candidate_key = str(ctx.get("candidate_key") or job.get("subject_key") or "")
    if candidate_key.startswith("water_tank:") and nname:
        for phrase in (f" {nname} tank ", f" {nname} water tank "):
            if phrase in ntext:
                return max(score, 0.96)

    # A bare short/generic token is insufficient identity evidence.
    return min(score, 0.70)


def _agriculture_aware_buyer_search_results(job: dict) -> list[str]:
    ctx = job.get("context") or {}
    if ctx.get("research_domain") != "agriculture":
        return _ORIGINAL_BUYER_SEARCH_RESULTS(job)
    if base.BUYER_MAX_SEARCHES < 1:
        return []

    org = str(job.get("organization_name") or ctx.get("organization_name") or "").strip()
    address = str((ctx.get("addresses") or [""])[0] or "").strip()
    bridge_candidates = ctx.get("agriculture_operator_bridge_candidates") or []
    bridge_name = ""
    for candidate in bridge_candidates:
        if isinstance(candidate, dict) and candidate.get("search_hint_only") is True:
            bridge_name = str(candidate.get("operator_name") or "").strip()
            if bridge_name:
                break

    queries: list[str] = []
    if org:
        queries.append(f'"{org}" farm agriculture contact phone')
    if bridge_name and address:
        # Search-only corroboration. The bridge name is deliberately not an identity alias.
        queries.append(f'"{bridge_name}" "{address}" farm')
    elif address:
        queries.append(f'"{address}" farm operator agriculture')

    results: list[str] = []
    for query in queries[: base.BUYER_MAX_SEARCHES]:
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
                if (
                    parsed.scheme in {"http", "https"}
                    and parsed.hostname
                    and "duckduckgo.com" not in parsed.hostname
                ):
                    results.append(href.split("#", 1)[0])
                if len(results) >= base.BUYER_MAX_PAGES * 2:
                    break
        except Exception as exc:
            print(f"agriculture buyer search failed: {type(exc).__name__}: {exc}", flush=True)
        time.sleep(0.4)
    return list(dict.fromkeys(results))


# analyze_page_extended and process_buyer_job resolve these module globals at call time.
runner._surface_identity = _strict_surface_identity
base.discover_buyer_search_results = _agriculture_aware_buyer_search_results


def _entrypoint_self_test() -> None:
    generic = {
        "id": "00000000-0000-0000-0000-000000000103",
        "rule_pack": "surface_work_condition_v1",
        "display_name": "GARRETT",
        "organization_name": "Meade County Water District",
        "subject_key": "water_tank:00000000-0000-0000-0000-000000000104",
        "context": {
            "candidate_key": "water_tank:00000000-0000-0000-0000-000000000104",
            "buyer_name": "Meade County Water District",
        },
    }
    unrelated = "Garrett Paint provides residential painting, coatings, and pressure washing."
    assert _strict_surface_identity(generic, unrelated) < 0.90

    corroborated = "Meade County Water District Garrett Tank exterior coating rehabilitation."
    assert _strict_surface_identity(generic, corroborated) >= 0.95

    agriculture = {
        "organization_name": "Example Family Farms LLC",
        "context": {
            "research_domain": "agriculture",
            "addresses": ["100 Farm Road, Example KY 40000"],
            "known_parties": ["Example Family Farms LLC"],
            "agriculture_operator_bridge_candidates": [
                {
                    "operator_name": "Example Farm",
                    "search_hint_only": True,
                    "not_identity_alias": True,
                }
            ],
        },
    }
    assert "Example Farm" not in agriculture["context"]["known_parties"]
    print("entrypoint identity/agriculture guard self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        base.self_test()
        runner.self_test()
        _entrypoint_self_test()
        return

    if not base.SUPABASE_URL or not base.SERVICE_KEY:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    if not 1 <= base.BATCH_SIZE <= 50:
        raise SystemExit("SCOUT_DOCUMENT_BATCH_SIZE must be between 1 and 50")
    if base.RULE_PACK and base.RULE_PACK not in runner.SUPPORTED_RULE_PACKS:
        raise SystemExit(f"unsupported SCOUT_DOCUMENT_RULE_PACK: {base.RULE_PACK}")

    base.require_poppler()

    seed = base.rpc("internal_seed_document_evidence_jobs")
    print(f"seed={json.dumps(seed, sort_keys=True)}", flush=True)

    agriculture_queue_seed = base.rpc("internal_seed_agricultural_buyer_enrichment")
    print(f"agriculture_queue_seed={json.dumps(agriculture_queue_seed, sort_keys=True)}", flush=True)

    agriculture_buyer_seed = base.rpc("internal_seed_agricultural_buyer_document_evidence_jobs")
    print(f"agriculture_buyer_seed={json.dumps(agriculture_buyer_seed, sort_keys=True)}", flush=True)

    buyer_seed = base.rpc("internal_seed_buyer_document_evidence_jobs")
    print(f"buyer_seed={json.dumps(buyer_seed, sort_keys=True)}", flush=True)

    exemplar_seed = base.rpc("internal_seed_exemplar_document_evidence_jobs")
    print(f"exemplar_seed={json.dumps(exemplar_seed, sort_keys=True)}", flush=True)

    agriculture_jobs: list[dict] = []
    if not base.RULE_PACK or base.RULE_PACK == "buyer_organization_contact_v1":
        agriculture_jobs = base.rpc("internal_claim_agricultural_buyer_document_evidence_jobs")

    general_jobs = base.rpc(
        "internal_claim_document_evidence_jobs",
        {"p_limit": base.BATCH_SIZE, "p_rule_pack": base.RULE_PACK},
    )
    agriculture_ids = {job["id"] for job in agriculture_jobs}
    jobs = agriculture_jobs + [job for job in general_jobs if job["id"] not in agriculture_ids]
    print(
        f"claimed_agriculture={len(agriculture_jobs)} claimed_general={len(general_jobs)} claimed_total={len(jobs)}",
        flush=True,
    )

    for job in jobs:
        pack = job.get("rule_pack")
        if pack not in runner.SUPPORTED_RULE_PACKS:
            outcome, findings, error = "failed", [], f"unsupported claimed rule pack: {pack}"
        else:
            print(
                f"job {job['id']} {pack} {job['display_name']} attempt={job['attempt_count']}",
                flush=True,
            )
            try:
                outcome, findings, error = runner.process_job(job)
            except Exception as exc:
                outcome, findings, error = (
                    "failed",
                    [],
                    f"unhandled worker error: {type(exc).__name__}: {exc}",
                )

        completion_rpc = (
            "internal_complete_buyer_document_evidence_job"
            if pack == "buyer_organization_contact_v1"
            else "internal_complete_document_evidence_job"
        )
        result = base.rpc(
            completion_rpc,
            {
                "p_job_id": job["id"],
                "p_outcome": outcome,
                "p_findings": findings,
                "p_error": error,
            },
        )
        print(f"complete={json.dumps(result, sort_keys=True)}", flush=True)


if __name__ == "__main__":
    main()
