-- Scout by Cadastory
-- Federal task-order capture graph delivery-semantics fix v1.
-- Exact asset delivery evidence is valid asset context, but does not prove contractor operational presence.

create or replace view research.v_federal_task_order_capture_graph_v1 as
with base as (
  select
    i.*,
    x.canonical_name as crosswalk_asset_name,
    x.target_namespace as crosswalk_target_namespace,
    x.nid_id,
    x.nid_asset_name,
    x.nid_state_name,
    x.nid_county_name,
    x.crosswalk_status,
    x.gap_kind,
    x.facility_context_nid_id,
    x.facility_context_name,
    case
      when nullif(i.awarding_office_name,'') is not null then
        'federal_buyer:' || md5(concat_ws('|',coalesce(i.awarding_agency_name,''),coalesce(i.awarding_subtier_name,''),coalesce(i.awarding_office_name,'')))
      else
        'federal_buyer:' || md5(concat_ws('|',coalesce(i.awarding_agency_name,''),coalesce(i.awarding_subtier_name,'')))
    end as buyer_node_key,
    'federal_vehicle:' || i.parent_piid as vehicle_node_key,
    'federal_task_order:' || i.child_generated_award_id as task_order_node_key,
    case when nullif(i.recipient_uei,'') is not null then 'uei:' || i.recipient_uei else 'recipient_name:' || md5(coalesce(i.recipient_name,'')) end as contractor_node_key,
    case
      when x.crosswalk_status='authoritative_nid_name_resolved' and x.nid_id is not null then 'nid:' || x.nid_id
      when i.alias_key is not null then 'federal_asset_alias:' || i.alias_key
      else null
    end as asset_node_key,
    coalesce(i.pop_potential_end_date,i.pop_end_date) as effective_end_date
  from research.v_regional_federal_child_order_intelligence i
  left join research.v_federal_infrastructure_asset_crosswalk_status x
    on x.alias_key=i.alias_key
  where i.order_class='substantive_order'
), classified as (
  select
    b.*,
    case
      when b.pop_start_date is not null and b.pop_start_date > current_date then 'upcoming'
      when b.effective_end_date is not null and b.effective_end_date < current_date then 'historical'
      when coalesce(b.pop_start_date,b.date_signed,current_date) <= current_date
       and (b.effective_end_date is null or b.effective_end_date >= current_date) then 'active'
      else 'unknown'
    end as performance_window_status,
    case when b.effective_end_date is not null then b.effective_end_date-current_date else null end as days_to_effective_end,
    (b.crosswalk_status='authoritative_nid_name_resolved' and b.nid_id is not null and b.alias_key is not null) as exact_asset_link_authorized
  from base b
)
select
  c.parent_piid,c.parent_generated_award_id,c.vehicle_node_key,c.child_piid,c.child_generated_award_id,c.task_order_node_key,
  c.buyer_node_key,c.awarding_agency_name,c.awarding_subtier_name,c.awarding_office_name,
  c.contractor_node_key,c.recipient_name as contractor_name,c.recipient_uei as contractor_uei,
  c.total_obligation,c.date_signed,c.pop_start_date,c.pop_end_date,c.pop_potential_end_date,c.effective_end_date,
  c.performance_window_status,c.days_to_effective_end,c.place_state_code,c.place_state_name,c.place_city_name,c.place_county_name,c.place_zip5,
  c.naics_code,c.naics_description,c.psc_code,c.psc_description,c.description,c.alias_key,
  coalesce(c.nid_asset_name,c.crosswalk_asset_name,c.named_asset) as asset_name,
  coalesce(c.crosswalk_target_namespace,c.named_asset_target_namespace) as asset_namespace,
  c.asset_node_key,c.nid_id,c.crosswalk_status,c.gap_kind,c.facility_context_nid_id,c.facility_context_name,
  c.fabrication_or_delivery_scope,c.surface_work_explicit,c.prep_or_cleaning_explicit,c.surface_work_class,c.cleaning_relationship_semantics,
  c.exact_asset_link_authorized,
  (c.exact_asset_link_authorized and not c.fabrication_or_delivery_scope) as contractor_operational_presence_authorized,
  (c.exact_asset_link_authorized and not c.fabrication_or_delivery_scope and c.performance_window_status='active') as active_task_scope_incumbency_authorized,
  case
    when c.exact_asset_link_authorized and c.fabrication_or_delivery_scope then 'verified_delivery_to_asset'
    when c.exact_asset_link_authorized then 'verified_task_scope_at_asset'
    when c.alias_key is not null then 'named_asset_quarantined_pending_authoritative_crosswalk'
    when c.formal_pop_supported_area then 'supported_place_task_scope_asset_unresolved'
    else 'asset_unresolved'
  end as contractor_asset_relationship_type,
  case
    when c.exact_asset_link_authorized and c.fabrication_or_delivery_scope and c.performance_window_status='active' then 'active_verified_delivery_context_only'
    when c.exact_asset_link_authorized and c.fabrication_or_delivery_scope and c.performance_window_status='upcoming' then 'upcoming_verified_delivery_context_only'
    when c.exact_asset_link_authorized and c.fabrication_or_delivery_scope and c.performance_window_status='historical' then 'historical_verified_delivery_context_only'
    when c.exact_asset_link_authorized and not c.fabrication_or_delivery_scope and c.performance_window_status='active' and c.days_to_effective_end between 0 and 180 then 'active_scope_ending_within_180_days'
    when c.exact_asset_link_authorized and not c.fabrication_or_delivery_scope and c.performance_window_status='active' then 'active_verified_task_scope'
    when c.exact_asset_link_authorized and not c.fabrication_or_delivery_scope and c.performance_window_status='upcoming' then 'upcoming_verified_task_scope'
    when c.exact_asset_link_authorized and not c.fabrication_or_delivery_scope and c.performance_window_status='historical' then 'historical_verified_task_scope'
    when c.alias_key is not null then 'quarantined_named_asset_evidence'
    else 'regional_task_order_context_only'
  end as capture_signal_status,
  c.alias_evidence_basis,
  false as broad_contractor_facility_propagation_authorized
from classified c;

comment on view research.v_federal_task_order_capture_graph_v1 is
  'One row per substantive verified federal child order, modeled as buyer -> vehicle -> task order -> contractor -> asset context. Exact asset delivery evidence is distinct from operational-presence evidence; broad contractor-to-facility propagation remains forbidden.';
