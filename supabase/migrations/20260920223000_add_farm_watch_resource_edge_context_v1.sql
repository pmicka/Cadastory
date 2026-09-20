-- Farm Watch resource-edge context v1.
-- Neutral agricultural geometry and crop-context primitives; no deer-use inference.

create table if not exists farm_watch.property_resource_edge_context_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  status text not null check (status in ('available','partial','unavailable')),
  context jsonb not null default '{}'::jsonb,
  field_area_geometry extensions.geometry(MultiPolygon,4326),
  field_edge_geometry extensions.geometry(MultiLineString,4326),
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

create index if not exists property_resource_edge_context_v1_area_gix
  on farm_watch.property_resource_edge_context_v1 using gist(field_area_geometry);
create index if not exists property_resource_edge_context_v1_edge_gix
  on farm_watch.property_resource_edge_context_v1 using gist(field_edge_geometry);

alter table farm_watch.property_resource_edge_context_v1 enable row level security;
revoke all on table farm_watch.property_resource_edge_context_v1 from public,anon,authenticated;
grant select,insert,update,delete on table farm_watch.property_resource_edge_context_v1 to service_role;

comment on table farm_watch.property_resource_edge_context_v1 is
'Barrier-aware mapped agricultural field-area and field-edge context for Farm Watch. Deterministic derived landscape evidence only; not forage quality, deer use, or hunting advice.';

create or replace function farm_watch.farm_watch_resource_edge_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path=pg_catalog
as $$
  select jsonb_build_object(
    'algorithm_version','barrier-aware-resource-edge-v1',
    'output_schema_version','farm-watch-resource-edge-v1',
    'source_signature',
      'agriculture.field_boundaries|agriculture.cdl_classes|domain=landscape-domain-current|zones=500,1500,3000|proximity=100,250,500|edge=field-boundary-clipped-to-domain'
  );
$$;

revoke all on function farm_watch.farm_watch_resource_edge_contract_v1() from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_resource_edge_contract_v1() to postgres,service_role;

create or replace function farm_watch.farm_watch_resource_edge_identity_v1(
  p_property_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,farm_watch,agriculture,extensions
as $$
declare
  v_boundary extensions.geometry;
  v_domain extensions.geometry;
  v_contract jsonb;
  v_domain_identity text;
  v_field_signature text;
  v_cdl_signature text;
  v_source_signature text;
  v_boundary_sha256 text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
begin
  select p.boundary,d.broad_3000m,d.identity_sha256
  into v_boundary,v_domain,v_domain_identity
  from farm_watch.properties p
  left join farm_watch.property_landscape_domains_v1 d
    on d.property_id=p.id
   and d.status='available'
   and d.identity_sha256 =
     farm_watch.farm_watch_context_identity_v1(p.id,'landscape-domain')->>'identity_sha256'
  where p.id=p_property_id
    and p.status='active'
  limit 1;

  if v_boundary is null or v_domain is null or v_domain_identity is null then
    return null;
  end if;

  v_contract := farm_watch.farm_watch_resource_edge_contract_v1();

  select encode(
    extensions.digest(
      convert_to(
        coalesce(
          string_agg(
            concat_ws(
              '~',
              f.id::text,
              coalesce(f.source_native_id,''),
              coalesce(f.boundary_status,''),
              coalesce(f.latest_crop_year::text,''),
              coalesce(f.latest_crop_code::text,''),
              coalesce(f.source_confidence::text,''),
              coalesce(f.last_observed_at::text,''),
              f.updated_at::text
            ),
            '|' order by f.id
          ),
          'none'
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_field_signature
  from agriculture.field_boundaries f
  where f.geometry is not null
    and coalesce(f.source_present,true)
    and extensions.st_intersects(f.geometry,v_domain);

  select encode(
    extensions.digest(
      convert_to(
        coalesce(
          string_agg(
            concat_ws(
              '~',
              c.year::text,
              c.class_code::text,
              coalesce(c.class_name,''),
              c.updated_at::text
            ),
            '|' order by c.year,c.class_code
          ),
          'none'
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_cdl_signature
  from agriculture.cdl_classes c
  where exists (
    select 1
    from agriculture.field_boundaries f
    where f.geometry is not null
      and coalesce(f.source_present,true)
      and extensions.st_intersects(f.geometry,v_domain)
      and f.latest_crop_year=c.year
      and f.latest_crop_code=c.class_code
  );

  v_source_signature := (v_contract->>'source_signature')
    || '|landscape_domain_identity=' || v_domain_identity
    || '|field_signature=' || coalesce(v_field_signature,'missing')
    || '|cdl_signature=' || coalesce(v_cdl_signature,'missing');

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
          'resource-edge',
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
    'product_kind','resource-edge',
    'boundary_sha256',v_boundary_sha256,
    'source_signature',v_source_signature,
    'source_signature_sha256',v_source_signature_sha256,
    'algorithm_version',v_contract->>'algorithm_version',
    'output_schema_version',v_contract->>'output_schema_version',
    'identity_sha256',v_identity_sha256
  );
end;
$$;

revoke all on function farm_watch.farm_watch_resource_edge_identity_v1(uuid) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_resource_edge_identity_v1(uuid) to postgres,service_role;

create or replace function farm_watch.farm_watch_refresh_resource_edge_context_v1_internal(
  p_slug text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,farm_watch,agriculture,extensions
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_local extensions.geometry;
  v_landscape extensions.geometry;
  v_broad extensions.geometry;
  v_domain_identity text;
  v_expected_domain_identity text;
  v_identity jsonb;
  v_context jsonb;
  v_field_area extensions.geometry;
  v_field_edges extensions.geometry;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select
    p.id,p.boundary,
    d.local_500m,d.landscape_1500m,d.broad_3000m,d.identity_sha256,
    farm_watch.farm_watch_context_identity_v1(p.id,'landscape-domain')->>'identity_sha256'
  into
    v_property_id,v_boundary,
    v_local,v_landscape,v_broad,v_domain_identity,v_expected_domain_identity
  from farm_watch.properties p
  left join farm_watch.property_landscape_domains_v1 d
    on d.property_id=p.id and d.status='available'
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object('status','unavailable','reason','active property boundary unavailable');
  end if;

  if v_broad is null or v_domain_identity is distinct from v_expected_domain_identity then
    return jsonb_build_object(
      'status','unavailable',
      'reason','current barrier-aware landscape domain required',
      'stored_domain_identity_sha256',v_domain_identity,
      'expected_domain_identity_sha256',v_expected_domain_identity
    );
  end if;

  with fields as (
    select
      f.id,
      f.source_native_id,
      f.boundary_source_kind,
      f.boundary_status,
      f.source_confidence,
      f.latest_crop_year,
      f.latest_crop_code,
      f.crop_sequence,
      f.geometry,
      c.class_name,
      extensions.st_distance(
        f.geometry::extensions.geography,
        v_boundary::extensions.geography
      ) distance_m
    from agriculture.field_boundaries f
    left join agriculture.cdl_classes c
      on c.year=f.latest_crop_year
     and c.class_code=f.latest_crop_code
    where f.geometry is not null
      and coalesce(f.source_present,true)
      and extensions.st_intersects(f.geometry,v_broad)
  ),
  clipped as (
    select
      *,
      extensions.st_collectionextract(
        extensions.st_makevalid(extensions.st_intersection(geometry,v_broad)),
        3
      ) clipped_geom,
      extensions.st_collectionextract(
        extensions.st_makevalid(
          extensions.st_intersection(extensions.st_boundary(geometry),v_broad)
        ),
        2
      ) clipped_edge
    from fields
  ),
  zones as (
    select 500 radius_m,v_local geom
    union all
    select 1500,v_landscape
    union all
    select 3000,v_broad
  ),
  zone_parts as (
    select
      z.radius_m,
      z.geom zone_geom,
      f.id,
      extensions.st_collectionextract(
        extensions.st_makevalid(extensions.st_intersection(f.geometry,z.geom)),
        3
      ) field_geom,
      extensions.st_collectionextract(
        extensions.st_makevalid(
          extensions.st_intersection(extensions.st_boundary(f.geometry),z.geom)
        ),
        2
      ) edge_geom
    from zones z
    left join fields f
      on extensions.st_intersects(f.geometry,z.geom)
  ),
  zone_stats as (
    select
      radius_m,
      count(distinct id)::integer field_count,
      extensions.st_area(max(zone_geom)::extensions.geography) zone_area_m2,
      coalesce(
        extensions.st_area(
          extensions.st_unaryunion(extensions.st_collect(field_geom))::extensions.geography
        ),
        0
      ) field_area_m2,
      coalesce(
        extensions.st_length(
          extensions.st_unaryunion(extensions.st_collect(edge_geom))::extensions.geography
        ),
        0
      ) field_edge_m
    from zone_parts
    group by radius_m
  ),
  proximity_buffers as (
    select
      x.radius_m,
      extensions.st_intersection(
        (extensions.st_buffer(v_boundary::extensions.geography,x.radius_m))::extensions.geometry,
        v_broad
      ) geom
    from (values (100),(250),(500)) x(radius_m)
  ),
  proximity_parts as (
    select
      b.radius_m,
      f.id,
      extensions.st_collectionextract(
        extensions.st_makevalid(extensions.st_intersection(f.geometry,b.geom)),
        3
      ) field_geom,
      extensions.st_collectionextract(
        extensions.st_makevalid(
          extensions.st_intersection(extensions.st_boundary(f.geometry),b.geom)
        ),
        2
      ) edge_geom
    from proximity_buffers b
    left join fields f
      on extensions.st_intersects(f.geometry,b.geom)
  ),
  proximity_stats as (
    select
      radius_m,
      count(distinct id)::integer field_count,
      coalesce(
        extensions.st_area(
          extensions.st_unaryunion(extensions.st_collect(field_geom))::extensions.geography
        ),
        0
      ) field_area_m2,
      coalesce(
        extensions.st_length(
          extensions.st_unaryunion(extensions.st_collect(edge_geom))::extensions.geography
        ),
        0
      ) field_edge_m
    from proximity_parts
    group by radius_m
  ),
  crop_stats as (
    select
      f.latest_crop_year,
      f.latest_crop_code,
      f.class_name,
      count(distinct f.id)::integer field_count,
      sum(extensions.st_area(f.clipped_geom::extensions.geography)) field_area_m2
    from clipped f
    where f.latest_crop_year is not null
      and f.latest_crop_code is not null
      and f.clipped_geom is not null
      and not extensions.st_isempty(f.clipped_geom)
    group by f.latest_crop_year,f.latest_crop_code,f.class_name
  ),
  boundary_quality as (
    select
      boundary_status,
      count(*)::integer field_count,
      avg(source_confidence) avg_source_confidence,
      min(source_confidence) min_source_confidence,
      max(source_confidence) max_source_confidence
    from fields
    group by boundary_status
  ),
  nearest as (
    select *
    from fields
    order by distance_m,id
    limit 1
  ),
  area_union as (
    select extensions.st_multi(
      extensions.st_collectionextract(
        extensions.st_unaryunion(extensions.st_collect(clipped_geom)),
        3
      )
    ) geom
    from clipped
    where clipped_geom is not null and not extensions.st_isempty(clipped_geom)
  ),
  edge_union as (
    select extensions.st_multi(
      extensions.st_collectionextract(
        extensions.st_unaryunion(extensions.st_collect(clipped_edge)),
        2
      )
    ) geom
    from clipped
    where clipped_edge is not null and not extensions.st_isempty(clipped_edge)
  )
  select
    jsonb_build_object(
      'context_version',1,
      'method','barrier_aware_resource_edge_v1',
      'evidence_class','deterministic_derived',
      'scoring_performed',false,
      'behavioral_inference_performed',false,
      'domain_identity_sha256',v_domain_identity,
      'nearest_mapped_field',(
        select case when n.id is null then null else jsonb_build_object(
          'field_id',n.id,
          'source_native_id',n.source_native_id,
          'distance_m',round(n.distance_m::numeric,1),
          'latest_crop_year',n.latest_crop_year,
          'latest_crop_code',n.latest_crop_code,
          'latest_crop_class',n.class_name,
          'boundary_status',n.boundary_status,
          'source_confidence',n.source_confidence
        ) end
        from nearest n
      ),
      'zone_context',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'radius_m',radius_m,
            'field_count',field_count,
            'mapped_field_area_acres',round((field_area_m2/4046.8564224)::numeric,2),
            'mapped_field_fraction_percent',
              round((100*field_area_m2/nullif(zone_area_m2,0))::numeric,2),
            'mapped_field_edge_km',round((field_edge_m/1000)::numeric,3),
            'mapped_field_edge_density_km_per_sq_km',
              round(((field_edge_m/1000)/nullif(zone_area_m2/1000000,0))::numeric,3)
          )
          order by radius_m
        )
        from zone_stats
      ),'[]'::jsonb),
      'property_proximity',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'radius_m',radius_m,
            'field_count',field_count,
            'mapped_field_area_acres',round((field_area_m2/4046.8564224)::numeric,2),
            'mapped_field_edge_m',round(field_edge_m::numeric,1)
          )
          order by radius_m
        )
        from proximity_stats
      ),'[]'::jsonb),
      'latest_crop_composition_3000m',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'year',latest_crop_year,
            'class_code',latest_crop_code,
            'class_name',class_name,
            'field_count',field_count,
            'mapped_field_area_acres',round((field_area_m2/4046.8564224)::numeric,2)
          )
          order by field_area_m2 desc,latest_crop_code
        )
        from crop_stats
      ),'[]'::jsonb),
      'boundary_quality',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'boundary_status',boundary_status,
            'field_count',field_count,
            'average_source_confidence',
              case when avg_source_confidence is null then null else round(avg_source_confidence::numeric,4) end,
            'minimum_source_confidence',
              case when min_source_confidence is null then null else round(min_source_confidence::numeric,4) end,
            'maximum_source_confidence',
              case when max_source_confidence is null then null else round(max_source_confidence::numeric,4) end
          )
          order by boundary_status
        )
        from boundary_quality
      ),'[]'::jsonb),
      'interpretation_boundary',
        'Mapped field polygons, their boundaries, and CDL classes are landscape/resource-context evidence only. They do not establish current crop availability, forage quality, harvest state, access permission, deer use, or movement.',
      'geometry_semantics',
        'Field area and edge geometry are clipped to the current same-side 3 km barrier-aware landscape domain. Edge length is mapped field-boundary length inside the domain, not a claim that every boundary is a biologically meaningful cover edge.',
      'retrieved_at',now()
    ),
    (select geom from area_union),
    (select geom from edge_union)
  into v_context,v_field_area,v_field_edges;

  v_identity := farm_watch.farm_watch_resource_edge_identity_v1(v_property_id);
  if v_identity is null then
    return jsonb_build_object('status','unavailable','reason','resource-edge identity unavailable');
  end if;

  insert into farm_watch.property_resource_edge_context_v1(
    property_id,status,context,field_area_geometry,field_edge_geometry,
    boundary_sha256,source_signature,source_signature_sha256,
    algorithm_version,output_schema_version,identity_sha256,
    retrieved_at,last_error,updated_at
  ) values (
    v_property_id,'available',v_context,v_field_area,v_field_edges,
    v_identity->>'boundary_sha256',v_identity->>'source_signature',v_identity->>'source_signature_sha256',
    v_identity->>'algorithm_version',v_identity->>'output_schema_version',v_identity->>'identity_sha256',
    now(),null,now()
  )
  on conflict(property_id) do update set
    status=excluded.status,
    context=excluded.context,
    field_area_geometry=excluded.field_area_geometry,
    field_edge_geometry=excluded.field_edge_geometry,
    boundary_sha256=excluded.boundary_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    last_error=null,
    updated_at=now();

  return jsonb_build_object(
    'status','available',
    'identity_sha256',v_identity->>'identity_sha256',
    'field_area_geometry_available',v_field_area is not null and not extensions.st_isempty(v_field_area),
    'field_edge_geometry_available',v_field_edges is not null and not extensions.st_isempty(v_field_edges),
    'retrieved_at',now()
  );
end;
$$;

revoke all on function farm_watch.farm_watch_refresh_resource_edge_context_v1_internal(text) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_refresh_resource_edge_context_v1_internal(text) to service_role;

create or replace function farm_watch.farm_watch_get_resource_edge_context_v1_internal(
  p_slug text,
  p_include_geometry boolean default false
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
  with property as (
    select id
    from farm_watch.properties
    where slug=p_slug and status='active'
    limit 1
  ),
  expected as (
    select farm_watch.farm_watch_resource_edge_identity_v1(id) identity
    from property
  ),
  cached as (
    select c.*
    from farm_watch.property_resource_edge_context_v1 c
    join property p on p.id=c.property_id
  )
  select case
    when not exists(select 1 from property) then
      jsonb_build_object('status','missing','context',null)
    when not exists(select 1 from cached) then
      jsonb_build_object('status','missing','context',null)
    when (select identity_sha256 from cached) is distinct from (select identity->>'identity_sha256' from expected) then
      jsonb_build_object(
        'status','stale',
        'context',null,
        'invalidation_reason','identity_mismatch',
        'stored_identity_sha256',(select identity_sha256 from cached),
        'expected_identity_sha256',(select identity->>'identity_sha256' from expected)
      )
    else
      jsonb_strip_nulls(jsonb_build_object(
        'status',(select status from cached),
        'context',(select context from cached),
        'field_area_geojson',case
          when p_include_geometry and (select field_area_geometry from cached) is not null
          then extensions.st_asgeojson((select field_area_geometry from cached),6)::jsonb
          else null end,
        'field_edge_geojson',case
          when p_include_geometry and (select field_edge_geometry from cached) is not null
          then extensions.st_asgeojson((select field_edge_geometry from cached),6)::jsonb
          else null end,
        'identity',jsonb_build_object(
          'boundary_sha256',(select boundary_sha256 from cached),
          'source_signature_sha256',(select source_signature_sha256 from cached),
          'algorithm_version',(select algorithm_version from cached),
          'output_schema_version',(select output_schema_version from cached),
          'identity_sha256',(select identity_sha256 from cached)
        ),
        'retrieved_at',(select retrieved_at from cached),
        'last_error',(select last_error from cached)
      ))
  end;
$$;

revoke all on function farm_watch.farm_watch_get_resource_edge_context_v1_internal(text,boolean) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_resource_edge_context_v1_internal(text,boolean) to service_role;

comment on function farm_watch.farm_watch_get_resource_edge_context_v1_internal(text,boolean) is
'Returns neutral barrier-aware mapped agricultural field-area and field-edge context. No deer-use, food-availability, or access inference is implied.';
