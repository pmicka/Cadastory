insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,license_notes,commercial_use_status,notes,updated_at
) values (
  'usda-nrcs-soil-data-access-ssurgo',
  'USDA NRCS Soil Data Access / SSURGO',
  'USDA Natural Resources Conservation Service',
  'government_dataset',
  'United States',
  'NRCS Soil Data Access REST/POST query service; WGS84 spatial lookup',
  'Soil Data Access service synchronized regularly; official soil survey releases refreshed by NRCS',
  'federal_authoritative',
  'active',
  'https://sdmdataaccess.nrcs.usda.gov/',
  'U.S. federal soil survey data; preserve source metadata and interpretation limitations',
  'government_public_data',
  'Scout v1 samples the SSURGO map unit at an interior point of a pasture field. This is representative-point evidence, not a polygon-weighted field soil survey. Forage Suitability Group and range-production attributes may be null where NRCS has not populated them.',
  now()
) on conflict(slug) do update set
  name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,status=excluded.status,
  homepage_url=excluded.homepage_url,license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,notes=excluded.notes,updated_at=now();

create table if not exists agriculture.pasture_soil_point_samples_v1 (
  field_id uuid primary key references agriculture.field_boundaries(id) on delete cascade,
  source_id uuid not null references ingest.sources(id),
  sample_method text not null default 'field_point_on_surface_v1',
  sample_point extensions.geometry(Point,4326) not null,
  mukey text,
  mapunit_name text,
  dominant_component_key text,
  dominant_component_name text,
  dominant_component_pct numeric,
  representative_slope_pct numeric,
  drainage_class text,
  hydrologic_group text,
  forage_suitability_group_id text,
  range_production_low_lb_ac_yr numeric,
  range_production_rv_lb_ac_yr numeric,
  range_production_high_lb_ac_yr numeric,
  available_water_storage_0_100_mm numeric,
  status text not null default 'queued',
  http_status integer,
  attempt_count integer not null default 0,
  last_error text,
  source_payload jsonb not null default '{}'::jsonb,
  first_sampled_at timestamptz,
  last_sampled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists pasture_soil_point_samples_v1_status_idx
  on agriculture.pasture_soil_point_samples_v1(status,last_sampled_at);
create index if not exists pasture_soil_point_samples_v1_mukey_idx
  on agriculture.pasture_soil_point_samples_v1(mukey) where mukey is not null;

comment on table agriculture.pasture_soil_point_samples_v1 is
'Representative-point SSURGO samples for Scout pasture fields. Values characterize the SSURGO map unit/component at an interior field point and must not be represented as polygon-weighted whole-field measurements.';

create or replace view agriculture.v_pasture_soil_enrichment_queue_v1 as
with candidate_fields as (
  select
    c.field_id,
    min(case
      when c.existing_bridge_state is not null then 1
      when c.landholding_corroborated then 2
      when c.candidate_rank=1 and c.grazing_relevance='high' then 3
      when c.candidate_rank=1 and c.grazing_relevance='moderate' then 4
      when c.candidate_rank=1 then 5
      else 9
    end) as priority,
    bool_or(c.existing_bridge_state is not null) as has_existing_bridge,
    bool_or(c.landholding_corroborated) as landholding_corroborated,
    bool_or(c.candidate_rank=1) as is_top_candidate,
    max(c.grazing_relevance) filter (where c.candidate_rank=1) as top_candidate_grazing_relevance,
    min(c.distance_m) as nearest_farm_distance_m,
    count(distinct c.candidate_id)::integer as candidate_farm_count
  from agriculture.v_livestock_pasture_corroboration_v1 c
  where c.existing_bridge_state is not null
     or c.landholding_corroborated
     or c.candidate_rank=1
  group by c.field_id
)
select
  cf.field_id,cf.priority,cf.has_existing_bridge,cf.landholding_corroborated,
  cf.is_top_candidate,cf.top_candidate_grazing_relevance,cf.nearest_farm_distance_m,
  cf.candidate_farm_count,p.profile_class,p.grazing_relevance,p.gross_acres,
  s.status as sample_status,s.attempt_count,s.last_sampled_at,s.last_error
from candidate_fields cf
join agriculture.field_pasture_profiles_v1 p on p.field_id=cf.field_id
left join agriculture.pasture_soil_point_samples_v1 s on s.field_id=cf.field_id
where coalesce(s.status,'') <> 'success'
order by cf.priority,cf.nearest_farm_distance_m,cf.field_id;

comment on view agriculture.v_pasture_soil_enrichment_queue_v1 is
'Priority queue for representative-point NRCS SSURGO sampling. Existing corroborated fields rank first, followed by each livestock farm''s top pasture candidate.';

create or replace function agriculture.refresh_pasture_soil_point_samples_v1(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','agriculture','ingest','extensions'
as $function$
declare
  rec record;
  v_source_id uuid;
  v_point extensions.geometry(Point,4326);
  v_wkt text;
  v_query text;
  v_status integer;
  v_content_type text;
  v_content text;
  v_json jsonb;
  v_table jsonb;
  v_row jsonb;
  v_success integer := 0;
  v_failed integer := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_limit < 1 or p_limit > 50 then
    raise exception 'p_limit must be between 1 and 50';
  end if;

  select id into v_source_id from ingest.sources where slug='usda-nrcs-soil-data-access-ssurgo';
  if v_source_id is null then raise exception 'NRCS SDA source not registered'; end if;

  for rec in
    select q.field_id
    from agriculture.v_pasture_soil_enrichment_queue_v1 q
    order by q.priority,q.nearest_farm_distance_m,q.field_id
    limit p_limit
  loop
    begin
      select extensions.st_pointonsurface(f.geometry)::extensions.geometry(Point,4326)
      into v_point from agriculture.field_boundaries f where f.id=rec.field_id;
      v_wkt := extensions.st_astext(v_point);

      v_query := format(
        'SELECT TOP 1 s.mukey,mu.muname,c.cokey,c.compname,c.comppct_r,c.slope_r,c.drainagecl,c.hydgrp,c.foragesuitgrpid,c.rsprod_l,c.rsprod_r,c.rsprod_h,(SELECT SUM((CASE WHEN ch.hzdepb_r>100 THEN 100 ELSE ch.hzdepb_r END-CASE WHEN ch.hzdept_r<0 THEN 0 ELSE ch.hzdept_r END)*ch.awc_r*10.0) FROM chorizon ch WHERE ch.cokey=c.cokey AND ch.awc_r IS NOT NULL AND ch.hzdept_r<100 AND ch.hzdepb_r>0) AS aws_0_100_mm FROM SDA_Get_Mukey_from_intersection_with_WktWgs84(''%s'') s JOIN mapunit mu ON mu.mukey=s.mukey JOIN component c ON c.mukey=mu.mukey WHERE c.comppct_r IS NOT NULL ORDER BY c.comppct_r DESC,c.cokey',
        replace(v_wkt,'''','''''')
      );

      select r.status,r.content_type,r.content
      into v_status,v_content_type,v_content
      from extensions.http_post(
        'https://SDMDataAccess.sc.egov.usda.gov/Tabular/post.rest'::varchar,
        jsonb_build_object('query',v_query,'format','JSON+COLUMNNAME')
      ) r;

      if v_status=200 then
        v_json := v_content::jsonb;
        v_table := v_json->'Table';
      else
        v_table := null;
      end if;

      if v_status=200 and v_table is not null and jsonb_array_length(v_table)>=2 then
        v_row := v_table->1;
        insert into agriculture.pasture_soil_point_samples_v1(
          field_id,source_id,sample_method,sample_point,mukey,mapunit_name,dominant_component_key,
          dominant_component_name,dominant_component_pct,representative_slope_pct,drainage_class,
          hydrologic_group,forage_suitability_group_id,range_production_low_lb_ac_yr,
          range_production_rv_lb_ac_yr,range_production_high_lb_ac_yr,available_water_storage_0_100_mm,
          status,http_status,attempt_count,last_error,source_payload,first_sampled_at,last_sampled_at,updated_at
        ) values (
          rec.field_id,v_source_id,'field_point_on_surface_v1',v_point,
          nullif(v_row->>0,''),nullif(v_row->>1,''),nullif(v_row->>2,''),nullif(v_row->>3,''),
          nullif(v_row->>4,'')::numeric,nullif(v_row->>5,'')::numeric,nullif(v_row->>6,''),nullif(v_row->>7,''),
          nullif(v_row->>8,''),nullif(v_row->>9,'')::numeric,nullif(v_row->>10,'')::numeric,
          nullif(v_row->>11,'')::numeric,nullif(v_row->>12,'')::numeric,
          'success',v_status,1,null,jsonb_build_object('query_version','ssurgo_point_component_v1','response',v_json),now(),now(),now()
        ) on conflict(field_id) do update set
          source_id=excluded.source_id,sample_method=excluded.sample_method,sample_point=excluded.sample_point,
          mukey=excluded.mukey,mapunit_name=excluded.mapunit_name,dominant_component_key=excluded.dominant_component_key,
          dominant_component_name=excluded.dominant_component_name,dominant_component_pct=excluded.dominant_component_pct,
          representative_slope_pct=excluded.representative_slope_pct,drainage_class=excluded.drainage_class,
          hydrologic_group=excluded.hydrologic_group,forage_suitability_group_id=excluded.forage_suitability_group_id,
          range_production_low_lb_ac_yr=excluded.range_production_low_lb_ac_yr,
          range_production_rv_lb_ac_yr=excluded.range_production_rv_lb_ac_yr,
          range_production_high_lb_ac_yr=excluded.range_production_high_lb_ac_yr,
          available_water_storage_0_100_mm=excluded.available_water_storage_0_100_mm,
          status='success',http_status=excluded.http_status,
          attempt_count=agriculture.pasture_soil_point_samples_v1.attempt_count+1,last_error=null,
          source_payload=excluded.source_payload,first_sampled_at=coalesce(agriculture.pasture_soil_point_samples_v1.first_sampled_at,now()),
          last_sampled_at=now(),updated_at=now();
        v_success := v_success+1;
      else
        insert into agriculture.pasture_soil_point_samples_v1(
          field_id,source_id,sample_method,sample_point,status,http_status,attempt_count,last_error,source_payload,first_sampled_at,last_sampled_at,updated_at
        ) values (
          rec.field_id,v_source_id,'field_point_on_surface_v1',v_point,'failed',v_status,1,
          coalesce('NRCS SDA returned no usable map-unit/component row; content_type='||coalesce(v_content_type,'unknown'),'NRCS SDA request failed'),
          jsonb_build_object('query_version','ssurgo_point_component_v1','raw_content',left(coalesce(v_content,''),4000)),now(),now(),now()
        ) on conflict(field_id) do update set
          status='failed',http_status=excluded.http_status,
          attempt_count=agriculture.pasture_soil_point_samples_v1.attempt_count+1,last_error=excluded.last_error,
          source_payload=excluded.source_payload,last_sampled_at=now(),updated_at=now();
        v_failed := v_failed+1;
      end if;
    exception when others then
      insert into agriculture.pasture_soil_point_samples_v1(
        field_id,source_id,sample_method,sample_point,status,attempt_count,last_error,source_payload,first_sampled_at,last_sampled_at,updated_at
      ) values (
        rec.field_id,v_source_id,'field_point_on_surface_v1',coalesce(v_point,extensions.st_setsrid(extensions.st_makepoint(0,0),4326)::extensions.geometry(Point,4326)),
        'failed',1,left(sqlerrm,2000),'{}'::jsonb,now(),now(),now()
      ) on conflict(field_id) do update set
        status='failed',attempt_count=agriculture.pasture_soil_point_samples_v1.attempt_count+1,last_error=left(sqlerrm,2000),last_sampled_at=now(),updated_at=now();
      v_failed := v_failed+1;
    end;
  end loop;

  return jsonb_build_object('requested_limit',p_limit,'success',v_success,'failed',v_failed);
end;
$function$;

revoke all on function agriculture.refresh_pasture_soil_point_samples_v1(integer) from public;
grant execute on function agriculture.refresh_pasture_soil_point_samples_v1(integer) to service_role;