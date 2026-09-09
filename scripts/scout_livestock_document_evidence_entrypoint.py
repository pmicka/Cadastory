#!/usr/bin/env python3
"""Bounded launcher for Scout's livestock document-evidence rule pack."""
from __future__ import annotations

import argparse
import json

import scout_document_evidence_runner as runner
import scout_livestock_evidence_extension as livestock

base = runner.base
RULE_PACK = livestock.RULE_PACK


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        base.self_test()
        runner.self_test()
        livestock.self_test()
        return

    if not base.SUPABASE_URL or not base.SERVICE_KEY:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    if not 1 <= base.BATCH_SIZE <= 50:
        raise SystemExit("SCOUT_DOCUMENT_BATCH_SIZE must be between 1 and 50")

    base.require_poppler()
    seed = base.rpc("internal_seed_livestock_document_evidence_jobs")
    print(f"livestock_seed={json.dumps(seed, sort_keys=True)}", flush=True)

    jobs = base.rpc(
        "internal_claim_document_evidence_jobs",
        {"p_limit": base.BATCH_SIZE, "p_rule_pack": RULE_PACK},
    )
    print(f"claimed_livestock={len(jobs)}", flush=True)

    for job in jobs:
        print(
            f"job {job['id']} {job.get('rule_pack')} {job.get('display_name')} attempt={job.get('attempt_count')}",
            flush=True,
        )
        try:
            outcome, findings, error = runner.process_job(job)
        except Exception as exc:
            outcome, findings, error = "failed", [], f"unhandled worker error: {type(exc).__name__}: {exc}"

        result = base.rpc(
            "internal_complete_document_evidence_job",
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
