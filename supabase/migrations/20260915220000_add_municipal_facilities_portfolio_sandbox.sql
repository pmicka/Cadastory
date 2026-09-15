
insert into ingest.sources(slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,authority_level,status,homepage_url,commercial_use_status,notes)
values('louisville-metro-government-locations','Louisville Metro Government Locations','Louisville Metro Government','official_municipal_facility_directory','Louisville/Jefferson County, KY','bounded_structured_capture','on_change','primary_local_government','active_reference','https://louisvilleky.gov/government/metro311/metro-government-locations','unknown','Bounded structured snapshot for the owner-approved municipal-facilities sandbox exemplar. Government-location listing is not an ownership or maintenance-responsibility registry.')
on conflict(slug) do update set name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,status=excluded.status,homepage_url=excluded.homepage_url,notes=excluded.notes,updated_at=now();

with src as(select id from ingest.sources where slug='louisville-metro-government-locations'), members(source_native_id,facility_name,address_display,geometry_match_address) as(values
('city-hall','City Hall','601 West Jefferson Street','601 W JEFFERSON STREET'),
('metrosafe-building','MetroSafe Building','410 S. 5th Street','410 S 5TH STREET'),
('police-headquarters','Police Headquarters','601 W. Chestnut Street','601 W CHESTNUT STREET'),
('records-management-archives','Records Management & Archives','635 Industry Road','635 INDUSTRY ROAD'),
('health-wellness','Health & Wellness','400 East Gray Street','400 E GRAY STREET'),
('judicial-center','Judicial Center','700 West Jefferson Street','700 W JEFFERSON STREET')
)
insert into ingest.raw_records(source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,parser_version,parse_status,provisional_entity_type,within_pilot_radius,raw_payload)
select src.id,m.source_native_id,'https://louisvilleky.gov/government/metro311/metro-government-locations',statement_timestamp(),statement_timestamp(),md5(m.source_native_id||'|municipal-facilities-v1'),'municipal-facilities-sandbox-v1','parsed','municipal_civic_facility_listing',true,jsonb_build_object('facility_name',m.facility_name,'address',m.address_display,'geometry_match_address',m.geometry_match_address,'city','Louisville','state_code','KY','listing_scope','official_government_location','claim_limit','Directory listing does not prove ownership, envelope-maintenance responsibility, access, or procurement authority.')
from src cross join members m
on conflict(source_id,source_native_id,content_hash) do nothing;

create or replace function public.scout_get_component_sandbox_municipal_portfolio_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
with org as(
  select o.id
  from core.organizations o
  where o.canonical_name='Louisville Metro Government' and o.organization_type='municipal_government' and o.status='active'
  order by o.updated_at desc,o.id
  limit 1
), listed as(
  select distinct on(r.source_native_id)
    r.source_native_id as member_id,r.raw_payload->>'facility_name' as facility_name,r.raw_payload->>'address' as address_display,r.raw_payload->>'geometry_match_address' as geometry_match_address,r.retrieved_at
  from ingest.raw_records r join ingest.sources s on s.id=r.source_id
  where s.slug='louisville-metro-government-locations' and r.provisional_entity_type='municipal_civic_facility_listing'
  order by r.source_native_id,r.retrieved_at desc,r.id
), geometry_match as(
  select distinct on(l.member_id)
    l.member_id,l.facility_name,l.address_display,l.retrieved_at as facility_observed_at,g.id as geometry_record_id,g.retrieved_at as geometry_observed_at,(g.raw_payload->'properties'->>'LONGITUDE')::double precision as lon,(g.raw_payload->'properties'->>'LATITUDE')::double precision as lat
  from listed l
  join ingest.sources gs on gs.slug='fema-usa-structures-current'
  join ingest.raw_records g on g.source_id=gs.id and upper(trim(g.raw_payload->'properties'->>'PROP_ADDR'))=upper(trim(l.geometry_match_address)) and upper(trim(g.raw_payload->'properties'->>'PROP_CITY'))='LOUISVILLE'
  where nullif(g.raw_payload->'properties'->>'LONGITUDE','') is not null and nullif(g.raw_payload->'properties'->>'LATITUDE','') is not null
  order by l.member_id,g.retrieved_at desc,g.id
), signal as(
  select s.candidate_key,s.signal_strength,s.confidence,s.why_now,s.procurement_status,s.buyer_contact_status,s.observed_at,s.refreshed_at
  from scout.opportunity_search_spine s join org o on s.buyer_organization_id=o.id join geometry_match gm on gm.member_id='judicial-center' and s.source_id=gm.geometry_record_id
  where s.source_kind='exterior_cleaning' and s.signal_kind='cleaning_need_proxy' and upper(trim(s.target_name))='700 W JEFFERSON STREET' and s.signal_strength='medium' and s.procurement_status='procurement_route_available' and s.buyer_contact_status='durable_route_available'
  order by s.refreshed_at desc nulls last,s.observed_at desc,s.candidate_key
  limit 1
)
select jsonb_build_object(
  'contract_version','municipal_facilities_portfolio_map_v1','account_name','Louisville Metro Government','organization_id',(select id from org),'scope','documented_civic_location_subset','facility_source_slug','louisville-metro-government-locations','geometry_source_slug','fema-usa-structures-current','signal_source_kind','scout_opportunity_search_spine','relationship','official_government_location_listing','generated_at',statement_timestamp(),'facility_observed_at',max(gm.facility_observed_at),'geometry_observed_at',max(gm.geometry_observed_at),'signal_observed_at',(select coalesce(refreshed_at,observed_at) from signal),
  'members',jsonb_agg(jsonb_build_object('id',gm.member_id,'name',gm.facility_name,'address',gm.address_display,'city','Louisville','state_code','KY','point',jsonb_build_object('type','Point','coordinates',jsonb_build_array(gm.lon,gm.lat)),'geometry_source_slug','fema-usa-structures-current','geometry_match_method','exact_address','signal_state',case when gm.member_id='judicial-center' then 'site_signal_present' else 'no_site_signal_linked' end,'observed_at',greatest(gm.facility_observed_at,gm.geometry_observed_at)) order by gm.facility_name,gm.member_id),
  'member_signals',(select jsonb_build_array(jsonb_build_object('id',signal.candidate_key,'kind','member_cleaning_need_proxy','member_id','judicial-center','member_name','Judicial Center','signal_strength',signal.signal_strength,'confidence',signal.confidence,'why_now',signal.why_now,'procurement_status',signal.procurement_status,'buyer_contact_status',signal.buyer_contact_status,'site_attribution','judicial_center_only','observed_at',signal.observed_at,'refreshed_at',signal.refreshed_at)) from signal)
)
from geometry_match gm
having count(*)=6 and (select count(*) from org)=1 and (select count(*) from signal)=1;
$function$;
revoke all on function public.scout_get_component_sandbox_municipal_portfolio_v1_internal() from public,anon,authenticated;
grant execute on function public.scout_get_component_sandbox_municipal_portfolio_v1_internal() to service_role;
