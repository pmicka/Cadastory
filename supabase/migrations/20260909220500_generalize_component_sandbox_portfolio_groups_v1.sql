create or replace function public.scout_get_component_sandbox_map_targets_internal(p_property_limit integer default 12, p_group_limit integer default 8)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','public','extensions'
as $function$
with property_seed as (
  select distinct on ((d.context->>'building_source_record_id')::uuid)
    d.exemplar_key as target_key,
    d.display_name as label,
    d.priority,
    (d.context->>'building_source_record_id')::uuid as building_source_record_id
  from research.demo_exemplar_priorities_v1 d
  where d.active = true
    and d.subject_type = 'premium_target'
    and d.context ? 'building_source_record_id'
    and nullif(d.context->>'building_source_record_id','') is not null
  order by (d.context->>'building_source_record_id')::uuid, d.priority asc, d.exemplar_key
),
property_pool as (
  select
    'property'::text as target_kind,
    s.target_key,
    s.label,
    1::integer as scope_count,
    st_xmin(box2d(coalesce(b.geometry, b.location::geometry)))::double precision as min_lon,
    st_ymin(box2d(coalesce(b.geometry, b.location::geometry)))::double precision as min_lat,
    st_xmax(box2d(coalesce(b.geometry, b.location::geometry)))::double precision as max_lon,
    st_ymax(box2d(coalesce(b.geometry, b.location::geometry)))::double precision as max_lat,
    '[]'::jsonb as members
  from property_seed s
  join decisioning.building_candidates b on b.source_record_id = s.building_source_record_id
  where coalesce(b.geometry, b.location::geometry) is not null
),
property_sample as (
  select * from property_pool
  order by target_key
  limit greatest(1, least(coalesce(p_property_limit, 12), 30))
),
property_management_members as (
  select
    'property_management'::text as portfolio_archetype,
    'property_management:' || f.organization_id::text as target_key,
    f.management_company_name as group_label,
    f.organization_facility_id::text as member_key,
    coalesce(nullif(f.site_name,''), nullif(f.site_address_text,''), 'Portfolio property') as member_label,
    coalesce(nullif(f.portfolio_property_type,''), nullif(f.primary_occupancy,''), nullif(f.facility_class,''), 'Residential property') as member_type_label,
    case
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(assisted|memory care|senior living|senior)' then 'senior_living'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(multifamily|apartment|apartments|loft|lofts|flats)' then 'multifamily'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(hotel|inn|lodge)' then 'hotel'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(office)' then 'office'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(retail|shopping|marketplace)' then 'retail'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(industrial|warehouse|distribution)' then 'industrial'
      else 'residential'
    end as member_type,
    f.city,
    f.state,
    st_x(f.location::geometry)::double precision as lon,
    st_y(f.location::geometry)::double precision as lat
  from scout.v_property_management_facilities f
  where f.location is not null
    and f.relationship_status = 'current'
    and f.portfolio_asset_status in ('operating','lease_up','under_construction','development')
    and st_dwithin(
      f.location,
      st_setsrid(st_makepoint(-85.7585,38.2527),4326)::geography,
      160934.4
    )
),
resolved_portfolio_sites as (
  select
    p.organization_id,
    p.account_name,
    p.portfolio_archetype,
    p.organization_facility_id,
    p.source_record_id,
    p.site_name,
    p.site_address_text,
    p.city,
    p.state_code,
    p.facility_class,
    p.portfolio_unit_type,
    avg(st_x(br.location::geometry))::double precision as lon,
    avg(st_y(br.location::geometry))::double precision as lat
  from scout.v_portfolio_account_facilities p
  join scout.property_building_links l
    on l.property_source_record_id = p.source_record_id
   and l.match_status = 'resolved'
  join ingest.raw_records br
    on br.id = l.building_source_record_id
   and br.location is not null
  where p.portfolio_asset_status in ('operating','lease_up','under_construction','development')
  group by
    p.organization_id,p.account_name,p.portfolio_archetype,p.organization_facility_id,p.source_record_id,
    p.site_name,p.site_address_text,p.city,p.state_code,p.facility_class,p.portfolio_unit_type
),
general_portfolio_members as (
  select
    r.portfolio_archetype,
    r.portfolio_archetype || ':' || r.organization_id::text as target_key,
    r.account_name as group_label,
    r.organization_facility_id::text as member_key,
    coalesce(nullif(r.site_name,''), nullif(r.site_address_text,''), 'Portfolio facility') as member_label,
    coalesce(nullif(r.portfolio_unit_type,''), nullif(r.facility_class,''), r.portfolio_archetype) as member_type_label,
    case r.portfolio_archetype
      when 'hotel_management' then 'hotel'
      when 'dealership_group' then 'dealership'
      when 'industrial_logistics' then 'industrial'
      else 'other'
    end as member_type,
    r.city,
    r.state_code as state,
    r.lon,
    r.lat
  from resolved_portfolio_sites r
  where st_dwithin(
    st_setsrid(st_makepoint(r.lon,r.lat),4326)::geography,
    st_setsrid(st_makepoint(-85.7585,38.2527),4326)::geography,
    160934.4
  )
),
water_utility_members as (
  select distinct
    'water_utility'::text as portfolio_archetype,
    'water_utility:' || o.id::text as target_key,
    o.canonical_name as group_label,
    r.id::text as member_key,
    coalesce(nullif(r.source_native_id,''), 'Water tank') as member_label,
    coalesce(nullif(r.raw_payload #>> '{attributes,TYPE}',''), 'Water tank') as member_type_label,
    case upper(coalesce(r.raw_payload #>> '{attributes,TYPE}',''))
      when 'ELEVATED' then 'water_tank_elevated'
      when 'HYDROPILAR' then 'water_tank_elevated'
      when 'PEDESPHERE' then 'water_tank_elevated'
      when 'STANDPIPE' then 'water_tank_standpipe'
      when 'GROUND STORAGE' then 'water_tank_ground_storage'
      else 'water_tank_other'
    end as member_type,
    null::text as city,
    'KY'::text as state,
    st_x(r.location::geometry)::double precision as lon,
    st_y(r.location::geometry)::double precision as lat
  from core.organizations o
  cross join lateral jsonb_array_elements_text(coalesce(o.attributes->'pwsids','[]'::jsonb)) as pwsid
  join ingest.raw_records r
    on (r.raw_payload #>> '{attributes,PWSID}') = pwsid
  join ingest.sources s
    on s.id = r.source_id
   and s.slug = 'ky-kia-water-tanks'
  where o.status = 'active'
    and o.organization_type = 'water_utility'
    and r.location is not null
    and st_dwithin(
      r.location,
      st_setsrid(st_makepoint(-85.7585,38.2527),4326)::geography,
      160934.4
    )
),
group_member_rows as (
  select * from property_management_members
  union all
  select * from general_portfolio_members
  union all
  select * from water_utility_members
),
group_pool as (
  select
    'group'::text as target_kind,
    portfolio_archetype,
    target_key,
    group_label as label,
    count(*)::integer as scope_count,
    min(lon)::double precision as min_lon,
    min(lat)::double precision as min_lat,
    max(lon)::double precision as max_lon,
    max(lat)::double precision as max_lat,
    jsonb_agg(
      jsonb_build_object(
        'key',member_key,
        'label',member_label,
        'property_type',member_type,
        'property_type_label',member_type_label,
        'city',city,
        'state',state,
        'lon',lon,
        'lat',lat
      ) order by state,city,member_label,member_key
    ) as members
  from group_member_rows
  group by portfolio_archetype,target_key,group_label
  having count(*) >= 2
),
ranked_groups as (
  select
    g.*,
    row_number() over(partition by portfolio_archetype order by scope_count desc,target_key) as archetype_rank,
    case portfolio_archetype
      when 'property_management' then 1
      when 'hotel_management' then 2
      when 'dealership_group' then 3
      when 'industrial_logistics' then 4
      when 'water_utility' then 5
      else 99
    end as archetype_order
  from group_pool g
),
group_sample as (
  select target_kind,target_key,label,scope_count,min_lon,min_lat,max_lon,max_lat,members
  from ranked_groups
  order by archetype_rank,archetype_order,target_key
  limit greatest(1, least(coalesce(p_group_limit,8),20))
),
combined as (
  select * from property_sample
  union all
  select * from group_sample
)
select coalesce(
  jsonb_agg(
    jsonb_build_object(
      'kind',target_kind,
      'key',target_key,
      'label',label,
      'scope_count',scope_count,
      'min_lon',min_lon,
      'min_lat',min_lat,
      'max_lon',max_lon,
      'max_lat',max_lat,
      'members',members
    ) order by target_kind,target_key
  ),
  '[]'::jsonb
)
from combined;
$function$;
