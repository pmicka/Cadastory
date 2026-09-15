-- Buyer identity evidence is durable independently of the research job lifecycle.
-- A job may be requeued/exhausted for additional contact/procurement research without
-- invalidating a previously documented/corroborated organization identity.

create or replace function scout.restore_document_evidence_buyer_identities_v1(
  p_candidate_keys text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_projected integer := 0;
  v_strong_candidates integer := 0;
  v_ambiguous_candidates integer := 0;
begin
  with strong as (
    select distinct
      jc.candidate_key,
      o.id as organization_id
    from research.document_evidence_jobs j
    join research.document_evidence_job_candidates jc on jc.job_id = j.id
    join core.organizations o
      on o.id::text = nullif(j.outcome_metadata->>'organization_id','')
     and o.status = 'active'
    where j.rule_pack = 'buyer_organization_contact_v1'
      and (p_candidate_keys is null or jc.candidate_key = any(p_candidate_keys))
      and exists (
        select 1
        from research.document_evidence_findings f
        where f.job_id = j.id
          and f.identity_confidence >= 0.95
          and f.decision_state in ('documented','corroborated')
      )
  ), roll as (
    select candidate_key, count(distinct organization_id) as organization_count
    from strong
    group by candidate_key
  )
  select
    count(*) filter (where organization_count >= 1),
    count(*) filter (where organization_count > 1)
  into v_strong_candidates, v_ambiguous_candidates
  from roll;

  with strong as (
    select
      jc.candidate_key,
      o.id as organization_id,
      max(coalesce(j.completed_at, j.updated_at)) as evidence_at
    from research.document_evidence_jobs j
    join research.document_evidence_job_candidates jc on jc.job_id = j.id
    join core.organizations o
      on o.id::text = nullif(j.outcome_metadata->>'organization_id','')
     and o.status = 'active'
    where j.rule_pack = 'buyer_organization_contact_v1'
      and (p_candidate_keys is null or jc.candidate_key = any(p_candidate_keys))
      and exists (
        select 1
        from research.document_evidence_findings f
        where f.job_id = j.id
          and f.identity_confidence >= 0.95
          and f.decision_state in ('documented','corroborated')
      )
    group by jc.candidate_key, o.id
  ), unambiguous as (
    select
      candidate_key,
      min(organization_id::text)::uuid as organization_id,
      max(evidence_at) as evidence_at
    from strong
    group by candidate_key
    having count(distinct organization_id) = 1
  )
  update scout.opportunity_buyer_identities b
  set organization_id = u.organization_id,
      buyer_name = o.canonical_name,
      organization_type = o.organization_type,
      identity_kind = 'customer_organization',
      resolution_status = 'organization_resolved',
      confidence = greatest(b.confidence, 0.95),
      identity_basis = 'document_evidence_exact_organization',
      observed_at = coalesce(greatest(b.observed_at, u.evidence_at), b.observed_at, u.evidence_at),
      last_normalized_at = now()
  from unambiguous u
  join core.organizations o on o.id = u.organization_id and o.status = 'active'
  where b.candidate_key = u.candidate_key;
  get diagnostics v_projected = row_count;

  return jsonb_build_object(
    'projected', v_projected,
    'strong_candidates', v_strong_candidates,
    'ambiguous_candidates', v_ambiguous_candidates
  );
end
$$;

revoke all on function scout.restore_document_evidence_buyer_identities_v1(text[]) from public, anon, authenticated;
grant execute on function scout.restore_document_evidence_buyer_identities_v1(text[]) to postgres, service_role;

-- Reconcile every durable strong identity immediately, then refresh only the
-- affected serving routes/projections so queue state and missing steps match.
do $$
declare
  v_candidates text[];
begin
  perform scout.restore_document_evidence_buyer_identities_v1(null);

  with strong as (
    select distinct jc.candidate_key, o.id as organization_id
    from research.document_evidence_jobs j
    join research.document_evidence_job_candidates jc on jc.job_id = j.id
    join core.organizations o
      on o.id::text = nullif(j.outcome_metadata->>'organization_id','')
     and o.status = 'active'
    where j.rule_pack = 'buyer_organization_contact_v1'
      and exists (
        select 1
        from research.document_evidence_findings f
        where f.job_id = j.id
          and f.identity_confidence >= 0.95
          and f.decision_state in ('documented','corroborated')
      )
  ), roll as (
    select candidate_key
    from strong
    group by candidate_key
    having count(distinct organization_id) = 1
  )
  select coalesce(array_agg(candidate_key order by candidate_key), '{}'::text[])
  into v_candidates
  from roll;

  if cardinality(v_candidates) > 0 then
    perform scout.refresh_opportunity_buyer_routes_for_candidates_v1(v_candidates);
    perform scout.refresh_buyer_projection_for_candidates_v1(v_candidates);
  end if;
end
$$;