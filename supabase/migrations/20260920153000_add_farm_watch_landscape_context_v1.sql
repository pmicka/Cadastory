-- Farm Watch deer-focused landscape context foundation v1.
-- This remains neutral landscape evidence: no deer score or behavioral prediction is produced.

alter table farm_watch.hydrology_refresh_state_v1
  drop constraint if exists hydrology_refresh_state_v1_buffer_m_check;

alter table farm_watch.hydrology_refresh_state_v1
  add constraint hydrology_refresh_state_v1_buffer_m_check
  check (buffer_m between 0 and 3000);

create table if not exists farm_watch.property_landscape_barrier_rules_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  barrier_label text not null,
  barrier_class text not null check (barrier_class in ('major_river')),
  source_slug text not null,
  source_feature_kind text not null check (source_feature_kind in ('flowline')),
  source_property_key text not null,
  source_property_value text not null,
  permeability numeric not null check (permeability between 0 and 1),
  evidence_class text not null check (evidence_class in ('operator_model_assumption')),
  rationale text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (property_id, barrier_label)
);

alter table farm_watch.property_landscape_barrier_rules_v1 enable row level security;
revoke all on table farm_watch.property_landscape_barrier_rules_v1 from public, anon, authenticated;
grant select, insert, update, delete on table farm_watch.property_landscape_barrier_rules_v1 to service_role;

comment on table farm_watch.property_landscape_barrier_rules_v1 is
'Explicit property-scoped movement-barrier assumptions for Farm Watch landscape analysis. These are model/operator assumptions, not wildlife observations.';

insert into farm_watch.property_landscape_barrier_rules_v1(
  property_id,barrier_label,barrier_class,source_slug,source_feature_kind,
  source_property_key,source_property_value,permeability,evidence_class,rationale,active
)
select
  p.id,
  'Kentucky River',
  'major_river',
  'usgs-3dhp',
  'flowline',
  'name',
  'Kentucky River',
  0,
  'operator_model_assumption',
  'Treat the Kentucky River as non-traversable for the initial property-scale deer landscape model. This is overrideable and does not assert that white-tailed deer are physically incapable of swimming the river.',
  true
from farm_watch.properties p
where p.slug='validation-property-01'
on conflict(property_id,barrier_label) do update set
  barrier_class=excluded.barrier_class,
  source_slug=excluded.source_slug,
  source_feature_kind=excluded.source_feature_kind,
  source_property_key=excluded.source_property_key,
  source_property_value=excluded.source_property_value,
  permeability=excluded.permeability,
  evidence_class=excluded.evidence_class,
  rationale=excluded.rationale,
  active=excluded.active,
  updated_at=now();

create or replace function farm_watch.farm_watch_context_contract_v1(
  p_product_kind text
) returns jsonb
language plpgsql
immutable
security definer
set search_path=pg_catalog
as $$
begin
  if p_product_kind='soils-map-units' then
    return jsonb_build_object(
      'algorithm_version','ssurgo-map-units-v1',
      'output_schema_version','farm-watch-soils-map-units-v1',
      'source_signature','usda-nrcs-geodata-cg-soils-ssurgo|usda-nrcs-soil-data-access-ssurgo|geometry_query=farm_watch_ssurgo_polygon_v1|attribute_query=farm_watch_ssurgo_mapunit_component_v1'
    );
  elsif p_product_kind='soils-profiles' then
    return jsonb_build_object(
      'algorithm_version','ssurgo-deep-profiles-v1',
      'output_schema_version','farm-watch-soils-profiles-v1',
      'source_signature','usda-nrcs-soil-data-access-ssurgo|query=farm_watch_ssurgo_deep_profile_v1'
    );
  elsif p_product_kind='hydrology' then
    return jsonb_build_object(
      'algorithm_version','authoritative-hydrology-buffer-v2',
      'output_schema_version','farm-watch-hydrology-v1',
      'source_signature','usgs-3dhp-mapserver-50-60|usfws-nwi-mapserver-0|buffer_m=3000|normalization=farm_watch_hydrology_v1'
    );
  elsif p_product_kind='landscape-domain' then
    return jsonb_build_object(
      'algorithm_version','barrier-aware-landscape-domain-v1',
      'output_schema_version','farm-watch-landscape-domain-v1',
      'source_signature','zones_m=500,1500,3000|hard_barrier=matched_3dhp_named_flowline_to_intersecting_river_waterbody|fallback_flowline_buffer_m=30|component_rule=intersects_property'
    );
  elsif p_product_kind='land' then
    return jsonb_build_object(
      'algorithm_version','farm-watch-land-context-v6',
      'output_schema_version','farm-watch-land-context-v1',
      'source_signature','kgs-24k-geology|kgs-lithology|kgs-sinkholes|ky-huc12|kyfromabove-phase3-dem|nlcd-tcc-v2025-6|science-tcc-v2025-6|science-tcc-se-v2025-6|physical-synthesis-v1'
    );
  elsif p_product_kind='environment' then
    return jsonb_build_object(
      'algorithm_version','farm-watch-environment-context-v1',
      'output_schema_version','farm-watch-environment-context-v1',
      'source_signature','daymet-daily-single-pixel|usgs-daily-values-nearest-gauge|usdm-county-weekly|soil-moisture-unresolved'
    );
  elsif p_product_kind='regulatory-static' then
    return jsonb_build_object(
      'algorithm_version','farm-watch-regulatory-static-v1',
      'output_schema_version','farm-watch-regulatory-static-v1',
      'source_signature','franklin-zoning|future-land-use|fema-nfhl|pad-us|kdfwr-deer-regulations|kentucky-drone-wildlife-rules'
    );
  elsif p_product_kind='regulatory-faa' then
    return jsonb_build_object(
      'algorithm_version','farm-watch-regulatory-faa-v1',
      'output_schema_version','farm-watch-regulatory-faa-v1',
      'source_signature','faa-airspace-awareness|uas-facility-map|national-security|special-use-airspace|airports|stadiums|tfr'
    );
  end if;
  raise exception 'unsupported Farm Watch context product: %', p_product_kind;
end;
$$;

create or replace function farm_watch.farm_watch_context_identity_v1(
  p_property_id uuid,
  p_product_kind text
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
declare
  v_boundary extensions.geometry;
  v_contract jsonb;
  v_source_signature text;
  v_boundary_sha256 text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_dep jsonb;
  v_soil_units_at text;
  v_soil_profiles_at text;
  v_hydrology_at text;
  v_barrier_rules text;
begin
  select boundary into v_boundary
  from farm_watch.properties
  where id=p_property_id and status='active'
  limit 1;

  if v_boundary is null then
    return null;
  end if;

  v_contract := farm_watch.farm_watch_context_contract_v1(p_product_kind);
  v_source_signature := v_contract->>'source_signature';

  if p_product_kind='soils-profiles' then
    v_dep := farm_watch.farm_watch_context_identity_v1(p_property_id,'soils-map-units');
    v_source_signature := v_source_signature
      || '|map_units_identity=' || coalesce(v_dep->>'identity_sha256','missing');
  elsif p_product_kind='landscape-domain' then
    select to_char(max(retrieved_at) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      into v_hydrology_at
    from farm_watch.hydrology_refresh_state_v1
    where property_id=p_property_id;

    select string_agg(
      concat_ws(
        '~',
        barrier_label,
        barrier_class,
        source_slug,
        source_feature_kind,
        source_property_key,
        source_property_value,
        permeability::text,
        evidence_class,
        active::text
      ),
      '|' order by barrier_label
    )
    into v_barrier_rules
    from farm_watch.property_landscape_barrier_rules_v1
    where property_id=p_property_id and active;

    v_source_signature := v_source_signature
      || '|hydrology_identity='
      || coalesce((farm_watch.farm_watch_context_identity_v1(p_property_id,'hydrology')->>'identity_sha256'),'missing')
      || '|hydrology_retrieved=' || coalesce(v_hydrology_at,'missing')
      || '|barrier_rules=' || coalesce(v_barrier_rules,'none');
  elsif p_product_kind='land' then
    select to_char(max(source_retrieved_at) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      into v_soil_units_at
    from farm_watch.property_soil_map_units_v1
    where property_id=p_property_id;

    select to_char(max(source_retrieved_at) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      into v_soil_profiles_at
    from farm_watch.property_soil_profiles_v1
    where property_id=p_property_id;

    select to_char(max(retrieved_at) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      into v_hydrology_at
    from farm_watch.hydrology_refresh_state_v1
    where property_id=p_property_id;

    v_source_signature := v_source_signature
      || '|soils_map_identity='
      || coalesce((farm_watch.farm_watch_context_identity_v1(p_property_id,'soils-map-units')->>'identity_sha256'),'missing')
      || '|soils_map_retrieved=' || coalesce(v_soil_units_at,'missing')
      || '|soils_profile_identity='
      || coalesce((farm_watch.farm_watch_context_identity_v1(p_property_id,'soils-profiles')->>'identity_sha256'),'missing')
      || '|soils_profile_retrieved=' || coalesce(v_soil_profiles_at,'missing')
      || '|hydrology_identity='
      || coalesce((farm_watch.farm_watch_context_identity_v1(p_property_id,'hydrology')->>'identity_sha256'),'missing')
      || '|hydrology_retrieved=' || coalesce(v_hydrology_at,'missing');
  end if;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),
    'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          p_property_id::text,
          p_product_kind,
          v_contract->>'algorithm_version',
          v_contract->>'output_schema_version',
          v_boundary_sha256,
          v_source_signature_sha256
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'product_kind',p_product_kind,
    'boundary_sha256',v_boundary_sha256,
    'source_signature',v_source_signature,
    'source_signature_sha256',v_source_signature_sha256,
    'algorithm_version',v_contract->>'algorithm_version',
    'output_schema_version',v_contract->>'output_schema_version',
    'identity_sha256',v_identity_sha256
  );
end;
$$;

revoke all on function farm_watch.farm_watch_context_contract_v1(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_context_identity_v1(uuid,text) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_context_contract_v1(text) to postgres,service_role;
grant execute on function farm_watch.farm_watch_context_identity_v1(uuid,text) to postgres,service_role;

create or replace function public.farm_watch_replace_hydrology_v1_internal(
  p_slug text,
  p_features jsonb,
  p_buffer_m integer default 3000,
  p_source_status jsonb default '{}'::jsonb,
  p_retrieved_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $function$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_item jsonb;
  v_kind text;
  v_source_slug text;
  v_source_feature_id text;
  v_geom extensions.geometry;
  v_intersects boolean;
  v_distance_m numeric;
  v_inserted integer := 0;
  v_available integer := 0;
  v_total_sources integer := 3;
  v_status text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_buffer_m < 0 or p_buffer_m > 3000 then
    raise exception 'p_buffer_m must be between 0 and 3000';
  end if;
  if jsonb_typeof(coalesce(p_features,'[]'::jsonb)) <> 'array' then
    raise exception 'p_features must be a JSON array';
  end if;

  select p.id, p.boundary
  into v_property_id, v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    raise exception 'active Farm Watch property with boundary required';
  end if;

  if coalesce(p_source_status->>'flowline','')='available' then
    delete from farm_watch.property_hydrology_features_v1
    where property_id=v_property_id and feature_kind='flowline';
    v_available := v_available + 1;
  end if;
  if coalesce(p_source_status->>'waterbody','')='available' then
    delete from farm_watch.property_hydrology_features_v1
    where property_id=v_property_id and feature_kind='waterbody';
    v_available := v_available + 1;
  end if;
  if coalesce(p_source_status->>'wetland','')='available' then
    delete from farm_watch.property_hydrology_features_v1
    where property_id=v_property_id and feature_kind='wetland';
    v_available := v_available + 1;
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_features,'[]'::jsonb))
  loop
    begin
      v_kind := nullif(v_item->>'feature_kind','');
      v_source_slug := nullif(v_item->>'source_slug','');
      v_source_feature_id := nullif(v_item->>'source_feature_id','');
      if v_kind not in ('flowline','waterbody','wetland') or v_source_slug is null or v_source_feature_id is null then
        continue;
      end if;
      if v_item->'geometry' is null or v_item->'geometry'='null'::jsonb then
        continue;
      end if;

      v_geom := extensions.st_setsrid(extensions.st_geomfromgeojson((v_item->'geometry')::text),4326);
      v_geom := extensions.st_makevalid(v_geom);
      if v_kind='flowline' then
        v_geom := extensions.st_collectionextract(v_geom,2);
      else
        v_geom := extensions.st_collectionextract(v_geom,3);
      end if;
      if v_geom is null or extensions.st_isempty(v_geom) then
        continue;
      end if;

      if not extensions.st_dwithin(v_geom::extensions.geography, v_boundary::extensions.geography, p_buffer_m) then
        continue;
      end if;

      v_intersects := extensions.st_intersects(v_geom,v_boundary);
      v_distance_m := extensions.st_distance(v_geom::extensions.geography,v_boundary::extensions.geography);

      insert into farm_watch.property_hydrology_features_v1(
        property_id,source_slug,feature_kind,source_feature_id,geometry,intersects_property,distance_m,
        intersection_acres,intersection_length_m,properties,retrieved_at,updated_at
      ) values (
        v_property_id,v_source_slug,v_kind,v_source_feature_id,v_geom,v_intersects,v_distance_m,
        case when v_intersects and v_kind in ('waterbody','wetland')
          then extensions.st_area(extensions.st_intersection(v_geom,v_boundary)::extensions.geography)/4046.8564224
          else null end,
        case when v_intersects and v_kind='flowline'
          then extensions.st_length(extensions.st_intersection(v_geom,v_boundary)::extensions.geography)
          else null end,
        coalesce(v_item->'properties','{}'::jsonb),coalesce(p_retrieved_at,now()),now()
      )
      on conflict(property_id,source_slug,feature_kind,source_feature_id) do update set
        geometry=excluded.geometry,
        intersects_property=excluded.intersects_property,
        distance_m=excluded.distance_m,
        intersection_acres=excluded.intersection_acres,
        intersection_length_m=excluded.intersection_length_m,
        properties=excluded.properties,
        retrieved_at=excluded.retrieved_at,
        updated_at=now();
      v_inserted := v_inserted + 1;
    exception when others then
      continue;
    end;
  end loop;

  v_status := case
    when v_available=v_total_sources then 'available'
    when v_available>0 then 'partial'
    else 'unavailable'
  end;

  insert into farm_watch.hydrology_refresh_state_v1(property_id,buffer_m,status,source_status,retrieved_at,last_error,updated_at)
  values (v_property_id,p_buffer_m,v_status,coalesce(p_source_status,'{}'::jsonb),coalesce(p_retrieved_at,now()),null,now())
  on conflict(property_id) do update set
    buffer_m=excluded.buffer_m,
    status=excluded.status,
    source_status=excluded.source_status,
    retrieved_at=excluded.retrieved_at,
    last_error=null,
    updated_at=now();

  return jsonb_build_object(
    'status',v_status,
    'features_stored',v_inserted,
    'sources_available',v_available,
    'sources_expected',v_total_sources,
    'buffer_m',p_buffer_m,
    'retrieved_at',coalesce(p_retrieved_at,now())
  );
end;
$function$;

revoke all on function public.farm_watch_replace_hydrology_v1_internal(text,jsonb,integer,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.farm_watch_replace_hydrology_v1_internal(text,jsonb,integer,jsonb,timestamptz) to service_role;

create table if not exists farm_watch.property_landscape_domains_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  status text not null check (status in ('available','partial','unavailable')),
  local_500m extensions.geometry(MultiPolygon,4326),
  landscape_1500m extensions.geometry(MultiPolygon,4326),
  broad_3000m extensions.geometry(MultiPolygon,4326),
  barrier_geometry extensions.geometry(MultiPolygon,4326),
  barrier_context jsonb not null default '{}'::jsonb,
  boundary_sha256 text not null,
  source_signature text not null,
  source_signature_sha256 text not null,
  algorithm_version text not null,
  output_schema_version text not null,
  identity_sha256 text not null,
  retrieved_at timestamptz not null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists property_landscape_domains_v1_local_gix
  on farm_watch.property_landscape_domains_v1 using gist(local_500m);
create index if not exists property_landscape_domains_v1_landscape_gix
  on farm_watch.property_landscape_domains_v1 using gist(landscape_1500m);
create index if not exists property_landscape_domains_v1_broad_gix
  on farm_watch.property_landscape_domains_v1 using gist(broad_3000m);

alter table farm_watch.property_landscape_domains_v1 enable row level security;
revoke all on table farm_watch.property_landscape_domains_v1 from public,anon,authenticated;
grant select,insert,update,delete on table farm_watch.property_landscape_domains_v1 to service_role;

comment on table farm_watch.property_landscape_domains_v1 is
'Barrier-aware 500 m / 1.5 km / 3 km Farm Watch analysis domains. These are deterministic landscape derivatives, not deer-use predictions.';

create or replace function farm_watch.farm_watch_barrier_aware_buffer_v1(
  p_boundary extensions.geometry,
  p_barrier extensions.geometry,
  p_radius_m integer
) returns extensions.geometry
language sql
immutable
security definer
set search_path=pg_catalog,extensions
as $$
  with buffered as (
    select (extensions.st_buffer(p_boundary::extensions.geography,p_radius_m))::extensions.geometry as geom
  ),
  cut as (
    select case
      when p_barrier is null or extensions.st_isempty(p_barrier) then geom
      else extensions.st_difference(geom,p_barrier)
    end as geom
    from buffered
  ),
  parts as (
    select (extensions.st_dump(extensions.st_collectionextract(extensions.st_makevalid(geom),3))).geom as geom
    from cut
  )
  select extensions.st_multi(extensions.st_unaryunion(extensions.st_collect(geom)))
  from parts
  where extensions.st_intersects(geom,p_boundary);
$$;

revoke all on function farm_watch.farm_watch_barrier_aware_buffer_v1(extensions.geometry,extensions.geometry,integer) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_barrier_aware_buffer_v1(extensions.geometry,extensions.geometry,integer) to postgres,service_role;

create or replace function farm_watch.farm_watch_refresh_landscape_domain_v1_internal(
  p_slug text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_hydrology_identity text;
  v_hydrology_current boolean;
  v_hydrology_buffer integer;
  v_rule_count integer;
  v_resolved_rule_count integer;
  v_barrier extensions.geometry;
  v_barrier_context jsonb;
  v_local extensions.geometry;
  v_landscape extensions.geometry;
  v_broad extensions.geometry;
  v_identity jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select id,boundary into v_property_id,v_boundary
  from farm_watch.properties
  where slug=p_slug and status='active' and boundary is not null
  limit 1;

  if v_property_id is null then
    return jsonb_build_object('status','unavailable','reason','active property boundary unavailable');
  end if;

  v_hydrology_identity := farm_watch.farm_watch_context_identity_v1(v_property_id,'hydrology')->>'identity_sha256';

  select
    exists(
      select 1 from farm_watch.hydrology_refresh_state_v1
      where property_id=v_property_id and identity_sha256=v_hydrology_identity
    ),
    coalesce(max(buffer_m),0)
  into v_hydrology_current,v_hydrology_buffer
  from farm_watch.hydrology_refresh_state_v1
  where property_id=v_property_id;

  if not v_hydrology_current or v_hydrology_buffer < 3000 then
    return jsonb_build_object(
      'status','unavailable',
      'reason','current 3000 m hydrology context required',
      'hydrology_identity_current',v_hydrology_current,
      'hydrology_buffer_m',v_hydrology_buffer
    );
  end if;

  select count(*) into v_rule_count
  from farm_watch.property_landscape_barrier_rules_v1
  where property_id=v_property_id and active and permeability=0;

  with rules as (
    select *
    from farm_watch.property_landscape_barrier_rules_v1
    where property_id=v_property_id and active and permeability=0
  ),
  lines as (
    select
      r.barrier_label,
      h.source_feature_id,
      h.geometry
    from rules r
    join farm_watch.property_hydrology_features_v1 h
      on h.property_id=r.property_id
     and h.source_slug=r.source_slug
     and h.feature_kind=r.source_feature_kind
     and lower(coalesce(h.properties->>r.source_property_key,''))=lower(r.source_property_value)
  ),
  bodies as (
    select distinct
      l.barrier_label,
      h.source_feature_id,
      h.geometry
    from lines l
    join farm_watch.property_hydrology_features_v1 h
      on h.property_id=v_property_id
     and h.source_slug='usgs-3dhp'
     and h.feature_kind='waterbody'
     and lower(coalesce(h.properties->>'feature_type',''))='river'
     and (
       extensions.st_intersects(h.geometry,l.geometry)
       or extensions.st_dwithin(h.geometry::extensions.geography,l.geometry::extensions.geography,25)
     )
  ),
  line_union as (
    select barrier_label,
           extensions.st_unaryunion(extensions.st_collect(geometry)) geom,
           jsonb_agg(source_feature_id order by source_feature_id) ids
    from lines group by barrier_label
  ),
  body_union as (
    select barrier_label,
           extensions.st_unaryunion(extensions.st_collect(geometry)) geom,
           jsonb_agg(source_feature_id order by source_feature_id) ids
    from bodies group by barrier_label
  ),
  resolved as (
    select
      r.barrier_label,
      r.evidence_class,
      r.rationale,
      r.permeability,
      lu.ids flowline_ids,
      bu.ids waterbody_ids,
      case
        when bu.geom is not null then bu.geom
        when lu.geom is not null then (extensions.st_buffer(lu.geom::extensions.geography,30))::extensions.geometry
        else null
      end geom
    from rules r
    left join line_union lu on lu.barrier_label=r.barrier_label
    left join body_union bu on bu.barrier_label=r.barrier_label
  )
  select
    count(*) filter(where geom is not null),
    extensions.st_multi(
      extensions.st_collectionextract(
        extensions.st_unaryunion(extensions.st_collect(geom)),
        3
      )
    ),
    coalesce(
      jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'barrier_label',barrier_label,
          'barrier_class','major_river',
          'permeability',permeability,
          'evidence_class',evidence_class,
          'rationale',rationale,
          'matched_flowline_ids',flowline_ids,
          'matched_waterbody_ids',waterbody_ids,
          'resolution',case
            when waterbody_ids is not null then 'intersecting_3dhp_river_waterbody'
            when flowline_ids is not null then '30m_flowline_fallback'
            else 'unresolved'
          end
        ))
        order by barrier_label
      ),
      '[]'::jsonb
    )
  into v_resolved_rule_count,v_barrier,v_barrier_context
  from resolved;

  if v_resolved_rule_count < v_rule_count then
    insert into farm_watch.property_landscape_domains_v1(
      property_id,status,barrier_context,boundary_sha256,source_signature,source_signature_sha256,
      algorithm_version,output_schema_version,identity_sha256,retrieved_at,last_error,updated_at
    )
    select
      v_property_id,'unavailable',v_barrier_context,
      i->>'boundary_sha256',i->>'source_signature',i->>'source_signature_sha256',
      i->>'algorithm_version',i->>'output_schema_version',i->>'identity_sha256',
      now(),'one or more hard barrier rules could not be resolved',now()
    from (select farm_watch.farm_watch_context_identity_v1(v_property_id,'landscape-domain') i) s
    on conflict(property_id) do update set
      status=excluded.status,
      local_500m=null,
      landscape_1500m=null,
      broad_3000m=null,
      barrier_geometry=excluded.barrier_geometry,
      barrier_context=excluded.barrier_context,
      boundary_sha256=excluded.boundary_sha256,
      source_signature=excluded.source_signature,
      source_signature_sha256=excluded.source_signature_sha256,
      algorithm_version=excluded.algorithm_version,
      output_schema_version=excluded.output_schema_version,
      identity_sha256=excluded.identity_sha256,
      retrieved_at=excluded.retrieved_at,
      last_error=excluded.last_error,
      updated_at=now();

    return jsonb_build_object(
      'status','unavailable',
      'reason','hard barrier rule unresolved',
      'rules_expected',v_rule_count,
      'rules_resolved',v_resolved_rule_count,
      'barriers',v_barrier_context
    );
  end if;

  v_local := farm_watch.farm_watch_barrier_aware_buffer_v1(v_boundary,v_barrier,500);
  v_landscape := farm_watch.farm_watch_barrier_aware_buffer_v1(v_boundary,v_barrier,1500);
  v_broad := farm_watch.farm_watch_barrier_aware_buffer_v1(v_boundary,v_barrier,3000);

  if v_local is null or v_landscape is null or v_broad is null then
    return jsonb_build_object('status','unavailable','reason','landscape domain geometry could not be derived');
  end if;

  v_identity := farm_watch.farm_watch_context_identity_v1(v_property_id,'landscape-domain');

  insert into farm_watch.property_landscape_domains_v1(
    property_id,status,local_500m,landscape_1500m,broad_3000m,barrier_geometry,barrier_context,
    boundary_sha256,source_signature,source_signature_sha256,algorithm_version,output_schema_version,
    identity_sha256,retrieved_at,last_error,updated_at
  ) values (
    v_property_id,'available',v_local,v_landscape,v_broad,v_barrier,v_barrier_context,
    v_identity->>'boundary_sha256',v_identity->>'source_signature',v_identity->>'source_signature_sha256',
    v_identity->>'algorithm_version',v_identity->>'output_schema_version',
    v_identity->>'identity_sha256',now(),null,now()
  )
  on conflict(property_id) do update set
    status=excluded.status,
    local_500m=excluded.local_500m,
    landscape_1500m=excluded.landscape_1500m,
    broad_3000m=excluded.broad_3000m,
    barrier_geometry=excluded.barrier_geometry,
    barrier_context=excluded.barrier_context,
    boundary_sha256=excluded.boundary_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    last_error=null,
    updated_at=now();

  return jsonb_build_object(
    'status','available',
    'identity_sha256',v_identity->>'identity_sha256',
    'zones_m',jsonb_build_array(500,1500,3000),
    'hard_barrier_count',v_rule_count,
    'barriers',v_barrier_context,
    'retrieved_at',now()
  );
end;
$$;

revoke all on function farm_watch.farm_watch_refresh_landscape_domain_v1_internal(text) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_refresh_landscape_domain_v1_internal(text) to service_role;

create or replace function farm_watch.farm_watch_get_landscape_domain_v1_internal(
  p_slug text
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
  with property as (
    select id from farm_watch.properties
    where slug=p_slug and status='active' limit 1
  ),
  expected as (
    select farm_watch.farm_watch_context_identity_v1(id,'landscape-domain') identity
    from property
  ),
  stored as (
    select d.* from farm_watch.property_landscape_domains_v1 d
    join property p on p.id=d.property_id
  ),
  current as (
    select d.* from stored d cross join expected e
    where d.identity_sha256=e.identity->>'identity_sha256'
  )
  select case
    when not exists(select 1 from property) then jsonb_build_object('status','missing')
    when not exists(select 1 from stored) then jsonb_build_object('status','missing')
    when not exists(select 1 from current) then jsonb_build_object(
      'status','stale',
      'invalidation_reason','identity_mismatch',
      'stored_identity_sha256',(select identity_sha256 from stored),
      'expected_identity_sha256',(select identity->>'identity_sha256' from expected)
    )
    else jsonb_build_object(
      'status',(select status from current),
      'zones',jsonb_build_object(
        'local_500m',case when (select local_500m from current) is null then null
          else extensions.st_asgeojson((select local_500m from current),6)::jsonb end,
        'landscape_1500m',case when (select landscape_1500m from current) is null then null
          else extensions.st_asgeojson((select landscape_1500m from current),6)::jsonb end,
        'broad_3000m',case when (select broad_3000m from current) is null then null
          else extensions.st_asgeojson((select broad_3000m from current),6)::jsonb end
      ),
      'barriers',jsonb_build_object(
        'geometry',case when (select barrier_geometry from current) is null then null
          else extensions.st_asgeojson((select barrier_geometry from current),6)::jsonb end,
        'context',(select barrier_context from current)
      ),
      'identity',jsonb_build_object(
        'boundary_sha256',(select boundary_sha256 from current),
        'source_signature_sha256',(select source_signature_sha256 from current),
        'algorithm_version',(select algorithm_version from current),
        'output_schema_version',(select output_schema_version from current),
        'identity_sha256',(select identity_sha256 from current)
      ),
      'retrieved_at',(select retrieved_at from current),
      'last_error',(select last_error from current)
    )
  end;
$$;

revoke all on function farm_watch.farm_watch_get_landscape_domain_v1_internal(text) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_landscape_domain_v1_internal(text) to service_role;

create or replace function farm_watch.farm_watch_get_landscape_context_v1_internal(
  p_slug text
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
  with property as (
    select id,boundary from farm_watch.properties
    where slug=p_slug and status='active' and boundary is not null limit 1
  ),
  expected as (
    select farm_watch.farm_watch_context_identity_v1(id,'landscape-domain') identity from property
  ),
  stored as (
    select d.* from farm_watch.property_landscape_domains_v1 d
    join property p on p.id=d.property_id
  ),
  domain as (
    select d.* from stored d cross join expected e
    where d.identity_sha256=e.identity->>'identity_sha256'
      and d.status='available'
  ),
  zones as (
    select 500 radius_m,local_500m geom from domain
    union all
    select 1500,landscape_1500m from domain
    union all
    select 3000,broad_3000m from domain
  ),
  field_stats as (
    select
      z.radius_m,
      count(distinct f.id)::integer field_count,
      count(distinct f.id) filter(where f.latest_crop_year is not null)::integer crop_history_field_count,
      coalesce(sum(extensions.st_area(extensions.st_intersection(f.geometry,z.geom)::extensions.geography)),0)/4046.8564224 field_acres
    from zones z
    left join agriculture.field_boundaries f
      on z.geom is not null and f.geometry is not null and extensions.st_intersects(f.geometry,z.geom)
    group by z.radius_m
  ),
  access_rows as (
    select
      a.*,
      extensions.st_distance(a.geometry::extensions.geography,p.boundary::extensions.geography) distance_m
    from decisioning.site_access_features a
    cross join property p
    cross join domain d
    where a.geometry is not null
      and d.landscape_1500m is not null
      and extensions.st_intersects(a.geometry,d.landscape_1500m)
  ),
  access_stats as (
    select
      count(*)::integer total,
      count(*) filter(where drivable)::integer drivable,
      count(*) filter(where feature_class='driveway')::integer driveways,
      count(*) filter(where feature_subclass='track')::integer tracks,
      count(*) filter(where access_point)::integer access_points,
      count(*) filter(where routing_barrier)::integer routing_barriers,
      min(distance_m) filter(where drivable) nearest_drivable_m,
      min(distance_m) filter(where feature_class='driveway') nearest_driveway_m,
      min(distance_m) filter(where feature_subclass='track') nearest_track_m
    from access_rows
  ),
  structure_sources as (
    select id,slug,name,source_class,status
    from ingest.sources
    where slug in (
      'fema-usa-structures-current',
      'ky-ornl-building-footprints',
      'overture-buildings',
      'openstreetmap-targeted-building-identity'
    )
  ),
  structure_stats as (
    select
      s.slug,s.name,s.source_class,s.status,
      count(r.id) filter(
        where r.geometry is not null
          and d.broad_3000m is not null
          and extensions.st_intersects(r.geometry,d.broad_3000m)
      )::integer feature_count
    from structure_sources s
    cross join domain d
    left join ingest.raw_records r on r.source_id=s.id
    group by s.slug,s.name,s.source_class,s.status
  ),
  zone_areas as (
    select radius_m,extensions.st_area(geom::extensions.geography)/4046.8564224 acres
    from zones where geom is not null
  )
  select case
    when not exists(select 1 from property) then jsonb_build_object('status','missing')
    when not exists(select 1 from stored) then jsonb_build_object('status','missing')
    when not exists(select 1 from domain) then jsonb_build_object(
      'status','stale_or_unavailable',
      'stored_status',(select status from stored),
      'stored_identity_sha256',(select identity_sha256 from stored),
      'expected_identity_sha256',(select identity->>'identity_sha256' from expected)
    )
    else jsonb_build_object(
      'status','available',
      'evidence_class','deterministic_derived',
      'scoring_performed',false,
      'domain',jsonb_build_object(
        'zones_m',jsonb_build_array(500,1500,3000),
        'areas_acres',coalesce((
          select jsonb_object_agg(radius_m::text,round(acres::numeric,2)) from zone_areas
        ),'{}'::jsonb),
        'barriers',(select barrier_context from domain)
      ),
      'agriculture',jsonb_build_object(
        'field_context_by_zone',coalesce((
          select jsonb_agg(jsonb_build_object(
            'radius_m',radius_m,
            'field_count',field_count,
            'crop_history_field_count',crop_history_field_count,
            'intersected_field_acres',round(field_acres::numeric,2)
          ) order by radius_m)
          from field_stats
        ),'[]'::jsonb),
        'interpretation_boundary','Mapped agricultural-field context only. A mapped field is not itself evidence of current forage quality or deer use.'
      ),
      'human_access',jsonb_build_object(
        'radius_m',1500,
        'feature_count',coalesce((select total from access_stats),0),
        'drivable_count',coalesce((select drivable from access_stats),0),
        'driveway_count',coalesce((select driveways from access_stats),0),
        'track_count',coalesce((select tracks from access_stats),0),
        'access_point_count',coalesce((select access_points from access_stats),0),
        'routing_barrier_count',coalesce((select routing_barriers from access_stats),0),
        'nearest_drivable_m',case when (select nearest_drivable_m from access_stats) is null then null
          else round((select nearest_drivable_m from access_stats)::numeric,1) end,
        'nearest_driveway_m',case when (select nearest_driveway_m from access_stats) is null then null
          else round((select nearest_driveway_m from access_stats)::numeric,1) end,
        'nearest_track_m',case when (select nearest_track_m from access_stats) is null then null
          else round((select nearest_track_m from access_stats)::numeric,1) end,
        'interpretation_boundary','Mapped access infrastructure is a human-access exposure input, not measured visitation, hunting pressure, or disturbance frequency.'
      ),
      'structures',jsonb_build_object(
        'radius_m',3000,
        'by_source',coalesce((
          select jsonb_agg(jsonb_build_object(
            'source_slug',slug,
            'source_name',name,
            'source_class',source_class,
            'source_status',status,
            'feature_count',feature_count
          ) order by slug)
          from structure_stats
        ),'[]'::jsonb),
        'merged_structure_count',null,
        'interpretation_boundary','Counts remain source-specific because footprint-source coverage and overlap have not yet been reconciled. Zero rows are not treated as proof that no structures exist.'
      ),
      'identity_sha256',(select identity_sha256 from domain),
      'retrieved_at',(select retrieved_at from domain)
    )
  end;
$$;

revoke all on function farm_watch.farm_watch_get_landscape_context_v1_internal(text) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_landscape_context_v1_internal(text) to service_role;

comment on function farm_watch.farm_watch_get_landscape_context_v1_internal(text) is
'Returns neutral barrier-aware landscape context for Farm Watch. No deer suitability score, behavioral prediction, or wildlife observation is implied.';
