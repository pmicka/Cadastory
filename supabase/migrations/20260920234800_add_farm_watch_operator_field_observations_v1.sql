begin;

create table if not exists farm_watch.property_operator_observations_v1 (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  observation_key text not null,
  observation_kind text not null,
  observation_state text not null
    check (observation_state in ('observed_present', 'observed_absent', 'uncertain')),
  persistence_status text not null default 'unknown'
    check (persistence_status in ('unknown', 'intermittent_or_seasonal', 'persistent_when_observed', 'event_driven')),
  timing_status text not null default 'unknown'
    check (timing_status in ('unknown', 'approximate', 'dated')),
  observed_at timestamptz,
  observed_date_start date,
  observed_date_end date,
  geometry_basis text not null,
  geometry_precision_m numeric check (geometry_precision_m is null or geometry_precision_m > 0),
  related_product_kind text,
  related_product_identity_sha256 text
    check (related_product_identity_sha256 is null or related_product_identity_sha256 ~ '^[0-9a-f]{64}$'),
  related_artifact_sha256 text
    check (related_artifact_sha256 is null or related_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  related_feature_key text,
  source_context jsonb not null default '{}'::jsonb,
  notes text,
  geometry extensions.geometry(Geometry, 4326) not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, observation_key),
  check (observation_kind ~ '^[a-z0-9][a-z0-9_-]{0,79}$'),
  check (
    upper(extensions.geometrytype(geometry)) in (
      'POINT', 'MULTIPOINT', 'LINESTRING', 'MULTILINESTRING', 'POLYGON', 'MULTIPOLYGON'
    )
  ),
  check (
    timing_status <> 'dated'
    or observed_at is not null
    or observed_date_start is not null
  ),
  check (
    observed_date_end is null
    or observed_date_start is not null
  ),
  check (
    observed_date_end is null
    or observed_date_end >= observed_date_start
  )
);

comment on table farm_watch.property_operator_observations_v1 is
  'Private property-scoped operator field observations. These remain operator evidence and do not alter authoritative or deterministic derived source products.';

comment on column farm_watch.property_operator_observations_v1.related_feature_key is
  'Optional stable feature key within the related derived artifact. The observation remains valid field evidence even if a later derived product version changes or removes that feature.';

create index if not exists property_operator_observations_v1_geometry_gix
  on farm_watch.property_operator_observations_v1
  using gist (geometry);

create index if not exists property_operator_observations_v1_property_kind_idx
  on farm_watch.property_operator_observations_v1(property_id, observation_kind)
  where active = true;

create index if not exists property_operator_observations_v1_related_product_idx
  on farm_watch.property_operator_observations_v1(
    property_id,
    related_product_kind,
    related_artifact_sha256,
    related_feature_key
  )
  where active = true and related_product_kind is not null;

alter table farm_watch.property_operator_observations_v1 enable row level security;

revoke all on table farm_watch.property_operator_observations_v1 from public, anon, authenticated;
grant select, insert, update, delete on table farm_watch.property_operator_observations_v1 to service_role;

create or replace function farm_watch.farm_watch_get_operator_observations_v1_internal(
  p_slug text,
  p_observation_kind text default null
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(
        jsonb_build_object(
          'observation_key', o.observation_key,
          'observation_kind', o.observation_kind,
          'observation_state', o.observation_state,
          'persistence_status', o.persistence_status,
          'timing_status', o.timing_status,
          'observed_at', o.observed_at,
          'observed_date_start', o.observed_date_start,
          'observed_date_end', o.observed_date_end,
          'geometry_basis', o.geometry_basis,
          'geometry_precision_m', o.geometry_precision_m,
          'related_product_kind', o.related_product_kind,
          'related_product_identity_sha256', o.related_product_identity_sha256,
          'related_artifact_sha256', o.related_artifact_sha256,
          'related_feature_key', o.related_feature_key,
          'source_context', o.source_context,
          'notes', o.notes,
          'geometry_geojson', extensions.st_asgeojson(o.geometry)::jsonb,
          'evidence_class', 'operator_field_observation',
          'updated_at', o.updated_at
        )
      )
      order by o.observation_key
    ),
    '[]'::jsonb
  )
  from farm_watch.property_operator_observations_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug=p_slug
    and p.status='active'
    and o.active
    and (p_observation_kind is null or o.observation_kind=p_observation_kind)
    and coalesce(auth.role(),'')='service_role';
$$;

revoke all on function farm_watch.farm_watch_get_operator_observations_v1_internal(text,text)
  from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_get_operator_observations_v1_internal(text,text)
  to service_role;

commit;
