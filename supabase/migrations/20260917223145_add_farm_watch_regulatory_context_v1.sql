create table if not exists farm_watch.property_regulatory_context_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  static_status text not null default 'unknown' check (static_status in ('available','partial','unavailable','unknown')),
  static_context jsonb not null default '{}'::jsonb,
  static_retrieved_at timestamptz,
  faa_status text not null default 'unknown' check (faa_status in ('available','partial','unavailable','unknown')),
  faa_context jsonb not null default '{}'::jsonb,
  faa_checked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table farm_watch.property_regulatory_context_v1 enable row level security;
revoke all on farm_watch.property_regulatory_context_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.property_regulatory_context_v1 to service_role;

create or replace function farm_watch.farm_watch_get_regulatory_anchor_v1_internal(p_slug text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, farm_watch, extensions
as $$
  with p as (
    select id, state_code, metadata, boundary,
      coalesce(center, extensions.st_pointonsurface(boundary)) as pt
    from farm_watch.properties
    where slug = p_slug
    limit 1
  )
  select jsonb_build_object(
    'property_id', p.id,
    'lat', case when p.pt is null then null else extensions.st_y(p.pt) end,
    'lon', case when p.pt is null then null else extensions.st_x(p.pt) end,
    'state_code', p.state_code,
    'county_fips', nullif(p.metadata->>'county_fips',''),
    'selected_parcel_id', nullif(p.metadata->>'selected_parcel_id',''),
    'boundary_geojson', case when p.boundary is null then null else extensions.st_asgeojson(p.boundary)::jsonb end
  ) from p;
$$;

create or replace function farm_watch.farm_watch_get_regulatory_local_v1_internal(p_slug text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, farm_watch, operability, environment, ingest, extensions
as $$
  with p as (
    select id, metadata, boundary,
      coalesce(center, extensions.st_pointonsurface(boundary)) as pt
    from farm_watch.properties where slug = p_slug limit 1
  ),
  deer_area as (
    select h.* from operability.hunting_areas h, p
    where h.jurisdiction = 'KY'
      and h.area_type = 'deer_management_county'
      and (h.attributes->>'geoid' = p.metadata->>'county_fips' or lower(h.county_name) = 'franklin')
      and (h.effective_from is null or h.effective_from <= current_date)
      and (h.effective_to is null or h.effective_to >= current_date)
    order by h.updated_at desc limit 1
  ),
  active_seasons as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'species',s.species,'season_year',s.season_year,'season_name',s.season_name,
      'start_date',s.start_date,'end_date',s.end_date,'legal_hours',s.legal_hours,
      'scope_type',s.scope_type,'scope_ref',s.scope_ref,'source_url',s.source_url
    ) order by s.start_date,s.season_name),'[]'::jsonb) value
    from operability.hunting_seasons s
    where s.jurisdiction='KY' and s.species='white_tailed_deer'
      and current_date between s.start_date and s.end_date
  ),
  upcoming_seasons as (
    select coalesce(jsonb_agg(x.obj order by x.start_date,x.season_name),'[]'::jsonb) value
    from (
      select s.start_date,s.season_name,jsonb_build_object(
        'species',s.species,'season_year',s.season_year,'season_name',s.season_name,
        'start_date',s.start_date,'end_date',s.end_date,'legal_hours',s.legal_hours,
        'scope_type',s.scope_type,'scope_ref',s.scope_ref,'source_url',s.source_url
      ) obj
      from operability.hunting_seasons s
      where s.jurisdiction='KY' and s.species='white_tailed_deer' and s.start_date > current_date
      order by s.start_date,s.season_name limit 5
    ) x
  ),
  drone_rules as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'species',r.species,'activity',r.activity,'determination',r.determination,
      'scope_type',r.scope_type,'scope_ref',r.scope_ref,'summary',r.summary,
      'effective_from',r.effective_from,'effective_to',r.effective_to,
      'authority_level',r.authority_level,'source_url',r.source_url
    ) order by r.activity),'[]'::jsonb) value
    from operability.hunting_rules r
    where r.jurisdiction='KY' and (r.species='white_tailed_deer' or r.species is null)
      and r.activity in (
        'drone_hunt_or_take_live_wildlife','drone_pursuit_live_wounded_animal',
        'drone_search_post_shot_presumed_dead','drone_direct_hunter_to_dead_carcass',
        'drone_terrain_scouting','thermal_or_infrared_night_recovery',
        'commercial_drone_service_on_public_land','drone_disrupt_or_interfere_legal_hunt',
        'physical_retrieval_on_adjacent_private_property'
      )
      and (r.effective_from is null or r.effective_from <= current_date)
      and (r.effective_to is null or r.effective_to >= current_date)
  ),
  protected as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'name',x.name,'area_kind',x.area_kind,'designation',x.designation,
      'jurisdiction_level',x.jurisdiction_level,'gap_status_code',x.gap_status_code,
      'iucn_category',x.iucn_category,'distance_m',x.distance_m,
      'intersects_property',x.intersects_property,'source_slug',x.source_slug,
      'source_authority',x.source_authority,'last_observed_at',x.last_observed_at
    ) order by x.distance_m),'[]'::jsonb) value
    from (
      select m.name,m.area_kind,m.designation,m.jurisdiction_level,m.gap_status_code,m.iucn_category,
        round(extensions.st_distance(m.geometry::geography,p.pt::geography)::numeric,1) distance_m,
        case when p.boundary is null then false else extensions.st_intersects(m.geometry,p.boundary) end intersects_property,
        s.slug source_slug,s.authority source_authority,m.last_observed_at
      from environment.managed_land_areas m join ingest.sources s on s.id=m.source_id cross join p
      where s.slug='usgs-pad-us-4-1' and m.source_present is true and m.geometry is not null and p.pt is not null
        and extensions.st_dwithin(m.geometry::geography,p.pt::geography,10000)
      order by m.geometry <-> p.pt limit 8
    ) x
  )
  select jsonb_build_object(
    'as_of_date',current_date,
    'hunting',jsonb_build_object(
      'jurisdiction','KY',
      'deer_management',(select case when d.id is null then null else jsonb_build_object(
        'county_name',d.county_name,'zone_code',d.code,'deer_zone',d.attributes->>'deer_zone',
        'season_year',d.attributes->>'season_year','source_url',d.source_url) end from deer_area d),
      'active_seasons',(select value from active_seasons),
      'upcoming_seasons',(select value from upcoming_seasons),
      'drone_wildlife_rules',(select value from drone_rules)
    ),
    'protected_lands',jsonb_build_object(
      'intersections',(select count(*) from jsonb_array_elements((select value from protected)) e where coalesce((e->>'intersects_property')::boolean,false)),
      'nearby_authoritative',(select value from protected),
      'source_scope','USGS PAD-US 4.1 cached in Scout'
    )
  );
$$;

create or replace function farm_watch.farm_watch_get_regulatory_context_v1_internal(p_slug text)
returns jsonb language sql security definer set search_path=pg_catalog,farm_watch as $$
  select jsonb_build_object(
    'static_status',c.static_status,'static_context',c.static_context,'static_retrieved_at',c.static_retrieved_at,
    'faa_status',c.faa_status,'faa_context',c.faa_context,'faa_checked_at',c.faa_checked_at
  )
  from farm_watch.property_regulatory_context_v1 c join farm_watch.properties p on p.id=c.property_id
  where p.slug=p_slug limit 1;
$$;

create or replace function farm_watch.farm_watch_upsert_regulatory_static_v1_internal(
  p_slug text,p_status text,p_context jsonb,p_retrieved_at timestamptz default now())
returns void language plpgsql security definer set search_path=pg_catalog,farm_watch as $$
declare v_property_id uuid;
begin
  if p_status not in ('available','partial','unavailable','unknown') then raise exception 'invalid static regulatory status'; end if;
  select id into v_property_id from farm_watch.properties where slug=p_slug limit 1;
  if v_property_id is null then raise exception 'property not found'; end if;
  insert into farm_watch.property_regulatory_context_v1(property_id,static_status,static_context,static_retrieved_at)
  values(v_property_id,p_status,coalesce(p_context,'{}'::jsonb),coalesce(p_retrieved_at,now()))
  on conflict(property_id) do update set static_status=excluded.static_status,static_context=excluded.static_context,
    static_retrieved_at=excluded.static_retrieved_at,updated_at=now();
end;
$$;

create or replace function farm_watch.farm_watch_upsert_regulatory_faa_v1_internal(
  p_slug text,p_status text,p_context jsonb,p_checked_at timestamptz default now())
returns void language plpgsql security definer set search_path=pg_catalog,farm_watch as $$
declare v_property_id uuid;
begin
  if p_status not in ('available','partial','unavailable','unknown') then raise exception 'invalid FAA regulatory status'; end if;
  select id into v_property_id from farm_watch.properties where slug=p_slug limit 1;
  if v_property_id is null then raise exception 'property not found'; end if;
  insert into farm_watch.property_regulatory_context_v1(property_id,faa_status,faa_context,faa_checked_at)
  values(v_property_id,p_status,coalesce(p_context,'{}'::jsonb),coalesce(p_checked_at,now()))
  on conflict(property_id) do update set faa_status=excluded.faa_status,faa_context=excluded.faa_context,
    faa_checked_at=excluded.faa_checked_at,updated_at=now();
end;
$$;

revoke all on function farm_watch.farm_watch_get_regulatory_anchor_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_regulatory_local_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_regulatory_context_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_upsert_regulatory_static_v1_internal(text,text,jsonb,timestamptz) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_upsert_regulatory_faa_v1_internal(text,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_regulatory_anchor_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_get_regulatory_local_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_get_regulatory_context_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_upsert_regulatory_static_v1_internal(text,text,jsonb,timestamptz) to service_role;
grant execute on function farm_watch.farm_watch_upsert_regulatory_faa_v1_internal(text,text,jsonb,timestamptz) to service_role;

create or replace function public.farm_watch_get_regulatory_anchor_v1_internal(p_slug text)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select farm_watch.farm_watch_get_regulatory_anchor_v1_internal(p_slug); $$;
create or replace function public.farm_watch_get_regulatory_local_v1_internal(p_slug text)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select farm_watch.farm_watch_get_regulatory_local_v1_internal(p_slug); $$;
create or replace function public.farm_watch_get_regulatory_context_v1_internal(p_slug text)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select farm_watch.farm_watch_get_regulatory_context_v1_internal(p_slug); $$;
create or replace function public.farm_watch_upsert_regulatory_static_v1_internal(p_slug text,p_status text,p_context jsonb,p_retrieved_at timestamptz default now())
returns void language sql security definer set search_path=pg_catalog as $$ select farm_watch.farm_watch_upsert_regulatory_static_v1_internal(p_slug,p_status,p_context,p_retrieved_at); $$;
create or replace function public.farm_watch_upsert_regulatory_faa_v1_internal(p_slug text,p_status text,p_context jsonb,p_checked_at timestamptz default now())
returns void language sql security definer set search_path=pg_catalog as $$ select farm_watch.farm_watch_upsert_regulatory_faa_v1_internal(p_slug,p_status,p_context,p_checked_at); $$;

revoke all on function public.farm_watch_get_regulatory_anchor_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_get_regulatory_local_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_get_regulatory_context_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_upsert_regulatory_static_v1_internal(text,text,jsonb,timestamptz) from public,anon,authenticated;
revoke all on function public.farm_watch_upsert_regulatory_faa_v1_internal(text,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.farm_watch_get_regulatory_anchor_v1_internal(text) to service_role;
grant execute on function public.farm_watch_get_regulatory_local_v1_internal(text) to service_role;
grant execute on function public.farm_watch_get_regulatory_context_v1_internal(text) to service_role;
grant execute on function public.farm_watch_upsert_regulatory_static_v1_internal(text,text,jsonb,timestamptz) to service_role;
grant execute on function public.farm_watch_upsert_regulatory_faa_v1_internal(text,text,jsonb,timestamptz) to service_role;
