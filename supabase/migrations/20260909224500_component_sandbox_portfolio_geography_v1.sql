create or replace function public.scout_get_component_sandbox_map_targets_v2_internal(
  p_property_limit integer default 12,
  p_group_limit integer default 10
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','public','extensions'
as $function$
with params as (
  select greatest(1, least(coalesce(p_group_limit,10),20))::integer as requested_group_limit
),
base_doc as (
  select public.scout_get_component_sandbox_map_targets_internal(
    p_property_limit,
    (select requested_group_limit from params)
  ) as doc
),
base_rows as (
  select value as item
  from base_doc
  cross join lateral jsonb_array_elements(coalesce(doc,'[]'::jsonb))
),
base_properties as (
  select item
  from base_rows
  where item->>'kind' = 'property'
),
base_groups as (
  select
    split_part(item->>'key',':',1) as portfolio_archetype,
    item || jsonb_build_object(
      'portfolio_archetype',split_part(item->>'key',':',1),
      'portfolio_geography_status','resolved_assets',
      'resolved_member_count',jsonb_array_length(coalesce(item->'members','[]'::jsonb)),
      'reported_member_count_minimum',null,
      'roster_status',null,
      'territories','[]'::jsonb
    ) as item
  from base_rows
  where item->>'kind' = 'group'
),
fm_accounts as (
  select
    a.organization_id,
    a.account_name,
    a.reported_client_location_count_minimum,
    a.service_areas,
    coalesce(
      (
        select evidence_item->>'status'
        from jsonb_array_elements(coalesce(a.evidence,'[]'::jsonb)) evidence_item
        where evidence_item->>'kind' = 'roster_research'
        limit 1
      ),
      case when a.roster_research_complete then 'roster_research_complete' else null end
    ) as roster_status
  from scout.v_facilities_management_intermediary_accounts a
),
fm_county_territories as (
  select
    a.organization_id,
    c.area_key as territory_key,
    coalesce(nullif(c.place_name,''),c.county_name || ' County') as territory_label,
    'administrative_area'::text as territory_kind,
    case when c.geometry is not null then 'resolved'::text else 'unresolved'::text end as boundary_status,
    c.coverage_basis,
    c.state_code,
    c.confidence,
    c.source_url,
    c.source_authority,
    c.geometry,
    case
      when c.geometry is null then null::jsonb
      else st_asgeojson(st_simplifypreservetopology(c.geometry,0.00035),6)::jsonb
    end as geometry_json
  from fm_accounts a
  join scout.v_facilities_management_account_counties c
    on c.organization_id = a.organization_id
),
fm_named_territories as (
  select
    a.organization_id,
    coalesce(nullif(area->>'area_key',''),'named:' || md5(area::text)) as territory_key,
    coalesce(nullif(area->>'place_name',''),'Documented service market') as territory_label,
    'named_market'::text as territory_kind,
    'unresolved'::text as boundary_status,
    'documented_named_market'::text as coverage_basis,
    nullif(area->>'state_code','') as state_code,
    case when nullif(area->>'confidence','') ~ '^[0-9]+(\.[0-9]+)?$' then (area->>'confidence')::numeric else null::numeric end as confidence,
    nullif(area->>'source_url','') as source_url,
    'documented service-area evidence'::text as source_authority,
    null::geometry as geometry,
    null::jsonb as geometry_json
  from fm_accounts a
  cross join lateral jsonb_array_elements(coalesce(a.service_areas,'[]'::jsonb)) area
  where coalesce(area->>'area_kind','') <> 'county'
),
fm_all_territories as (
  select * from fm_county_territories
  union all
  select * from fm_named_territories
),
fm_territory_agg as (
  select
    a.organization_id,
    a.account_name,
    a.reported_client_location_count_minimum,
    a.roster_status,
    count(*) filter (where t.geometry is not null)::integer as resolved_territory_count,
    min(st_xmin(box2d(t.geometry))) filter (where t.geometry is not null)::double precision as min_lon,
    min(st_ymin(box2d(t.geometry))) filter (where t.geometry is not null)::double precision as min_lat,
    max(st_xmax(box2d(t.geometry))) filter (where t.geometry is not null)::double precision as max_lon,
    max(st_ymax(box2d(t.geometry))) filter (where t.geometry is not null)::double precision as max_lat,
    jsonb_agg(
      jsonb_build_object(
        'key',t.territory_key,
        'label',t.territory_label,
        'territory_kind',t.territory_kind,
        'boundary_status',t.boundary_status,
        'coverage_basis',t.coverage_basis,
        'state',t.state_code,
        'confidence',t.confidence,
        'source_url',t.source_url,
        'source_authority',t.source_authority,
        'geometry',t.geometry_json
      ) order by
        case t.boundary_status when 'resolved' then 0 else 1 end,
        t.territory_kind,
        t.territory_key
    ) as territories
  from fm_accounts a
  join fm_all_territories t on t.organization_id = a.organization_id
  group by a.organization_id,a.account_name,a.reported_client_location_count_minimum,a.roster_status
),
fm_groups as (
  select
    'facilities_management'::text as portfolio_archetype,
    jsonb_build_object(
      'kind','group',
      'key','facilities_management:' || organization_id::text,
      'label',account_name,
      'scope_count',0,
      'min_lon',min_lon,
      'min_lat',min_lat,
      'max_lon',max_lon,
      'max_lat',max_lat,
      'members','[]'::jsonb,
      'portfolio_archetype','facilities_management',
      'portfolio_geography_status','documented_territory',
      'resolved_member_count',0,
      'reported_member_count_minimum',reported_client_location_count_minimum,
      'roster_status',roster_status,
      'territories',territories
    ) as item
  from fm_territory_agg
  where resolved_territory_count > 0
),
all_groups as (
  select * from base_groups
  union all
  select * from fm_groups
),
ranked_groups as (
  select
    portfolio_archetype,
    item,
    row_number() over(
      partition by portfolio_archetype
      order by
        coalesce((item->>'resolved_member_count')::integer,0) desc,
        item->>'label',
        item->>'key'
    ) as archetype_rank,
    case portfolio_archetype
      when 'property_management' then 1
      when 'hotel_management' then 2
      when 'dealership_group' then 3
      when 'industrial_logistics' then 4
      when 'water_utility' then 5
      when 'facilities_management' then 6
      else 99
    end as archetype_order
  from all_groups
),
sampled_groups as (
  select item
  from ranked_groups
  order by archetype_rank,archetype_order,item->>'key'
  limit (select requested_group_limit from params)
),
combined as (
  select item from base_properties
  union all
  select item from sampled_groups
)
select coalesce(
  jsonb_agg(item order by item->>'kind',item->>'key'),
  '[]'::jsonb
)
from combined;
$function$;

revoke all on function public.scout_get_component_sandbox_map_targets_v2_internal(integer,integer) from public;
revoke all on function public.scout_get_component_sandbox_map_targets_v2_internal(integer,integer) from anon;
revoke all on function public.scout_get_component_sandbox_map_targets_v2_internal(integer,integer) from authenticated;
grant execute on function public.scout_get_component_sandbox_map_targets_v2_internal(integer,integer) to service_role;
