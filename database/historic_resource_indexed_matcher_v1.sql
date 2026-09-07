-- Scout historic-resource matcher optimization v1
--
-- Uses the indexed canonical raw-record location/geometry substrate directly
-- instead of repeatedly rebuilding point-on-surface values through the
-- decisioning.building_candidates view. Candidate universe and confidence
-- semantics are unchanged.

create or replace function public.internal_ingest_historic_resource_batch(
  p_source_slug text,
  p_features jsonb,
  p_observed_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','extensions','ingest','intelligence','decisioning'
as $$
declare
  v_source_id uuid;
  v_feature jsonb;
  v_geom geometry;
  v_resource_id uuid;
  v_resource_type text;
  v_building record;
  v_inserted int := 0;
  v_matches int := 0;
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

  for v_feature in select value from jsonb_array_elements(p_features)
  loop
    begin
      v_geom := st_setsrid(st_geomfromgeojson((v_feature->'geometry')::text),4326);
      if v_geom is null or st_isempty(v_geom) then
        raise exception 'empty geometry';
      end if;
      if not st_isvalid(v_geom) then
        v_geom := st_makevalid(v_geom);
      end if;
      v_resource_type := lower(coalesce(nullif(v_feature->>'resource_type',''),'unknown'));

      insert into intelligence.historic_resources(
        source_id,source_native_id,resource_name,resource_type,reference_number,
        designation_status,listed_date,address_text,city,county_name,state_code,
        is_national_historic_landmark,geometry,confidence,source_url,observed_at,
        attributes,updated_at
      ) values (
        v_source_id,
        nullif(v_feature->>'source_native_id',''),
        nullif(v_feature->>'resource_name',''),
        v_resource_type,
        nullif(v_feature->>'reference_number',''),
        nullif(v_feature->>'designation_status',''),
        nullif(v_feature->>'listed_date','')::date,
        nullif(v_feature->>'address_text',''),
        nullif(v_feature->>'city',''),
        nullif(v_feature->>'county_name',''),
        upper(nullif(v_feature->>'state_code','')),
        coalesce(nullif(v_feature->>'is_national_historic_landmark','')::boolean,false),
        v_geom,
        coalesce(nullif(v_feature->>'confidence','')::numeric,0.90),
        nullif(v_feature->>'source_url',''),
        coalesce(p_observed_at,now()),
        coalesce(v_feature->'attributes','{}'::jsonb),
        now()
      )
      on conflict(source_id,source_native_id) do update set
        resource_name=excluded.resource_name,
        resource_type=excluded.resource_type,
        reference_number=excluded.reference_number,
        designation_status=excluded.designation_status,
        listed_date=excluded.listed_date,
        address_text=excluded.address_text,
        city=excluded.city,
        county_name=excluded.county_name,
        state_code=excluded.state_code,
        is_national_historic_landmark=excluded.is_national_historic_landmark,
        geometry=excluded.geometry,
        confidence=excluded.confidence,
        source_url=excluded.source_url,
        observed_at=excluded.observed_at,
        attributes=excluded.attributes,
        updated_at=now()
      returning id into v_resource_id;

      v_inserted := v_inserted + 1;
      delete from intelligence.historic_resource_building_matches
      where historic_resource_id=v_resource_id;

      if st_dimension(v_geom)=0 and v_resource_type <> 'district' then
        select r.id as source_record_id,
               st_distance(r.location, v_geom::geography) as distance_m
        into v_building
        from ingest.raw_records r
        join ingest.sources s on s.id=r.source_id
        where s.slug = any(array['ky-ornl-building-footprints','in-state-building-footprints'])
          and r.within_pilot_radius is true
          and r.location is not null
          and st_dwithin(r.location, v_geom::geography, 50)
        order by r.location <-> v_geom::geography
        limit 1;

        if v_building.source_record_id is not null then
          insert into intelligence.historic_resource_building_matches(
            historic_resource_id,building_source_record_id,relationship_type,
            distance_m,confidence
          ) values (
            v_resource_id,
            v_building.source_record_id,
            'listed_resource_point_match',
            v_building.distance_m,
            case when v_building.distance_m <= 10 then 0.95
                 when v_building.distance_m <= 25 then 0.85
                 else 0.70 end
          );
          v_matches := v_matches + 1;
        end if;
      elsif st_dimension(v_geom)=2 then
        for v_building in
          select r.id as source_record_id,
                 st_distance(
                   r.location,
                   st_pointonsurface(v_geom)::geography
                 ) as distance_m
          from ingest.raw_records r
          join ingest.sources s on s.id=r.source_id
          where s.slug = any(array['ky-ornl-building-footprints','in-state-building-footprints'])
            and r.within_pilot_radius is true
            and r.geometry is not null
            and r.geometry && v_geom
            and st_intersects(st_makevalid(r.geometry),v_geom)
        loop
          insert into intelligence.historic_resource_building_matches(
            historic_resource_id,building_source_record_id,relationship_type,
            distance_m,confidence
          ) values (
            v_resource_id,
            v_building.source_record_id,
            case when v_resource_type='district'
              then 'within_listed_district'
              else 'listed_resource_polygon_match'
            end,
            v_building.distance_m,
            case when v_resource_type='district' then 0.80 else 0.95 end
          )
          on conflict do nothing;
          v_matches := v_matches + 1;
        end loop;
      end if;
    exception when others then
      v_invalid := v_invalid + 1;
    end;
  end loop;

  return jsonb_build_object(
    'accepted',v_inserted,
    'building_matches',v_matches,
    'invalid',v_invalid
  );
end;
$$;

revoke all on function public.internal_ingest_historic_resource_batch(text,jsonb,timestamptz)
  from public,anon,authenticated;
grant execute on function public.internal_ingest_historic_resource_batch(text,jsonb,timestamptz)
  to service_role;
