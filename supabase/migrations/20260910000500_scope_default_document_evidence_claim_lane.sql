-- Keep the unfiltered/default document-evidence claim lane aligned with the
-- generic Python runner. Specialized workers must claim their own rule pack
-- explicitly so they cannot be consumed by a runner that does not support them.

create or replace function public.internal_claim_document_evidence_jobs(
  p_limit integer default 6,
  p_rule_pack text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'research'
as $function$
declare
  v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_limit < 1 or p_limit > 50 then
    raise exception 'p_limit must be between 1 and 50';
  end if;

  update research.document_evidence_jobs
  set state='queued', claimed_at=null, lease_until=null,
      last_error=coalesce(last_error,'') || case when last_error is null then '' else E'\n' end || 'claim lease expired',
      updated_at=now()
  where state='claimed'
    and lease_until < now()
    and (
      (p_rule_pack is not null and rule_pack=p_rule_pack)
      or
      (p_rule_pack is null and rule_pack in (
        'water_tank_morphology_v1',
        'facade_material_glazing_v1',
        'buyer_organization_contact_v1',
        'surface_work_condition_v1',
        'account_portfolio_context_v1'
      ))
    );

  update research.document_evidence_jobs
  set state='exhausted', completed_at=coalesce(completed_at,now()), updated_at=now()
  where state in ('queued','failed')
    and attempt_count >= max_attempts
    and (
      (p_rule_pack is not null and rule_pack=p_rule_pack)
      or
      (p_rule_pack is null and rule_pack in (
        'water_tank_morphology_v1',
        'facade_material_glazing_v1',
        'buyer_organization_contact_v1',
        'surface_work_condition_v1',
        'account_portfolio_context_v1'
      ))
    );

  with picked as (
    select id
    from research.document_evidence_jobs
    where state in ('queued','failed')
      and attempt_count < max_attempts
      and next_attempt_at <= now()
      and (
        (p_rule_pack is not null and rule_pack=p_rule_pack)
        or
        (p_rule_pack is null and rule_pack in (
          'water_tank_morphology_v1',
          'facade_material_glazing_v1',
          'buyer_organization_contact_v1',
          'surface_work_condition_v1',
          'account_portfolio_context_v1'
        ))
      )
    order by priority asc, next_attempt_at asc, created_at asc
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
end;
$function$;

comment on function public.internal_claim_document_evidence_jobs(integer,text) is
  'Unfiltered claims are restricted to rule packs supported by the generic document-evidence runner. Specialized workers must pass p_rule_pack explicitly.';
