begin;

create table if not exists farm_watch.property_operator_paths_v1 (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  path_key text not null,
  name text not null,
  feature_class text not null check (feature_class in ('road', 'trail', 'other')),
  feature_subclass text,
  surface_tag text,
  existence_status text not null default 'operator_confirmed'
    check (existence_status in ('operator_confirmed')),
  legal_access_status text not null default 'unknown'
    check (legal_access_status in ('unknown', 'confirmed', 'restricted')),
  drivable_status text not null default 'not_assessed'
    check (drivable_status in ('not_assessed', 'confirmed', 'not_drivable')),
  geometry_basis text not null,
  geometry_precision_m numeric check (geometry_precision_m is null or geometry_precision_m > 0),
  source_context jsonb not null default '{}'::jsonb,
  notes text,
  geometry extensions.geometry(MultiLineString, 4326) not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, path_key)
);

create index if not exists property_operator_paths_v1_geometry_gix
  on farm_watch.property_operator_paths_v1
  using gist (geometry);

create index if not exists property_operator_paths_v1_property_idx
  on farm_watch.property_operator_paths_v1(property_id)
  where active = true;

alter table farm_watch.property_operator_paths_v1 enable row level security;

revoke all on table farm_watch.property_operator_paths_v1 from anon, authenticated;
grant select, insert, update, delete on table farm_watch.property_operator_paths_v1 to service_role;

with property_row as (
  select id
  from farm_watch.properties
  where slug = 'validation-property-01'
  limit 1
)
insert into farm_watch.property_operator_paths_v1 (
  property_id,
  path_key,
  name,
  feature_class,
  feature_subclass,
  surface_tag,
  existence_status,
  legal_access_status,
  drivable_status,
  geometry_basis,
  geometry_precision_m,
  source_context,
  notes,
  geometry
)
select
  p.id,
  'flat-creek-gravel-access-road',
  'Flat Creek gravel access road',
  'road',
  'gravel_road',
  'gravel',
  'operator_confirmed',
  'unknown',
  'not_assessed',
  'operator_confirmed_screen_trace_georeferenced_v1',
  5.0,
  jsonb_build_object(
    'operator_assertion', 'Existing gravel road used for property access',
    'tracing_basis', 'Operator-drawn route traced against Farm Watch Phase 3 shaded relief',
    'reference_terrain', 'KyFromAbove Phase 3 shaded relief',
    'reference_imagery', 'KyFromAbove Phase 3 3 in leaf-off mosaic',
    'reference_imagery_window', '2022-2024',
    'network_segments', jsonb_build_array(
      'western approach',
      'neighboring-house spur',
      'north parcel-edge branch',
      'south branch'
    )
  ),
  'Operator confirmed the gravel road and the early branch serving the neighboring parcel with a house. Geometry is a georeferenced centerline trace of that confirmed road network; no additional access paths were inferred.',
  extensions.st_setsrid(
    extensions.st_geomfromgeojson(
      $geojson$
      {
        "type": "MultiLineString",
        "coordinates": [
          [
            [-84.8943173, 38.3246390],
            [-84.8942870, 38.3246748],
            [-84.8940139, 38.3247581],
            [-84.8938166, 38.3247700],
            [-84.8931642, 38.3246748],
            [-84.8922538, 38.3246867],
            [-84.8915407, 38.3246271],
            [-84.8913435, 38.3245795],
            [-84.8912676, 38.3245319],
            [-84.8908124, 38.3244962],
            [-84.8903572, 38.3244010],
            [-84.8897200, 38.3241986],
            [-84.8891889, 38.3241629],
            [-84.8888703, 38.3240915],
            [-84.8885213, 38.3239725],
            [-84.8880054, 38.3239367],
            [-84.8878385, 38.3239010],
            [-84.8877020, 38.3238534],
            [-84.8874896, 38.3236987],
            [-84.8872620, 38.3236511]
          ],
          [
            [-84.8922994, 38.3246867],
            [-84.8923297, 38.3247819],
            [-84.8923904, 38.3248414],
            [-84.8927545, 38.3249723],
            [-84.8928608, 38.3250557],
            [-84.8930125, 38.3251152]
          ],
          [
            [-84.8872620, 38.3236511],
            [-84.8872164, 38.3237463],
            [-84.8872771, 38.3240082],
            [-84.8872468, 38.3241748],
            [-84.8870647, 38.3244962],
            [-84.8870647, 38.3246152],
            [-84.8871558, 38.3247938],
            [-84.8871709, 38.3249485],
            [-84.8870799, 38.3253889],
            [-84.8870951, 38.3259722],
            [-84.8869889, 38.3261865],
            [-84.8869585, 38.3263650]
          ],
          [
            [-84.8872620, 38.3236511],
            [-84.8872164, 38.3234963],
            [-84.8872620, 38.3231273],
            [-84.8871861, 38.3229607],
            [-84.8870951, 38.3228892],
            [-84.8869585, 38.3228416],
            [-84.8865792, 38.3227821],
            [-84.8863971, 38.3226631],
            [-84.8863212, 38.3225678],
            [-84.8863061, 38.3223536],
            [-84.8863516, 38.3221631],
            [-84.8865033, 38.3219250],
            [-84.8866550, 38.3217703]
          ]
        ]
      }
      $geojson$
    ),
    4326
  )
from property_row p
on conflict (property_id, path_key) do update
set
  name = excluded.name,
  feature_class = excluded.feature_class,
  feature_subclass = excluded.feature_subclass,
  surface_tag = excluded.surface_tag,
  existence_status = excluded.existence_status,
  legal_access_status = excluded.legal_access_status,
  drivable_status = excluded.drivable_status,
  geometry_basis = excluded.geometry_basis,
  geometry_precision_m = excluded.geometry_precision_m,
  source_context = excluded.source_context,
  notes = excluded.notes,
  geometry = excluded.geometry,
  active = true,
  updated_at = now();

create or replace function public.farm_watch_get_access_features_v1_internal(
  p_slug text,
  p_buffer_m integer default 1000
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  with property as (
    select p.id, p.boundary
    from farm_watch.properties p
    where p.slug = p_slug
      and p.status = 'active'
      and p.boundary is not null
    limit 1
  ),
  source_features as (
    select
      s.id,
      s.feature_class,
      s.feature_subclass,
      s.name,
      s.access_tag,
      s.surface_tag,
      s.service_tag,
      s.drivable,
      s.staging_candidate,
      s.routing_barrier,
      s.access_point,
      s.source_confidence,
      extensions.st_distance(s.geometry::extensions.geography, property.boundary::extensions.geography) as distance_m,
      s.geometry,
      'reference'::text as source_kind,
      'source_backed_reference'::text as evidence_class,
      null::text as geometry_basis,
      null::text as legal_access_status,
      null::numeric as geometry_precision_m,
      null::text as operator_notes
    from decisioning.site_access_features s
    cross join property
    where s.geometry is not null
      and extensions.st_dwithin(
        s.geometry::extensions.geography,
        property.boundary::extensions.geography,
        least(greatest(coalesce(p_buffer_m, 1000), 0), 1500)
      )
  ),
  operator_features as (
    select
      o.id,
      o.feature_class,
      o.feature_subclass,
      o.name,
      null::text as access_tag,
      o.surface_tag,
      null::text as service_tag,
      null::boolean as drivable,
      false::boolean as staging_candidate,
      false::boolean as routing_barrier,
      false::boolean as access_point,
      0.95::numeric as source_confidence,
      extensions.st_distance(o.geometry::extensions.geography, property.boundary::extensions.geography) as distance_m,
      o.geometry,
      'operator'::text as source_kind,
      o.existence_status::text as evidence_class,
      o.geometry_basis,
      o.legal_access_status,
      o.geometry_precision_m,
      o.notes as operator_notes
    from farm_watch.property_operator_paths_v1 o
    cross join property
    where o.property_id = property.id
      and o.active = true
      and extensions.st_dwithin(
        o.geometry::extensions.geography,
        property.boundary::extensions.geography,
        least(greatest(coalesce(p_buffer_m, 1000), 0), 1500)
      )
  ),
  bounded as (
    select * from operator_features
    union all
    select * from source_features
    order by distance_m, id
    limit 100
  )
  select jsonb_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'type', 'Feature',
          'id', b.id,
          'geometry', extensions.st_asgeojson(b.geometry, 7)::jsonb,
          'properties', jsonb_strip_nulls(jsonb_build_object(
            'feature_class', b.feature_class,
            'feature_subclass', b.feature_subclass,
            'name', nullif(b.name, ''),
            'access_tag', b.access_tag,
            'surface_tag', b.surface_tag,
            'service_tag', b.service_tag,
            'drivable', b.drivable,
            'staging_candidate', b.staging_candidate,
            'routing_barrier', b.routing_barrier,
            'access_point', b.access_point,
            'source_confidence', b.source_confidence,
            'distance_m', round(b.distance_m::numeric, 1),
            'source_kind', b.source_kind,
            'evidence_class', b.evidence_class,
            'geometry_basis', b.geometry_basis,
            'geometry_precision_m', b.geometry_precision_m,
            'legal_access_status', b.legal_access_status,
            'operator_notes', b.operator_notes
          ))
        )
        order by b.distance_m, b.id
      ),
      '[]'::jsonb
    )
  )
  from bounded b;
$function$;

revoke all on function public.farm_watch_get_access_features_v1_internal(text, integer) from public, anon, authenticated;
grant execute on function public.farm_watch_get_access_features_v1_internal(text, integer) to service_role;

commit;
