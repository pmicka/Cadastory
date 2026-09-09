-- Restore retry budget consumed only because livestock jobs were incorrectly
-- claimed by the generic document-evidence runner before the default claim lane
-- was scoped to its supported rule packs.

update research.document_evidence_jobs
set state='queued',
    attempt_count=0,
    next_attempt_at=now(),
    claimed_at=null,
    lease_until=null,
    completed_at=null,
    last_error=null,
    exhaustion_reason=null,
    updated_at=now()
where rule_pack='livestock_inventory_v1'
  and state='failed'
  and last_error='unsupported claimed rule pack: livestock_inventory_v1'
  and not exists (
    select 1
    from research.document_evidence_findings f
    where f.job_id=research.document_evidence_jobs.id
  );
