create or replace function public.farm_watch_get_physical_synthesis_inputs_v1_internal(
  p_slug text,
  p_geology jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog'
as $function$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_property_area_m2 double precision;
  v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select p.id, p.boundary, extensions.st_area(p.boundary::extensions.geography)
  into v_property_id, v_boundary, v_property_area_m2
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active' and p.boundary is not null
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object(
      'status','unavailable',
      'reason','active property boundary unavailable',
      'soils','[]'::jsonb,
      'geology','[]'::jsonb,
      'hydrology','[]'::jsonb
    );
  end if;

  with soil_rows as (
    select
      s.mukey as unit_id,
      jsonb_strip_nulls(jsonb_build_object(
        'mukey',s.mukey,
        'musym',s.musym,
        'muname',s.muname,
        'parcel_acres',round(s.parcel_acres,6),
        'parcel_percent',round(s.parcel_pct,6)
      )) as properties,
      s.clipped_geometry as geom
    from farm_watch.property_soil_map_units_v1 s
    where s.property_id=v_property_id
  ),
  geology_source as (
    select
      feature,
      coalesce(feature->'properties','{}'::jsonb) as props,
      extensions.st_makevalid(
        extensions.st_setsrid(
          extensions.st_geomfromgeojson((feature->'geometry')::text),
          4326
        )
      ) as geom
    from jsonb_array_elements(coalesce(p_geology->'features','[]'::jsonb)) feature
    where feature->'geometry' is not null and feature->'geometry' <> 'null'::jsonb
  ),
  geology_clipped as (
    select
      coalesce(nullif(props->>'formation_code',''),nullif(props->>'map_symbol',''),'mapped-geology') as unit_id,
      props,
      extensions.st_multi(
        extensions.st_collectionextract(
          extensions.st_intersection(geom,v_boundary),
          3
        )
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
          'parcel_percent',round((
            case when v_property_area_m2>0
              then extensions.st_area(geom::extensions.geography)/v_property_area_m2*100
              else 0
            end
          )::numeric,6)
        )
      ) as properties,
      geom
    from geology_clipped
    where geom is not null and not extensions.st_isempty(geom)
  ),
  hydro_clipped as (
    select
      h.source_slug,
      h.feature_kind,
      h.source_feature_id,
      h.properties,
      h.intersection_acres,
      h.intersection_length_m,
      case
        when h.feature_kind='flowline' then
          extensions.st_collectionextract(extensions.st_intersection(h.geometry,v_boundary),2)
        else
          extensions.st_multi(
            extensions.st_collectionextract(extensions.st_intersection(h.geometry,v_boundary),3)
          )
      end as geom
    from farm_watch.property_hydrology_features_v1 h
    where h.property_id=v_property_id and h.intersects_property
  ),
  hydro_rows as (
    select
      source_slug||':'||feature_kind||':'||source_feature_id as unit_id,
      jsonb_strip_nulls(
        coalesce(properties,'{}'::jsonb) || jsonb_build_object(
          'source_slug',source_slug,
          'feature_kind',feature_kind,
          'source_feature_id',source_feature_id,
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
    'soils',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',unit_id,
        'properties',properties,
        'geometry',extensions.st_asgeojson(geom,6)::jsonb
      ) order by (properties->>'parcel_acres')::numeric desc,unit_id)
      from soil_rows
    ),'[]'::jsonb),
    'geology',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',unit_id,
        'properties',properties,
        'geometry',extensions.st_asgeojson(geom,6)::jsonb
      ) order by (properties->>'intersection_acres')::numeric desc,unit_id)
      from geology_rows
    ),'[]'::jsonb),
    'hydrology',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',unit_id,
        'properties',properties,
        'geometry',extensions.st_asgeojson(geom,6)::jsonb
      ) order by properties->>'feature_kind',unit_id)
      from hydro_rows
    ),'[]'::jsonb)
  )
  into v_result;

  return coalesce(v_result,jsonb_build_object(
    'status','unavailable',
    'soils','[]'::jsonb,
    'geology','[]'::jsonb,
    'hydrology','[]'::jsonb
  ));
end;
$function$;

revoke all on function public.farm_watch_get_physical_synthesis_inputs_v1_internal(text,jsonb)
  from public, anon, authenticated;
grant execute on function public.farm_watch_get_physical_synthesis_inputs_v1_internal(text,jsonb)
  to service_role;

comment on function public.farm_watch_get_physical_synthesis_inputs_v1_internal(text,jsonb) is
'Service-role-only vector preparation for Farm Watch cross-layer physical synthesis. Returns exact parcel-clipped existing SSURGO, KGS geology, and on-parcel 3DHP/NWI geometries; performs no suitability scoring or new evidence collection.';