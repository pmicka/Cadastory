-- Farm Watch barrier-aware canopy/terrain landscape primitives v1.
-- Structured raster summaries only; no deer score, habitat score, or behavioral inference.

create table if not exists farm_watch.property_landscape_physical_context_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  status text not null check (status in ('available','partial','unavailable')),
  context jsonb not null default '{}'::jsonb,
  boundary_sha256 text not null,
  source_signature text not null,
  source_signature_sha256 text not null,
  algorithm_version text not null,
  output_schema_version text not null,
  identity_sha256 text not null,
  retrieved_at timestamptz not null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table farm_watch.property_landscape_physical_context_v1 enable row level security;
revoke all on table farm_watch.property_landscape_physical_context_v1 from public, anon, authenticated;
grant select, insert, update, delete on table farm_watch.property_landscape_physical_context_v1 to service_role;

comment on table farm_watch.property_landscape_physical_context_v1 is
'Central Farm Watch barrier-aware surrounding-landscape raster summaries for canopy and terrain. Deterministic physical context only; no wildlife-use or suitability prediction.';

create or replace function farm_watch.farm_watch_landscape_physical_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path=pg_catalog
as $$
  select jsonb_build_object(
    'algorithm_version','landscape-raster-context-v1',
    'output_schema_version','farm-watch-landscape-physical-v1',
    'source_signature',
      'kyfromabove-phase3-dem|nlcd-tcc-v2025-6|rings=property,0-500,500-1500,1500-3000|slope=percent-rise|slope_z_factor=0.3048|canopy_bands=0,1-20,21-40,41-60,61-80,81-100|transition=aggregate_composition_gradient_v1'
  );
$$;

revoke all on function farm_watch.farm_watch_landscape_physical_contract_v1() from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_landscape_physical_contract_v1() to postgres, service_role;

create or replace function farm_watch.farm_watch_landscape_physical_identity_v1(
  p_property_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
declare
  v_boundary extensions.geometry;
  v_contract jsonb;
  v_domain_identity jsonb;
  v_land_identity jsonb;
  v_domain_retrieved text;
  v_land_retrieved text;
  v_source_signature text;
  v_boundary_sha256 text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
begin
  select boundary into v_boundary
  from farm_watch.properties
  where id=p_property_id and status='active'
  limit 1;

  if v_boundary is null then return null; end if;

  v_contract := farm_watch.farm_watch_landscape_physical_contract_v1();
  v_domain_identity := farm_watch.farm_watch_context_identity_v1(p_property_id,'landscape-domain');
  v_land_identity := farm_watch.farm_watch_context_identity_v1(p_property_id,'land');

  select to_char(max(retrieved_at) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  into v_domain_retrieved
  from farm_watch.property_landscape_domains_v1
  where property_id=p_property_id
    and identity_sha256=v_domain_identity->>'identity_sha256';

  select to_char(max(retrieved_at) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  into v_land_retrieved
  from farm_watch.property_land_context_v1
  where property_id=p_property_id
    and identity_sha256=v_land_identity->>'identity_sha256';

  v_source_signature := (v_contract->>'source_signature')
    || '|landscape_domain_identity=' || coalesce(v_domain_identity->>'identity_sha256','missing')
    || '|landscape_domain_retrieved=' || coalesce(v_domain_retrieved,'missing')
    || '|parcel_land_identity=' || coalesce(v_land_identity->>'identity_sha256','missing')
    || '|parcel_land_retrieved=' || coalesce(v_land_retrieved,'missing');

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),
    'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          p_property_id::text,
          'landscape-physical',
          v_contract->>'algorithm_version',
          v_contract->>'output_schema_version',
          v_boundary_sha256,
          v_source_signature_sha256
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'product_kind','landscape-physical',
    'boundary_sha256',v_boundary_sha256,
    'source_signature',v_source_signature,
    'source_signature_sha256',v_source_signature_sha256,
    'algorithm_version',v_contract->>'algorithm_version',
    'output_schema_version',v_contract->>'output_schema_version',
    'identity_sha256',v_identity_sha256
  );
end;
$$;

revoke all on function farm_watch.farm_watch_landscape_physical_identity_v1(uuid) from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_landscape_physical_identity_v1(uuid) to postgres, service_role;

create or replace function farm_watch.farm_watch_get_landscape_raster_domains_v1_internal(
  p_slug text
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
  with property as (
    select id,boundary
    from farm_watch.properties
    where slug=p_slug and status='active' and boundary is not null
    limit 1
  ),
  expected as (
    select farm_watch.farm_watch_context_identity_v1(id,'landscape-domain') identity
    from property
  ),
  domain as (
    select d.*
    from farm_watch.property_landscape_domains_v1 d
    join property p on p.id=d.property_id
    cross join expected e
    where d.identity_sha256=e.identity->>'identity_sha256'
      and d.status='available'
  ),
  ring_geometries as (
    select
      'local_ring_0_500m'::text zone_key,
      extensions.st_multi(
        extensions.st_collectionextract(
          extensions.st_makevalid(extensions.st_difference(d.local_500m,p.boundary)),
          3
        )
      ) geom
    from domain d cross join property p

    union all

    select
      'mid_ring_500_1500m',
      extensions.st_multi(
        extensions.st_collectionextract(
          extensions.st_makevalid(extensions.st_difference(d.landscape_1500m,d.local_500m)),
          3
        )
      )
    from domain d

    union all

    select
      'outer_ring_1500_3000m',
      extensions.st_multi(
        extensions.st_collectionextract(
          extensions.st_makevalid(extensions.st_difference(d.broad_3000m,d.landscape_1500m)),
          3
        )
      )
    from domain d
  ),
  zones as (
    select
      zone_key,
      geom,
      extensions.st_area(geom::extensions.geography)/4046.8564224 area_acres
    from ring_geometries
    where geom is not null and not extensions.st_isempty(geom)
  )
  select case
    when not exists(select 1 from property) then
      jsonb_build_object('status','missing','reason','active property boundary unavailable')
    when not exists(select 1 from domain) then
      jsonb_build_object(
        'status','unavailable',
        'reason','current barrier-aware landscape domain unavailable',
        'expected_domain_identity_sha256',(select identity->>'identity_sha256' from expected)
      )
    else
      jsonb_build_object(
        'status','available',
        'domain_identity_sha256',(select identity_sha256 from domain),
        'domain_retrieved_at',(select retrieved_at from domain),
        'zones',coalesce((
          select jsonb_object_agg(
            zone_key,
            jsonb_build_object(
              'area_acres',round(area_acres::numeric,6),
              'geometry',extensions.st_asgeojson(geom,6)::jsonb
            )
          )
          from zones
        ),'{}'::jsonb)
      )
  end;
$$;

revoke all on function farm_watch.farm_watch_get_landscape_raster_domains_v1_internal(text) from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_get_landscape_raster_domains_v1_internal(text) to service_role;

create or replace function farm_watch.farm_watch_upsert_landscape_physical_context_v1_internal(
  p_slug text,
  p_status text,
  p_context jsonb,
  p_retrieved_at timestamptz default now(),
  p_last_error text default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,farm_watch
as $$
declare
  v_property_id uuid;
  v_identity jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_status not in ('available','partial','unavailable') then
    raise exception 'invalid landscape physical status';
  end if;

  select id into v_property_id
  from farm_watch.properties
  where slug=p_slug and status='active'
  limit 1;

  if v_property_id is null then
    raise exception 'active Farm Watch property required';
  end if;

  v_identity := farm_watch.farm_watch_landscape_physical_identity_v1(v_property_id);
  if v_identity is null then
    raise exception 'landscape physical identity unavailable';
  end if;

  insert into farm_watch.property_landscape_physical_context_v1(
    property_id,status,context,
    boundary_sha256,source_signature,source_signature_sha256,
    algorithm_version,output_schema_version,identity_sha256,
    retrieved_at,last_error,updated_at
  ) values (
    v_property_id,p_status,coalesce(p_context,'{}'::jsonb),
    v_identity->>'boundary_sha256',v_identity->>'source_signature',v_identity->>'source_signature_sha256',
    v_identity->>'algorithm_version',v_identity->>'output_schema_version',v_identity->>'identity_sha256',
    coalesce(p_retrieved_at,now()),p_last_error,now()
  )
  on conflict(property_id) do update set
    status=excluded.status,
    context=excluded.context,
    boundary_sha256=excluded.boundary_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    last_error=excluded.last_error,
    updated_at=now();

  return jsonb_build_object(
    'status',p_status,
    'identity_sha256',v_identity->>'identity_sha256',
    'retrieved_at',coalesce(p_retrieved_at,now())
  );
end;
$$;

revoke all on function farm_watch.farm_watch_upsert_landscape_physical_context_v1_internal(text,text,jsonb,timestamptz,text) from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_upsert_landscape_physical_context_v1_internal(text,text,jsonb,timestamptz,text) to service_role;

create or replace function farm_watch.farm_watch_get_landscape_physical_context_v1_internal(
  p_slug text
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,farm_watch
as $$
  with property as (
    select id
    from farm_watch.properties
    where slug=p_slug and status='active'
    limit 1
  ),
  expected as (
    select farm_watch.farm_watch_landscape_physical_identity_v1(id) identity
    from property
  ),
  cached as (
    select c.*
    from farm_watch.property_landscape_physical_context_v1 c
    join property p on p.id=c.property_id
  )
  select case
    when not exists(select 1 from property) then
      jsonb_build_object('status','missing','context',null)
    when not exists(select 1 from cached) then
      jsonb_build_object('status','missing','context',null)
    when (select identity_sha256 from cached)=(select identity->>'identity_sha256' from expected) then
      jsonb_build_object(
        'status',(select status from cached),
        'context',(select context from cached),
        'retrieved_at',(select retrieved_at from cached),
        'last_error',(select last_error from cached),
        'identity',jsonb_build_object(
          'boundary_sha256',(select boundary_sha256 from cached),
          'source_signature_sha256',(select source_signature_sha256 from cached),
          'algorithm_version',(select algorithm_version from cached),
          'output_schema_version',(select output_schema_version from cached),
          'identity_sha256',(select identity_sha256 from cached)
        )
      )
    else
      jsonb_build_object(
        'status','stale',
        'context',null,
        'retrieved_at',(select retrieved_at from cached),
        'last_error',(select last_error from cached),
        'invalidation_reason','identity_mismatch',
        'stored_identity_sha256',(select identity_sha256 from cached),
        'expected_identity_sha256',(select identity->>'identity_sha256' from expected)
      )
  end;
$$;

revoke all on function farm_watch.farm_watch_get_landscape_physical_context_v1_internal(text) from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_get_landscape_physical_context_v1_internal(text) to service_role;

comment on function farm_watch.farm_watch_get_landscape_physical_context_v1_internal(text) is
'Returns central barrier-aware canopy/terrain landscape primitives. Aggregate canopy gradients are composition shifts across rings, not pixel-edge detection or wildlife-use inference.';
