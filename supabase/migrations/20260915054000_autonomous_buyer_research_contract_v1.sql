-- Autonomous buyer document-evidence worker contract.
--
-- This migration deliberately separates three concerns:
--   1. claim only work the generic buyer web-research executor can safely service;
--   2. permit bounded creation of a durable organization only from strong evidence;
--   3. route address-only/no-identity jobs out of the generic buyer-web queue.
--
-- Address-only opportunities remain unresolved in scout.buyer_resolution_queue so
-- they can be handled by property/permit-party resolution. They are not treated
-- as generic web-search work because a search result for an address can be a
-- tenant/operator and is not ownership, management, or buying-authority proof.

create or replace function public.internal_get_buyer_research_provider_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select nullif(decrypted_secret,'')
  into v_key
  from vault.decrypted_secrets
  where name='scout_buyer_research_tavily_api_key'
  order by updated_at desc
  limit 1;

  return jsonb_build_object(
    'provider','tavily',
    'configured',v_key is not null,
    'api_key',v_key
  );
end
$$;

revoke all on function public.internal_get_buyer_research_provider_v1() from public, anon, authenticated;
grant execute on function public.internal_get_buyer_research_provider_v1() to service_role;

create or replace function public.internal_claim_buyer_web_research_jobs_v1(
  p_limit integer default 4,
  p_search_available boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_limit < 1 or p_limit > 10 then
    raise exception 'p_limit must be between 1 and 10';
  end if;

  update research.document_evidence_jobs j
  set state='queued',
      claimed_at=null,
      lease_until=null,
      last_error=concat_ws(E'\n',nullif(j.last_error,''),'claim lease expired'),
      updated_at=now()
  where j.rule_pack='buyer_organization_contact_v1'
    and coalesce(j.context->>'research_domain','buyer') <> 'agriculture'
    and j.state='claimed'
    and j.lease_until < now();

  update research.document_evidence_jobs j
  set state='exhausted',
      completed_at=coalesce(j.completed_at,now()),
      exhaustion_reason=coalesce(j.exhaustion_reason,'retry_budget_exhausted'),
      requery_after=coalesce(j.requery_after,now()+interval '90 days'),
      updated_at=now()
  where j.rule_pack='buyer_organization_contact_v1'
    and coalesce(j.context->>'research_domain','buyer') <> 'agriculture'
    and j.state in ('queued','failed')
    and j.attempt_count >= j.max_attempts;

  with picked as (
    select j.id
    from research.document_evidence_jobs j
    where j.rule_pack='buyer_organization_contact_v1'
      and coalesce(j.context->>'research_domain','buyer') <> 'agriculture'
      and j.state in ('queued','failed')
      and j.attempt_count < j.max_attempts
      and j.next_attempt_at <= now()
      and nullif(btrim(j.organization_name),'') is not null
      and (
        -- Existing organizations with authoritative roots can be researched
        -- without a search provider.
        (
          nullif(j.context->>'organization_id','') is not null
          and jsonb_typeof(coalesce(j.source_roots,'[]'::jsonb))='array'
          and jsonb_array_length(coalesce(j.source_roots,'[]'::jsonb)) > 0
        )
        -- Discovery is only attempted when a sanctioned provider is configured.
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

revoke all on function public.internal_claim_buyer_web_research_jobs_v1(integer,boolean) from public, anon, authenticated;
grant execute on function public.internal_claim_buyer_web_research_jobs_v1(integer,boolean) to service_role;

create or replace function public.internal_resolve_or_create_buyer_research_organization_v1(
  p_job_id uuid,
  p_canonical_name text,
  p_website_url text,
  p_phone text default null,
  p_source_url text default null,
  p_source_authority text default null,
  p_identity_confidence numeric default 0,
  p_evidence_excerpt text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job research.document_evidence_jobs%rowtype;
  v_norm text;
  v_job_norm text;
  v_domain text;
  v_org_id uuid;
  v_matches integer:=0;
  v_created boolean:=false;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if coalesce(p_identity_confidence,0) < .95 then
    raise exception 'identity confidence below automatic organization threshold';
  end if;
  if nullif(btrim(p_canonical_name),'') is null then
    raise exception 'canonical organization name required';
  end if;
  if p_source_url !~ '^https?://' or p_website_url !~ '^https?://' then
    raise exception 'public source and website URLs are required';
  end if;

  select * into v_job
  from research.document_evidence_jobs
  where id=p_job_id
  for update;

  if not found
     or v_job.rule_pack <> 'buyer_organization_contact_v1'
     or v_job.state <> 'claimed'
     or coalesce(v_job.context->>'research_domain','buyer')='agriculture' then
    raise exception 'eligible claimed buyer evidence job required';
  end if;
  if nullif(btrim(v_job.organization_name),'') is null then
    raise exception 'address-only research cannot create a buyer organization';
  end if;

  v_norm:=public.scout_normalize_business_name(p_canonical_name);
  v_job_norm:=public.scout_normalize_business_name(v_job.organization_name);
  if nullif(v_norm,'') is null or v_norm <> v_job_norm then
    raise exception 'researched organization name does not match the named buyer subject';
  end if;

  -- The evidence excerpt must actually contain the named organization. This is
  -- deliberately conservative; a search ranking alone is never enough.
  if position(v_norm in public.scout_normalize_business_name(coalesce(p_evidence_excerpt,'')))=0 then
    raise exception 'source content does not establish the named organization';
  end if;

  v_domain:=regexp_replace(
    split_part(regexp_replace(lower(p_website_url),'^https?://','','i'),'/',1),
    '^www\\.','','i'
  );
  if nullif(v_domain,'') is null
     or v_domain = any(array[
       'facebook.com','linkedin.com','instagram.com','x.com','twitter.com',
       'yelp.com','bbb.org','mapquest.com','buildzoom.com','manta.com',
       'chamberofcommerce.com','yellowpages.com'
     ]) then
    raise exception 'directory/social source cannot establish an automatic organization identity';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('buyer-research-org:'||v_norm,0));

  with matches as (
    select o.id
    from core.organizations o
    where o.status='active'
      and public.scout_normalize_business_name(o.canonical_name)=v_norm
    union
    select a.organization_id
    from core.organization_aliases a
    join core.organizations o on o.id=a.organization_id and o.status='active'
    where public.scout_normalize_business_name(a.alias)=v_norm
  )
  select count(*),(array_agg(id order by id))[1]
  into v_matches,v_org_id
  from matches;

  if v_matches > 1 then
    return jsonb_build_object('status','ambiguous_existing_organization','match_count',v_matches);
  end if;

  if v_matches=0 then
    insert into core.organizations(
      canonical_name,normalized_name,organization_type,status,website_url,phone,attributes,updated_at
    ) values(
      btrim(p_canonical_name),v_norm,null,'active',p_website_url,nullif(btrim(p_phone),''),
      jsonb_strip_nulls(jsonb_build_object(
        'identity_source','bounded_document_evidence_worker',
        'identity_source_url',p_source_url,
        'identity_source_authority',p_source_authority,
        'identity_confidence',least(1,greatest(.95,p_identity_confidence)),
        'document_evidence_job_id',p_job_id,
        'buyer_authority_not_implied',true
      )),now()
    ) returning id into v_org_id;
    v_created:=true;
  else
    update core.organizations
    set website_url=coalesce(website_url,p_website_url),
        phone=coalesce(phone,nullif(btrim(p_phone),'')),
        attributes=attributes||jsonb_strip_nulls(jsonb_build_object(
          'last_identity_corroboration_source_url',p_source_url,
          'last_identity_corroboration_authority',p_source_authority,
          'last_identity_corroboration_confidence',least(1,greatest(.95,p_identity_confidence)),
          'buyer_authority_not_implied',true
        )),
        updated_at=now()
    where id=v_org_id;
  end if;

  if public.scout_normalize_business_name(btrim(p_canonical_name))
     <> public.scout_normalize_business_name(v_job.organization_name) then
    insert into core.organization_aliases(organization_id,alias,alias_type)
    values(v_org_id,v_job.organization_name,'document_evidence_subject')
    on conflict do nothing;
  end if;

  update research.document_evidence_jobs
  set organization_name=btrim(p_canonical_name),
      source_roots=(
        select coalesce(jsonb_agg(x order by x),'[]'::jsonb)
        from (
          select distinct value as x
          from jsonb_array_elements_text(coalesce(source_roots,'[]'::jsonb)||jsonb_build_array(p_website_url))
        ) d
      ),
      context=jsonb_set(
        jsonb_set(coalesce(context,'{}'::jsonb),'{organization_id}',to_jsonb(v_org_id::text),true),
        '{organization_name}',to_jsonb(btrim(p_canonical_name)),true
      ),
      updated_at=now()
  where id=p_job_id;

  return jsonb_build_object(
    'status',case when v_created then 'created' else 'resolved_existing' end,
    'organization_id',v_org_id,
    'canonical_name',btrim(p_canonical_name),
    'website_url',p_website_url,
    'created',v_created
  );
end
$$;

revoke all on function public.internal_resolve_or_create_buyer_research_organization_v1(uuid,text,text,text,text,text,numeric,text) from public, anon, authenticated;
grant execute on function public.internal_resolve_or_create_buyer_research_organization_v1(uuid,text,text,text,text,text,numeric,text) to service_role;

create or replace function research.route_address_only_buyer_document_evidence_jobs_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_routed integer:=0;
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then
    raise exception 'postgres scheduler only';
  end if;

  update research.document_evidence_jobs j
  set state='exhausted',
      claimed_at=null,
      lease_until=null,
      completed_at=coalesce(j.completed_at,now()),
      exhaustion_reason='requires_upstream_property_or_permit_party_resolution',
      requery_after='2999-12-31 00:00:00+00'::timestamptz,
      updated_at=now()
  where j.rule_pack='buyer_organization_contact_v1'
    and coalesce(j.context->>'research_domain','buyer') <> 'agriculture'
    and j.state in ('queued','failed')
    and nullif(btrim(j.organization_name),'') is null
    and nullif(j.context->>'organization_id','') is null;
  get diagnostics v_routed=row_count;

  return jsonb_build_object('routed_out_of_generic_web_research',v_routed);
end
$$;

revoke all on function research.route_address_only_buyer_document_evidence_jobs_v1() from public, anon, authenticated, service_role;
grant execute on function research.route_address_only_buyer_document_evidence_jobs_v1() to postgres;

create or replace function research.seed_buyer_document_evidence_jobs_cron_v3(
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
  v_routed jsonb;
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then
    raise exception 'postgres scheduler only';
  end if;
  if p_cluster_limit < 1 or p_cluster_limit > 1000 then
    raise exception 'p_cluster_limit must be between 1 and 1000';
  end if;

  perform set_config('request.jwt.claim.role','service_role',true);
  v_seed:=public.internal_seed_buyer_document_evidence_jobs(p_cluster_limit);
  v_reconcile:=research.reconcile_buyer_document_evidence_jobs_v1();
  v_routed:=research.route_address_only_buyer_document_evidence_jobs_v1();

  return jsonb_build_object('seed',v_seed,'reconcile',v_reconcile,'routing',v_routed);
end
$$;

revoke all on function research.seed_buyer_document_evidence_jobs_cron_v3(integer) from public, anon, authenticated, service_role;
grant execute on function research.seed_buyer_document_evidence_jobs_cron_v3(integer) to postgres;

insert into ingest.collector_routes(slug,enabled,allow_dispatch,updated_at)
values('collect-buyer-document-evidence',true,true,now())
on conflict(slug) do update set enabled=true,allow_dispatch=true,updated_at=now();

select cron.unschedule('scout-buyer-document-evidence-seed-hourly')
where exists(select 1 from cron.job where jobname='scout-buyer-document-evidence-seed-hourly');

select cron.schedule(
  'scout-buyer-document-evidence-seed-hourly',
  '29 * * * *',
  $$select research.seed_buyer_document_evidence_jobs_cron_v3(250);$$
);

-- Route the currently misclassified address-only backlog immediately. This
-- does not mark the corresponding buyer-resolution candidates resolved or
-- blocked; it only removes them from the generic web-research worker queue.
select research.route_address_only_buyer_document_evidence_jobs_v1();
