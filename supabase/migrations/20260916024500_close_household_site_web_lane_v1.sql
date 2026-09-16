-- Phase 3 acceptance closure.
-- The strict exact-address first-party web resolver completed a full first-pass sweep
-- with zero accepted operator identities after third-party false positives were retracted.
-- Park this resolver lane for 90 days; do not schedule recurring web search.

update research.document_evidence_jobs j
set state='exhausted',
    completed_at=coalesce(j.completed_at,now()),
    claimed_at=null,
    lease_until=null,
    last_error=null,
    exhaustion_reason='no_documented_site_organization',
    requery_after=now()+interval '90 days',
    outcome_metadata=coalesce(j.outcome_metadata,'{}'::jsonb)||jsonb_build_object(
      'phase3_first_pass_complete',true,
      'accepted_operator_identity',false,
      'strict_first_party_domain_required',true,
      'recurring_web_search_enabled',false,
      'buyer_authority_not_implied',true,
      'outbound_contact_performed',false
    ),
    updated_at=now()
where j.rule_pack='household_site_organization_v1'
  and j.state in ('queued','failed')
  and j.attempt_count>=1;

insert into research.household_owner_fallback_deferrals(
  candidate_key,reason,source_kind,site_address_text,requery_after,details,resolved_at,updated_at
)
select
  l.candidate_key,
  'no_documented_site_organization',
  q.source_kind,
  q.address_hint,
  now()+interval '90 days',
  jsonb_build_object(
    'resolution_scope','household_owner_fallback',
    'document_evidence_job_id',l.job_id,
    'phase3_first_pass_complete',true,
    'strict_first_party_domain_required',true,
    'accepted_operator_identity',false,
    'owner_identity_not_researched',true,
    'global_buyer_queue_not_blocked',true,
    'recurring_web_search_enabled',false,
    'outbound_contact_performed',false
  ),
  null,
  now()
from research.household_site_organization_job_candidates l
join research.document_evidence_jobs j on j.id=l.job_id
join scout.buyer_resolution_queue q using(candidate_key)
where j.rule_pack='household_site_organization_v1'
  and j.state='exhausted'
on conflict(candidate_key) do update set
  reason=excluded.reason,
  source_kind=excluded.source_kind,
  site_address_text=excluded.site_address_text,
  requery_after=excluded.requery_after,
  details=excluded.details,
  resolved_at=null,
  updated_at=now();

-- Acceptance invariants: this lane must stay research-only and unscheduled.
do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from scout.opportunity_responsible_party_evidence
  where party_role='operator'
    and attributes->>'resolution_scope'='household_owner_fallback';
  if v_bad<>0 then
    raise exception 'household fallback still contains accepted operator evidence';
  end if;

  select count(*) into v_bad
  from research.document_evidence_job_candidates jc
  join research.document_evidence_jobs j on j.id=jc.job_id
  where j.rule_pack='household_site_organization_v1';
  if v_bad<>0 then
    raise exception 'household fallback entered generic buyer projection';
  end if;

  select count(*) into v_bad
  from research.document_evidence_jobs
  where rule_pack='household_site_organization_v1'
    and context->>'outbound_contact_performed'='true';
  if v_bad<>0 then
    raise exception 'household fallback recorded outbound contact';
  end if;

  select count(*) into v_bad
  from cron.job
  where active
    and command ilike '%collect-household-site-organization-evidence%';
  if v_bad<>0 then
    raise exception 'household fallback collector must remain unscheduled';
  end if;
end
$$;