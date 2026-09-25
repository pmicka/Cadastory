begin;

create or replace function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_property_id uuid;
  v_products jsonb;
  v_surface_water jsonb;
  v_mast_resource jsonb;
  v_human_footprint jsonb;
  v_multiscale_cover jsonb;
  v_extreme_weather jsonb;
  v_available_count integer := 0;
  v_stale_count integer := 0;
  v_unavailable_count integer := 0;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_as_of_date is null then
    raise exception 'evidence-stack as-of date is required';
  end if;

  select p.id
  into v_property_id
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null then
    return jsonb_build_object(
      'status','missing',
      'schema','deer-evidence-stack-v1',
      'as_of_date',p_as_of_date,
      'property',jsonb_build_object('slug',p_slug),
      'products','{}'::jsonb,
      'surface_water_state',jsonb_build_object('status','missing'),
      'mast_resource_context',jsonb_build_object('status','missing'),
      'human_footprint_context',jsonb_build_object('status','missing'),
      'multiscale_cover_context',jsonb_build_object('status','missing'),
      'extreme_weather_event_context',jsonb_build_object('status','missing')
    );
  end if;

  with wanted(product_kind,display_name,category,sort_order) as (
    values
      ('lidar-physical-structure','LiDAR physical vertical structure','physical_structure',10),
      ('landscape-structure-context','Landscape physical structure','physical_structure',20),
      ('terrain-form-permeability','Terrain form / permeability','terrain',30),
      ('spatial-edge-patch-context','Spatial edge / patch context','terrain',40),
      ('solar-exposure-context','Potential solar exposure','thermal_light',50),
      ('thermal-exposure-context','Thermal exposure context','thermal_light',60),
      ('horizontal-visibility-context','Horizontal visibility / obstruction','visibility',70),
      ('mast-capacity','Mast-producing species capacity','resources',80)
  ),
  latest as (
    select distinct on (m.product_kind)
      m.product_kind,
      m.algorithm_version,
      m.output_schema_version,
      m.identity_sha256,
      m.evidence_class,
      m.summary,
      m.source_provenance,
      m.limitations,
      m.artifact_sha256,
      m.completed_at,
      m.expires_at
    from farm_watch.property_materializations_v1 m
    where m.property_id=v_property_id
      and m.product_kind in (select product_kind from wanted)
      and m.completed_at is not null
    order by m.product_kind,m.completed_at desc,m.created_at desc
  ),
  rows as (
    select
      w.product_kind,
      w.display_name,
      w.category,
      w.sort_order,
      case
        when l.product_kind is null then 'unavailable'
        when l.expires_at is not null and l.expires_at <= now() then 'stale'
        else 'available'
      end as state,
      l.algorithm_version,
      l.output_schema_version,
      l.identity_sha256,
      l.evidence_class,
      l.summary,
      l.source_provenance,
      l.limitations,
      l.artifact_sha256,
      l.completed_at,
      l.expires_at
    from wanted w
    left join latest l using(product_kind)
  )
  select
    coalesce(
      jsonb_object_agg(
        r.product_kind,
        jsonb_strip_nulls(jsonb_build_object(
          'product_kind',r.product_kind,
          'display_name',r.display_name,
          'category',r.category,
          'sort_order',r.sort_order,
          'status',r.state,
          'algorithm_version',r.algorithm_version,
          'output_schema_version',r.output_schema_version,
          'identity_sha256',r.identity_sha256,
          'evidence_class',r.evidence_class,
          'summary',r.summary,
          'source_provenance',r.source_provenance,
          'limitations',r.limitations,
          'artifact_sha256',r.artifact_sha256,
          'completed_at',r.completed_at,
          'expires_at',r.expires_at
        ))
        order by r.sort_order
      ),
      '{}'::jsonb
    ),
    count(*) filter (where r.state='available'),
    count(*) filter (where r.state='stale'),
    count(*) filter (where r.state='unavailable')
  into v_products,v_available_count,v_stale_count,v_unavailable_count
  from rows r;

  if to_regclass('farm_watch.property_surface_water_state_v1') is not null then
    execute $sql$
      select jsonb_strip_nulls(jsonb_build_object(
        'status',s.status,
        'as_of_date',s.as_of_date,
        'identity_sha256',s.identity_sha256,
        'algorithm_version',s.algorithm_version,
        'output_schema_version',s.output_schema_version,
        'retrieved_at',s.retrieved_at,
        'context',s.context
      ))
      from farm_watch.property_surface_water_state_v1 s
      where s.property_id=$1
        and s.as_of_date=$2
      limit 1
    $sql$
    into v_surface_water
    using v_property_id,p_as_of_date;
  end if;

  if v_surface_water is null then
    v_surface_water := jsonb_build_object(
      'status',case
        when to_regclass('farm_watch.property_surface_water_state_v1') is null
          then 'not_deployed'
        else 'not_materialized'
      end,
      'as_of_date',p_as_of_date,
      'interpretation_boundary',
        'Surface Water State v1 is not available for this date. Existing mapped hydrography and Seasonal State evidence remain separate inputs.'
    );
  end if;

  if to_regclass('farm_watch.property_mast_resource_context_v1') is not null then
    execute $sql$
      select jsonb_strip_nulls(jsonb_build_object(
        'status',m.status,
        'survey_year',m.survey_year,
        'identity_sha256',m.identity_sha256,
        'algorithm_version',m.algorithm_version,
        'output_schema_version',m.output_schema_version,
        'retrieved_at',m.retrieved_at,
        'context',m.context
      ))
      from farm_watch.property_mast_resource_context_v1 m
      where m.property_id=$1
        and m.survey_year=$2
      limit 1
    $sql$
    into v_mast_resource
    using v_property_id,extract(year from p_as_of_date)::integer;
  end if;

  if v_mast_resource is null then
    v_mast_resource := jsonb_build_object(
      'status',case
        when to_regclass('farm_watch.property_mast_resource_context_v1') is null
          then 'not_deployed'
        else 'not_materialized'
      end,
      'survey_year',extract(year from p_as_of_date)::integer,
      'interpretation_boundary',
        'Mast Resource Context v1 is not materialized for this survey year. Mast Capacity remains a separate neutral product and no annual mast state is inferred.'
    );
  end if;

  if to_regclass('farm_watch.property_human_footprint_context_v1') is not null then
    select jsonb_strip_nulls(jsonb_build_object(
      'status',h.status,
      'identity_sha256',h.identity_sha256,
      'algorithm_version',h.algorithm_version,
      'output_schema_version',h.output_schema_version,
      'retrieved_at',h.retrieved_at,
      'context',h.context
    ))
    into v_human_footprint
    from farm_watch.property_human_footprint_context_v1 h
    where h.property_id=v_property_id
    limit 1;
  end if;

  if v_human_footprint is null then
    v_human_footprint := jsonb_build_object(
      'status',case
        when to_regclass('farm_watch.property_human_footprint_context_v1') is null
          then 'not_deployed'
        else 'not_materialized'
      end,
      'interpretation_boundary',
        'Human Footprint Context v1 is not available. No building-density or road-response inference is substituted.'
    );
  end if;

  if to_regclass('farm_watch.property_study_scale_windows_v1') is not null then
    v_multiscale_cover := farm_watch.farm_watch_get_multiscale_cover_context_v1_internal(p_slug);
  end if;

  if v_multiscale_cover is null then
    v_multiscale_cover := jsonb_build_object(
      'status',case
        when to_regclass('farm_watch.property_study_scale_windows_v1') is null
          then 'not_deployed'
        else 'not_materialized'
      end,
      'interpretation_boundary',
        'Study-scale context is not available. Existing 500 m / 1.5 km / 3 km Farm Watch domains do not substitute for the source 1 km2 / 9 km2 windows.'
    );
  end if;

  if to_regclass('farm_watch.property_extreme_weather_event_context_v1') is not null then
    select jsonb_strip_nulls(jsonb_build_object(
      'status',e.status,
      'as_of_at',e.as_of_at,
      'identity_sha256',e.identity_sha256,
      'algorithm_version',e.algorithm_version,
      'output_schema_version',e.output_schema_version,
      'retrieved_at',e.retrieved_at,
      'context',e.context
    ))
    into v_extreme_weather
    from farm_watch.property_extreme_weather_event_context_v1 e
    where e.property_id=v_property_id
      and e.as_of_at::date=p_as_of_date
    limit 1;
  end if;

  if v_extreme_weather is null then
    v_extreme_weather := jsonb_build_object(
      'status',case
        when to_regclass('farm_watch.property_extreme_weather_event_context_v1') is null
          then 'not_deployed'
        else 'not_materialized_for_date'
      end,
      'as_of_date',p_as_of_date,
      'interpretation_boundary',
        'No date-matched extreme-event context is materialized. Ordinary rain, wind, severe-thunderstorm, or generic weather state must not substitute for the FW-D18 event gate.'
    );
  end if;

  return jsonb_build_object(
    'status',case
      when v_available_count > 0 then 'available'
      when v_stale_count > 0 then 'stale'
      else 'unavailable'
    end,
    'schema','deer-evidence-stack-v1',
    'as_of_date',p_as_of_date,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'counts',jsonb_build_object(
      'available',v_available_count,
      'stale',v_stale_count,
      'unavailable',v_unavailable_count
    ),
    'products',v_products,
    'surface_water_state',v_surface_water,
    'mast_resource_context',v_mast_resource,
    'human_footprint_context',v_human_footprint,
    'multiscale_cover_context',v_multiscale_cover,
    'extreme_weather_event_context',v_extreme_weather,
    'interpretation_boundary',
      'Neutral Farm Watch evidence inventory for UI review. Availability here does not mean a deer relationship is applicable, a coefficient is transferable, or a deer-use prediction has been made.'
  );
end;
$$;

revoke all on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)
  to service_role;

commit;
