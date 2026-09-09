#!/usr/bin/env python3
"""Bounded orchestration entrypoint for Scout's document evidence worker.

Base domain seeding, buyer seeding, and demo-exemplar prioritization are intentionally
separate RPCs so each phase gets its own transaction/HTTP timeout budget. The rule-pack
implementation remains in scout_document_evidence_runner.py.
"""
from __future__ import annotations

import argparse
import json

import scout_document_evidence_runner as runner

base = runner.base


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        base.self_test()
        runner.self_test()
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

    buyer_seed = base.rpc("internal_seed_buyer_document_evidence_jobs")
    print(f"buyer_seed={json.dumps(buyer_seed, sort_keys=True)}", flush=True)

    exemplar_seed = base.rpc("internal_seed_exemplar_document_evidence_jobs")
    print(f"exemplar_seed={json.dumps(exemplar_seed, sort_keys=True)}", flush=True)

    jobs = base.rpc(
        "internal_claim_document_evidence_jobs",
        {"p_limit": base.BATCH_SIZE, "p_rule_pack": base.RULE_PACK},
    )
    print(f"claimed={len(jobs)}", flush=True)

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
