-- Scout by Cadastory
-- Roll cadence projections forward to the first current/future statistical watch window.
-- Preserve v1 one-step projections for auditability; v2/current views are the operational research surface.

create or replace view research.v_federal_buyer_scope_cadence_current_v1 as
with base as (
  select b.*,
    case
      when b.cadence_projection_authorized and coalesce(b.median_interval_days,0)>0 then
        greatest(1,ceil(greatest(0,(current_date-b.latest_award_date))::numeric / b.median_interval_days)::integer)
      else null
    end as projection_cycles_forward
  from research.v_federal_buyer_scope_cadence_v1 b
), projected as (
  select b.*,
    case when projection_cycles_forward is not null
      then latest_award_date + greatest(1,round(projection_cycles_forward * median_interval_days))::integer end as projected_center,
    case when projection_cycles_forward is not null
      then latest_award_date + greatest(1,round(projection_cycles_forward * median_interval_days))::integer
           + floor(coalesce(p25_interval_days,median_interval_days)-median_interval_days)::integer end as projected_early,
    case when projection_cycles_forward is not null
      then latest_award_date + greatest(1,round(projection_cycles_forward * median_interval_days))::integer
           + ceil(coalesce(p75_interval_days,median_interval_days)-median_interval_days)::integer end as projected_late
  from base b
)
select
  awarding_agency_name,awarding_subtier_name,awarding_office_name,scope_class,
  task_order_count,distinct_award_events,parent_vehicle_count,contractor_count,total_obligation,supported_state_order_count,
  first_award_date,latest_award_date,observed_history_days,p25_interval_days,median_interval_days,p75_interval_days,
  peak_federal_fiscal_quarter,peak_fiscal_quarter_share,cadence_confidence,cadence_projection_authorized,
  projected_center as next_expected_award_center,
  projected_early as next_expected_award_early,
  projected_late as next_expected_award_late,
  cadence_variability,
  projection_cycles_forward,
  case
    when not cadence_projection_authorized then 'not_projected'
    when current_date between projected_early and projected_late then 'watch_window_open'
    when current_date < projected_early then 'watch_window_upcoming'
    else 'watch_window_elapsed_pending_next_cycle'
  end as cadence_watch_status,
  false as future_award_assertion_authorized
from projected;

comment on view research.v_federal_buyer_scope_cadence_current_v1 is
  'Current/future buyer-scope cadence watch surface. It rolls the historical median cadence forward by whole cycles and retains an uncertainty band from the observed interquartile interval spread; not a future-award assertion.';

create or replace view research.v_federal_vehicle_scope_cadence_current_v1 as
with base as (
  select b.*,
    case
      when b.cadence_projection_authorized and coalesce(b.median_interval_days,0)>0 then
        greatest(1,ceil(greatest(0,(current_date-b.latest_award_date))::numeric / b.median_interval_days)::integer)
      else null
    end as projection_cycles_forward
  from research.v_federal_vehicle_scope_cadence_v1 b
), projected as (
  select b.*,
    case when projection_cycles_forward is not null
      then latest_award_date + greatest(1,round(projection_cycles_forward * median_interval_days))::integer end as projected_center,
    case when projection_cycles_forward is not null
      then latest_award_date + greatest(1,round(projection_cycles_forward * median_interval_days))::integer
           + floor(coalesce(p25_interval_days,median_interval_days)-median_interval_days)::integer end as projected_early,
    case when projection_cycles_forward is not null
      then latest_award_date + greatest(1,round(projection_cycles_forward * median_interval_days))::integer
           + ceil(coalesce(p75_interval_days,median_interval_days)-median_interval_days)::integer end as projected_late
  from base b
)
select
  awarding_agency_name,awarding_subtier_name,awarding_office_name,parent_piid,scope_class,
  task_order_count,distinct_award_events,contractor_count,total_obligation,
  first_award_date,latest_award_date,observed_history_days,p25_interval_days,median_interval_days,p75_interval_days,
  cadence_confidence,cadence_projection_authorized,
  projected_center as next_expected_award_center,
  projected_early as next_expected_award_early,
  projected_late as next_expected_award_late,
  projection_cycles_forward,
  case
    when not cadence_projection_authorized then 'not_projected'
    when current_date between projected_early and projected_late then 'watch_window_open'
    when current_date < projected_early then 'watch_window_upcoming'
    else 'watch_window_elapsed_pending_next_cycle'
  end as cadence_watch_status,
  false as future_award_assertion_authorized
from projected;

comment on view research.v_federal_vehicle_scope_cadence_current_v1 is
  'Current/future parent-vehicle scope cadence watch surface, cycle-rolled from observed award history. Sparse histories remain unprojected.';

create or replace view research.v_federal_task_order_predictive_handoff_v2 as
select
  h.*,
  bc.next_expected_award_early as current_buyer_scope_next_expected_award_early,
  bc.next_expected_award_center as current_buyer_scope_next_expected_award_center,
  bc.next_expected_award_late as current_buyer_scope_next_expected_award_late,
  bc.projection_cycles_forward as buyer_scope_projection_cycles_forward,
  bc.cadence_watch_status as buyer_scope_cadence_watch_status,
  vc.next_expected_award_early as current_vehicle_scope_next_expected_award_early,
  vc.next_expected_award_center as current_vehicle_scope_next_expected_award_center,
  vc.next_expected_award_late as current_vehicle_scope_next_expected_award_late,
  vc.projection_cycles_forward as vehicle_scope_projection_cycles_forward,
  vc.cadence_watch_status as vehicle_scope_cadence_watch_status,
  case
    when h.predictive_handoff_kind='recompete_watch_plus_purchasing_cadence'
      and (bc.cadence_watch_status='watch_window_open' or vc.cadence_watch_status='watch_window_open')
      then 'recompete_watch_and_cadence_window_open'
    when h.predictive_handoff_kind='recompete_watch_plus_purchasing_cadence'
      then 'recompete_watch_with_projected_cadence'
    when bc.cadence_watch_status='watch_window_open' or vc.cadence_watch_status='watch_window_open'
      then 'historical_scope_with_cadence_window_open'
    else h.predictive_handoff_kind
  end as current_predictive_handoff_kind
from research.v_federal_task_order_predictive_handoff_v1 h
left join research.v_federal_buyer_scope_cadence_current_v1 bc
  on bc.awarding_agency_name is not distinct from h.awarding_agency_name
 and bc.awarding_subtier_name is not distinct from h.awarding_subtier_name
 and bc.awarding_office_name is not distinct from h.awarding_office_name
 and bc.scope_class=h.scope_class
left join research.v_federal_vehicle_scope_cadence_current_v1 vc
  on vc.awarding_agency_name is not distinct from h.awarding_agency_name
 and vc.awarding_subtier_name is not distinct from h.awarding_subtier_name
 and vc.awarding_office_name is not distinct from h.awarding_office_name
 and vc.parent_piid=h.parent_piid
 and vc.scope_class=h.scope_class;

comment on view research.v_federal_task_order_predictive_handoff_v2 is
  'Current predictive research handoff. Adds cycle-rolled buyer/vehicle cadence windows to verified regional task-order context. Does not auto-create leads or assert future awards/winners.';

revoke all on table research.v_federal_buyer_scope_cadence_current_v1 from anon,authenticated;
revoke all on table research.v_federal_vehicle_scope_cadence_current_v1 from anon,authenticated;
revoke all on table research.v_federal_task_order_predictive_handoff_v2 from anon,authenticated;