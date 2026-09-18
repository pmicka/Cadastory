create table if not exists farm_watch.property_soil_profiles_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  mukey text not null,
  dominant_component_key text,
  dominant_component_name text,
  dominant_component_pct numeric,
  runoff_class text,
  tax_order text,
  tax_subgroup text,
  geomorphic_description text,
  restrictive_depth_cm numeric,
  restriction_kind text,
  restriction_hardness text,
  parent_material_group text,
  parent_material_kind text,
  parent_material_origins jsonb not null default '[]'::jsonb,
  flooding_classes jsonb not null default '[]'::jsonb,
  ponding_classes jsonb not null default '[]'::jsonb,
  horizon_profile jsonb not null default '[]'::jsonb,
  source_payload jsonb not null default '{}'::jsonb,
  attribute_status text not null default 'unknown',
  http_status integer,
  last_error text,
  source_retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(property_id,mukey)
);

alter table farm_watch.property_soil_profiles_v1 enable row level security;
revoke all on farm_watch.property_soil_profiles_v1 from public,anon,authenticated;
grant select,insert,update,delete on farm_watch.property_soil_profiles_v1 to service_role;

create or replace function farm_watch.farm_watch_refresh_soil_profiles_v1_internal(p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_property_id uuid;
  v_unit record;
  v_query text;
  v_status integer;
  v_content text;
  v_json jsonb;
  v_table jsonb;
  v_first jsonb;
  v_parent_origins jsonb;
  v_flooding jsonb;
  v_ponding jsonb;
  v_horizons jsonb;
  v_refreshed integer := 0;
  v_failures integer := 0;
  v_seen text[] := array[]::text[];
  v_started timestamptz := clock_timestamp();
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select id into v_property_id
  from farm_watch.properties
  where slug=p_slug and status='active'
  limit 1;

  if v_property_id is null then
    return jsonb_build_object('status','unavailable','reason','property unavailable');
  end if;

  for v_unit in
    select mukey
    from farm_watch.property_soil_map_units_v1
    where property_id=v_property_id
    order by parcel_acres desc,mukey
  loop
    v_seen := array_append(v_seen,v_unit.mukey);
    begin
      v_query := format($sda$
SELECT
  m.mukey,m.muname,
  c.cokey,c.compname,c.comppct_r,c.slope_r,c.drainagecl,c.hydgrp,c.hydricrating,
  c.runoff,c.taxorder,c.taxsubgrp,c.geomdesc,
  r.resdept_r,r.reskind,r.reshard,
  pmg.pmgroupname,pm.pmkind,pm.pmorigin,
  h.chkey,h.hzname,h.hzdept_r,h.hzdepb_r,h.awc_r,h.ksat_r,h.claytotal_r,h.sandtotal_r,h.silttotal_r,
  tg.texture,tg.texdesc,
  cm.monthseq,cm.month,cm.flodfreqcl,cm.pondfreqcl
FROM mapunit m
CROSS APPLY (
  SELECT TOP 1 c0.*
  FROM component c0
  WHERE c0.mukey=m.mukey
  ORDER BY ISNULL(c0.comppct_r,0) DESC,c0.cokey
) c
OUTER APPLY (
  SELECT TOP 1 cr.resdept_r,cr.reskind,cr.reshard
  FROM corestrictions cr
  WHERE cr.cokey=c.cokey
  ORDER BY cr.resdept_r
) r
LEFT JOIN copmgrp pmg ON pmg.cokey=c.cokey
LEFT JOIN copm pm ON pm.copmgrpkey=pmg.copmgrpkey
LEFT JOIN chorizon h ON h.cokey=c.cokey
LEFT JOIN chtexturegrp tg ON tg.chkey=h.chkey AND tg.rvindicator='Yes'
LEFT JOIN comonth cm ON cm.cokey=c.cokey
WHERE m.mukey=%L
ORDER BY h.hzdept_r,pm.copmkey,cm.monthseq
$sda$,v_unit.mukey);

      select r.status,r.content into v_status,v_content
      from extensions.http_post(
        'https://SDMDataAccess.sc.egov.usda.gov/Tabular/post.rest'::varchar,
        jsonb_build_object('query',v_query,'format','JSON+COLUMNNAME')
      ) r;

      v_json := null;
      v_table := null;
      v_first := null;

      if v_status=200 then
        begin
          v_json := v_content::jsonb;
          v_table := v_json->'Table';
          if v_table is not null and jsonb_array_length(v_table)>=2 then
            v_first := v_table->1;
          end if;
        exception when others then
          v_first := null;
        end;
      end if;

      if v_first is null then
        insert into farm_watch.property_soil_profiles_v1(
          property_id,mukey,attribute_status,http_status,last_error,source_payload,source_retrieved_at,updated_at
        ) values (
          v_property_id,v_unit.mukey,'unavailable',v_status,
          left(coalesce(v_content,'NRCS Soil Data Access returned no usable profile'),1000),
          jsonb_build_object('query_version','farm_watch_ssurgo_deep_profile_v1','response',coalesce(v_json,'{}'::jsonb)),
          now(),now()
        )
        on conflict(property_id,mukey) do update set
          attribute_status=excluded.attribute_status,http_status=excluded.http_status,last_error=excluded.last_error,
          source_payload=excluded.source_payload,source_retrieved_at=excluded.source_retrieved_at,updated_at=now();
        v_failures := v_failures+1;
        continue;
      end if;

      select coalesce(jsonb_agg(to_jsonb(x.val) order by x.val),'[]'::jsonb)
      into v_parent_origins
      from (
        select distinct nullif(e.value->>18,'') val
        from jsonb_array_elements(v_table) with ordinality e(value,ord)
        where e.ord>1 and nullif(e.value->>18,'') is not null
      ) x;

      select coalesce(jsonb_agg(to_jsonb(x.val) order by x.val),'[]'::jsonb)
      into v_flooding
      from (
        select distinct nullif(e.value->>32,'') val
        from jsonb_array_elements(v_table) with ordinality e(value,ord)
        where e.ord>1 and nullif(e.value->>32,'') is not null
      ) x;

      select coalesce(jsonb_agg(to_jsonb(x.val) order by x.val),'[]'::jsonb)
      into v_ponding
      from (
        select distinct nullif(e.value->>33,'') val
        from jsonb_array_elements(v_table) with ordinality e(value,ord)
        where e.ord>1 and nullif(e.value->>33,'') is not null
      ) x;

      select coalesce(jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'chkey',x.chkey,
          'name',x.hzname,
          'top_cm',x.hzdept,
          'bottom_cm',x.hzdepb,
          'awc_cm_per_cm',x.awc,
          'ksat_um_per_s',x.ksat,
          'clay_pct',x.clay,
          'sand_pct',x.sand,
          'silt_pct',x.silt,
          'texture_code',x.texture,
          'texture',x.texdesc
        )) order by x.hzdept nulls last,x.chkey
      ),'[]'::jsonb)
      into v_horizons
      from (
        select distinct
          nullif(e.value->>19,'') chkey,
          nullif(e.value->>20,'') hzname,
          nullif(e.value->>21,'')::numeric hzdept,
          nullif(e.value->>22,'')::numeric hzdepb,
          nullif(e.value->>23,'')::numeric awc,
          nullif(e.value->>24,'')::numeric ksat,
          nullif(e.value->>25,'')::numeric clay,
          nullif(e.value->>26,'')::numeric sand,
          nullif(e.value->>27,'')::numeric silt,
          nullif(e.value->>28,'') texture,
          nullif(e.value->>29,'') texdesc
        from jsonb_array_elements(v_table) with ordinality e(value,ord)
        where e.ord>1 and nullif(e.value->>19,'') is not null
      ) x;

      insert into farm_watch.property_soil_profiles_v1(
        property_id,mukey,
        dominant_component_key,dominant_component_name,dominant_component_pct,
        runoff_class,tax_order,tax_subgroup,geomorphic_description,
        restrictive_depth_cm,restriction_kind,restriction_hardness,
        parent_material_group,parent_material_kind,parent_material_origins,
        flooding_classes,ponding_classes,horizon_profile,
        source_payload,attribute_status,http_status,last_error,source_retrieved_at,updated_at
      ) values (
        v_property_id,v_unit.mukey,
        nullif(v_first->>2,''),nullif(v_first->>3,''),nullif(v_first->>4,'')::numeric,
        nullif(v_first->>9,''),nullif(v_first->>10,''),nullif(v_first->>11,''),nullif(v_first->>12,''),
        nullif(v_first->>13,'')::numeric,nullif(v_first->>14,''),nullif(v_first->>15,''),
        nullif(v_first->>16,''),nullif(v_first->>17,''),coalesce(v_parent_origins,'[]'::jsonb),
        coalesce(v_flooding,'[]'::jsonb),coalesce(v_ponding,'[]'::jsonb),coalesce(v_horizons,'[]'::jsonb),
        jsonb_build_object(
          'query_version','farm_watch_ssurgo_deep_profile_v1',
          'response',coalesce(v_json,'{}'::jsonb)
        ),
        'available',v_status,null,now(),now()
      )
      on conflict(property_id,mukey) do update set
        dominant_component_key=excluded.dominant_component_key,
        dominant_component_name=excluded.dominant_component_name,
        dominant_component_pct=excluded.dominant_component_pct,
        runoff_class=excluded.runoff_class,
        tax_order=excluded.tax_order,
        tax_subgroup=excluded.tax_subgroup,
        geomorphic_description=excluded.geomorphic_description,
        restrictive_depth_cm=excluded.restrictive_depth_cm,
        restriction_kind=excluded.restriction_kind,
        restriction_hardness=excluded.restriction_hardness,
        parent_material_group=excluded.parent_material_group,
        parent_material_kind=excluded.parent_material_kind,
        parent_material_origins=excluded.parent_material_origins,
        flooding_classes=excluded.flooding_classes,
        ponding_classes=excluded.ponding_classes,
        horizon_profile=excluded.horizon_profile,
        source_payload=excluded.source_payload,
        attribute_status=excluded.attribute_status,
        http_status=excluded.http_status,
        last_error=excluded.last_error,
        source_retrieved_at=excluded.source_retrieved_at,
        updated_at=now();

      v_refreshed := v_refreshed+1;
    exception when others then
      v_failures := v_failures+1;
      insert into farm_watch.property_soil_profiles_v1(
        property_id,mukey,attribute_status,http_status,last_error,source_payload,source_retrieved_at,updated_at
      ) values (
        v_property_id,v_unit.mukey,'unavailable',v_status,left(sqlerrm,1000),
        jsonb_build_object('query_version','farm_watch_ssurgo_deep_profile_v1'),
        now(),now()
      )
      on conflict(property_id,mukey) do update set
        attribute_status=excluded.attribute_status,http_status=excluded.http_status,last_error=excluded.last_error,
        source_payload=excluded.source_payload,source_retrieved_at=excluded.source_retrieved_at,updated_at=now();
    end;
  end loop;

  if coalesce(array_length(v_seen,1),0)>0 then
    delete from farm_watch.property_soil_profiles_v1
    where property_id=v_property_id and not (mukey=any(v_seen));
  end if;

  return jsonb_build_object(
    'status',case when v_refreshed>0 and v_failures=0 then 'available' when v_refreshed>0 then 'partial' else 'unavailable' end,
    'profiles_refreshed',v_refreshed,
    'failures',v_failures,
    'started_at',v_started,
    'finished_at',clock_timestamp()
  );
end;
$$;

create or replace function public.farm_watch_refresh_soil_profiles_v1_internal(p_slug text)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $$
  select farm_watch.farm_watch_refresh_soil_profiles_v1_internal(p_slug);
$$;

revoke all on function farm_watch.farm_watch_refresh_soil_profiles_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_refresh_soil_profiles_v1_internal(text) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_refresh_soil_profiles_v1_internal(text) to service_role;
grant execute on function public.farm_watch_refresh_soil_profiles_v1_internal(text) to service_role;

create or replace function public.farm_watch_get_soils_v1_internal(p_slug text)
returns jsonb
language sql
stable security definer
set search_path=pg_catalog
as $$
  with property as (
    select p.id from farm_watch.properties p
    where p.slug=p_slug and p.status='active'
    limit 1
  ), units as (
    select s.*,d.runoff_class,d.tax_order,d.tax_subgroup,d.geomorphic_description,
           d.restrictive_depth_cm,d.restriction_kind,d.restriction_hardness,
           d.parent_material_group,d.parent_material_kind,d.parent_material_origins,
           d.flooding_classes,d.ponding_classes,d.horizon_profile,
           d.attribute_status as deep_attribute_status,
           d.source_retrieved_at as deep_retrieved_at
    from farm_watch.property_soil_map_units_v1 s
    join property p on p.id=s.property_id
    left join farm_watch.property_soil_profiles_v1 d
      on d.property_id=s.property_id and d.mukey=s.mukey
  ), summary as (
    select count(*)::integer as map_unit_count,
           count(*) filter(where deep_attribute_status='available')::integer as deep_profile_count,
           coalesce(sum(parcel_acres),0) as covered_acres,
           coalesce(sum(parcel_pct),0) as covered_pct,
           max(source_retrieved_at) as retrieved_at,
           max(deep_retrieved_at) as deep_retrieved_at
    from units
  )
  select jsonb_build_object(
    'status',case when summary.map_unit_count>0 then 'available' else 'unavailable' end,
    'feature_collection',jsonb_build_object(
      'type','FeatureCollection',
      'features',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'type','Feature',
            'id',u.mukey,
            'geometry',extensions.st_asgeojson(u.clipped_geometry,6)::jsonb,
            'properties',jsonb_strip_nulls(jsonb_build_object(
              'mukey',u.mukey,'musym',u.musym,'muname',u.muname,'mukind',u.mukind,
              'farmland_class',u.farmland_class,'non_irrigated_capability',u.non_irrigated_capability,
              'dominant_component_name',u.dominant_component_name,
              'dominant_component_pct',u.dominant_component_pct,
              'representative_slope_pct',u.representative_slope_pct,
              'drainage_class',u.drainage_class,'hydrologic_group',u.hydrologic_group,
              'hydric_rating',u.hydric_rating,
              'available_water_storage_0_100_mm',u.available_water_storage_0_100_mm,
              'runoff_class',u.runoff_class,
              'tax_order',u.tax_order,'tax_subgroup',u.tax_subgroup,
              'geomorphic_description',u.geomorphic_description,
              'restrictive_depth_cm',u.restrictive_depth_cm,
              'restriction_kind',u.restriction_kind,
              'restriction_hardness',u.restriction_hardness,
              'parent_material_group',u.parent_material_group,
              'parent_material_kind',u.parent_material_kind,
              'parent_material_origins',u.parent_material_origins,
              'flooding_classes',u.flooding_classes,
              'ponding_classes',u.ponding_classes,
              'horizon_profile',u.horizon_profile,
              'deep_attribute_status',u.deep_attribute_status,
              'parcel_acres',round(u.parcel_acres,2),'parcel_pct',round(u.parcel_pct,1),
              'attribute_status',u.attribute_status
            ))
          ) order by u.parcel_acres desc,u.mukey
        ) from units u
      ),'[]'::jsonb)
    ),
    'summary',jsonb_build_object(
      'map_unit_count',summary.map_unit_count,
      'deep_profile_count',summary.deep_profile_count,
      'covered_acres',round(summary.covered_acres,2),
      'covered_pct',round(summary.covered_pct,1),
      'retrieved_at',summary.retrieved_at,
      'deep_retrieved_at',summary.deep_retrieved_at,
      'source','USDA NRCS SSURGO / Soil Data Access'
    )
  )
  from summary;
$$;

revoke all on function public.farm_watch_get_soils_v1_internal(text) from public,anon,authenticated;
grant execute on function public.farm_watch_get_soils_v1_internal(text) to service_role;

update ingest.sources
set notes='Farm Watch clips current NRCS SSURGO map-unit polygons to an authenticated private property boundary. Geometry is soil-survey reference mapping, not a legal parcel survey or site-specific engineering investigation.',
    updated_at=now()
where slug='usda-nrcs-geodata-cg-soils-ssurgo';

update ingest.sources
set notes='Farm Watch uses NRCS Soil Data Access for map-unit aggregates plus dominant-component runoff, taxonomy, geomorphic setting, restrictive layer, parent material, monthly flooding/ponding classes, and horizon-level texture/Ksat/AWC/particle-size attributes. These are soil-survey interpretations, not parcel soil borings, laboratory tests, or engineering determinations.',
    updated_at=now()
where slug='usda-nrcs-soil-data-access-ssurgo';
