-- Scout building attribute ingestion v2: match before persistence for bulk,
-- reproducible sources. This avoids insert/delete churn for the overwhelming
-- majority of Overture/OSM features that do not resolve to Scout's canonical
-- building substrate. The existing deferred retention trigger remains a safety
-- net. Refreshes also remove stale prior building matches.

create or replace function public.internal_ingest_building_attribute_batch(
  p_source_slug text,
  p_features jsonb,
  p_source_timestamp timestamp with time zone default null::timestamp with time zone
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','ingest','decisioning'
as $function$
declare
  v_source_id uuid;
  v_feature jsonb;
  v_geom geometry;
  v_obs_id uuid;
  v_existing_obs_id uuid;
  v_building_id uuid;
  v_overlap numeric;
  v_distance numeric;
  v_candidate_area numeric;
  v_source_area numeric;
  v_match_conf numeric;
  v_source_native_id text;
  v_feature_kind text;
  v_is_match boolean;
  v_match_only boolean;
  v_accepted int := 0;
  v_matched int := 0;
  v_unmatched int := 0;
  v_invalid int := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if jsonb_typeof(p_features) <> 'array' then
    raise exception 'p_features must be a JSON array';
  end if;

  select id into v_source_id
  from ingest.sources
  where slug=p_source_slug
    and status in ('active','active_reference','source_identified')
  limit 1;
  if v_source_id is null then
    raise exception 'unknown or inactive source: %', p_source_slug;
  end if;

  v_match_only := p_source_slug in (
    'overture-buildings',
    'openstreetmap-geofabrik-building-attributes'
  );

  for v_feature in select value from jsonb_array_elements(p_features)
  loop
    begin
      v_source_native_id := nullif(v_feature->>'source_native_id','');
      v_feature_kind := coalesce(nullif(v_feature->>'feature_kind',''),'building');
      v_building_id := null;
      v_overlap := null;
      v_distance := null;
      v_candidate_area := null;
      v_source_area := null;
      v_match_conf := null;
      v_obs_id := null;
      v_existing_obs_id := null;

      v_geom := st_setsrid(st_geomfromgeojson((v_feature->'geometry')::text),4326);
      if v_geom is null or st_isempty(v_geom) then
        raise exception 'empty geometry';
      end if;
      if not st_isvalid(v_geom) then
        v_geom := st_makevalid(v_geom);
      end if;

      select q.source_record_id,q.overlap_ratio,q.distance_m,q.candidate_area,q.source_area
      into v_building_id,v_overlap,v_distance,v_candidate_area,v_source_area
      from (
        select bc.source_record_id,
          case
            when st_dimension(v_geom)=2 and st_dimension(bc.geometry)=2 then
              st_area(st_intersection(st_makevalid(bc.geometry),v_geom)::geography) /
              nullif(least(
                st_area(st_makevalid(bc.geometry)::geography),
                st_area(v_geom::geography)
              ),0)
            else 0
          end as overlap_ratio,
          st_distance(
            st_pointonsurface(st_makevalid(bc.geometry))::geography,
            st_pointonsurface(v_geom)::geography
          ) as distance_m,
          st_area(st_makevalid(bc.geometry)::geography) as candidate_area,
          case when st_dimension(v_geom)=2 then st_area(v_geom::geography) else null end as source_area
        from decisioning.building_candidates bc
        where bc.geometry is not null
          and bc.geometry && st_expand(v_geom,0.001)
        order by overlap_ratio desc nulls last, distance_m asc
        limit 1
      ) q;

      v_is_match := v_building_id is not null and (
        coalesce(v_overlap,0) >= 0.45 or
        (
          coalesce(v_distance,999999) <= 7
          and v_source_area is not null
          and v_candidate_area is not null
          and v_source_area/nullif(v_candidate_area,0) between 0.40 and 2.50
        )
      );

      if not v_is_match and v_match_only then
        if v_source_native_id is not null then
          select id into v_existing_obs_id
          from decisioning.building_attribute_observations
          where source_id=v_source_id
            and source_native_id=v_source_native_id
            and source_feature_kind=v_feature_kind
          limit 1;
          if v_existing_obs_id is not null then
            delete from decisioning.building_attribute_observations
            where id=v_existing_obs_id;
          end if;
        end if;
        v_unmatched := v_unmatched + 1;
        continue;
      end if;

      insert into decisioning.building_attribute_observations(
        source_id,source_native_id,source_feature_kind,observed_at,source_timestamp,geometry,
        height_m,height_status,story_count,story_status,facade_material,raw_facade_material,
        facade_material_status,glazing_signal,has_parts,confidence,attributes,updated_at
      ) values (
        v_source_id,
        v_source_native_id,
        v_feature_kind,
        now(),p_source_timestamp,v_geom,
        nullif(v_feature->>'height_m','')::numeric,
        coalesce(nullif(v_feature->>'height_status',''),'unknown'),
        nullif(v_feature->>'story_count','')::integer,
        coalesce(nullif(v_feature->>'story_status',''),'unknown'),
        nullif(v_feature->>'facade_material',''),
        nullif(v_feature->>'raw_facade_material',''),
        coalesce(nullif(v_feature->>'facade_material_status',''),'unknown'),
        nullif(v_feature->>'glazing_signal',''),
        nullif(v_feature->>'has_parts','')::boolean,
        coalesce(nullif(v_feature->>'confidence','')::numeric,0.80),
        coalesce(v_feature->'attributes','{}'::jsonb),
        now()
      )
      on conflict(source_id,source_native_id,source_feature_kind) do update set
        observed_at=excluded.observed_at,
        source_timestamp=excluded.source_timestamp,
        geometry=excluded.geometry,
        height_m=excluded.height_m,
        height_status=excluded.height_status,
        story_count=excluded.story_count,
        story_status=excluded.story_status,
        facade_material=excluded.facade_material,
        raw_facade_material=excluded.raw_facade_material,
        facade_material_status=excluded.facade_material_status,
        glazing_signal=excluded.glazing_signal,
        has_parts=excluded.has_parts,
        confidence=excluded.confidence,
        attributes=excluded.attributes,
        updated_at=now()
      returning id into v_obs_id;
      v_accepted := v_accepted + 1;

      delete from decisioning.building_attribute_matches
      where observation_id=v_obs_id
        and (not v_is_match or building_source_record_id<>v_building_id);

      if v_is_match then
        v_match_conf := least(0.99,greatest(0.65,coalesce(v_overlap,0.65)));
        insert into decisioning.building_attribute_matches(
          building_source_record_id,observation_id,match_basis,overlap_ratio,
          centroid_distance_m,confidence,matched_at
        ) values (
          v_building_id,v_obs_id,
          case when coalesce(v_overlap,0) >= 0.45 then 'footprint_overlap' else 'centroid_and_area_agreement' end,
          v_overlap,v_distance,v_match_conf,now()
        )
        on conflict(building_source_record_id,observation_id) do update set
          match_basis=excluded.match_basis,
          overlap_ratio=excluded.overlap_ratio,
          centroid_distance_m=excluded.centroid_distance_m,
          confidence=excluded.confidence,
          matched_at=now();
        v_matched := v_matched + 1;
      else
        v_unmatched := v_unmatched + 1;
      end if;
    exception when others then
      v_invalid := v_invalid + 1;
    end;
  end loop;

  return jsonb_build_object(
    'accepted',v_accepted,
    'matched',v_matched,
    'unmatched',v_unmatched,
    'invalid',v_invalid,
    'retention_mode',case when v_match_only then 'matched_only' else 'all_observations' end
  );
end;
$function$;

revoke all on function public.internal_ingest_building_attribute_batch(text,jsonb,timestamp with time zone) from public,anon,authenticated;
grant execute on function public.internal_ingest_building_attribute_batch(text,jsonb,timestamp with time zone) to service_role;
