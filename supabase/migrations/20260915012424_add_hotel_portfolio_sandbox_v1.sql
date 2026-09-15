-- Add the bounded Commonwealth Hotels management-portfolio sandbox projection.
-- The roster is first-party management evidence; map points come only from resolved building crosswalks.
create or replace function public.scout_get_component_sandbox_hotel_portfolio_v1_internal()
returns jsonb language sql stable security definer set search_path='pg_catalog'
as $function$
with org as (
  select s.organization_id,s.account_name
  from scout.v_portfolio_account_summary s
  where s.account_name='Commonwealth Hotels' and s.organization_type='hotel_management_company' and s.portfolio_archetype='hotel_management'
  limit 1
), facilities as (
  select f.organization_facility_id,f.organization_id,f.account_name,f.source_record_id,f.site_name,f.site_address_text,f.city,f.state_code,f.brands,f.within_pilot_radius,f.last_observed_at
  from scout.v_portfolio_account_facilities f join org o on o.organization_id=f.organization_id
  where f.source_slug='commonwealth-hotels-managed-portfolio' and f.relationship_type='manages' and f.relationship_status='current' and f.portfolio_asset_status='operating' and f.portfolio_unit_type='hotel' and f.within_pilot_radius=true
), resolved as (
  select f.source_record_id,count(distinct p.building_source_record_id)::integer resolved_building_count,min(p.confidence)::numeric link_confidence,extensions.st_centroid(extensions.st_collect(br.location::extensions.geometry)) site_point
  from facilities f join scout.property_building_links p on p.property_source_record_id=f.source_record_id and p.match_status='resolved'
  join ingest.raw_records br on br.id=p.building_source_record_id and br.location is not null
  group by f.source_record_id
), account_research as (
  select q.any_contact_route_available,q.operations_route_available,q.procurement_route_available,q.operating_asset_vendor_route_proven,q.current_need_scan_complete
  from scout.v_portfolio_account_research_queue q join org o on o.organization_id=q.organization_id limit 1
)
select jsonb_build_object('contract_version','hotel_management_portfolio_map_v1','account_name',min(f.account_name),'organization_id',min(f.organization_id::text),'scope','documented_operating_roster','source_slug','commonwealth-hotels-managed-portfolio','relationship','manages','target_kind','site_member','map_semantics','documented_operating_hotel_portfolio','evidence_boundary','first-party hotel-management roster plus resolved building crosswalks','generated_at',statement_timestamp(),'observed_at',max(f.last_observed_at),'contact_route_available',max(ar.any_contact_route_available::int)::boolean,'operations_route_available',max(ar.operations_route_available::int)::boolean,'procurement_route_available',max(ar.procurement_route_available::int)::boolean,'vendor_route_proven',max(ar.operating_asset_vendor_route_proven::int)::boolean,'current_need_scan_complete',max(ar.current_need_scan_complete::int)::boolean,'members',jsonb_agg(jsonb_build_object('id',f.organization_facility_id::text,'name',f.site_name,'address',f.site_address_text,'city',f.city,'state_code',f.state_code,'brands',coalesce(f.brands,'[]'::jsonb),'point',case when r.site_point is null then jsonb_build_object('type','unresolved') else extensions.st_asgeojson(r.site_point)::jsonb end,'resolution_state',case when coalesce(r.resolved_building_count,0)=0 then 'unresolved' when r.resolved_building_count=1 then 'single_building_resolved' else 'multi_building_resolved' end,'resolved_building_count',coalesce(r.resolved_building_count,0),'link_confidence',r.link_confidence,'within_pilot_radius',f.within_pilot_radius,'observed_at',f.last_observed_at) order by f.site_name,f.organization_facility_id))
from facilities f left join resolved r on r.source_record_id=f.source_record_id cross join account_research ar having count(*) between 1 and 100;
$function$;
comment on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() is 'Owner sandbox-only Commonwealth Hotels operating management roster. Map points are derived only from resolved property-to-building crosswalks; unresolved roster members remain unmapped.';
revoke all on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() from public;
revoke all on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() from anon;
revoke all on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() from authenticated;
grant execute on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() to service_role;
