-- Scout by Cadastory
-- Federal task-order capture graph v1 -- consolidated final state.
-- Production migrations:
--   20260910055718_federal_task_order_capture_graph_v1.sql
--   20260910055855_federal_task_order_capture_graph_delivery_semantics_fix_v1.sql
--
-- Purpose: model verified federal child awards as
-- buyer -> vehicle -> task order -> contractor -> exact asset / quarantined asset context.
-- This layer is deliberately scope-limited. It does not assert ownership, management,
-- or broad contractor incumbency across an agency or facility portfolio.

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
    case
      when nullif(i.recipient_uei,'') is not null then 'uei:' || i.recipient_uei
      else 'recipient_name:' || md5(coalesce(i.recipient_name,''))
    end as contractor_node_key,
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
  c.parent_piid,
  c.parent_generated_award_id,
  c.vehicle_node_key,
  c.child_piid,
  c.child_generated_award_id,
  c.task_order_node_key,
  c.buyer_node_key,
  c.awarding_agency_name,
  c.awarding_subtier_name,
  c.awarding_office_name,
  c.contractor_node_key,
  c.recipient_name as contractor_name,
  c.recipient_uei as contractor_uei,
  c.total_obligation,
  c.date_signed,
  c.pop_start_date,
  c.pop_end_date,
  c.pop_potential_end_date,
  c.effective_end_date,
  c.performance_window_status,
  c.days_to_effective_end,
  c.place_state_code,
  c.place_state_name,
  c.place_city_name,
  c.place_county_name,
  c.place_zip5,
  c.naics_code,
  c.naics_description,
  c.psc_code,
  c.psc_description,
  c.description,
  c.alias_key,
  coalesce(c.nid_asset_name,c.crosswalk_asset_name,c.named_asset) as asset_name,
  coalesce(c.crosswalk_target_namespace,c.named_asset_target_namespace) as asset_namespace,
  c.asset_node_key,
  c.nid_id,
  c.crosswalk_status,
  c.gap_kind,
  c.facility_context_nid_id,
  c.facility_context_name,
  c.fabrication_or_delivery_scope,
  c.surface_work_explicit,
  c.prep_or_cleaning_explicit,
  c.surface_work_class,
  c.cleaning_relationship_semantics,
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

create or replace view research.v_federal_task_order_graph_edges_v1 as
select
  g.child_generated_award_id,
  g.date_signed as observed_on,
  g.buyer_node_key as source_node_key,
  'federal_buyer'::text as source_node_type,
  'issued_task_order_under_vehicle'::text as edge_type,
  g.vehicle_node_key as target_node_key,
  'federal_contract_vehicle'::text as target_node_type,
  'verified'::text as edge_status,
  true as edge_authorized,
  jsonb_build_object('parent_piid',g.parent_piid,'awarding_office_name',g.awarding_office_name) as evidence
from research.v_federal_task_order_capture_graph_v1 g
union all
select
  g.child_generated_award_id,g.date_signed,
  g.vehicle_node_key,'federal_contract_vehicle','contains_task_order',
  g.task_order_node_key,'federal_task_order','verified',true,
  jsonb_build_object('parent_piid',g.parent_piid,'child_piid',g.child_piid)
from research.v_federal_task_order_capture_graph_v1 g
union all
select
  g.child_generated_award_id,g.date_signed,
  g.task_order_node_key,'federal_task_order','awarded_to_contractor',
  g.contractor_node_key,'contractor','verified',true,
  jsonb_build_object('recipient_name',g.contractor_name,'recipient_uei',g.contractor_uei,'total_obligation',g.total_obligation)
from research.v_federal_task_order_capture_graph_v1 g
union all
select
  g.child_generated_award_id,g.date_signed,
  g.task_order_node_key,'federal_task_order',g.contractor_asset_relationship_type,
  g.asset_node_key,
  case when g.exact_asset_link_authorized then 'authoritative_asset' else 'asset_alias' end,
  case when g.exact_asset_link_authorized then 'verified' else 'quarantined' end,
  g.exact_asset_link_authorized,
  jsonb_build_object(
    'asset_name',g.asset_name,
    'asset_namespace',g.asset_namespace,
    'nid_id',g.nid_id,
    'crosswalk_status',g.crosswalk_status,
    'fabrication_or_delivery_scope',g.fabrication_or_delivery_scope,
    'performance_window_status',g.performance_window_status,
    'scope_limited',true
  )
from research.v_federal_task_order_capture_graph_v1 g
where g.asset_node_key is not null;

comment on view research.v_federal_task_order_graph_edges_v1 is
  'Typed evidence edges for the federal child-order graph. Quarantined asset aliases remain visible internally but edge_authorized=false until exact authoritative resolution.';

create or replace view research.v_federal_task_order_capture_quarantine_v1 as
select *
from research.v_federal_task_order_capture_graph_v1
where not exact_asset_link_authorized
order by
  case when alias_key is not null then 0 else 1 end,
  total_obligation desc nulls last,
  date_signed desc nulls last;

comment on view research.v_federal_task_order_capture_quarantine_v1 is
  'Fail-closed queue for substantive task orders that cannot yet support an exact contractor-to-asset task-scope edge.';

create or replace view scout.v_federal_contract_asset_context_v1 as
select
  g.asset_node_key as asset_key,
  g.nid_id,
  g.asset_name,
  g.asset_namespace,
  g.place_state_code as state_code,
  g.place_county_name as county_name,
  g.buyer_node_key,
  g.awarding_agency_name,
  g.awarding_subtier_name,
  g.awarding_office_name,
  g.vehicle_node_key,
  g.parent_piid,
  g.task_order_node_key,
  g.child_piid,
  g.child_generated_award_id,
  g.contractor_node_key,
  g.contractor_name,
  g.contractor_uei,
  g.total_obligation,
  g.date_signed,
  g.pop_start_date,
  g.effective_end_date,
  g.performance_window_status,
  g.days_to_effective_end,
  g.surface_work_explicit,
  g.prep_or_cleaning_explicit,
  g.contractor_asset_relationship_type,
  g.contractor_operational_presence_authorized,
  g.active_task_scope_incumbency_authorized,
  g.capture_signal_status,
  jsonb_build_object(
    'scope_limited',true,
    'source','USAspending child award',
    'child_generated_award_id',g.child_generated_award_id,
    'parent_piid',g.parent_piid,
    'description',g.description,
    'crosswalk_status',g.crosswalk_status,
    'broad_relationship_propagation_authorized',false
  ) as evidence_summary
from research.v_federal_task_order_capture_graph_v1 g
where g.exact_asset_link_authorized;

comment on view scout.v_federal_contract_asset_context_v1 is
  'Internal production-facing handoff for exact authoritative federal asset/task-order context. Every contractor relationship is order/scope limited; this view does not assert ownership, management, or broad portfolio incumbency.';

create or replace view scout.v_federal_contract_portfolio_context_v1 as
select
  buyer_node_key,
  max(awarding_agency_name) as awarding_agency_name,
  max(awarding_subtier_name) as awarding_subtier_name,
  max(awarding_office_name) as awarding_office_name,
  vehicle_node_key,
  parent_piid,
  contractor_node_key,
  max(contractor_name) as contractor_name,
  max(contractor_uei) as contractor_uei,
  count(*)::integer as verified_task_orders,
  count(distinct asset_key)::integer as verified_asset_count,
  count(*) filter (where performance_window_status='active')::integer as active_task_orders,
  count(*) filter (where performance_window_status='upcoming')::integer as upcoming_task_orders,
  count(*) filter (where performance_window_status='historical')::integer as historical_task_orders,
  sum(total_obligation) as observed_total_obligation,
  min(date_signed) as first_observed_award_date,
  max(date_signed) as latest_observed_award_date,
  min(effective_end_date) filter (where performance_window_status='active') as next_active_scope_end_date,
  jsonb_agg(jsonb_build_object(
    'asset_key',asset_key,
    'asset_name',asset_name,
    'child_piid',child_piid,
    'performance_window_status',performance_window_status,
    'effective_end_date',effective_end_date,
    'relationship_type',contractor_asset_relationship_type,
    'scope_incumbency_authorized',active_task_scope_incumbency_authorized
  ) order by date_signed desc nulls last) as task_asset_scopes,
  false as broad_portfolio_incumbency_authorized
from scout.v_federal_contract_asset_context_v1
where contractor_operational_presence_authorized
group by buyer_node_key,vehicle_node_key,parent_piid,contractor_node_key;

comment on view scout.v_federal_contract_portfolio_context_v1 is
  'Aggregated scope-limited federal buyer/vehicle/contractor/asset history for capture analysis. It may describe repeated verified task scopes but must not be read as broad contractor incumbency across an agency portfolio.';

create or replace view scout.v_federal_contract_opportunity_handoff_v1 as
select
  a.*,
  case
    when a.performance_window_status='active' and a.days_to_effective_end between 0 and 180 and a.contractor_operational_presence_authorized then 'recompete_or_follow_on_watch'
    when a.performance_window_status='active' and a.contractor_operational_presence_authorized then 'active_scope_watch'
    when a.performance_window_status='upcoming' then 'mobilization_or_adjacent_scope_watch'
    when a.performance_window_status='historical' then 'cadence_and_precedent_evidence'
    else 'context_only'
  end as opportunity_handoff_kind,
  case
    when a.asset_namespace='federal_navigation_asset' and a.nid_id is not null then 'authoritative_asset_key_ready'
    else 'canonical_asset_bridge_required'
  end as spine_join_status,
  false as auto_insert_into_opportunity_spine
from scout.v_federal_contract_asset_context_v1 a;

comment on view scout.v_federal_contract_opportunity_handoff_v1 is
  'Conservative opportunity-spine handoff. Produces capture context and timing signals but intentionally does not auto-insert task orders as Scout opportunities or infer service demand beyond the verified order scope.';

revoke all on research.v_federal_task_order_capture_graph_v1 from anon,authenticated;
revoke all on research.v_federal_task_order_graph_edges_v1 from anon,authenticated;
revoke all on research.v_federal_task_order_capture_quarantine_v1 from anon,authenticated;
revoke all on scout.v_federal_contract_asset_context_v1 from anon,authenticated;
revoke all on scout.v_federal_contract_portfolio_context_v1 from anon,authenticated;
revoke all on scout.v_federal_contract_opportunity_handoff_v1 from anon,authenticated;
