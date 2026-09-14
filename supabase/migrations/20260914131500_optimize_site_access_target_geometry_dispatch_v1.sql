-- Batch 1: remove the all-target UNION view from the hot site-access geometry lookup.
--
-- The queue worker resolves up to 50 targets per refresh. The prior implementation
-- queried decisioning.v_operational_targets for every target key; in production a
-- single field lookup could take ~3.7s because the UNION view touched unrelated
-- target families. Dispatching by the canonical target-key prefix keeps the public
-- function contract stable while using each source table's natural/primary key.

create or replace function decisioning.get_site_access_target_geometry(p_target_key text)
returns table(target_type text, geometry extensions.geometry)
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_prefix text;
  v_native text;
  v_solar_separator integer;
  v_plant_id text;
  v_generator_id text;
begin
  if p_target_key is null or strpos(p_target_key, ':') = 0 then
    return;
  end if;

  v_prefix := split_part(p_target_key, ':', 1);
  v_native := substr(p_target_key, length(v_prefix) + 2);

  if v_prefix = 'building' then
    if v_native !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
      return;
    end if;

    return query
    select 'building'::text, r.geometry
    from ingest.raw_records r
    join ingest.sources s on s.id = r.source_id
    where r.id = v_native::uuid
      and s.slug = any(array[
        'ky-ornl-building-footprints'::text,
        'in-state-building-footprints'::text,
        'openstreetmap-targeted-building-identity'::text
      ])
      and r.within_pilot_radius is true
      and r.geometry is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'telecom' then
    return query
    select 'telecom_structure'::text, t.location
    from telecom.asr_structures t
    where t.registration_number = v_native
      and t.within_pilot is true
      and t.location is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'water_tank' then
    if v_native !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
      return;
    end if;

    return query
    select 'water_tank'::text, w.location::extensions.geometry
    from water.tanks w
    where w.id = v_native::uuid
      and coalesce(w.out_of_service, false) = false
      and w.location is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'rail_crossing' then
    return query
    select 'rail_crossing'::text, r.location
    from transportation.rail_crossings r
    where r.crossing_id = v_native
      and r.location is not null
      and coalesce(r.crossing_closed, false) = false
    limit 1;
    return;
  end if;

  if v_prefix = 'rail_yard' then
    return query
    select 'rail_yard'::text, y.geometry
    from transportation.rail_yards y
    where y.source_native_id = v_native
      and y.geometry is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'solar_generator' then
    v_solar_separator := strpos(v_native, ':');
    if v_solar_separator <= 1 or v_solar_separator >= length(v_native) then
      return;
    end if;

    v_plant_id := left(v_native, v_solar_separator - 1);
    v_generator_id := substr(v_native, v_solar_separator + 1);

    return query
    select 'solar_generator'::text, s.location::extensions.geometry
    from energy.eia_solar_generators s
    where s.plant_id = v_plant_id
      and s.generator_id = v_generator_id
      and s.within_pilot is true
      and s.source_present is true
      and s.location is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'construction_project' then
    if v_native !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
      return;
    end if;

    return query
    select 'construction_project'::text, c.location
    from intelligence.construction_projects c
    where c.id = v_native::uuid
      and c.status = 'active'
      and c.location is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'field' then
    if v_native !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
      return;
    end if;

    return query
    select 'field'::text, f.geometry
    from agriculture.field_boundaries f
    where f.id = v_native::uuid
      and f.within_pilot
      and f.source_present
      and f.geometry is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'bridge' then
    if v_native !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
      return;
    end if;

    return query
    select 'bridge_asset'::text, b.location::extensions.geometry
    from transportation.bridges b
    where b.id = v_native::uuid
      and b.location is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'dam' then
    if v_native !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
      return;
    end if;

    return query
    select 'dam_site'::text,
           extensions.ST_SetSRID(
             extensions.ST_MakePoint(
               ((r.raw_payload -> 'attributes' ->> 'LONGITUDE'))::double precision,
               ((r.raw_payload -> 'attributes' ->> 'LATITUDE'))::double precision
             ),
             4326
           )
    from ingest.raw_records r
    join ingest.sources s on s.id = r.source_id
    where r.id = v_native::uuid
      and s.slug = 'usace-nid'
      and nullif(r.raw_payload -> 'attributes' ->> 'LATITUDE', '') is not null
      and nullif(r.raw_payload -> 'attributes' ->> 'LONGITUDE', '') is not null
    limit 1;
    return;
  end if;

  if v_prefix = 'job' then
    if v_native !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
      return;
    end if;

    return query
    select 'job_site'::text,
           extensions.ST_SetSRID(
             extensions.ST_MakePoint(
               (j.target ->> 'longitude')::double precision,
               (j.target ->> 'latitude')::double precision
             ),
             4326
           )
    from decisioning.jobs j
    where j.id = v_native::uuid
      and jsonb_typeof(j.target -> 'latitude') = 'number'
      and jsonb_typeof(j.target -> 'longitude') = 'number'
    limit 1;
    return;
  end if;

  -- Compatibility fallback for a future target family that has been added to the
  -- operational-target view but not yet promoted to an indexed prefix branch.
  return query
  select t.target_type, t.geometry
  from decisioning.v_operational_targets t
  where t.target_key = p_target_key
    and t.geometry is not null
  limit 1;
end
$function$;

comment on function decisioning.get_site_access_target_geometry(text) is
  'Resolves canonical site-access target geometry by indexed target-key prefix; falls back to v_operational_targets only for unknown future target families.';
