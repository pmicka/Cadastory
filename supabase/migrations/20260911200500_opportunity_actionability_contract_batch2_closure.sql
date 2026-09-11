-- Batch 2 closure: a reachable farm organization does not make
-- state/regional crop progress an asset-specific immediate-action signal.

create or replace view scout.v_opportunity_actionability_v1
with (security_invoker = true)
as
with classified as (
  select
    s.*,
    coalesce(s.valid_from, s.observed_at, now()) <= now()
      and (
        s.expires_at >= now()
        or (
          s.expires_at is null
          and s.ideal_until >= now()
          and s.ideal_until <= now() + interval '120 days'
        )
      ) as bounded_window_open,
    s.buyer_resolution_status = 'organization_resolved'
      and s.buyer_contact_status <> 'unresolved' as reachable_buyer
  from scout.opportunity_search_spine s
)
select
  s.candidate_key,
  s.source_kind,
  s.time_sensitive as has_timing_context,
  case
    when not coalesce(s.time_sensitive, false) then false
    when s.source_kind = 'event_detailing' then
      coalesce(s.event_context ->> 'relationship_type', '') = 'primary_venue'
      and coalesce(s.event_context ->> 'action_basis', '') = 'documented_pre_event_service_pattern'
      and s.bounded_window_open
    when s.source_kind = 'bridge' then
      s.ideal_until >= now()
      and s.ideal_until <= now() + interval '90 days'
    when s.source_kind = 'construction_window' then
      s.bounded_window_open and s.reachable_buyer
    when s.source_kind = 'farm_seasonal' then false
    when s.source_kind = 'dam_condition_cadence' then false
    when s.source_kind = 'telecom_change' then false
    else s.bounded_window_open
  end as action_window_open,
  case
    when not coalesce(s.time_sensitive, false) then 'ongoing_context'
    when s.source_kind = 'event_detailing'
      and not (
        coalesce(s.event_context ->> 'relationship_type', '') = 'primary_venue'
        and coalesce(s.event_context ->> 'action_basis', '') = 'documented_pre_event_service_pattern'
      ) then 'event_context_only'
    when s.source_kind = 'bridge' and s.ideal_until < now() then 'projected_date_passed'
    when s.source_kind = 'construction_window' and not s.reachable_buyer then 'buyer_route_needed'
    when s.source_kind = 'farm_seasonal' then 'regional_crop_timing_context_only'
    when s.source_kind = 'dam_condition_cadence' then 'asset_condition_context_only'
    when s.source_kind = 'telecom_change' then 'registration_context_only'
    when coalesce(s.valid_from, s.observed_at, now()) > now() then 'not_yet_open'
    when s.expires_at is null and s.ideal_until is null then 'unbounded_context_only'
    when coalesce(s.expires_at, s.ideal_until) < now() then 'window_closed'
    when s.expires_at is null and s.ideal_until > now() + interval '120 days' then 'long_horizon_context'
    when s.source_kind = 'construction_window'
      and s.bounded_window_open and s.reachable_buyer then 'buyer_ready_prospecting_window'
    else 'action_window_open'
  end as actionability_state,
  case
    when s.source_kind = 'event_detailing'
      and not (
        coalesce(s.event_context ->> 'relationship_type', '') = 'primary_venue'
        and coalesce(s.event_context ->> 'action_basis', '') = 'documented_pre_event_service_pattern'
      )
      then 'Event proximity is context only; no asset-specific pre-event service pattern is documented.'
    when s.source_kind = 'bridge' and s.ideal_until < now()
      then 'The nominal inspection date has passed and does not prove an open procurement or unmet service need.'
    when s.source_kind = 'construction_window' and not s.reachable_buyer
      then 'Construction timing is plausible, but Scout has no resolved reachable buyer; unmet drone-service demand is not established.'
    when s.source_kind = 'farm_seasonal'
      then 'Regional crop progress can time market outreach, but it does not establish field-level need or an immediate job window even when a farm organization is reachable.'
    when s.source_kind = 'dam_condition_cadence'
      then 'Dam condition and nominal inspection cadence are important context but do not establish outsourced drone work or an open buying window.'
    when s.source_kind = 'telecom_change'
      then 'The FCC registration change is verified, but no asset-specific inspection, construction, mapping, or purchasing need is corroborated.'
    when s.expires_at is null and s.ideal_until is null
      then 'The evidence has no bounded buying or service window.'
    when coalesce(s.valid_from, s.observed_at, now()) > now()
      then 'The bounded window has not opened.'
    when coalesce(s.expires_at, s.ideal_until) < now()
      then 'The bounded window has closed.'
    when s.expires_at is null and s.ideal_until > now() + interval '120 days'
      then 'The timing horizon is too broad to imply immediate action.'
    when s.source_kind = 'construction_window'
      then 'A bounded construction prospecting period is open and Scout has a resolved reachable buyer; service need still requires qualification.'
    else 'A bounded evidence-backed window is currently open.'
  end as actionability_reason,
  s.valid_from,
  s.ideal_until,
  s.expires_at,
  s.refreshed_at
from classified s;

comment on view scout.v_opportunity_actionability_v1 is
  'Canonical actionability overlay. Batch 2 requires causal service fit, keeps regional crop timing as context until field/operator corroboration, and keeps dam condition/cadence plus FCC registration changes as context pending service or purchasing evidence.';

revoke all on scout.v_opportunity_actionability_v1 from public, anon, authenticated;
grant select on scout.v_opportunity_actionability_v1 to service_role;
