-- Production migration mirror: stabilize_scheduled_collector_hot_paths_v1
-- Applied to Supabase project ufpkjaadmmpmeogzhrcq on 2026-09-09.
--
-- Goals:
-- 1. make pilot-county lookup indexable for PHMSA collectors;
-- 2. defer expensive field geometry work until after bounded target selection;
-- 3. stop every NWI target from forcing a full-corpus NWI signal refresh;
-- 4. reduce avoidable stream-gauge write churn while preserving source_present semantics.

create index if not exists field_boundaries_pilot_county_scope_idx
  on agriculture.field_boundaries(state_fips, county_name, county_fips)
  where within_pilot is true;

create or replace function public.internal_get_soil_moisture_field_targets(p_limit integer default 25)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
with candidate_fields as (
  select distinct ec.field_id
  from agriculture.field_entity_candidates ec
), selected as (
  select f.id::text as field_id,
         f.geometry,
         f.acres,
         f.latest_crop_year,
         f.latest_crop_code,
         c.observed_at
  from candidate_fields cf
  join agriculture.field_boundaries f on f.id=cf.field_id
  left join hydrology.field_soil_moisture_context c on c.field_id=f.id
  where f.source_present
    and f.within_pilot
    and (c.field_id is null or c.expires_at is null or c.expires_at<=now())
  order by c.observed_at nulls first,f.acres desc nulls last
  limit greatest(1,least(coalesce(p_limit,25),100))
), q as (
  select s.field_id,
         extensions.st_x(p.pt) as longitude,
         extensions.st_y(p.pt) as latitude,
         extensions.st_x(extensions.st_transform(p.pt,5070)) as x5070,
         extensions.st_y(extensions.st_transform(p.pt,5070)) as y5070,
         s.acres,s.latest_crop_year,s.latest_crop_code
  from selected s
  cross join lateral (
    select extensions.st_pointonsurface(s.geometry) as pt
  ) p
)
select coalesce(jsonb_agg(jsonb_build_object(
  'field_id',field_id,
  'longitude',longitude,
  'latitude',latitude,
  'x5070',x5070,
  'y5070',y5070,
  'acres',acres,
  'latest_crop_year',latest_crop_year,
  'latest_crop_code',latest_crop_code
)),'[]'::jsonb)
from q;
$function$;

create or replace function public.internal_get_nwi_field_targets(p_limit integer default 25)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
with candidate_links as (
  select ec.field_id,
         count(distinct ec.candidate_id)::int as candidate_count,
         max(ec.confidence) as max_relationship_confidence,
         max(case fc.resolution_status
               when 'operator_candidate' then 3
               when 'landholder_farm_candidate' then 2
               when 'landholder_only' then 1
               else 0
             end) as resolution_rank
  from agriculture.field_entity_candidates ec
  join agriculture.farm_entity_candidates fc on fc.id=ec.candidate_id
  where coalesce(ec.relationship_status,'observed') not in ('rejected','inactive')
  group by ec.field_id
), selected as (
  select f.id::text as subject_key,
         f.geometry,
         f.acres,
         f.boundary_source_kind,
         cl.candidate_count,
         cl.max_relationship_confidence,
         cl.resolution_rank,
         c.checked_at
  from candidate_links cl
  join agriculture.field_boundaries f on f.id=cl.field_id
  left join hydrology.nwi_context_checks c
    on c.subject_type='ag_field' and c.subject_key=f.id::text
  where f.source_present
    and f.within_pilot
    and (c.id is null or c.expires_at is null or c.expires_at<=now())
  order by cl.resolution_rank desc,
           cl.max_relationship_confidence desc nulls last,
           c.checked_at nulls first,
           f.acres desc nulls last
  limit greatest(1,least(coalesce(p_limit,25),100))
), q as (
  select s.subject_key,
         extensions.st_x(p.pt) as longitude,
         extensions.st_y(p.pt) as latitude,
         least(1500,greatest(250,ceil(100 + sqrt(greatest(coalesce(s.acres,1),1)::double precision*4046.8564224/pi()))::int)) as radius_m,
         s.acres,
         s.boundary_source_kind,
         s.candidate_count,
         s.max_relationship_confidence,
         s.resolution_rank
  from selected s
  cross join lateral (
    select extensions.st_pointonsurface(s.geometry) as pt
  ) p
)
select coalesce(jsonb_agg(jsonb_build_object(
  'subject_type','ag_field',
  'subject_key',subject_key,
  'longitude',longitude,
  'latitude',latitude,
  'radius_m',radius_m,
  'acres',acres,
  'boundary_source_kind',boundary_source_kind,
  'candidate_count',candidate_count,
  'max_relationship_confidence',max_relationship_confidence,
  'candidate_resolution_rank',resolution_rank
)),'[]'::jsonb)
from q;
$function$;

create or replace function public.internal_store_nwi_context(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_source uuid;
  v_indicator uuid;
  v_ag_service uuid;
  v_swppp_service uuid;
  n int;
begin
  select id into v_source from ingest.sources where slug='usfws-nwi';
  select id into v_indicator from intelligence.indicator_definitions where slug='hydrologic_sensitivity';
  select id into v_ag_service from commerce.service_types where slug='agricultural-drainage-mapping';
  select id into v_swppp_service from commerce.service_types where slug='swppp-erosion-documentation';

  insert into hydrology.nwi_context_checks(
    subject_type,subject_key,source_id,location,query_radius_m,feature_count,
    reported_feature_acres_sum,wetland_types,checked_at,expires_at,attributes
  )
  select x.subject_type,x.subject_key,v_source,
         extensions.st_setsrid(extensions.st_makepoint(x.longitude,x.latitude),4326)::extensions.geography,
         x.query_radius_m,x.feature_count,x.reported_feature_acres_sum,
         coalesce(x.wetland_types,'{}'::text[]),now(),now()+interval '120 days',
         coalesce(x.attributes,'{}'::jsonb)
  from jsonb_to_recordset(p_rows) x(
    subject_type text,subject_key text,longitude double precision,latitude double precision,
    query_radius_m int,feature_count int,reported_feature_acres_sum numeric,
    wetland_types text[],attributes jsonb
  )
  on conflict(subject_type,subject_key) do update
    set location=excluded.location,
        query_radius_m=excluded.query_radius_m,
        feature_count=excluded.feature_count,
        reported_feature_acres_sum=excluded.reported_feature_acres_sum,
        wetland_types=excluded.wetland_types,
        checked_at=now(),
        expires_at=excluded.expires_at,
        attributes=excluded.attributes;
  get diagnostics n=row_count;

  insert into intelligence.business_need_signals(
    service_type_id,indicator_id,subject_type,subject_key,location,signal_type,
    signal_strength,confidence,observed_at,valid_from,ideal_until,expires_at,
    can_open_window,reason,evidence,source_slugs,status
  )
  select case c.subject_type
           when 'ag_field' then v_ag_service
           when 'construction_project' then v_swppp_service
         end,
         v_indicator,c.subject_type,c.subject_key,c.location,'nwi_mapped_wetland_context',
         case when c.feature_count>=10 then 'high' when c.feature_count>0 then 'medium' else 'context' end,
         case when c.feature_count>0 then 0.82 else 0.70 end,
         c.checked_at,c.checked_at,c.expires_at,c.expires_at,false,
         case
           when c.subject_type='ag_field' and c.feature_count>0 then
             format('USFWS NWI maps %s wetland/deepwater feature(s) in the field-scale context area; use as drainage/hydrologic-sensitivity context, not a jurisdictional determination.',c.feature_count)
           when c.subject_type='ag_field' then
             'No NWI wetland/deepwater features were returned in the cached field-scale context query; mapped absence is not proof of physical absence.'
           when c.subject_type='construction_project' and c.feature_count>0 then
             format('USFWS NWI maps %s wetland/deepwater feature(s) near this construction project; this increases hydrologic sensitivity but does not establish SWPPP applicability or jurisdiction.',c.feature_count)
           else
             'No NWI wetland/deepwater features were returned in the cached project-scale context query; mapped absence is not proof of physical absence.'
         end,
         jsonb_build_object(
           'feature_count',c.feature_count,
           'reported_feature_acres_sum',c.reported_feature_acres_sum,
           'wetland_types',c.wetland_types,
           'query_radius_m',c.query_radius_m,
           'nwi_semantics','biological inventory/context only; not jurisdictional',
           'cache_expires_at',c.expires_at
         ),
         array['usfws-nwi']::text[],'active'
  from hydrology.nwi_context_checks c
  join jsonb_to_recordset(p_rows) x(subject_type text,subject_key text)
    on x.subject_type=c.subject_type and x.subject_key=c.subject_key
  where c.subject_type in ('ag_field','construction_project')
  on conflict(service_type_id,indicator_id,subject_type,subject_key,signal_type) do update
    set location=excluded.location,
        signal_strength=excluded.signal_strength,
        confidence=excluded.confidence,
        observed_at=excluded.observed_at,
        valid_from=excluded.valid_from,
        ideal_until=excluded.ideal_until,
        expires_at=excluded.expires_at,
        can_open_window=excluded.can_open_window,
        reason=excluded.reason,
        evidence=excluded.evidence,
        source_slugs=excluded.source_slugs,
        status='active',
        updated_at=now();

  return n;
end;
$function$;

create or replace function public.internal_ingest_stream_data(p_gauges jsonb, p_observations jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_source uuid;
  ng int;
  no int;
begin
  select id into v_source from ingest.sources where slug='usgs-water-data-api';

  insert into hydrology.stream_gauges(
    gauge_id,source_id,name,site_type,state,county,huc,latitude,longitude,location,
    drainage_area_sqmi,source_present,last_seen_at,attributes
  )
  select distinct on (x.gauge_id)
         x.gauge_id,v_source,x.name,x.site_type,x.state,x.county,x.huc,
         x.latitude,x.longitude,
         extensions.st_setsrid(extensions.st_makepoint(x.longitude,x.latitude),4326)::extensions.geography,
         x.drainage_area_sqmi,true,now(),coalesce(x.attributes,'{}'::jsonb)
  from jsonb_to_recordset(p_gauges) x(
    gauge_id text,name text,site_type text,state text,county text,huc text,
    latitude double precision,longitude double precision,drainage_area_sqmi numeric,attributes jsonb
  )
  where x.gauge_id is not null
  order by x.gauge_id
  on conflict(gauge_id) do update
    set name=excluded.name,
        site_type=excluded.site_type,
        state=excluded.state,
        county=excluded.county,
        huc=excluded.huc,
        latitude=excluded.latitude,
        longitude=excluded.longitude,
        location=excluded.location,
        drainage_area_sqmi=excluded.drainage_area_sqmi,
        source_present=true,
        last_seen_at=now(),
        attributes=excluded.attributes,
        updated_at=now();
  get diagnostics ng=row_count;

  update hydrology.stream_gauges g
  set source_present=false,updated_at=now()
  where g.source_present is true
    and not exists (
      select 1
      from jsonb_to_recordset(p_gauges) x(gauge_id text)
      where x.gauge_id=g.gauge_id
    );

  insert into hydrology.stream_observations(
    gauge_id,source_id,parameter_code,parameter_name,value,unit,approval_status,
    qualifier,observed_at,retrieved_at,attributes
  )
  select distinct on (x.gauge_id,x.parameter_code,x.observed_at)
         x.gauge_id,v_source,x.parameter_code,x.parameter_name,x.value,x.unit,
         x.approval_status,x.qualifier,x.observed_at,now(),coalesce(x.attributes,'{}'::jsonb)
  from jsonb_to_recordset(p_observations) x(
    gauge_id text,parameter_code text,parameter_name text,value numeric,unit text,
    approval_status text,qualifier text,observed_at timestamptz,attributes jsonb
  )
  join hydrology.stream_gauges g on g.gauge_id=x.gauge_id
  order by x.gauge_id,x.parameter_code,x.observed_at,x.approval_status desc nulls last
  on conflict(gauge_id,parameter_code,observed_at) do update
    set value=excluded.value,
        unit=excluded.unit,
        approval_status=excluded.approval_status,
        qualifier=excluded.qualifier,
        retrieved_at=now(),
        attributes=excluded.attributes;
  get diagnostics no=row_count;

  return jsonb_build_object('gauges',ng,'observations',no);
end;
$function$;
