
create or replace function public.scout_get_component_sandbox_telecom_change_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
with event as(
  select e.id,e.registration_number,e.observed_at,e.event_type,e.importance
  from telecom.asr_change_events e
  where e.registration_number='1333510' and e.event_type='new_registration'
  order by e.observed_at desc,e.id
  limit 1
), structure as(
  select s.*
  from telecom.asr_structures s join event e on e.registration_number=s.registration_number
  where s.canonical_source='fcc_asr' and s.within_pilot=true
  order by s.last_seen_at desc nulls last,s.first_seen_at desc nulls last
  limit 1
), signal as(
  select o.*
  from scout.opportunity_search_spine o join event e on o.source_id=e.id
  where o.source_kind='telecom_change' and o.signal_kind='new_registration' and o.signal_strength='high'
  order by o.refreshed_at desc nulls last,o.observed_at desc
  limit 1
), buyer as(
  select org.id,org.canonical_name,org.organization_type
  from core.organizations org join signal sig on sig.buyer_organization_id=org.id
  where org.status='active' and org.organization_type='tower_owner'
  limit 1
)
select jsonb_build_object(
 'contract_version','telecom_change_single_site_map_v1','opportunity_type','telecom_change','candidate_key',sig.candidate_key,'event_id',e.id,'registration_number',e.registration_number,'event_type',e.event_type,'signal_strength',sig.signal_strength,'confidence',sig.confidence,'observed_at',e.observed_at,
 'site_point',jsonb_build_object('lon',extensions.st_x(s.location::extensions.geometry),'lat',extensions.st_y(s.location::extensions.geometry),'source','fcc_asr_registration','source_authority','Federal Communications Commission','canonical_source',s.canonical_source),
 'asset',jsonb_build_object('owner_name',s.owner_name,'owner_frn',s.owner_frn,'status_code',s.status_code,'structure_type_code',s.structure_type,'application_purpose_code',s.application_purpose,'structure_height_m',s.structure_height_m,'overall_height_agl_m',s.overall_height_agl_m,'date_constructed',s.date_constructed,'date_entered',s.date_entered,'last_action_date',s.last_action_date,'structure_address',s.structure_address,'city',s.structure_city,'state_code',s.structure_state,'zip',s.structure_zip,'faa_study_number',s.faa_study_number),
 'buyer',jsonb_build_object('organization_id',b.id,'canonical_name',b.canonical_name,'organization_type',b.organization_type,'resolution_state','resolved_scout_organization','resolution_basis','opportunity_buyer_identity','contact_route_available',sig.buyer_contact_status='durable_route_available','procurement_route_available',sig.procurement_status='procurement_route_available'),
 'guardrail','This is a bounded FCC Antenna Structure Registration change signal. FCC ASR registration 1333510 and its coordinates and structure attributes identify a registered antenna-structure record; Scout does not infer inspection need, maintenance due, commissioning scope, procurement, buyer intent, vendor eligibility, site access, climb authorization, or work availability. The Towers, LLC buyer resolution is separate Scout organization linkage; a durable contact route is not a documented procurement route.'
)
from event e cross join structure s cross join signal sig cross join buyer b
where s.owner_name='The Towers, LLC' and s.owner_frn='0033815929' and s.status_code='C' and s.structure_type='LTOWER' and s.application_purpose='NT' and s.date_constructed='09/04/2026' and s.date_entered='09/09/2026' and s.last_action_date='09/09/2026' and s.structure_address='S. Becker Road / IN-5286' and s.structure_city='Leavenworth' and s.structure_state='IN' and s.structure_zip='47137' and s.faa_study_number='2026-AGL-2286-OE' and sig.buyer_contact_status='durable_route_available' and sig.procurement_status='durable_contact_available';
$function$;
revoke all on function public.scout_get_component_sandbox_telecom_change_v1_internal() from public,anon,authenticated;
grant execute on function public.scout_get_component_sandbox_telecom_change_v1_internal() to service_role;
