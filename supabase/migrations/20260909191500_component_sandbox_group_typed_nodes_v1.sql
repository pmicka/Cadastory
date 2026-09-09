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
group_member_rows as (
  select
    a.account_key as target_key,
    a.display_name as group_label,
    f.organization_facility_id::text as member_key,
    coalesce(nullif(f.site_name,''), nullif(f.site_address_text,''), 'Portfolio property') as member_label,
    coalesce(nullif(f.portfolio_property_type,''), nullif(f.primary_occupancy,''), nullif(f.facility_class,''), 'Residential property') as property_type_label,
    case
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(assisted|memory care|senior living|senior)' then 'senior_living'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(multifamily|apartment|apartments|loft|lofts|flats)' then 'multifamily'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(hotel|inn|lodge)' then 'hotel'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(office)' then 'office'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(retail|shopping|marketplace)' then 'retail'
      when lower(coalesce(f.portfolio_property_type,'') || ' ' || coalesce(f.site_name,'')) ~ '(industrial|warehouse|distribution)' then 'industrial'
      else 'residential'
    end as property_type,
    f.city,
    f.state,
    st_x(f.location::geometry)::double precision as lon,
    st_y(f.location::geometry)::double precision as lat
  from research.v_demo_exemplar_account_queue_v1 a
  join scout.v_property_management_facilities f on f.organization_id = a.organization_id
  where a.exemplar_class = 'property_management'
    and a.organization_id is not null
    and f.location is not null
    and f.relationship_status = 'current'
    and f.portfolio_asset_status in ('operating','lease_up','under_construction','development')
    and st_dwithin(
      f.location,
      st_setsrid(st_makepoint(-85.7585,38.2527),4326)::geography,
      160934.4
    )
),
group_pool as (
  select
    'group'::text as target_kind,
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
        'property_type',property_type,
        'property_type_label',property_type_label,
        'city',city,
        'state',state,
        'lon',lon,
        'lat',lat
      ) order by state,city,member_label,member_key
    ) as members
  from group_member_rows
  group by target_key,group_label
  having count(*) >= 2
),
group_sample as (
  select * from group_pool
  order by target_key
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
