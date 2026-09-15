-- Materialize durable organization records from authoritative named-party source evidence
-- before generic web contact discovery. This separates legal/source identity from
-- website branding and avoids asking a website to prove a corporate suffix it may
-- never display.
--
-- This does NOT establish purchasing authority. It only records the named
-- organization/responsible party already present in authoritative Scout source data.

create or replace function public.internal_materialize_authoritative_named_buyer_org_v1(
  p_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job research.document_evidence_jobs%rowtype;
  v_name text;
  v_norm text;
  v_org_id uuid;
  v_match_count integer:=0;
  v_source_kind text;
  v_source_url text;
  v_source_party text;
  v_source_count integer:=0;
  v_created boolean:=false;
  v_website text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
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

  if nullif(v_job.context->>'organization_id','') is not null then
    return jsonb_build_object(
      'status','already_resolved',
      'organization_id',v_job.context->>'organization_id'
    );
  end if;

  v_name:=nullif(btrim(v_job.organization_name),'');
  if v_name is null then
    return jsonb_build_object('status','not_named');
  end if;

  -- Person-like names must never be turned into organizations by this worker.
  -- Require a clear business/legal/industry marker in the source-provided name.
  if lower(v_name) !~ '(^|[^a-z])(llc|inc|incorporated|corp|corporation|company|co|construction|contracting|contractors|engineering|electric|electrical|mechanical|heating|cooling|hvac|solar|energy|power|coop|cooperative|group|builders|building|roofing|plumbing|services)([^a-z]|$)' then
    return jsonb_build_object('status','not_business_like');
  end if;

  v_norm:=public.scout_normalize_business_name(v_name);
  if nullif(v_norm,'') is null then
    return jsonb_build_object('status','invalid_name');
  end if;

  -- Only source classes with an authoritative named responsible party are eligible.
  -- The source party must normalize exactly to the research subject name.
  select count(*),
         (array_agg(s.source_kind order by s.source_kind))[1],
         (array_agg(nullif(s.details->>'source_url','') order by s.source_kind)
            filter(where nullif(s.details->>'source_url','') is not null))[1],
         (array_agg(
            case
              when s.source_kind='construction_window' then nullif(s.details->>'contractor_name','')
              when s.source_kind='solar_lifecycle' then nullif(s.details->>'entity_name','')
              else null
            end
            order by s.source_kind
          ) filter(where
            case
              when s.source_kind='construction_window' then nullif(s.details->>'contractor_name','')
              when s.source_kind='solar_lifecycle' then nullif(s.details->>'entity_name','')
              else null
            end is not null))[1]
  into v_source_count,v_source_kind,v_source_url,v_source_party
  from research.document_evidence_job_candidates jc
  join scout.opportunity_search_spine s on s.candidate_key=jc.candidate_key
  where jc.job_id=v_job.id
    and s.source_kind in ('construction_window','solar_lifecycle')
    and public.scout_normalize_business_name(
      case
        when s.source_kind='construction_window' then coalesce(s.details->>'contractor_name','')
        when s.source_kind='solar_lifecycle' then coalesce(s.details->>'entity_name','')
        else ''
      end
    )=v_norm;

  if v_source_count=0 then
    return jsonb_build_object('status','no_authoritative_exact_source_party');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('authoritative-named-buyer-org:'||v_norm,0));

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
  into v_match_count,v_org_id
  from matches;

  if v_match_count>1 then
    return jsonb_build_object('status','ambiguous_existing_organization','match_count',v_match_count);
  end if;

  if v_match_count=0 then
    insert into core.organizations(
      canonical_name,normalized_name,organization_type,status,attributes,updated_at
    ) values(
      v_name,v_norm,null,'active',
      jsonb_strip_nulls(jsonb_build_object(
        'identity_source','authoritative_named_responsibility',
        'identity_source_kind',v_source_kind,
        'identity_source_url',v_source_url,
        'document_evidence_job_id',v_job.id,
        'source_party_name',v_source_party,
        'buyer_authority_not_implied',true,
        'identity_scope','organization_identity_only'
      )),now()
    ) returning id into v_org_id;
    v_created:=true;
  end if;

  select o.website_url into v_website
  from core.organizations o
  where o.id=v_org_id;

  update research.document_evidence_jobs
  set context=jsonb_set(
        jsonb_set(coalesce(context,'{}'::jsonb),'{organization_id}',to_jsonb(v_org_id::text),true),
        '{organization_identity_basis}',to_jsonb('authoritative_named_responsibility'::text),true
      ),
      source_roots=case
        when v_website ~ '^https?://' then (
          select coalesce(jsonb_agg(x order by x),'[]'::jsonb)
          from (
            select distinct value as x
            from jsonb_array_elements_text(coalesce(source_roots,'[]'::jsonb)||jsonb_build_array(v_website))
          ) q
        )
        else source_roots
      end,
      updated_at=now()
  where id=v_job.id;

  return jsonb_build_object(
    'status',case when v_created then 'created_from_authoritative_source' else 'resolved_existing' end,
    'organization_id',v_org_id,
    'canonical_name',v_name,
    'source_kind',v_source_kind,
    'source_url',v_source_url,
    'created',v_created,
    'buyer_authority_not_implied',true
  );
end
$$;

revoke all on function public.internal_materialize_authoritative_named_buyer_org_v1(uuid) from public, anon, authenticated;
grant execute on function public.internal_materialize_authoritative_named_buyer_org_v1(uuid) to service_role;
