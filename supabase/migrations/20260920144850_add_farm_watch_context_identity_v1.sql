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
      'algorithm_version','authoritative-hydrology-buffer-v1',
      'output_schema_version','farm-watch-hydrology-v1',
      'source_signature','usgs-3dhp-mapserver-50-60|usfws-nwi-mapserver-0|buffer_m=1000|normalization=farm_watch_hydrology_v1'
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

alter table farm_watch.property_soil_map_units_v1
  add column if not exists boundary_sha256 text,
  add column if not exists source_signature text,
  add column if not exists source_signature_sha256 text,
  add column if not exists algorithm_version text,
  add column if not exists output_schema_version text,
  add column if not exists identity_sha256 text;

alter table farm_watch.property_soil_profiles_v1
  add column if not exists boundary_sha256 text,
  add column if not exists source_signature text,
  add column if not exists source_signature_sha256 text,
  add column if not exists algorithm_version text,
  add column if not exists output_schema_version text,
  add column if not exists identity_sha256 text;

alter table farm_watch.hydrology_refresh_state_v1
  add column if not exists boundary_sha256 text,
  add column if not exists source_signature text,
  add column if not exists source_signature_sha256 text,
  add column if not exists algorithm_version text,
  add column if not exists output_schema_version text,
  add column if not exists identity_sha256 text;

alter table farm_watch.property_land_context_v1
  add column if not exists boundary_sha256 text,
  add column if not exists source_signature text,
  add column if not exists source_signature_sha256 text,
  add column if not exists algorithm_version text,
  add column if not exists output_schema_version text,
  add column if not exists identity_sha256 text;

alter table farm_watch.property_environment_context_v1
  add column if not exists boundary_sha256 text,
  add column if not exists source_signature text,
  add column if not exists source_signature_sha256 text,
  add column if not exists algorithm_version text,
  add column if not exists output_schema_version text,
  add column if not exists identity_sha256 text;

alter table farm_watch.property_regulatory_context_v1
  add column if not exists static_boundary_sha256 text,
  add column if not exists static_source_signature text,
  add column if not exists static_source_signature_sha256 text,
  add column if not exists static_algorithm_version text,
  add column if not exists static_output_schema_version text,
  add column if not exists static_identity_sha256 text,
  add column if not exists faa_boundary_sha256 text,
  add column if not exists faa_source_signature text,
  add column if not exists faa_source_signature_sha256 text,
  add column if not exists faa_algorithm_version text,
  add column if not exists faa_output_schema_version text,
  add column if not exists faa_identity_sha256 text;

create or replace function farm_watch.farm_watch_stamp_context_identity_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,farm_watch
as $$
declare
  v_identity jsonb;
begin
  v_identity := farm_watch.farm_watch_context_identity_v1(new.property_id,tg_argv[0]);
  if v_identity is null then
    raise exception 'active Farm Watch property boundary required';
  end if;
  new.boundary_sha256 := v_identity->>'boundary_sha256';
  new.source_signature := v_identity->>'source_signature';
  new.source_signature_sha256 := v_identity->>'source_signature_sha256';
  new.algorithm_version := v_identity->>'algorithm_version';
  new.output_schema_version := v_identity->>'output_schema_version';
  new.identity_sha256 := v_identity->>'identity_sha256';
  return new;
end;
$$;

create or replace function farm_watch.farm_watch_stamp_regulatory_identity_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,farm_watch
as $$
declare
  v_identity jsonb;
begin
  if tg_op='INSERT'
     or new.static_status is distinct from old.static_status
     or new.static_context is distinct from old.static_context
     or new.static_retrieved_at is distinct from old.static_retrieved_at then
    v_identity := farm_watch.farm_watch_context_identity_v1(new.property_id,'regulatory-static');
    new.static_boundary_sha256 := v_identity->>'boundary_sha256';
    new.static_source_signature := v_identity->>'source_signature';
    new.static_source_signature_sha256 := v_identity->>'source_signature_sha256';
    new.static_algorithm_version := v_identity->>'algorithm_version';
    new.static_output_schema_version := v_identity->>'output_schema_version';
    new.static_identity_sha256 := v_identity->>'identity_sha256';
  end if;

  if tg_op='INSERT'
     or new.faa_status is distinct from old.faa_status
     or new.faa_context is distinct from old.faa_context
     or new.faa_checked_at is distinct from old.faa_checked_at then
    v_identity := farm_watch.farm_watch_context_identity_v1(new.property_id,'regulatory-faa');
    new.faa_boundary_sha256 := v_identity->>'boundary_sha256';
    new.faa_source_signature := v_identity->>'source_signature';
    new.faa_source_signature_sha256 := v_identity->>'source_signature_sha256';
    new.faa_algorithm_version := v_identity->>'algorithm_version';
    new.faa_output_schema_version := v_identity->>'output_schema_version';
    new.faa_identity_sha256 := v_identity->>'identity_sha256';
  end if;
  return new;
end;
$$;

revoke all on function farm_watch.farm_watch_stamp_context_identity_v1() from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_stamp_regulatory_identity_v1() from public,anon,authenticated;

drop trigger if exists property_soil_map_units_identity_v1 on farm_watch.property_soil_map_units_v1;
create trigger property_soil_map_units_identity_v1
before insert or update on farm_watch.property_soil_map_units_v1
for each row execute function farm_watch.farm_watch_stamp_context_identity_v1('soils-map-units');

drop trigger if exists property_soil_profiles_identity_v1 on farm_watch.property_soil_profiles_v1;
create trigger property_soil_profiles_identity_v1
before insert or update on farm_watch.property_soil_profiles_v1
for each row execute function farm_watch.farm_watch_stamp_context_identity_v1('soils-profiles');

drop trigger if exists hydrology_refresh_state_identity_v1 on farm_watch.hydrology_refresh_state_v1;
create trigger hydrology_refresh_state_identity_v1
before insert or update on farm_watch.hydrology_refresh_state_v1
for each row execute function farm_watch.farm_watch_stamp_context_identity_v1('hydrology');

drop trigger if exists property_land_context_identity_v1 on farm_watch.property_land_context_v1;
create trigger property_land_context_identity_v1
before insert or update on farm_watch.property_land_context_v1
for each row execute function farm_watch.farm_watch_stamp_context_identity_v1('land');

drop trigger if exists property_environment_context_identity_v1 on farm_watch.property_environment_context_v1;
create trigger property_environment_context_identity_v1
before insert or update on farm_watch.property_environment_context_v1
for each row execute function farm_watch.farm_watch_stamp_context_identity_v1('environment');

drop trigger if exists property_regulatory_context_identity_v1 on farm_watch.property_regulatory_context_v1;
create trigger property_regulatory_context_identity_v1
before insert or update on farm_watch.property_regulatory_context_v1
for each row execute function farm_watch.farm_watch_stamp_regulatory_identity_v1();

update farm_watch.property_soil_map_units_v1 set updated_at=updated_at;
update farm_watch.property_soil_profiles_v1 set updated_at=updated_at;
update farm_watch.hydrology_refresh_state_v1 set updated_at=updated_at;
update farm_watch.property_land_context_v1 set updated_at=updated_at;
update farm_watch.property_environment_context_v1 set updated_at=updated_at;

update farm_watch.property_regulatory_context_v1 r
set
  static_boundary_sha256=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-static')->>'boundary_sha256'),
  static_source_signature=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-static')->>'source_signature'),
  static_source_signature_sha256=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-static')->>'source_signature_sha256'),
  static_algorithm_version=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-static')->>'algorithm_version'),
  static_output_schema_version=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-static')->>'output_schema_version'),
  static_identity_sha256=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-static')->>'identity_sha256'),
  faa_boundary_sha256=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-faa')->>'boundary_sha256'),
  faa_source_signature=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-faa')->>'source_signature'),
  faa_source_signature_sha256=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-faa')->>'source_signature_sha256'),
  faa_algorithm_version=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-faa')->>'algorithm_version'),
  faa_output_schema_version=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-faa')->>'output_schema_version'),
  faa_identity_sha256=(farm_watch.farm_watch_context_identity_v1(r.property_id,'regulatory-faa')->>'identity_sha256');

alter table farm_watch.property_soil_map_units_v1
  alter column boundary_sha256 set not null,
  alter column source_signature set not null,
  alter column source_signature_sha256 set not null,
  alter column algorithm_version set not null,
  alter column output_schema_version set not null,
  alter column identity_sha256 set not null;
alter table farm_watch.property_soil_profiles_v1
  alter column boundary_sha256 set not null,
  alter column source_signature set not null,
  alter column source_signature_sha256 set not null,
  alter column algorithm_version set not null,
  alter column output_schema_version set not null,
  alter column identity_sha256 set not null;
alter table farm_watch.hydrology_refresh_state_v1
  alter column boundary_sha256 set not null,
  alter column source_signature set not null,
  alter column source_signature_sha256 set not null,
  alter column algorithm_version set not null,
  alter column output_schema_version set not null,
  alter column identity_sha256 set not null;
alter table farm_watch.property_land_context_v1
  alter column boundary_sha256 set not null,
  alter column source_signature set not null,
  alter column source_signature_sha256 set not null,
  alter column algorithm_version set not null,
  alter column output_schema_version set not null,
  alter column identity_sha256 set not null;
alter table farm_watch.property_environment_context_v1
  alter column boundary_sha256 set not null,
  alter column source_signature set not null,
  alter column source_signature_sha256 set not null,
  alter column algorithm_version set not null,
  alter column output_schema_version set not null,
  alter column identity_sha256 set not null;
alter table farm_watch.property_regulatory_context_v1
  alter column static_boundary_sha256 set not null,
  alter column static_source_signature set not null,
  alter column static_source_signature_sha256 set not null,
  alter column static_algorithm_version set not null,
  alter column static_output_schema_version set not null,
  alter column static_identity_sha256 set not null,
  alter column faa_boundary_sha256 set not null,
  alter column faa_source_signature set not null,
  alter column faa_source_signature_sha256 set not null,
  alter column faa_algorithm_version set not null,
  alter column faa_output_schema_version set not null,
  alter column faa_identity_sha256 set not null;

create or replace function farm_watch.farm_watch_get_land_context_v1_internal(p_slug text)
returns jsonb
language sql
security definer
set search_path=pg_catalog,farm_watch
as $$
  with property as (
    select p.id from farm_watch.properties p
    where p.slug=p_slug and p.status='active' limit 1
  ),
  expected as (
    select farm_watch.farm_watch_context_identity_v1(id,'land') as identity from property
  ),
  cached as (
    select c.* from farm_watch.property_land_context_v1 c
    join property p on p.id=c.property_id
  )
  select case
    when not exists(select 1 from property) then jsonb_build_object('status','missing','context',null)
    when not exists(select 1 from cached) then jsonb_build_object('status','missing','context',null)
    when (select identity_sha256 from cached)=(select identity->>'identity_sha256' from expected)
      then jsonb_build_object(
        'status',(select status from cached),
        'context',(select context from cached),
        'retrieved_at',(select retrieved_at from cached),
        'identity',jsonb_build_object(
          'boundary_sha256',(select boundary_sha256 from cached),
          'source_signature_sha256',(select source_signature_sha256 from cached),
          'algorithm_version',(select algorithm_version from cached),
          'output_schema_version',(select output_schema_version from cached),
          'identity_sha256',(select identity_sha256 from cached)
        )
      )
    else jsonb_build_object(
      'status','stale','context',null,
      'retrieved_at',(select retrieved_at from cached),
      'invalidation_reason','identity_mismatch',
      'stored_identity_sha256',(select identity_sha256 from cached),
      'expected_identity_sha256',(select identity->>'identity_sha256' from expected)
    )
  end;
$$;

create or replace function farm_watch.farm_watch_get_environment_context_v1_internal(
  p_slug text,p_context_date date
) returns jsonb
language sql
security definer
set search_path=pg_catalog,farm_watch
as $$
  with property as (
    select p.id from farm_watch.properties p
    where p.slug=p_slug and p.status='active' limit 1
  ),
  expected as (
    select farm_watch.farm_watch_context_identity_v1(id,'environment') as identity from property
  ),
  cached as (
    select c.* from farm_watch.property_environment_context_v1 c
    join property p on p.id=c.property_id
    where c.context_date=p_context_date
  )
  select case
    when not exists(select 1 from property) then jsonb_build_object('status','missing','context',null)
    when not exists(select 1 from cached) then jsonb_build_object('status','missing','context',null)
    when (select identity_sha256 from cached)=(select identity->>'identity_sha256' from expected)
      then jsonb_build_object(
        'status',(select status from cached),
        'context',(select context from cached),
        'retrieved_at',(select retrieved_at from cached),
        'identity_sha256',(select identity_sha256 from cached)
      )
    else jsonb_build_object(
      'status','stale','context',null,
      'retrieved_at',(select retrieved_at from cached),
      'invalidation_reason','identity_mismatch',
      'stored_identity_sha256',(select identity_sha256 from cached),
      'expected_identity_sha256',(select identity->>'identity_sha256' from expected)
    )
  end;
$$;

create or replace function farm_watch.farm_watch_get_regulatory_context_v1_internal(p_slug text)
returns jsonb
language sql
security definer
set search_path=pg_catalog,farm_watch
as $$
  with property as (
    select p.id from farm_watch.properties p
    where p.slug=p_slug and p.status='active' limit 1
  ),
  expected as (
    select
      farm_watch.farm_watch_context_identity_v1(id,'regulatory-static') as static_identity,
      farm_watch.farm_watch_context_identity_v1(id,'regulatory-faa') as faa_identity
    from property
  ),
  cached as (
    select c.* from farm_watch.property_regulatory_context_v1 c
    join property p on p.id=c.property_id
  )
  select jsonb_build_object(
    'static_status',case
      when not exists(select 1 from cached) then 'missing'
      when (select static_identity_sha256 from cached)=(select static_identity->>'identity_sha256' from expected)
        then (select static_status from cached)
      else 'stale'
    end,
    'static_context',case
      when exists(select 1 from cached)
       and (select static_identity_sha256 from cached)=(select static_identity->>'identity_sha256' from expected)
        then (select static_context from cached)
      else null
    end,
    'static_retrieved_at',(select static_retrieved_at from cached),
    'static_invalidation_reason',case
      when exists(select 1 from cached)
       and (select static_identity_sha256 from cached)<>(select static_identity->>'identity_sha256' from expected)
        then 'identity_mismatch'
      else null
    end,
    'faa_status',case
      when not exists(select 1 from cached) then 'missing'
      when (select faa_identity_sha256 from cached)=(select faa_identity->>'identity_sha256' from expected)
        then (select faa_status from cached)
      else 'stale'
    end,
    'faa_context',case
      when exists(select 1 from cached)
       and (select faa_identity_sha256 from cached)=(select faa_identity->>'identity_sha256' from expected)
        then (select faa_context from cached)
      else null
    end,
    'faa_checked_at',(select faa_checked_at from cached),
    'faa_invalidation_reason',case
      when exists(select 1 from cached)
       and (select faa_identity_sha256 from cached)<>(select faa_identity->>'identity_sha256' from expected)
        then 'identity_mismatch'
      else null
    end
  );
$$;

create or replace function public.farm_watch_get_soils_v1_internal(p_slug text)
returns jsonb
language sql
stable security definer
set search_path=pg_catalog
as $$
  with property as (
    select p.id from farm_watch.properties p
    where p.slug=p_slug and p.status='active' limit 1
  ),
  expected as (
    select
      farm_watch.farm_watch_context_identity_v1(id,'soils-map-units') as map_identity,
      farm_watch.farm_watch_context_identity_v1(id,'soils-profiles') as profile_identity
    from property
  ),
  stored_units as (
    select s.* from farm_watch.property_soil_map_units_v1 s
    join property p on p.id=s.property_id
  ),
  units as (
    select
      s.*,
      d.runoff_class,d.tax_order,d.tax_subgroup,d.geomorphic_description,
      d.restrictive_depth_cm,d.restriction_kind,d.restriction_hardness,
      d.parent_material_group,d.parent_material_kind,d.parent_material_origins,
      d.flooding_classes,d.ponding_classes,d.horizon_profile,
      d.attribute_status as deep_attribute_status,
      d.source_retrieved_at as deep_retrieved_at
    from stored_units s
    cross join expected e
    left join farm_watch.property_soil_profiles_v1 d
      on d.property_id=s.property_id
     and d.mukey=s.mukey
     and d.identity_sha256=e.profile_identity->>'identity_sha256'
    where s.identity_sha256=e.map_identity->>'identity_sha256'
  ),
  summary as (
    select
      (select count(*) from stored_units)::integer as stored_map_unit_count,
      count(*)::integer as map_unit_count,
      count(*) filter(where deep_attribute_status='available')::integer as deep_profile_count,
      coalesce(sum(parcel_acres),0) as covered_acres,
      coalesce(sum(parcel_pct),0) as covered_pct,
      max(source_retrieved_at) as retrieved_at,
      max(deep_retrieved_at) as deep_retrieved_at
    from units
  )
  select jsonb_build_object(
    'status',case
      when summary.map_unit_count>0 then 'available'
      when summary.stored_map_unit_count>0 then 'stale'
      else 'unavailable'
    end,
    'feature_collection',jsonb_build_object(
      'type','FeatureCollection',
      'features',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'type','Feature','id',u.mukey,
            'geometry',extensions.st_asgeojson(u.clipped_geometry,6)::jsonb,
            'properties',jsonb_strip_nulls(jsonb_build_object(
              'mukey',u.mukey,'musym',u.musym,'muname',u.muname,'mukind',u.mukind,
              'farmland_class',u.farmland_class,'non_irrigated_capability',u.non_irrigated_capability,
              'dominant_component_name',u.dominant_component_name,
              'dominant_component_pct',u.dominant_component_pct,
              'representative_slope_pct',u.representative_slope_pct,
              'drainage_class',u.drainage_class,'hydrologic_group',u.hydrologic_group,
              'hydric_rating',u.hydric_rating,
              'available_water_storage_0_100_mm',u.available_water_storage_0_100_mm,
              'runoff_class',u.runoff_class,
              'tax_order',u.tax_order,'tax_subgroup',u.tax_subgroup,
              'geomorphic_description',u.geomorphic_description,
              'restrictive_depth_cm',u.restrictive_depth_cm,
              'restriction_kind',u.restriction_kind,
              'restriction_hardness',u.restriction_hardness,
              'parent_material_group',u.parent_material_group,
              'parent_material_kind',u.parent_material_kind,
              'parent_material_origins',u.parent_material_origins,
              'flooding_classes',u.flooding_classes,
              'ponding_classes',u.ponding_classes,
              'horizon_profile',u.horizon_profile,
              'deep_attribute_status',u.deep_attribute_status,
              'parcel_acres',round(u.parcel_acres,2),'parcel_pct',round(u.parcel_pct,1),
              'attribute_status',u.attribute_status
            ))
          ) order by u.parcel_acres desc,u.mukey
        ) from units u
      ),'[]'::jsonb)
    ),
    'summary',jsonb_build_object(
      'map_unit_count',summary.map_unit_count,
      'stored_map_unit_count',summary.stored_map_unit_count,
      'deep_profile_count',summary.deep_profile_count,
      'covered_acres',round(summary.covered_acres,2),
      'covered_pct',round(summary.covered_pct,1),
      'retrieved_at',summary.retrieved_at,
      'deep_retrieved_at',summary.deep_retrieved_at,
      'source','USDA NRCS SSURGO / Soil Data Access',
      'identity_status',case
        when summary.map_unit_count>0 then 'current'
        when summary.stored_map_unit_count>0 then 'stale'
        else 'missing'
      end
    )
  ) from summary;
$$;

create or replace function public.farm_watch_get_hydrology_v1_internal(p_slug text)
returns jsonb
language sql
stable security definer
set search_path=pg_catalog
as $$
  with property as (
    select p.id from farm_watch.properties p
    where p.slug=p_slug and p.status='active' limit 1
  ),
  expected as (
    select farm_watch.farm_watch_context_identity_v1(id,'hydrology') as identity from property
  ),
  state_any as (
    select s.* from farm_watch.hydrology_refresh_state_v1 s
    join property p on p.id=s.property_id
  ),
  state as (
    select s.* from state_any s
    cross join expected e
    where s.identity_sha256=e.identity->>'identity_sha256'
  ),
  features as (
    select h.* from farm_watch.property_hydrology_features_v1 h
    join property p on p.id=h.property_id
    where exists(select 1 from state)
  ),
  feature_json as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'type','Feature',
        'id',f.source_slug||':'||f.feature_kind||':'||f.source_feature_id,
        'geometry',extensions.st_asgeojson(f.geometry,6)::jsonb,
        'properties',coalesce(f.properties,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
          'source_slug',f.source_slug,'feature_kind',f.feature_kind,
          'source_feature_id',f.source_feature_id,
          'intersects_property',f.intersects_property,
          'distance_m',round(f.distance_m,1),
          'intersection_acres',case when f.intersection_acres is null then null else round(f.intersection_acres,3) end,
          'intersection_length_m',case when f.intersection_length_m is null then null else round(f.intersection_length_m,1) end
        ))
      ) order by f.feature_kind,f.distance_m,f.source_feature_id
    ),'[]'::jsonb) as features from features f
  ),
  stats as (
    select
      count(*)::integer as feature_count,
      count(*) filter(where feature_kind='flowline')::integer as flowline_count,
      count(*) filter(where feature_kind='waterbody')::integer as waterbody_count,
      count(*) filter(where feature_kind='wetland')::integer as wetland_count,
      count(*) filter(where intersects_property)::integer as intersecting_count,
      min(distance_m) filter(where feature_kind='flowline') as nearest_flowline_m,
      min(distance_m) filter(where feature_kind='waterbody') as nearest_waterbody_m,
      min(distance_m) filter(where feature_kind='wetland') as nearest_wetland_m,
      sum(coalesce(intersection_acres,0)) filter(where feature_kind='wetland') as wetland_intersection_acres,
      sum(coalesce(intersection_acres,0)) filter(where feature_kind='waterbody') as waterbody_intersection_acres,
      sum(coalesce(intersection_length_m,0)) filter(where feature_kind='flowline') as flowline_intersection_m
    from features
  )
  select jsonb_build_object(
    'status',case
      when exists(select 1 from state) then (select status from state)
      when exists(select 1 from state_any) then 'stale'
      else 'unavailable'
    end,
    'feature_collection',jsonb_build_object('type','FeatureCollection','features',(select features from feature_json)),
    'summary',jsonb_strip_nulls(jsonb_build_object(
      'source','USGS 3DHP + USFWS NWI',
      'feature_count',coalesce((select feature_count from stats),0),
      'flowline_count',coalesce((select flowline_count from stats),0),
      'waterbody_count',coalesce((select waterbody_count from stats),0),
      'wetland_count',coalesce((select wetland_count from stats),0),
      'intersecting_count',coalesce((select intersecting_count from stats),0),
      'nearest_flowline_m',case when (select nearest_flowline_m from stats) is null then null else round((select nearest_flowline_m from stats),1) end,
      'nearest_waterbody_m',case when (select nearest_waterbody_m from stats) is null then null else round((select nearest_waterbody_m from stats),1) end,
      'nearest_wetland_m',case when (select nearest_wetland_m from stats) is null then null else round((select nearest_wetland_m from stats),1) end,
      'wetland_intersection_acres',case when (select wetland_intersection_acres from stats) is null then null else round((select wetland_intersection_acres from stats),3) end,
      'waterbody_intersection_acres',case when (select waterbody_intersection_acres from stats) is null then null else round((select waterbody_intersection_acres from stats),3) end,
      'flowline_intersection_m',case when (select flowline_intersection_m from stats) is null then null else round((select flowline_intersection_m from stats),1) end,
      'buffer_m',(select buffer_m from state),
      'source_status',(select source_status from state),
      'retrieved_at',(select retrieved_at from state),
      'stored_retrieved_at',(select retrieved_at from state_any),
      'identity_status',case
        when exists(select 1 from state) then 'current'
        when exists(select 1 from state_any) then 'stale'
        else 'missing'
      end
    ))
  );
$$;

create or replace function public.farm_watch_get_physical_synthesis_inputs_v1_internal(
  p_slug text,p_geology jsonb
) returns jsonb
language plpgsql
stable security definer
set search_path='pg_catalog'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_property_area_m2 double precision;
  v_soil_identity text;
  v_hydrology_identity text;
  v_stored_soils integer;
  v_current_soils integer;
  v_hydrology_state_exists boolean;
  v_hydrology_current boolean;
  v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select p.id,p.boundary,extensions.st_area(p.boundary::extensions.geography)
  into v_property_id,v_boundary,v_property_area_m2
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active' and p.boundary is not null limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object(
      'status','unavailable','reason','active property boundary unavailable',
      'soils','[]'::jsonb,'geology','[]'::jsonb,'hydrology','[]'::jsonb
    );
  end if;

  v_soil_identity := farm_watch.farm_watch_context_identity_v1(v_property_id,'soils-map-units')->>'identity_sha256';
  v_hydrology_identity := farm_watch.farm_watch_context_identity_v1(v_property_id,'hydrology')->>'identity_sha256';

  select count(*),count(*) filter(where identity_sha256=v_soil_identity)
  into v_stored_soils,v_current_soils
  from farm_watch.property_soil_map_units_v1
  where property_id=v_property_id;

  select
    exists(select 1 from farm_watch.hydrology_refresh_state_v1 where property_id=v_property_id),
    exists(select 1 from farm_watch.hydrology_refresh_state_v1
           where property_id=v_property_id and identity_sha256=v_hydrology_identity)
  into v_hydrology_state_exists,v_hydrology_current;

  if v_stored_soils>0 and v_current_soils=0 then
    return jsonb_build_object(
      'status','unavailable','reason','soil context identity is stale',
      'soils','[]'::jsonb,'geology','[]'::jsonb,'hydrology','[]'::jsonb
    );
  end if;
  if v_hydrology_state_exists and not v_hydrology_current then
    return jsonb_build_object(
      'status','unavailable','reason','hydrology context identity is stale',
      'soils','[]'::jsonb,'geology','[]'::jsonb,'hydrology','[]'::jsonb
    );
  end if;

  with soil_rows as (
    select
      s.mukey as unit_id,
      jsonb_strip_nulls(jsonb_build_object(
        'mukey',s.mukey,'musym',s.musym,'muname',s.muname,
        'parcel_acres',round(s.parcel_acres,6),'parcel_percent',round(s.parcel_pct,6)
      )) as properties,
      s.clipped_geometry as geom
    from farm_watch.property_soil_map_units_v1 s
    where s.property_id=v_property_id and s.identity_sha256=v_soil_identity
  ),
  geology_source as (
    select
      feature,coalesce(feature->'properties','{}'::jsonb) as props,
      extensions.st_makevalid(
        extensions.st_setsrid(extensions.st_geomfromgeojson((feature->'geometry')::text),4326)
      ) as geom
    from jsonb_array_elements(coalesce(p_geology->'features','[]'::jsonb)) feature
    where feature->'geometry' is not null and feature->'geometry'<>'null'::jsonb
  ),
  geology_clipped as (
    select
      coalesce(nullif(props->>'formation_code',''),nullif(props->>'map_symbol',''),'mapped-geology') as unit_id,
      props,
      extensions.st_multi(
        extensions.st_collectionextract(extensions.st_intersection(geom,v_boundary),3)
      ) as geom
    from geology_source
    where extensions.st_intersects(geom,v_boundary)
  ),
  geology_rows as (
    select
      unit_id,
      jsonb_strip_nulls(
        props || jsonb_build_object(
          'intersection_acres',round((extensions.st_area(geom::extensions.geography)/4046.8564224)::numeric,6),
          'parcel_percent',round((case when v_property_area_m2>0
            then extensions.st_area(geom::extensions.geography)/v_property_area_m2*100 else 0 end)::numeric,6)
        )
      ) as properties,
      geom
    from geology_clipped
    where geom is not null and not extensions.st_isempty(geom)
  ),
  hydro_clipped as (
    select
      h.source_slug,h.feature_kind,h.source_feature_id,h.properties,
      h.intersection_acres,h.intersection_length_m,
      case when h.feature_kind='flowline'
        then extensions.st_collectionextract(extensions.st_intersection(h.geometry,v_boundary),2)
        else extensions.st_multi(
          extensions.st_collectionextract(extensions.st_intersection(h.geometry,v_boundary),3)
        )
      end as geom
    from farm_watch.property_hydrology_features_v1 h
    where h.property_id=v_property_id and h.intersects_property and v_hydrology_current
  ),
  hydro_rows as (
    select
      source_slug||':'||feature_kind||':'||source_feature_id as unit_id,
      jsonb_strip_nulls(
        coalesce(properties,'{}'::jsonb) || jsonb_build_object(
          'source_slug',source_slug,'feature_kind',feature_kind,'source_feature_id',source_feature_id,
          'intersection_acres',case when intersection_acres is null then null else round(intersection_acres,6) end,
          'intersection_length_m',case when intersection_length_m is null then null else round(intersection_length_m,3) end
        )
      ) as properties,
      geom
    from hydro_clipped
    where geom is not null and not extensions.st_isempty(geom)
  )
  select jsonb_build_object(
    'status','available',
    'soils',coalesce((select jsonb_agg(jsonb_build_object(
      'id',unit_id,'properties',properties,'geometry',extensions.st_asgeojson(geom,6)::jsonb
    ) order by (properties->>'parcel_acres')::numeric desc,unit_id) from soil_rows),'[]'::jsonb),
    'geology',coalesce((select jsonb_agg(jsonb_build_object(
      'id',unit_id,'properties',properties,'geometry',extensions.st_asgeojson(geom,6)::jsonb
    ) order by (properties->>'intersection_acres')::numeric desc,unit_id) from geology_rows),'[]'::jsonb),
    'hydrology',coalesce((select jsonb_agg(jsonb_build_object(
      'id',unit_id,'properties',properties,'geometry',extensions.st_asgeojson(geom,6)::jsonb
    ) order by properties->>'feature_kind',unit_id) from hydro_rows),'[]'::jsonb)
  ) into v_result;

  return coalesce(v_result,jsonb_build_object(
    'status','unavailable','soils','[]'::jsonb,'geology','[]'::jsonb,'hydrology','[]'::jsonb
  ));
end;
$$;

revoke all on function public.farm_watch_get_soils_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_get_hydrology_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_get_physical_synthesis_inputs_v1_internal(text,jsonb) from public,anon,authenticated;
grant execute on function public.farm_watch_get_soils_v1_internal(text) to service_role;
grant execute on function public.farm_watch_get_hydrology_v1_internal(text) to service_role;
grant execute on function public.farm_watch_get_physical_synthesis_inputs_v1_internal(text,jsonb) to service_role;

comment on function farm_watch.farm_watch_context_identity_v1(uuid,text) is
'Deterministic Farm Watch canonical-context identity. Includes exact property boundary plus product source/algorithm/schema contract. Land additionally includes current soil/hydrology refresh revisions. Stated acreage is intentionally excluded because these products derive spatial quantities from the boundary rather than using stated acreage as a deterministic input.';

comment on column farm_watch.property_land_context_v1.identity_sha256 is
'Identity of the exact property boundary, land source contract, algorithm/schema versions, and current soil/hydrology dependency revisions used by this cached context.';
