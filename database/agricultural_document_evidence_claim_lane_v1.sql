-- Scout bounded agriculture Document Evidence Worker claim lane v1.
--
-- Claims a small number of agriculture buyer/contact jobs independently of the global
-- queue so farm enrichment cannot be starved by unrelated higher-priority evidence work.

create or replace function public.internal_claim_agricultural_buyer_document_evidence_jobs(
  p_limit integer default 2
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_limit<1 or p_limit>10 then
    raise exception 'p_limit must be between 1 and 10';
  end if;

  update research.document_evidence_jobs
  set state='queued',claimed_at=null,lease_until=null,
      last_error=coalesce(last_error,'')||case when last_error is null then '' else E'\n' end||'claim lease expired',
      updated_at=now()
  where state='claimed'
    and lease_until<now()
    and rule_pack='buyer_organization_contact_v1'
    and context->>'research_domain'='agriculture';

  update research.document_evidence_jobs
  set state='exhausted',completed_at=coalesce(completed_at,now()),updated_at=now()
  where state in ('queued','failed')
    and attempt_count>=max_attempts
    and rule_pack='buyer_organization_contact_v1'
    and context->>'research_domain'='agriculture';

  with picked as (
    select id
    from research.document_evidence_jobs
    where state in ('queued','failed')
      and attempt_count<max_attempts
      and next_attempt_at<=now()
      and rule_pack='buyer_organization_contact_v1'
      and context->>'research_domain'='agriculture'
    order by priority asc,next_attempt_at asc,created_at asc
    for update skip locked
    limit p_limit
  ), claimed as (
    update research.document_evidence_jobs j
    set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),
        lease_until=now()+interval '45 minutes',last_error=null,updated_at=now()
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

revoke all on function public.internal_claim_agricultural_buyer_document_evidence_jobs(integer) from public,anon,authenticated;
grant execute on function public.internal_claim_agricultural_buyer_document_evidence_jobs(integer) to service_role;

comment on function public.internal_claim_agricultural_buyer_document_evidence_jobs(integer) is
  'Reserves a bounded claim lane for agriculture buyer/contact jobs so the global Document Evidence Worker backlog cannot starve farm enrichment.';
