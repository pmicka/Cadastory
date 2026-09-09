create or replace function public.internal_get_livestock_farm_geocode_queue(p_limit integer default 100)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
with livestock as (
  select i.candidate_id
  from agriculture.farm_livestock_inventory_v1 i
  where i.state_code='KY'
    and i.needs_location_enrichment
), ranked as (
  select
    e.candidate_id,
    e.id as evidence_id,
    e.observed_name as name,
    e.observed_address as address,
    upper(coalesce(nullif(e.attributes->>'state_code',''),nullif(c.attributes->>'state_code',''))) as state_code,
    e.confidence as evidence_confidence,
    row_number() over (
      partition by e.candidate_id
      order by e.confidence desc nulls last,e.observed_at desc nulls last,e.created_at desc
    ) as rn
  from agriculture.farm_entity_evidence e
  join livestock lv on lv.candidate_id=e.candidate_id
  join agriculture.farm_entity_candidates c on c.id=e.candidate_id
  left join agriculture.farm_directory_locations l on l.candidate_id=e.candidate_id
  where e.supports_agricultural_operation is true
    and coalesce(e.attributes->>'source_slug','')='kentucky-kda-ag-business-directory'
    and coalesce((e.attributes->>'directory_self_declared')::boolean,false) is true
    and nullif(btrim(e.observed_address),'') is not null
    and e.observed_address !~* '^\s*(p\.?\s*o\.?\s*box|box\s+[0-9]|cpo\s+[0-9]|r\.?\s*r\.?\s*\d|rural\s+route\b|route\s+\d+\s+box\b)'
    and (
      l.candidate_id is null
      or l.observed_address is distinct from e.observed_address
      or l.geocode_status='error'
      or (l.geocode_status='no_match' and l.updated_at < now()-interval '180 days')
      or (l.geocode_status='matched' and (l.county_name is null or upper(l.county_name) like '% CCD %'))
    )
), q as (
  select candidate_id,evidence_id,name,address,state_code,evidence_confidence
  from ranked
  where rn=1
  order by evidence_confidence desc nulls last,name
  limit greatest(1,least(coalesce(p_limit,100),500))
)
select coalesce(jsonb_agg(jsonb_build_object(
  'candidate_id',candidate_id,
  'evidence_id',evidence_id,
  'name',name,
  'address',address,
  'state_code',state_code,
  'evidence_confidence',evidence_confidence
) order by evidence_confidence desc nulls last,name),'[]'::jsonb)
from q;
$function$;

revoke all on function public.internal_get_livestock_farm_geocode_queue(integer) from public;
grant execute on function public.internal_get_livestock_farm_geocode_queue(integer) to service_role;

comment on function public.internal_get_livestock_farm_geocode_queue(integer) is
'Livestock-only Kentucky KDA farm geocode queue. Excludes obvious non-street mailbox/rural-route formats and recent no-match records; intended for bounded U.S. Census geocoding.';
