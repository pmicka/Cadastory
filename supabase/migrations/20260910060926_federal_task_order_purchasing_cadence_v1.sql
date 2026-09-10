-- Scout by Cadastory
-- Federal task-order purchasing cadence and contractor win-pattern intelligence v1.
-- Internal/research-only. This layer learns from authoritative award history but does not
-- create opportunities, assert future awards, or broaden contractor-to-asset relationships.

create or replace view research.v_federal_task_order_scope_facts_v1 as
with classified as (
  select
    f.*,
    lower(concat_ws(' ',coalesce(f.description,''),coalesce(f.psc_description,''),coalesce(f.naics_description,''))) as scope_text,
    lower(coalesce(f.description,'')) ~ '(minimum[[:space:]]+(contract[[:space:]]+)?guarantee|guaranteed[[:space:]]+amount([[:space:]]+task[[:space:]]+order)?|guarantee(d)?[[:space:]]+amount[[:space:]]+for[[:space:]]+(base|contract)[[:space:]]+period)' as is_administrative_guarantee
  from procurement.federal_task_orders f
), scoped as (
  select
    c.*,
    case
      when c.is_administrative_guarantee then 'administrative_guarantee'
      when c.scope_text ~ '(fabricat|manufactur|assemble).*(deliver|shipment)|deliver.*(fabricat|manufactur|assemble)|emergency bulkhead fabrication|gate fabrication|valve.*deliver|chain assemblies fabrication' then 'fabrication_delivery'
      when c.scope_text ~ '(paint|coating|surface prep|surface preparation|abrasive blast|sandblast|waterproof)' then 'surface_preservation'
      when c.scope_text ~ '(bridge|roadway|asphalt|resurfac|pavement)' then 'bridge_roadway_rehab'
      when c.scope_text ~ '(levee|flood control|bluff stabilization|toe drain)' then 'levee_flood_control'
      when c.scope_text ~ '(lock|dam|spillway|weir|miter gate|tainter gate|culvert valve|gate cable|gate chain)' then 'water_control_structure_repair'
      when coalesce(c.psc_code,'')='Z1DA'
        or c.scope_text ~ '(medical treatment facilit|hospital|infirmar|facility management support|operations and maintenance|facilities maintenance)' then 'facilities_operations_maintenance'
      when c.scope_text ~ '(building|facility repair|facility renovation|repair or alteration of miscellaneous buildings)' then 'facility_repair_improvement'
      when c.scope_text ~ '(construction|repair|rehab|replacement|stabilization|maintenance)' then 'general_physical_construction_repair'
      else 'other_physical_fm'
    end as scope_class
  from classified c
)
select
  s.id as task_order_id,
  s.source_record_id,
  s.parent_generated_award_id,
  s.parent_piid,
  s.child_generated_award_id,
  s.child_piid,
  s.description,
  s.recipient_name,
  s.recipient_uei,
  s.total_obligation,
  s.date_signed,
  s.pop_start_date,
  s.pop_end_date,
  s.pop_potential_end_date,
  s.awarding_agency_name,
  s.awarding_subtier_name,
  s.awarding_office_name,
  s.funding_agency_name,
  s.funding_subtier_name,
  s.funding_office_name,
  s.place_country_code,
  s.place_state_code,
  s.place_state_name,
  s.place_city_name,
  s.place_county_name,
  s.place_zip5,
  s.naics_code,
  s.naics_description,
  s.psc_code,
  s.psc_description,
  s.is_administrative_guarantee,
  s.scope_class,
  case
    when s.date_signed is null then null
    when extract(month from s.date_signed) between 10 and 12 then 1
    when extract(month from s.date_signed) between 1 and 3 then 2
    when extract(month from s.date_signed) between 4 and 6 then 3
    else 4
  end as federal_fiscal_quarter,
  case when s.place_state_code in ('KY','IN','OH') then true else false end as in_supported_state,
  s.first_observed_at,
  s.last_observed_at
from scoped s;

comment on view research.v_federal_task_order_scope_facts_v1 is
  'Normalized federal task-order learning facts. Administrative guarantee/bookkeeping orders are explicitly separated from substantive purchasing behavior; scope classes are deterministic heuristics for aggregation, not claims about complete contract scope.';

create or replace view research.v_federal_buyer_scope_cadence_v1 as
with substantive as (
  select *
  from research.v_federal_task_order_scope_facts_v1
  where not is_administrative_guarantee
    and date_signed is not null
), award_dates as (
  select distinct awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class,date_signed
  from substantive
), intervals as (
  select
    d.*,
    d.date_signed - lag(d.date_signed) over (
      partition by d.awarding_agency_name,d.awarding_subtier_name,d.awarding_office_name,d.scope_class
      order by d.date_signed
    ) as interval_days
  from award_dates d
), cadence as (
  select
    awarding_agency_name,
    awarding_subtier_name,
    awarding_office_name,
    scope_class,
    count(*)::integer as distinct_award_events,
    min(date_signed) as first_award_date,
    max(date_signed) as latest_award_date,
    (max(date_signed)-min(date_signed))::integer as observed_history_days,
    percentile_cont(0.25) within group (order by interval_days) filter (where interval_days is not null) as p25_interval_days,
    percentile_cont(0.50) within group (order by interval_days) filter (where interval_days is not null) as median_interval_days,
    percentile_cont(0.75) within group (order by interval_days) filter (where interval_days is not null) as p75_interval_days
  from intervals
  group by awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class
), totals as (
  select
    awarding_agency_name,
    awarding_subtier_name,
    awarding_office_name,
    scope_class,
    count(*)::integer as task_order_count,
    count(distinct parent_piid)::integer as parent_vehicle_count,
    count(distinct recipient_uei) filter (where recipient_uei is not null)::integer as contractor_count,
    sum(total_obligation) as total_obligation,
    count(*) filter (where place_state_code in ('KY','IN','OH'))::integer as supported_state_order_count
  from substantive
  group by awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class
), fq as (
  select
    awarding_agency_name,
    awarding_subtier_name,
    awarding_office_name,
    scope_class,
    federal_fiscal_quarter,
    count(*)::integer as n,
    row_number() over (
      partition by awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class
      order by count(*) desc,federal_fiscal_quarter
    ) as rn
  from substantive
  group by awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class,federal_fiscal_quarter
)
select
  c.awarding_agency_name,
  c.awarding_subtier_name,
  c.awarding_office_name,
  c.scope_class,
  t.task_order_count,
  c.distinct_award_events,
  t.parent_vehicle_count,
  t.contractor_count,
  t.total_obligation,
  t.supported_state_order_count,
  c.first_award_date,
  c.latest_award_date,
  c.observed_history_days,
  round(c.p25_interval_days::numeric,1) as p25_interval_days,
  round(c.median_interval_days::numeric,1) as median_interval_days,
  round(c.p75_interval_days::numeric,1) as p75_interval_days,
  fq.federal_fiscal_quarter as peak_federal_fiscal_quarter,
  case when fq.n is not null then round(fq.n::numeric / nullif(t.task_order_count,0),3) else null end as peak_fiscal_quarter_share,
  case
    when c.distinct_award_events >= 5 and c.observed_history_days >= 365 then 'high'
    when c.distinct_award_events >= 3 and c.observed_history_days >= 120 then 'medium'
    when c.distinct_award_events >= 2 then 'low'
    else 'insufficient'
  end as cadence_confidence,
  case
    when c.distinct_award_events >= 3 and c.observed_history_days >= 120 and coalesce(c.median_interval_days,0) > 0 then true
    else false
  end as cadence_projection_authorized,
  case
    when c.distinct_award_events >= 3 and c.observed_history_days >= 120 and coalesce(c.median_interval_days,0) > 0
      then c.latest_award_date + greatest(1,round(c.median_interval_days))::integer
    else null
  end as next_expected_award_center,
  case
    when c.distinct_award_events >= 3 and c.observed_history_days >= 120 and coalesce(c.p25_interval_days,0) > 0
      then c.latest_award_date + greatest(1,floor(c.p25_interval_days))::integer
    else null
  end as next_expected_award_early,
  case
    when c.distinct_award_events >= 3 and c.observed_history_days >= 120 and coalesce(c.p75_interval_days,0) > 0
      then c.latest_award_date + greatest(1,ceil(c.p75_interval_days))::integer
    else null
  end as next_expected_award_late,
  case
    when coalesce(c.median_interval_days,0) <= 0 then 'unknown'
    when (coalesce(c.p75_interval_days,c.median_interval_days)-coalesce(c.p25_interval_days,c.median_interval_days)) / nullif(c.median_interval_days,0) <= 0.35 then 'regular'
    when (coalesce(c.p75_interval_days,c.median_interval_days)-coalesce(c.p25_interval_days,c.median_interval_days)) / nullif(c.median_interval_days,0) <= 0.80 then 'moderately_variable'
    else 'highly_variable'
  end as cadence_variability,
  false as future_award_assertion_authorized
from cadence c
join totals t using(awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class)
left join fq on fq.awarding_agency_name is not distinct from c.awarding_agency_name
  and fq.awarding_subtier_name is not distinct from c.awarding_subtier_name
  and fq.awarding_office_name is not distinct from c.awarding_office_name
  and fq.scope_class=c.scope_class
  and fq.rn=1;

comment on view research.v_federal_buyer_scope_cadence_v1 is
  'Buyer-office and deterministic scope-class award cadence. Projection fields require at least three distinct award dates and 120 days of observed history; they are statistical watch windows, never assertions that a future award will occur.';

create or replace view research.v_federal_vehicle_scope_cadence_v1 as
with substantive as (
  select *
  from research.v_federal_task_order_scope_facts_v1
  where not is_administrative_guarantee
    and date_signed is not null
), award_dates as (
  select distinct awarding_agency_name,awarding_subtier_name,awarding_office_name,parent_piid,scope_class,date_signed
  from substantive
), intervals as (
  select
    d.*,
    d.date_signed - lag(d.date_signed) over (
      partition by d.awarding_agency_name,d.awarding_subtier_name,d.awarding_office_name,d.parent_piid,d.scope_class
      order by d.date_signed
    ) as interval_days
  from award_dates d
), cadence as (
  select
    awarding_agency_name,awarding_subtier_name,awarding_office_name,parent_piid,scope_class,
    count(*)::integer as distinct_award_events,
    min(date_signed) as first_award_date,
    max(date_signed) as latest_award_date,
    (max(date_signed)-min(date_signed))::integer as observed_history_days,
    percentile_cont(0.25) within group (order by interval_days) filter (where interval_days is not null) as p25_interval_days,
    percentile_cont(0.50) within group (order by interval_days) filter (where interval_days is not null) as median_interval_days,
    percentile_cont(0.75) within group (order by interval_days) filter (where interval_days is not null) as p75_interval_days
  from intervals
  group by awarding_agency_name,awarding_subtier_name,awarding_office_name,parent_piid,scope_class
), totals as (
  select
    awarding_agency_name,awarding_subtier_name,awarding_office_name,parent_piid,scope_class,
    count(*)::integer as task_order_count,
    count(distinct recipient_uei) filter (where recipient_uei is not null)::integer as contractor_count,
    sum(total_obligation) as total_obligation
  from substantive
  group by awarding_agency_name,awarding_subtier_name,awarding_office_name,parent_piid,scope_class
)
select
  c.awarding_agency_name,c.awarding_subtier_name,c.awarding_office_name,c.parent_piid,c.scope_class,
  t.task_order_count,c.distinct_award_events,t.contractor_count,t.total_obligation,
  c.first_award_date,c.latest_award_date,c.observed_history_days,
  round(c.p25_interval_days::numeric,1) as p25_interval_days,
  round(c.median_interval_days::numeric,1) as median_interval_days,
  round(c.p75_interval_days::numeric,1) as p75_interval_days,
  case
    when c.distinct_award_events >= 5 and c.observed_history_days >= 365 then 'high'
    when c.distinct_award_events >= 3 and c.observed_history_days >= 120 then 'medium'
    when c.distinct_award_events >= 2 then 'low'
    else 'insufficient'
  end as cadence_confidence,
  (c.distinct_award_events >= 3 and c.observed_history_days >= 120 and coalesce(c.median_interval_days,0)>0) as cadence_projection_authorized,
  case when c.distinct_award_events >= 3 and c.observed_history_days >= 120 and coalesce(c.median_interval_days,0)>0
    then c.latest_award_date + greatest(1,round(c.median_interval_days))::integer end as next_expected_award_center,
  case when c.distinct_award_events >= 3 and c.observed_history_days >= 120 and coalesce(c.p25_interval_days,0)>0
    then c.latest_award_date + greatest(1,floor(c.p25_interval_days))::integer end as next_expected_award_early,
  case when c.distinct_award_events >= 3 and c.observed_history_days >= 120 and coalesce(c.p75_interval_days,0)>0
    then c.latest_award_date + greatest(1,ceil(c.p75_interval_days))::integer end as next_expected_award_late,
  false as future_award_assertion_authorized
from cadence c
join totals t using(awarding_agency_name,awarding_subtier_name,awarding_office_name,parent_piid,scope_class);

comment on view research.v_federal_vehicle_scope_cadence_v1 is
  'Parent-PIID-specific scope cadence. Sparse parent vehicles remain visible but are not projected until history clears deterministic evidence thresholds.';

create or replace view research.v_federal_buyer_scope_contractor_patterns_v1 as
with substantive as (
  select *
  from research.v_federal_task_order_scope_facts_v1
  where not is_administrative_guarantee
    and recipient_uei is not null
), buyer_totals as (
  select
    awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class,
    count(*)::integer as buyer_scope_orders,
    count(distinct recipient_uei)::integer as buyer_scope_contractors,
    sum(total_obligation) as buyer_scope_obligation
  from substantive
  group by awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class
), contractor as (
  select
    awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class,
    recipient_uei,
    max(recipient_name) as recipient_name,
    count(*)::integer as contractor_orders,
    count(distinct parent_piid)::integer as contractor_parent_vehicles,
    sum(total_obligation) as contractor_obligation,
    min(date_signed) as first_award_date,
    max(date_signed) as latest_award_date,
    count(*) filter (where coalesce(pop_potential_end_date,pop_end_date) >= current_date)::integer as currently_unexpired_orders
  from substantive
  group by awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class,recipient_uei
)
select
  c.awarding_agency_name,c.awarding_subtier_name,c.awarding_office_name,c.scope_class,
  c.recipient_uei,c.recipient_name,
  c.contractor_orders,c.contractor_parent_vehicles,c.contractor_obligation,
  c.first_award_date,c.latest_award_date,c.currently_unexpired_orders,
  t.buyer_scope_orders,t.buyer_scope_contractors,t.buyer_scope_obligation,
  round(c.contractor_orders::numeric/nullif(t.buyer_scope_orders,0),3) as order_share,
  round(coalesce(c.contractor_obligation,0)/nullif(t.buyer_scope_obligation,0),3) as obligation_share,
  case
    when c.contractor_orders >= 3 and c.contractor_orders::numeric/nullif(t.buyer_scope_orders,0) >= 0.60 then 'dominant_repeat_winner'
    when c.contractor_orders >= 2 and c.contractor_orders::numeric/nullif(t.buyer_scope_orders,0) >= 0.40 then 'repeat_winner'
    when c.contractor_orders >= 2 then 'repeat_participant_winner'
    else 'single_observed_win'
  end as win_pattern,
  case
    when t.buyer_scope_orders >= 5 then 'high'
    when t.buyer_scope_orders >= 3 then 'medium'
    when t.buyer_scope_orders >= 2 then 'low'
    else 'insufficient'
  end as pattern_confidence,
  false as future_win_assertion_authorized
from contractor c
join buyer_totals t using(awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class);

comment on view research.v_federal_buyer_scope_contractor_patterns_v1 is
  'Observed contractor win concentration by buyer office and scope class across parent vehicles. Repeat-winner labels describe historical awards only and never imply entitlement to future work.';

create or replace view research.v_federal_task_order_predictive_handoff_v1 as
select
  g.parent_piid,
  g.child_piid,
  g.child_generated_award_id,
  g.awarding_agency_name,
  g.awarding_subtier_name,
  g.awarding_office_name,
  g.contractor_name,
  g.contractor_uei,
  g.asset_name,
  g.asset_namespace,
  g.asset_node_key,
  g.performance_window_status,
  g.effective_end_date,
  g.capture_signal_status,
  s.scope_class,
  bc.task_order_count as buyer_scope_order_count,
  bc.parent_vehicle_count as buyer_scope_parent_vehicle_count,
  bc.contractor_count as buyer_scope_contractor_count,
  bc.cadence_confidence as buyer_scope_cadence_confidence,
  bc.cadence_variability as buyer_scope_cadence_variability,
  bc.peak_federal_fiscal_quarter,
  bc.peak_fiscal_quarter_share,
  bc.cadence_projection_authorized as buyer_scope_projection_authorized,
  bc.next_expected_award_early as buyer_scope_next_expected_award_early,
  bc.next_expected_award_center as buyer_scope_next_expected_award_center,
  bc.next_expected_award_late as buyer_scope_next_expected_award_late,
  vc.task_order_count as vehicle_scope_order_count,
  vc.cadence_confidence as vehicle_scope_cadence_confidence,
  vc.cadence_projection_authorized as vehicle_scope_projection_authorized,
  vc.next_expected_award_early as vehicle_scope_next_expected_award_early,
  vc.next_expected_award_center as vehicle_scope_next_expected_award_center,
  vc.next_expected_award_late as vehicle_scope_next_expected_award_late,
  cp.contractor_orders as buyer_scope_contractor_orders,
  cp.order_share as buyer_scope_contractor_order_share,
  cp.obligation_share as buyer_scope_contractor_obligation_share,
  cp.win_pattern,
  cp.pattern_confidence as contractor_pattern_confidence,
  case
    when g.active_task_scope_incumbency_authorized and g.effective_end_date between current_date and current_date + 180
      and (bc.cadence_projection_authorized or vc.cadence_projection_authorized)
      then 'recompete_watch_plus_purchasing_cadence'
    when g.active_task_scope_incumbency_authorized and g.effective_end_date between current_date and current_date + 180
      then 'recompete_watch_contract_end_only'
    when g.contractor_operational_presence_authorized and bc.cadence_projection_authorized
      then 'buyer_scope_cadence_context'
    when g.exact_asset_link_authorized and bc.cadence_projection_authorized
      then 'resolved_asset_buyer_cadence_context'
    else 'historical_context_only'
  end as predictive_handoff_kind,
  false as auto_insert_into_opportunity_spine,
  false as future_award_assertion_authorized,
  false as future_contractor_win_assertion_authorized
from research.v_federal_task_order_capture_graph_v1 g
left join research.v_federal_task_order_scope_facts_v1 s
  on s.child_generated_award_id=g.child_generated_award_id
left join research.v_federal_buyer_scope_cadence_v1 bc
  on bc.awarding_agency_name is not distinct from g.awarding_agency_name
 and bc.awarding_subtier_name is not distinct from g.awarding_subtier_name
 and bc.awarding_office_name is not distinct from g.awarding_office_name
 and bc.scope_class=s.scope_class
left join research.v_federal_vehicle_scope_cadence_v1 vc
  on vc.awarding_agency_name is not distinct from g.awarding_agency_name
 and vc.awarding_subtier_name is not distinct from g.awarding_subtier_name
 and vc.awarding_office_name is not distinct from g.awarding_office_name
 and vc.parent_piid=g.parent_piid
 and vc.scope_class=s.scope_class
left join research.v_federal_buyer_scope_contractor_patterns_v1 cp
  on cp.awarding_agency_name is not distinct from g.awarding_agency_name
 and cp.awarding_subtier_name is not distinct from g.awarding_subtier_name
 and cp.awarding_office_name is not distinct from g.awarding_office_name
 and cp.scope_class=s.scope_class
 and cp.recipient_uei=g.contractor_uei;

comment on view research.v_federal_task_order_predictive_handoff_v1 is
  'Research-only bridge from verified regional task-order/asset evidence to buyer cadence and historical contractor win concentration. It never auto-creates opportunity-spine rows and never asserts a future award or winner.';

revoke all on table research.v_federal_task_order_scope_facts_v1 from anon,authenticated;
revoke all on table research.v_federal_buyer_scope_cadence_v1 from anon,authenticated;
revoke all on table research.v_federal_vehicle_scope_cadence_v1 from anon,authenticated;
revoke all on table research.v_federal_buyer_scope_contractor_patterns_v1 from anon,authenticated;
revoke all on table research.v_federal_task_order_predictive_handoff_v1 from anon,authenticated;