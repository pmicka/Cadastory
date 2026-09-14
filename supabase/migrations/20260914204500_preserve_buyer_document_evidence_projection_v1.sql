-- Preserve durable buyer identity conclusions from completed document-evidence research
-- across the rebuildable opportunity-normalization projection.
--
-- Root cause addressed:
--   scout.refresh_opportunity_normalized_facts() rebuilt opportunity_buyer_identities
--   from source candidates, erasing later evidence-backed organization resolution.
--
-- Guardrails:
--   * only completed buyer evidence jobs qualify;
--   * at least one documented/corroborated finding with identity_confidence >= 0.95;
--   * conflicting completed organization conclusions for the same candidate are not projected;
--   * the organization must still be active;
--   * no new inference of buying authority or direct-person contact is introduced.

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
      and j.state = 'completed'
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
      max(j.completed_at) as completed_at
    from research.document_evidence_jobs j
    join research.document_evidence_job_candidates jc on jc.job_id = j.id
    join core.organizations o
      on o.id::text = nullif(j.outcome_metadata->>'organization_id','')
     and o.status = 'active'
    where j.rule_pack = 'buyer_organization_contact_v1'
      and j.state = 'completed'
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
      max(completed_at) as completed_at
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
      observed_at = coalesce(greatest(b.observed_at, u.completed_at), b.observed_at, u.completed_at),
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

-- Keep the existing source-derived normalization implementation intact as the
-- rebuild core, then layer durable research conclusions on top every time.
do $$
begin
  if to_regprocedure('scout.refresh_opportunity_normalized_facts_source_v1()') is null then
    alter function scout.refresh_opportunity_normalized_facts()
      rename to refresh_opportunity_normalized_facts_source_v1;
  end if;
end
$$;

revoke all on function scout.refresh_opportunity_normalized_facts_source_v1() from public, anon, authenticated;
grant execute on function scout.refresh_opportunity_normalized_facts_source_v1() to postgres, service_role;

create or replace function scout.refresh_opportunity_normalized_facts()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source jsonb;
  v_evidence jsonb;
begin
  v_source := scout.refresh_opportunity_normalized_facts_source_v1();
  v_evidence := scout.restore_document_evidence_buyer_identities_v1(null);
  return coalesce(v_source, '{}'::jsonb)
    || jsonb_build_object('buyer_document_evidence_projection', v_evidence);
end
$$;

revoke all on function scout.refresh_opportunity_normalized_facts() from public, anon, authenticated;
grant execute on function scout.refresh_opportunity_normalized_facts() to postgres, service_role;

-- When a buyer evidence job newly completes, immediately re-project the bounded
-- candidate set and refresh its buyer route/projection. This keeps the durable
-- evidence source and the rebuildable serving projection synchronized without
-- waiting for the hourly normalization cycle.
create or replace function research.project_completed_buyer_document_evidence_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_candidates text[];
begin
  if new.rule_pack <> 'buyer_organization_contact_v1'
     or new.state <> 'completed'
     or nullif(new.outcome_metadata->>'organization_id','') is null then
    return new;
  end if;

  select coalesce(array_agg(jc.candidate_key order by jc.candidate_key), '{}'::text[])
  into v_candidates
  from research.document_evidence_job_candidates jc
  where jc.job_id = new.id;

  if cardinality(v_candidates) > 0 then
    perform scout.restore_document_evidence_buyer_identities_v1(v_candidates);
    perform scout.refresh_opportunity_buyer_routes_for_candidates_v1(v_candidates);
    perform scout.refresh_buyer_projection_for_candidates_v1(v_candidates);
  end if;

  return new;
end
$$;

revoke all on function research.project_completed_buyer_document_evidence_v1() from public, anon, authenticated, service_role;
grant execute on function research.project_completed_buyer_document_evidence_v1() to postgres;

drop trigger if exists trg_project_completed_buyer_document_evidence_v1
  on research.document_evidence_jobs;
create trigger trg_project_completed_buyer_document_evidence_v1
after update of state, outcome_metadata on research.document_evidence_jobs
for each row
when (
  new.rule_pack = 'buyer_organization_contact_v1'
  and new.state = 'completed'
  and (
    old.state is distinct from new.state
    or old.outcome_metadata is distinct from new.outcome_metadata
  )
)
execute function research.project_completed_buyer_document_evidence_v1();

-- Reconcile stale research jobs after organization resolution becomes durable.
-- Non-organization clusters are retired once every linked candidate is now
-- organization-resolved; if a completed organization-scoped job still has a
-- bounded contact/procurement gap and retry budget remains, allow one more pass.
create or replace function research.reconcile_buyer_document_evidence_jobs_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_superseded integer := 0;
  v_requeued integer := 0;
begin
  update research.document_evidence_jobs j
  set state = 'exhausted',
      claimed_at = null,
      lease_until = null,
      completed_at = coalesce(j.completed_at, now()),
      exhaustion_reason = 'superseded_by_evidence_resolved_organization',
      requery_after = now() + interval '90 days',
      updated_at = now()
  where j.rule_pack = 'buyer_organization_contact_v1'
    and j.state in ('queued','failed')
    and j.cluster_key not like 'organization:%'
    and exists (
      select 1
      from research.document_evidence_job_candidates jc
      where jc.job_id = j.id
    )
    and not exists (
      select 1
      from research.document_evidence_job_candidates jc
      left join scout.opportunity_buyer_identities b on b.candidate_key = jc.candidate_key
      where jc.job_id = j.id
        and (
          b.organization_id is null
          or b.resolution_status <> 'organization_resolved'
        )
    );
  get diagnostics v_superseded = row_count;

  update research.document_evidence_jobs j
  set state = 'queued',
      completed_at = null,
      next_attempt_at = now(),
      last_error = null,
      exhaustion_reason = null,
      requery_after = null,
      updated_at = now()
  where j.rule_pack = 'buyer_organization_contact_v1'
    and j.state = 'completed'
    and j.cluster_key like 'organization:%'
    and j.attempt_count < j.max_attempts
    and exists (
      select 1
      from research.document_evidence_job_candidates jc
      join scout.buyer_resolution_queue q on q.candidate_key = jc.candidate_key
      where jc.job_id = j.id
        and q.state in ('pending','researching')
        and q.missing_steps && array['durable_contact','procurement_route']::text[]
    );
  get diagnostics v_requeued = row_count;

  return jsonb_build_object(
    'superseded_nonorganization_jobs', v_superseded,
    'requeued_incomplete_organization_jobs', v_requeued
  );
end
$$;

revoke all on function research.reconcile_buyer_document_evidence_jobs_v1() from public, anon, authenticated, service_role;
grant execute on function research.reconcile_buyer_document_evidence_jobs_v1() to postgres;

create or replace function research.seed_buyer_document_evidence_jobs_cron_v2(
  p_cluster_limit integer default 250
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seed jsonb;
  v_reconcile jsonb;
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then
    raise exception 'postgres scheduler only';
  end if;
  if p_cluster_limit < 1 or p_cluster_limit > 1000 then
    raise exception 'p_cluster_limit must be between 1 and 1000';
  end if;

  perform set_config('request.jwt.claim.role','service_role',true);
  v_seed := public.internal_seed_buyer_document_evidence_jobs(p_cluster_limit);
  v_reconcile := research.reconcile_buyer_document_evidence_jobs_v1();

  return jsonb_build_object('seed', v_seed, 'reconcile', v_reconcile);
end
$$;

revoke all on function research.seed_buyer_document_evidence_jobs_cron_v2(integer) from public, anon, authenticated, service_role;
grant execute on function research.seed_buyer_document_evidence_jobs_cron_v2(integer) to postgres;

-- Search-spine projection refreshes at minute 27. Move buyer evidence seeding
-- behind it so the seed sees the current buyer organization/contact/procurement
-- state instead of the previous hour's projection.
select cron.unschedule('scout-buyer-document-evidence-seed-hourly')
where exists (select 1 from cron.job where jobname = 'scout-buyer-document-evidence-seed-hourly');

select cron.schedule(
  'scout-buyer-document-evidence-seed-hourly',
  '29 * * * *',
  $$select research.seed_buyer_document_evidence_jobs_cron_v2(250);$$
);

-- Repair currently drifted evidence-backed identities immediately on rollout,
-- then refresh only the affected buyer routes/search projection and reconcile
-- stale duplicate research jobs.
do $$
declare
  v_candidates text[];
begin
  perform scout.restore_document_evidence_buyer_identities_v1(null);

  select coalesce(array_agg(distinct jc.candidate_key order by jc.candidate_key), '{}'::text[])
  into v_candidates
  from research.document_evidence_jobs j
  join research.document_evidence_job_candidates jc on jc.job_id = j.id
  join core.organizations o
    on o.id::text = nullif(j.outcome_metadata->>'organization_id','')
   and o.status = 'active'
  where j.rule_pack = 'buyer_organization_contact_v1'
    and j.state = 'completed'
    and exists (
      select 1
      from research.document_evidence_findings f
      where f.job_id = j.id
        and f.identity_confidence >= 0.95
        and f.decision_state in ('documented','corroborated')
    );

  if cardinality(v_candidates) > 0 then
    perform scout.refresh_opportunity_buyer_routes_for_candidates_v1(v_candidates);
    perform scout.refresh_buyer_projection_for_candidates_v1(v_candidates);
  end if;

  perform research.reconcile_buyer_document_evidence_jobs_v1();
end
$$;
