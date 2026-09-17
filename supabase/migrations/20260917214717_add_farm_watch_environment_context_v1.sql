insert into ingest.sources (
  slug, name, authority, source_class, geographic_scope, acquisition_method,
  update_cadence, authority_level, status, homepage_url, license_notes,
  commercial_use_status, notes
)
values (
  'nasa-daymet-v4',
  'NASA ORNL Daymet Daily Surface Weather',
  'NASA ORNL DAAC / Oak Ridge National Laboratory',
  'modeled_environmental',
  'North America',
  'Daymet Single Pixel REST API',
  'annual archive refresh',
  'federal_research_authoritative',
  'active_reference',
  'https://daymet.ornl.gov/',
  'Public NASA/ORNL research data; retain product citation and modeled-data caveat.',
  'public_government',
  'Daily 1 km gridded modeled/interpolated surface weather. Use for historical environmental context, not parcel-level measured rainfall truth.'
)
on conflict (slug) do update set
  name = excluded.name,
  authority = excluded.authority,
  source_class = excluded.source_class,
  geographic_scope = excluded.geographic_scope,
  acquisition_method = excluded.acquisition_method,
  update_cadence = excluded.update_cadence,
  authority_level = excluded.authority_level,
  status = excluded.status,
  homepage_url = excluded.homepage_url,
  license_notes = excluded.license_notes,
  commercial_use_status = excluded.commercial_use_status,
  notes = excluded.notes,
  updated_at = now();

create table if not exists farm_watch.property_environment_context_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  context_date date not null,
  status text not null check (status in ('available','partial','unavailable')),
  context jsonb not null default '{}'::jsonb,
  retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (property_id, context_date)
);

create index if not exists property_environment_context_retrieved_idx
  on farm_watch.property_environment_context_v1 (retrieved_at desc);

alter table farm_watch.property_environment_context_v1 enable row level security;
revoke all on farm_watch.property_environment_context_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.property_environment_context_v1 to service_role;

create or replace function farm_watch.farm_watch_get_environment_anchor_v1_internal(p_slug text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, farm_watch, hydrology, extensions
as $$
  with p as (
    select
      id,
      slug,
      state_code,
      postal_code,
      metadata,
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
    'postal_code', p.postal_code,
    'county_fips', nullif(p.metadata->>'county_fips',''),
    'nearest_gauge', (
      select jsonb_build_object(
        'gauge_id', g.gauge_id,
        'name', g.name,
        'distance_m', round(extensions.st_distance(g.location::geography, p.pt::geography)::numeric, 1)
      )
      from hydrology.stream_gauges g
      where p.pt is not null
        and g.location is not null
        and g.source_present is true
      order by g.location <-> p.pt
      limit 1
    )
  )
  from p;
$$;

create or replace function farm_watch.farm_watch_get_environment_context_v1_internal(
  p_slug text,
  p_context_date date
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, farm_watch
as $$
  select jsonb_build_object(
    'status', c.status,
    'context', c.context,
    'retrieved_at', c.retrieved_at
  )
  from farm_watch.property_environment_context_v1 c
  join farm_watch.properties p on p.id = c.property_id
  where p.slug = p_slug
    and c.context_date = p_context_date
  limit 1;
$$;

create or replace function farm_watch.farm_watch_upsert_environment_context_v1_internal(
  p_slug text,
  p_context_date date,
  p_status text,
  p_context jsonb,
  p_retrieved_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, farm_watch
as $$
declare
  v_property_id uuid;
begin
  if p_status not in ('available','partial','unavailable') then
    raise exception 'invalid environment context status';
  end if;

  select id into v_property_id
  from farm_watch.properties
  where slug = p_slug
  limit 1;

  if v_property_id is null then
    raise exception 'property not found';
  end if;

  insert into farm_watch.property_environment_context_v1 (
    property_id, context_date, status, context, retrieved_at
  )
  values (
    v_property_id, p_context_date, p_status, coalesce(p_context, '{}'::jsonb), coalesce(p_retrieved_at, now())
  )
  on conflict (property_id, context_date) do update set
    status = excluded.status,
    context = excluded.context,
    retrieved_at = excluded.retrieved_at,
    updated_at = now();
end;
$$;

revoke all on function farm_watch.farm_watch_get_environment_anchor_v1_internal(text) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_get_environment_context_v1_internal(text, date) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_upsert_environment_context_v1_internal(text, date, text, jsonb, timestamptz) from public, anon, authenticated;

grant execute on function farm_watch.farm_watch_get_environment_anchor_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_get_environment_context_v1_internal(text, date) to service_role;
grant execute on function farm_watch.farm_watch_upsert_environment_context_v1_internal(text, date, text, jsonb, timestamptz) to service_role;
