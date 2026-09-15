-- Add a bounded remote ArcGIS parcel-owner provider for counties where the
-- authoritative public parcel layer already exposes ownership. This avoids
-- mirroring an entire county dataset when Scout only needs responsibility
-- evidence for current opportunity points.
--
-- Property owner != property manager != operator != buyer. The downstream
-- responsible-party guardrails remain unchanged.

alter table research.responsible_party_source_profiles
  drop constraint if exists responsible_party_source_profiles_provider_kind_check;
alter table research.responsible_party_source_profiles
  add constraint responsible_party_source_profiles_provider_kind_check
  check (provider_kind in ('pva_lrsn_html','embedded_parcel_owner','arcgis_point_owner'));

insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,homepage_url,commercial_use_status,notes,updated_at
) values (
  'nelson-county-ky-parcels-live',
  'Nelson County KY PVA Parcels',
  'Nelson County Property Valuation Administrator / Schneider Geospatial',
  'county_parcel_assessor',
  'Nelson County, Kentucky',
  'Public ArcGIS MapServer point query',
  'publisher-maintained live service',
  'county_authoritative',
  'active_reference',
  'https://wfs.schneidercorp.com/arcgis/rest/services/NelsonCountyKY_WFS/MapServer/2',
  'unknown',
  'Public parcel layer exposes PARCEL_ID and OwnerName1. Scout queries only current opportunity points; it does not bulk-mirror or redistribute the county dataset. Ownership is responsibility evidence only and does not imply management, operation, or purchasing authority.',
  now()
)
on conflict(slug) do update set
  name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,
  status=excluded.status,homepage_url=excluded.homepage_url,
  commercial_use_status=excluded.commercial_use_status,notes=excluded.notes,updated_at=now();

insert into research.responsible_party_source_profiles(
  profile_key,state_code,county_name,provider_kind,parcel_source_slug,
  owner_lookup_url_template,source_authority,source_url,active,priority,attributes
) values (
  'ky_nelson_arcgis_owner','KY','Nelson','arcgis_point_owner','nelson-county-ky-parcels-live',
  'https://wfs.schneidercorp.com/arcgis/rest/services/NelsonCountyKY_WFS/MapServer/2/query',
  'Nelson County Property Valuation Administrator / Schneider Geospatial',
  'https://wfs.schneidercorp.com/arcgis/rest/services/NelsonCountyKY_WFS/MapServer/2',
  true,20,
  jsonb_build_object(
    'eligible_source_kinds',jsonb_build_array('exterior_cleaning'),
    'owner_field','OwnerName1','parcel_id_field','PARCEL_ID','query_sr',4326,
    'identity_scope','property_owner_only','query_mode','point_intersection',
    'buyer_authority_not_implied',true,'property_manager_not_implied',true,
    'operator_not_implied',true,'bulk_mirror',false
  )
)
on conflict(profile_key) do update set
  state_code=excluded.state_code,county_name=excluded.county_name,
  provider_kind=excluded.provider_kind,parcel_source_slug=excluded.parcel_source_slug,
  owner_lookup_url_template=excluded.owner_lookup_url_template,
  source_authority=excluded.source_authority,source_url=excluded.source_url,
  active=excluded.active,priority=excluded.priority,attributes=excluded.attributes,updated_at=now();

create or replace function public.internal_seed_remote_responsible_party_resolution_jobs_v1(p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_jobs integer:=0; v_links integer:=0; v_eligible integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 2000 then raise exception 'p_limit must be between 1 and 2000'; end if;

  create temporary table remote_responsible_party_seed on commit drop as
  select q.candidate_key,q.source_kind,q.priority,q.address_hint,p.profile_key,
         q.candidate_key lookup_key,
         extensions.st_x(s.location::extensions.geometry) longitude,
         extensions.st_y(s.location::extensions.geometry) latitude,
         md5(concat_ws('|',p.profile_key,q.candidate_key,coalesce(q.address_hint,''),
           round(extensions.st_x(s.location::extensions.geometry)::numeric,7)::text,
           round(extensions.st_y(s.location::extensions.geometry)::numeric,7)::text)) input_fingerprint
  from scout.buyer_resolution_queue q
  join scout.opportunity_search_spine s using(candidate_key)
  join research.responsible_party_source_profiles p
    on p.active and p.state_code=s.state_code and p.county_name=s.county_name
   and p.provider_kind='arcgis_point_owner'
   and pg_catalog.jsonb_exists(
     coalesce(pg_catalog.jsonb_extract_path(p.attributes,'eligible_source_kinds'),'[]'::jsonb),q.source_kind)
  where q.state in ('pending','researching')
    and q.next_attempt_at<=now()
    and q.missing_steps @> array['organization_resolution']::text[]
    and nullif(btrim(q.buyer_hint),'') is null
    and s.location is not null
    and coalesce(s.global_suppressed,false)=false
  order by q.priority desc,q.candidate_key
  limit p_limit;

  select count(*) into v_eligible from remote_responsible_party_seed;

  insert into research.responsible_party_resolution_jobs(
    profile_key,lookup_key,priority,input_fingerprint,updated_at
  )
  select profile_key,lookup_key,priority,input_fingerprint,now()
  from remote_responsible_party_seed
  on conflict(profile_key,lookup_key) do update set
    priority=greatest(research.responsible_party_resolution_jobs.priority,excluded.priority),
    state=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint
       and research.responsible_party_resolution_jobs.state in ('failed','exhausted','needs_review') then 'queued'
      when research.responsible_party_resolution_jobs.state='exhausted'
       and research.responsible_party_resolution_jobs.requery_after<=now() then 'queued'
      else research.responsible_party_resolution_jobs.state end,
    attempt_count=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint then 0
      else research.responsible_party_resolution_jobs.attempt_count end,
    input_fingerprint=excluded.input_fingerprint,updated_at=now();
  get diagnostics v_jobs=row_count;

  insert into research.responsible_party_resolution_job_candidates(
    job_id,candidate_key,source_kind,address_hint,updated_at
  )
  select j.id,s.candidate_key,s.source_kind,s.address_hint,now()
  from remote_responsible_party_seed s
  join research.responsible_party_resolution_jobs j
    on j.profile_key=s.profile_key and j.lookup_key=s.lookup_key
  on conflict(job_id,candidate_key) do update set
    source_kind=excluded.source_kind,address_hint=excluded.address_hint,updated_at=now();
  get diagnostics v_links=row_count;

  return jsonb_build_object(
    'eligible_candidates',v_eligible,'jobs_upserted',v_jobs,'candidate_links_upserted',v_links,
    'ready_jobs',(select count(*) from research.responsible_party_resolution_jobs j
      join research.responsible_party_source_profiles p on p.profile_key=j.profile_key
      where p.provider_kind='arcgis_point_owner' and j.state in ('queued','failed')
        and j.attempt_count<j.max_attempts and j.next_attempt_at<=now())
  );
end
$$;

revoke all on function public.internal_seed_remote_responsible_party_resolution_jobs_v1(integer) from public,anon,authenticated;
grant execute on function public.internal_seed_remote_responsible_party_resolution_jobs_v1(integer) to service_role;

create or replace function public.internal_claim_responsible_party_resolution_jobs_v1(p_limit integer default 8)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 20 then raise exception 'p_limit must be between 1 and 20'; end if;

  update research.responsible_party_resolution_jobs
  set state='queued',claimed_at=null,lease_until=null,last_error=concat_ws(E'\n',nullif(last_error,''),'claim lease expired'),updated_at=now()
  where state='claimed' and lease_until<now();
  update research.responsible_party_resolution_jobs
  set state='exhausted',completed_at=coalesce(completed_at,now()),
      exhaustion_reason=coalesce(exhaustion_reason,'retry_budget_exhausted'),
      requery_after=coalesce(requery_after,now()+interval '90 days'),updated_at=now()
  where state in ('queued','failed') and attempt_count>=max_attempts;

  with picked as (
    select id from research.responsible_party_resolution_jobs
    where state in ('queued','failed') and attempt_count<max_attempts and next_attempt_at<=now()
    order by priority desc,next_attempt_at,created_at for update skip locked limit p_limit
  ), claimed as (
    update research.responsible_party_resolution_jobs j
    set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),lease_until=now()+interval '30 minutes',last_error=null,updated_at=now()
    from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'profile_key',c.profile_key,'lookup_key',c.lookup_key,
    'parcel_source_record_id',c.parcel_source_record_id,'parcel_source_native_id',c.parcel_source_native_id,
    'parcel_id',c.parcel_id,'priority',c.priority,'attempt_count',c.attempt_count,'max_attempts',c.max_attempts,
    'provider_kind',p.provider_kind,'owner_lookup_url_template',p.owner_lookup_url_template,
    'source_authority',p.source_authority,'source_url',p.source_url,'profile_attributes',p.attributes,
    'lookup_latitude',(select extensions.st_y(s.location::extensions.geometry)
      from research.responsible_party_resolution_job_candidates l
      join scout.opportunity_search_spine s on s.candidate_key=l.candidate_key
      where l.job_id=c.id and s.location is not null order by l.candidate_key limit 1),
    'lookup_longitude',(select extensions.st_x(s.location::extensions.geometry)
      from research.responsible_party_resolution_job_candidates l
      join scout.opportunity_search_spine s on s.candidate_key=l.candidate_key
      where l.job_id=c.id and s.location is not null order by l.candidate_key limit 1),
    'lookup_address',(select l.address_hint
      from research.responsible_party_resolution_job_candidates l
      where l.job_id=c.id order by l.candidate_key limit 1),
    'candidate_keys',(select coalesce(jsonb_agg(l.candidate_key order by l.candidate_key),'[]'::jsonb)
      from research.responsible_party_resolution_job_candidates l where l.job_id=c.id)
  ) order by c.priority desc,c.created_at),'[]'::jsonb)
  into v_result from claimed c join research.responsible_party_source_profiles p on p.profile_key=c.profile_key;
  return v_result;
end
$$;

revoke all on function public.internal_claim_responsible_party_resolution_jobs_v1(integer) from public,anon,authenticated;
grant execute on function public.internal_claim_responsible_party_resolution_jobs_v1(integer) to service_role;

create or replace function research.seed_responsible_party_resolution_jobs_cron_v1(p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_local jsonb; v_remote jsonb;
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then raise exception 'postgres scheduler only'; end if;
  perform set_config('request.jwt.claim.role','service_role',true);
  v_local:=public.internal_seed_responsible_party_resolution_jobs_v1(p_limit);
  v_remote:=public.internal_seed_remote_responsible_party_resolution_jobs_v1(p_limit);
  return jsonb_build_object('local',v_local,'remote',v_remote);
end
$$;

revoke all on function research.seed_responsible_party_resolution_jobs_cron_v1(integer) from public,anon,authenticated,service_role;
grant execute on function research.seed_responsible_party_resolution_jobs_cron_v1(integer) to postgres;

-- Contract guards: Nelson is bounded to exterior-cleaning for its initial rollout,
-- and the public layer contract must identify both owner and parcel fields.
do $$
declare v_attrs jsonb;
begin
  select attributes into v_attrs from research.responsible_party_source_profiles
  where profile_key='ky_nelson_arcgis_owner';
  if v_attrs is null
     or not pg_catalog.jsonb_exists(v_attrs->'eligible_source_kinds','exterior_cleaning')
     or v_attrs->>'owner_field' <> 'OwnerName1'
     or v_attrs->>'parcel_id_field' <> 'PARCEL_ID' then
    raise exception 'Nelson ArcGIS owner provider contract regression';
  end if;
end
$$;
