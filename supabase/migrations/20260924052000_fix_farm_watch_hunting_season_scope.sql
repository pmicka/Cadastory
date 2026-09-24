-- Farm Watch: make Kentucky deer-season applicability property-aware.
-- Authoritative 2026-27 CWD Surveillance Zone counties verified against KDFWR on 2026-09-24.

insert into operability.hunting_areas (
  jurisdiction,
  area_type,
  name,
  code,
  county_name,
  effective_from,
  effective_to,
  source_url,
  attributes
)
select
  'KY',
  'cwd_surveillance_zone_county',
  county_name || ' County CWD Surveillance Zone',
  'cwd_surveillance',
  county_name,
  date '2026-09-05',
  date '2027-01-31',
  'https://fw.ky.gov/Wildlife/Pages/CWD-SurveillanceZone.aspx',
  jsonb_build_object(
    'season_year', '2026-27',
    'source_verified_on', '2026-09-24'
  )
from (
  values
    ('Ballard'),
    ('Breckinridge'),
    ('Calloway'),
    ('Carlisle'),
    ('Casey'),
    ('Fulton'),
    ('Graves'),
    ('Hardin'),
    ('Henderson'),
    ('Hickman'),
    ('Laurel'),
    ('Lincoln'),
    ('Marshall'),
    ('McCracken'),
    ('McCreary'),
    ('Meade'),
    ('Pulaski'),
    ('Rockcastle'),
    ('Russell'),
    ('Union'),
    ('Wayne'),
    ('Webster'),
    ('Whitley')
) as counties(county_name)
on conflict (jurisdiction, area_type, name, code) do update set
  county_name = excluded.county_name,
  effective_from = coalesce(
    least(operability.hunting_areas.effective_from, excluded.effective_from),
    operability.hunting_areas.effective_from,
    excluded.effective_from
  ),
  effective_to = excluded.effective_to,
  source_url = excluded.source_url,
  attributes = excluded.attributes,
  updated_at = now();

update operability.hunting_areas
set
  effective_to = least(coalesce(effective_to, date '9999-12-31'), date '2026-09-04'),
  updated_at = now()
where jurisdiction = 'KY'
  and area_type = 'cwd_surveillance_zone_county'
  and (effective_to is null or effective_to >= date '2026-09-05')
  and county_name not in (
    'Ballard','Breckinridge','Calloway','Carlisle','Casey','Fulton','Graves',
    'Hardin','Henderson','Hickman','Laurel','Lincoln','Marshall','McCracken',
    'McCreary','Meade','Pulaski','Rockcastle','Russell','Union','Wayne',
    'Webster','Whitley'
  );

create or replace function farm_watch.farm_watch_get_regulatory_local_v1_internal(p_slug text)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog', 'farm_watch', 'operability', 'environment', 'ingest', 'extensions'
as $function$
  with p as (
    select
      id,
      metadata,
      boundary,
      coalesce(center, extensions.st_pointonsurface(boundary)) as pt
    from farm_watch.properties
    where slug = p_slug
    limit 1
  ),
  deer_area as (
    select h.*
    from operability.hunting_areas h, p
    where h.jurisdiction = 'KY'
      and h.area_type = 'deer_management_county'
      and h.attributes->>'geoid' = p.metadata->>'county_fips'
      and (h.effective_from is null or h.effective_from <= current_date)
      and (h.effective_to is null or h.effective_to >= current_date)
    order by h.updated_at desc
    limit 1
  ),
  cwd_area as (
    select h.*
    from operability.hunting_areas h
    join deer_area d
      on lower(h.county_name) = lower(d.county_name)
    where h.jurisdiction = 'KY'
      and h.area_type = 'cwd_surveillance_zone_county'
      and (h.effective_from is null or h.effective_from <= current_date)
      and (h.effective_to is null or h.effective_to >= current_date)
    order by h.updated_at desc
    limit 1
  ),
  applicable_seasons as (
    select s.*
    from operability.hunting_seasons s
    where s.jurisdiction = 'KY'
      and s.species = 'white_tailed_deer'
      and (
        s.scope_type = 'statewide'
        or (
          s.scope_type = 'cwd_surveillance_zone'
          and s.scope_ref = 'zone_1_to_3_counties'
          and exists (select 1 from cwd_area)
          and exists (
            select 1
            from deer_area d
            where d.attributes->>'deer_zone' in ('1','2','3')
          )
        )
      )
  ),
  active_seasons as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'species', s.species,
      'season_year', s.season_year,
      'season_name', s.season_name,
      'start_date', s.start_date,
      'end_date', s.end_date,
      'legal_hours', s.legal_hours,
      'scope_type', s.scope_type,
      'scope_ref', s.scope_ref,
      'source_url', s.source_url
    ) order by s.start_date, s.season_name), '[]'::jsonb) value
    from applicable_seasons s
    where current_date between s.start_date and s.end_date
  ),
  upcoming_seasons as (
    select coalesce(jsonb_agg(x.obj order by x.start_date, x.season_name), '[]'::jsonb) value
    from (
      select
        s.start_date,
        s.season_name,
        jsonb_build_object(
          'species', s.species,
          'season_year', s.season_year,
          'season_name', s.season_name,
          'start_date', s.start_date,
          'end_date', s.end_date,
          'legal_hours', s.legal_hours,
          'scope_type', s.scope_type,
          'scope_ref', s.scope_ref,
          'source_url', s.source_url
        ) obj
      from applicable_seasons s
      where s.start_date > current_date
      order by s.start_date, s.season_name
      limit 5
    ) x
  ),
  drone_rules as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'species', r.species,
      'activity', r.activity,
      'determination', r.determination,
      'scope_type', r.scope_type,
      'scope_ref', r.scope_ref,
      'summary', r.summary,
      'effective_from', r.effective_from,
      'effective_to', r.effective_to,
      'authority_level', r.authority_level,
      'source_url', r.source_url
    ) order by r.activity), '[]'::jsonb) value
    from operability.hunting_rules r
    where r.jurisdiction = 'KY'
      and (r.species = 'white_tailed_deer' or r.species is null)
      and r.activity in (
        'drone_hunt_or_take_live_wildlife',
        'drone_pursuit_live_wounded_animal',
        'drone_search_post_shot_presumed_dead',
        'drone_direct_hunter_to_dead_carcass',
        'drone_terrain_scouting',
        'thermal_or_infrared_night_recovery',
        'commercial_drone_service_on_public_land',
        'drone_disrupt_or_interfere_legal_hunt',
        'physical_retrieval_on_adjacent_private_property'
      )
      and (r.effective_from is null or r.effective_from <= current_date)
      and (r.effective_to is null or r.effective_to >= current_date)
  ),
  protected as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'name', x.name,
      'area_kind', x.area_kind,
      'designation', x.designation,
      'jurisdiction_level', x.jurisdiction_level,
      'gap_status_code', x.gap_status_code,
      'iucn_category', x.iucn_category,
      'distance_m', x.distance_m,
      'intersects_property', x.intersects_property,
      'source_slug', x.source_slug,
      'source_authority', x.source_authority,
      'last_observed_at', x.last_observed_at
    ) order by x.distance_m), '[]'::jsonb) value
    from (
      select
        m.name,
        m.area_kind,
        m.designation,
        m.jurisdiction_level,
        m.gap_status_code,
        m.iucn_category,
        round(extensions.st_distance(m.geometry::geography, p.pt::geography)::numeric, 1) as distance_m,
        case
          when p.boundary is null then false
          else extensions.st_intersects(m.geometry, p.boundary)
        end as intersects_property,
        s.slug as source_slug,
        s.authority as source_authority,
        m.last_observed_at
      from environment.managed_land_areas m
      join ingest.sources s on s.id = m.source_id
      cross join p
      where s.slug = 'usgs-pad-us-4-1'
        and m.source_present is true
        and m.geometry is not null
        and p.pt is not null
        and extensions.st_dwithin(m.geometry::geography, p.pt::geography, 10000)
      order by m.geometry <-> p.pt
      limit 8
    ) x
  )
  select jsonb_build_object(
    'as_of_date', current_date,
    'hunting', jsonb_build_object(
      'jurisdiction', 'KY',
      'deer_management', (
        select case
          when d.id is null then null
          else jsonb_build_object(
            'county_name', d.county_name,
            'zone_code', d.code,
            'deer_zone', d.attributes->>'deer_zone',
            'season_year', d.attributes->>'season_year',
            'source_url', d.source_url
          )
        end
        from deer_area d
      ),
      'active_seasons', (select value from active_seasons),
      'upcoming_seasons', (select value from upcoming_seasons),
      'drone_wildlife_rules', (select value from drone_rules)
    ),
    'protected_lands', jsonb_build_object(
      'intersections', (
        select count(*)
        from jsonb_array_elements((select value from protected)) e
        where coalesce((e->>'intersects_property')::boolean, false)
      ),
      'nearby_authoritative', (select value from protected),
      'source_scope', 'USGS PAD-US 4.1 cached in Scout'
    )
  );
$function$;

-- Refresh the cached hunting subsection immediately from the corrected canonical local context.
update farm_watch.property_regulatory_context_v1 c
set
  static_context = jsonb_set(
    coalesce(c.static_context, '{}'::jsonb),
    '{hunting}',
    farm_watch.farm_watch_get_regulatory_local_v1_internal(p.slug)->'hunting',
    true
  ),
  static_retrieved_at = to_timestamp(0),
  updated_at = now()
from farm_watch.properties p
where p.id = c.property_id;
