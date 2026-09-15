-- Give documented property-manager contact research its own bounded claim lane.
-- This reuses the existing contact-research worker without changing buyer identity semantics.

create or replace function public.internal_claim_responsible_party_contact_research_jobs_v1(
  p_limit integer default 2,
  p_search_available boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_limit < 1 or p_limit > 6 then
    raise exception 'p_limit must be between 1 and 6';
  end if;

  update research.document_evidence_jobs j
  set state='queued',
      claimed_at=null,
      lease_until=null,
      last_error=concat_ws(E'\n',nullif(j.last_error,''),'claim lease expired'),
      updated_at=now()
  where j.rule_pack='buyer_organization_contact_v1'
    and j.subject_type='responsible_party_contact'
    and j.context->>'research_domain'='responsible_party_contact'
    and j.context->>'identity_projection'='suppressed'
    and j.state='claimed'
    and j.lease_until < now();

  update research.document_evidence_jobs j
  set state='exhausted',
      completed_at=coalesce(j.completed_at,now()),
      exhaustion_reason=coalesce(j.exhaustion_reason,'retry_budget_exhausted'),
      requery_after=coalesce(j.requery_after,now()+interval '90 days'),
      updated_at=now()
  where j.rule_pack='buyer_organization_contact_v1'
    and j.subject_type='responsible_party_contact'
    and j.context->>'research_domain'='responsible_party_contact'
    and j.context->>'identity_projection'='suppressed'
    and j.state in ('queued','failed')
    and j.attempt_count >= j.max_attempts;

  with picked as (
    select j.id
    from research.document_evidence_jobs j
    where j.rule_pack='buyer_organization_contact_v1'
      and j.subject_type='responsible_party_contact'
      and j.context->>'research_domain'='responsible_party_contact'
      and j.context->>'responsibility_role'='property_manager'
      and j.context->>'identity_projection'='suppressed'
      and coalesce((j.context->>'buyer_authority_not_implied')::boolean,false)=true
      and nullif(j.context->>'organization_id','') is not null
      and j.state in ('queued','failed')
      and j.attempt_count < j.max_attempts
      and j.next_attempt_at <= now()
      and nullif(btrim(j.organization_name),'') is not null
      and (
        (jsonb_typeof(coalesce(j.source_roots,'[]'::jsonb))='array'
          and jsonb_array_length(coalesce(j.source_roots,'[]'::jsonb)) > 0)
        or p_search_available
      )
    order by j.priority asc,j.next_attempt_at asc,j.created_at asc
    for update skip locked
    limit p_limit
  ), claimed as (
    update research.document_evidence_jobs j
    set state='claimed',
        attempt_count=j.attempt_count+1,
        claimed_at=now(),
        lease_until=now()+interval '45 minutes',
        last_error=null,
        updated_at=now()
    from picked
    where j.id=picked.id
    returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'rule_pack',c.rule_pack,
    'subject_type',c.subject_type,
    'subject_id',c.subject_id,
    'subject_key',c.subject_key,
    'cluster_key',c.cluster_key,
    'display_name',c.display_name,
    'organization_name',c.organization_name,
    'priority',c.priority,
    'attempt_count',c.attempt_count,
    'max_attempts',c.max_attempts,
    'search_query',c.search_query,
    'source_roots',c.source_roots,
    'context',c.context
  ) order by c.priority,c.created_at),'[]'::jsonb)
  into v_result
  from claimed c;

  return v_result;
end
$$;

revoke all on function public.internal_claim_responsible_party_contact_research_jobs_v1(integer,boolean)
  from public,anon,authenticated;
grant execute on function public.internal_claim_responsible_party_contact_research_jobs_v1(integer,boolean)
  to service_role;

-- Manager-only jobs must remain outside the buyer projection link table.
do $$
declare v_bad integer;
begin
  select count(*) into v_bad
  from research.document_evidence_jobs j
  join research.document_evidence_job_candidates jc on jc.job_id=j.id
  where j.subject_type='responsible_party_contact';
  if v_bad<>0 then
    raise exception 'manager contact claim lane found buyer projection links';
  end if;
end
$$;