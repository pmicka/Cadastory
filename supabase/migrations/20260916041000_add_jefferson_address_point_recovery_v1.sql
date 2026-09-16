-- Phase 4: recover Jefferson responsible-party parcel deferrals by authoritative
-- LOJIC address-point -> LRSN/PARCELID linkage, then reuse the existing PVA detail lookup.
--
-- This profile is intentionally excluded from the ordinary spatial parcel seeder:
-- eligible_source_kinds is empty. The dedicated recovery seeder reads
-- recovery_source_kinds instead and only considers candidates already deferred by
-- the canonical Jefferson spatial profile.
--
-- automated_dispatch starts false so bounded production acceptance can use the
-- dedicated recovery claim lane without racing the ordinary Jefferson worker.

insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,homepage_url,license_notes,
  commercial_use_status,notes,updated_at
)
values(
  'jefferson-county-address-points',
  'Jefferson County KY Address Points',
  'LOJIC',
  'address_point_reference',
  'Jefferson County, Kentucky',
  'bounded ArcGIS query',
  'live reference',
  'authoritative local government GIS',
  'active_reference',
  'https://gis.lojic.org/maps/rest/services/LojicSolutions/OpenDataAddresses/MapServer/0',
  'Public LOJIC ArcGIS address-point service. Scout issues bounded current-address queries and does not bulk-mirror this layer for responsible-party recovery.',
  'internal_reference_only',
  'Current address points expose FULL_ADDRESS, PARCELID and LRSN. Used only to bridge an exact site address to authoritative parcel identity; ownership still comes from Jefferson County PVA.',
  now()
)
on conflict(slug) do update set
  name=excluded.name,
  authority=excluded.authority,
  source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,
  acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,
  authority_level=excluded.authority_level,
  status=excluded.status,
  homepage_url=excluded.homepage_url,
  license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,
  notes=excluded.notes,
  updated_at=now();

insert into research.responsible_party_source_profiles(
  profile_key,provider_kind,state_code,county_name,parcel_source_slug,
  owner_lookup_url_template,source_authority,source_url,attributes,active,updated_at
)
values(
  'ky_jefferson_pva_address_lrsn',
  'pva_lrsn_html',
  'KY',
  'Jefferson',
  'jefferson-county-address-points',
  'https://jeffersonpva.ky.gov/property-search/property-details/?lrsn={lookup_key}',
  'LOJIC / Jefferson County Property Valuation Administrator',
  'https://gis.lojic.org/maps/rest/services/LojicSolutions/OpenDataAddresses/MapServer/0',
  jsonb_build_object(
    'resolution_mode','address_point_lrsn_recovery',
    'recovery_from_profile','ky_jefferson_pva_lrsn',
    'automated_dispatch',false,
    'eligible_source_kinds',jsonb_build_array(),
    'recovery_source_kinds',jsonb_build_array('construction_window','exterior_cleaning','roof_lifecycle'),
    'address_lookup_url','https://gis.lojic.org/maps/rest/services/LojicSolutions/OpenDataAddresses/MapServer/0/query',
    'address_full_field','FULL_ADDRESS',
    'address_house_number_field','HOUSENO',
    'address_parcel_id_field','PARCELID',
    'address_lrsn_field','LRSN',
    'address_apartment_field','APT',
    'identity_scope','property_owner_only',
    'exact_address_required',true,
    'bulk_mirror',false,
    'buyer_authority_not_implied',true,
    'property_manager_not_implied',true,
    'operator_not_implied',true
  ),
  true,
  now()
)
on conflict(profile_key) do update set
  provider_kind=excluded.provider_kind,
  state_code=excluded.state_code,
  county_name=excluded.county_name,
  parcel_source_slug=excluded.parcel_source_slug,
  owner_lookup_url_template=excluded.owner_lookup_url_template,
  source_authority=excluded.source_authority,
  source_url=excluded.source_url,
  attributes=excluded.attributes,
  active=excluded.active,
  updated_at=now();

create or replace function public.internal_seed_responsible_party_address_recovery_jobs_v1(
  p_limit integer default 250
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_jobs integer:=0;
  v_links integer:=0;
  v_candidates integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit<1 or p_limit>1000 then raise exception 'p_limit must be between 1 and 1000'; end if;

  create temporary table responsible_party_address_recovery_seed on commit drop as
  with eligible as (
    select
      q.candidate_key,
      q.source_kind,
      q.priority,
      coalesce(
        nullif(btrim(q.address_hint),''),
        nullif(btrim(s.details->>'address'),''),
        nullif(btrim(cp.address),'')
      ) as lookup_address,
      p.profile_key,
      scout.normalize_address_key_v2(coalesce(
        nullif(btrim(q.address_hint),''),
        nullif(btrim(s.details->>'address'),''),
        nullif(btrim(cp.address),'')
      )) as address_key
    from scout.buyer_resolution_queue q
    join scout.opportunity_search_spine s using(candidate_key)
    join research.responsible_party_source_profiles p
      on p.active
     and p.state_code=s.state_code
     and p.county_name=s.county_name
     and p.provider_kind='pva_lrsn_html'
     and p.attributes->>'resolution_mode'='address_point_lrsn_recovery'
     and pg_catalog.jsonb_exists(
       coalesce(pg_catalog.jsonb_extract_path(p.attributes,'recovery_source_kinds'),'[]'::jsonb),
       q.source_kind
     )
    join research.responsible_party_resolution_deferrals d
      on d.candidate_key=q.candidate_key
     and d.profile_key=p.attributes->>'recovery_from_profile'
     and d.reason in ('no_local_parcel_match','ambiguous_local_parcel_match','missing_local_parcel_lookup_key')
    left join intelligence.construction_service_windows w
      on q.source_kind='construction_window' and w.id=s.source_id
    left join intelligence.construction_projects cp on cp.id=w.project_id
    where q.state in ('pending','researching')
      and q.next_attempt_at<=now()
      and q.missing_steps @> array['organization_resolution']::text[]
      and nullif(btrim(q.buyer_hint),'') is null
      and coalesce(s.global_suppressed,false)=false
      and coalesce(
        nullif(btrim(q.address_hint),''),
        nullif(btrim(s.details->>'address'),''),
        nullif(btrim(cp.address),'')
      ) is not null
      and scout.normalize_address_key_v2(coalesce(
        nullif(btrim(q.address_hint),''),
        nullif(btrim(s.details->>'address'),''),
        nullif(btrim(cp.address),'')
      ))<>''
      and not exists (
        select 1
        from research.responsible_party_resolution_job_candidates l
        join research.responsible_party_resolution_jobs j on j.id=l.job_id
        where l.candidate_key=q.candidate_key
          and j.profile_key=p.profile_key
          and not (
            j.state='exhausted'
            and coalesce(j.requery_after,'infinity'::timestamptz)<=now()
          )
      )
    order by q.priority desc,q.candidate_key
    limit p_limit
  ), clustered as (
    select
      profile_key,
      address_key lookup_key,
      max(lookup_address) lookup_address,
      max(priority) priority,
      array_agg(candidate_key order by priority desc,candidate_key) candidate_keys,
      md5(concat_ws('|',profile_key,address_key,
        string_agg(candidate_key,',' order by candidate_key))) input_fingerprint
    from eligible
    group by profile_key,address_key
  )
  select * from clustered;

  select coalesce(sum(cardinality(candidate_keys)),0)::integer
  into v_candidates
  from responsible_party_address_recovery_seed;

  insert into research.responsible_party_resolution_jobs(
    profile_key,lookup_key,priority,max_attempts,input_fingerprint,updated_at
  )
  select profile_key,lookup_key,priority,2,input_fingerprint,now()
  from responsible_party_address_recovery_seed
  on conflict(profile_key,lookup_key) do update set
    priority=greatest(research.responsible_party_resolution_jobs.priority,excluded.priority),
    max_attempts=2,
    state=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint
       and research.responsible_party_resolution_jobs.state in ('failed','exhausted','needs_review') then 'queued'
      when research.responsible_party_resolution_jobs.state='exhausted'
       and research.responsible_party_resolution_jobs.requery_after<=now() then 'queued'
      else research.responsible_party_resolution_jobs.state
    end,
    attempt_count=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint then 0
      when research.responsible_party_resolution_jobs.state='exhausted'
       and research.responsible_party_resolution_jobs.requery_after<=now() then 0
      else research.responsible_party_resolution_jobs.attempt_count
    end,
    completed_at=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null
      else research.responsible_party_resolution_jobs.completed_at
    end,
    exhaustion_reason=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null
      else research.responsible_party_resolution_jobs.exhaustion_reason
    end,
    requery_after=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null
      else research.responsible_party_resolution_jobs.requery_after
    end,
    input_fingerprint=excluded.input_fingerprint,
    updated_at=now();
  get diagnostics v_jobs=row_count;

  insert into research.responsible_party_resolution_job_candidates(
    job_id,candidate_key,source_kind,address_hint,updated_at
  )
  select j.id,e.candidate_key,e.source_kind,e.lookup_address,now()
  from responsible_party_address_recovery_seed c
  join research.responsible_party_resolution_jobs j
    on j.profile_key=c.profile_key and j.lookup_key=c.lookup_key
  join lateral unnest(c.candidate_keys) ck(candidate_key) on true
  join (
    select q.candidate_key,q.source_kind,
      coalesce(nullif(btrim(q.address_hint),''),nullif(btrim(s.details->>'address'),''),nullif(btrim(cp.address),'')) lookup_address
    from scout.buyer_resolution_queue q
    join scout.opportunity_search_spine s using(candidate_key)
    left join intelligence.construction_service_windows w
      on q.source_kind='construction_window' and w.id=s.source_id
    left join intelligence.construction_projects cp on cp.id=w.project_id
  ) e on e.candidate_key=ck.candidate_key
  on conflict(job_id,candidate_key) do update set
    source_kind=excluded.source_kind,
    address_hint=excluded.address_hint,
    updated_at=now();
  get diagnostics v_links=row_count;

  return jsonb_build_object(
    'address_clusters',(select count(*) from responsible_party_address_recovery_seed),
    'eligible_candidates',v_candidates,
    'jobs_upserted',v_jobs,
    'candidate_links_upserted',v_links,
    'ready_recovery_jobs',(
      select count(*)
      from research.responsible_party_resolution_jobs j
      join research.responsible_party_source_profiles p on p.profile_key=j.profile_key
      where p.active
        and p.attributes->>'resolution_mode'='address_point_lrsn_recovery'
        and j.state in ('queued','failed')
        and j.attempt_count<j.max_attempts
        and j.next_attempt_at<=now()
    )
  );
end
$$;

revoke all on function public.internal_seed_responsible_party_address_recovery_jobs_v1(integer)
  from public,anon,authenticated;
grant execute on function public.internal_seed_responsible_party_address_recovery_jobs_v1(integer)
  to service_role;

create or replace function public.internal_claim_local_responsible_party_resolution_jobs_v1(
  p_limit integer default 8
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 20 then raise exception 'p_limit must be between 1 and 20'; end if;

  update research.responsible_party_resolution_jobs j
  set state='queued',claimed_at=null,lease_until=null,
      last_error=concat_ws(E'\n',nullif(j.last_error,''),'claim lease expired'),updated_at=now()
  where j.state='claimed' and j.lease_until<now()
    and exists (
      select 1 from research.responsible_party_source_profiles p
      where p.profile_key=j.profile_key and p.active and p.provider_kind='pva_lrsn_html'
    );

  update research.responsible_party_resolution_jobs j
  set state='exhausted',completed_at=coalesce(j.completed_at,now()),
      exhaustion_reason=coalesce(j.exhaustion_reason,'retry_budget_exhausted'),
      requery_after=coalesce(j.requery_after,now()+interval '90 days'),updated_at=now()
  where j.state in ('queued','failed') and j.attempt_count>=j.max_attempts
    and exists (
      select 1 from research.responsible_party_source_profiles p
      where p.profile_key=j.profile_key and p.provider_kind='pva_lrsn_html'
    );

  with picked as (
    select j.id
    from research.responsible_party_resolution_jobs j
    join research.responsible_party_source_profiles p on p.profile_key=j.profile_key
    where p.active and p.provider_kind='pva_lrsn_html'
      and coalesce((p.attributes->>'automated_dispatch')::boolean,true)=true
      and j.state in ('queued','failed')
      and j.attempt_count<j.max_attempts
      and j.next_attempt_at<=now()
    order by j.priority desc,j.next_attempt_at,j.created_at
    for update of j skip locked
    limit p_limit
  ), claimed as (
    update research.responsible_party_resolution_jobs j
    set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),
        lease_until=now()+interval '30 minutes',last_error=null,updated_at=now()
    from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'profile_key',c.profile_key,'lookup_key',c.lookup_key,
    'parcel_source_record_id',c.parcel_source_record_id,
    'parcel_source_native_id',c.parcel_source_native_id,'parcel_id',c.parcel_id,
    'priority',c.priority,'attempt_count',c.attempt_count,'max_attempts',c.max_attempts,
    'provider_kind',p.provider_kind,'owner_lookup_url_template',p.owner_lookup_url_template,
    'source_authority',p.source_authority,'source_url',p.source_url,
    'profile_attributes',p.attributes,
    'lookup_address',(select max(nullif(btrim(l.address_hint),''))
      from research.responsible_party_resolution_job_candidates l where l.job_id=c.id),
    'candidate_keys',(select coalesce(jsonb_agg(l.candidate_key order by l.candidate_key),'[]'::jsonb)
      from research.responsible_party_resolution_job_candidates l where l.job_id=c.id)
  ) order by c.priority desc,c.created_at),'[]'::jsonb)
  into v_result
  from claimed c
  join research.responsible_party_source_profiles p on p.profile_key=c.profile_key;

  return v_result;
end
$$;

revoke all on function public.internal_claim_local_responsible_party_resolution_jobs_v1(integer)
  from public,anon,authenticated;
grant execute on function public.internal_claim_local_responsible_party_resolution_jobs_v1(integer)
  to service_role;

create or replace function public.internal_claim_responsible_party_address_recovery_jobs_v1(
  p_limit integer default 4
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 8 then raise exception 'p_limit must be between 1 and 8'; end if;

  update research.responsible_party_resolution_jobs j
  set state='queued',claimed_at=null,lease_until=null,
      last_error=concat_ws(E'\n',nullif(j.last_error,''),'claim lease expired'),updated_at=now()
  where j.state='claimed' and j.lease_until<now()
    and exists (
      select 1 from research.responsible_party_source_profiles p
      where p.profile_key=j.profile_key and p.active
        and p.attributes->>'resolution_mode'='address_point_lrsn_recovery'
    );

  with picked as (
    select j.id
    from research.responsible_party_resolution_jobs j
    join research.responsible_party_source_profiles p on p.profile_key=j.profile_key
    where p.active
      and p.provider_kind='pva_lrsn_html'
      and p.attributes->>'resolution_mode'='address_point_lrsn_recovery'
      and j.state in ('queued','failed')
      and j.attempt_count<j.max_attempts
      and j.next_attempt_at<=now()
    order by j.priority desc,j.next_attempt_at,j.created_at
    for update of j skip locked
    limit p_limit
  ), claimed as (
    update research.responsible_party_resolution_jobs j
    set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),
        lease_until=now()+interval '30 minutes',last_error=null,updated_at=now()
    from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'profile_key',c.profile_key,'lookup_key',c.lookup_key,
    'parcel_source_record_id',c.parcel_source_record_id,
    'parcel_source_native_id',c.parcel_source_native_id,'parcel_id',c.parcel_id,
    'priority',c.priority,'attempt_count',c.attempt_count,'max_attempts',c.max_attempts,
    'provider_kind',p.provider_kind,'owner_lookup_url_template',p.owner_lookup_url_template,
    'source_authority',p.source_authority,'source_url',p.source_url,
    'profile_attributes',p.attributes,
    'lookup_address',(select max(nullif(btrim(l.address_hint),''))
      from research.responsible_party_resolution_job_candidates l where l.job_id=c.id),
    'candidate_keys',(select coalesce(jsonb_agg(l.candidate_key order by l.candidate_key),'[]'::jsonb)
      from research.responsible_party_resolution_job_candidates l where l.job_id=c.id)
  ) order by c.priority desc,c.created_at),'[]'::jsonb)
  into v_result
  from claimed c
  join research.responsible_party_source_profiles p on p.profile_key=c.profile_key;

  return v_result;
end
$$;

revoke all on function public.internal_claim_responsible_party_address_recovery_jobs_v1(integer)
  from public,anon,authenticated;
grant execute on function public.internal_claim_responsible_party_address_recovery_jobs_v1(integer)
  to service_role;

-- Recovery jobs are an alternate authoritative resolver and must not mutate the
-- original spatial deferral record merely by being seeded.
do $$
declare v_bad integer;
begin
  select count(*) into v_bad
  from research.responsible_party_source_profiles p
  where p.profile_key='ky_jefferson_pva_address_lrsn'
    and (
      pg_catalog.jsonb_array_length(coalesce(p.attributes->'eligible_source_kinds','[]'::jsonb))<>0
      or coalesce((p.attributes->>'automated_dispatch')::boolean,true)<>false
    );
  if v_bad<>0 then raise exception 'address recovery profile entered ordinary production dispatch'; end if;
end
$$;