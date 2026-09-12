-- Batch 1 commercial semantics foundation.
-- This is a shadow/additive contract. Existing opportunity searches remain unchanged.

create or replace view scout.v_opportunity_commercial_semantics_v1
with (security_invoker = true)
as
with base as (
  select
    c.*,
    s.procurement_status,
    s.buyer_resolution_status,
    s.buyer_contact_status,
    (
      s.procurement_status in ('open_solicitation','open_bid','rfq_open','direct_purchase_open')
      and s.details ->> 'opportunity_confirmation' = 'documented_open_purchase'
    ) as purchase_event_confirmed,
    (
      c.subject_key is not null
      and nullif(btrim(c.display_name), '') is not null
      and cardinality(c.service_slugs) > 0
    ) as specific_service_target,
    lower(coalesce(c.signal_strength, '')) in ('high','strong','serious') as strong_need_signal
  from scout.v_opportunity_candidates_v2 c
  join scout.opportunity_search_spine s using (candidate_key)
), viability as (
  select
    b.*,
    case
      when b.purchase_event_confirmed then 'confirmed_demand'
      when b.specific_service_target
        and b.buyer_readiness = 'buyer_ready'
        and b.evidence_confidence >= 0.70
        and b.strong_need_signal
        then 'high_potential_prospect'
      when b.specific_service_target
        and (
          b.buyer_readiness in ('buyer_ready','organization_identified')
          or b.action_window_open
        )
        and b.evidence_confidence >= 0.60
        then 'viable_prospect'
      when b.specific_service_target
        then 'research_candidate'
      else 'market_context_only'
    end as lead_viability_label
  from base b
), staged as (
  select
    v.*,
    case v.lead_viability_label
      when 'confirmed_demand' then 4
      when 'high_potential_prospect' then 3
      when 'viable_prospect' then 2
      when 'research_candidate' then 1
      else 0
    end as lead_viability_rank,
    case
      when v.purchase_event_confirmed then 'confirmed_opportunity'
      when v.lead_viability_label in ('high_potential_prospect','viable_prospect')
        and v.buyer_readiness = 'buyer_ready'
        then 'outreach_ready'
      when v.lead_viability_label <> 'market_context_only'
        then 'qualification_required'
      else 'context_only'
    end as lead_stage,
    case
      when v.purchase_event_confirmed and v.action_window_open then 'immediate_confirmed'
      when v.action_window_open then 'time_sensitive_prospecting'
      when coalesce(v.valid_from, v.observed_at) > now() then 'not_yet_relevant'
      when coalesce(v.expires_at, v.ideal_until) < now() then 'expired_or_stale_window'
      when coalesce(v.ideal_until, v.expires_at) <= now() + interval '90 days' then 'near_term'
      when coalesce(v.ideal_until, v.expires_at) is not null then 'planned_or_monitor'
      when v.lead_viability_label <> 'market_context_only' then 'evergreen'
      else 'no_action_timing'
    end as urgency_label
  from viability v
)
select
  s.candidate_key,
  s.evidence_confidence,
  s.lead_viability_label,
  s.lead_viability_rank,
  case s.lead_viability_label
    when 'confirmed_demand'
      then 'A documented open purchasing event is present.'
    when 'high_potential_prospect'
      then 'A specific service target, strong evidence-backed need signal, and reachable buyer are present; purchase intent is not confirmed.'
    when 'viable_prospect'
      then 'The record materially improves prospect targeting through a specific service target plus buyer, organization, or timing evidence; qualification is still required.'
    when 'research_candidate'
      then 'A specific service target exists, but buyer access or material need validation must be improved before outreach.'
    else 'The record currently supports market understanding rather than individual sales pursuit.'
  end as lead_viability_reason,
  s.lead_stage,
  s.urgency_label,
  case s.urgency_label
    when 'immediate_confirmed' then 5
    when 'time_sensitive_prospecting' then 4
    when 'near_term' then 3
    when 'planned_or_monitor' then 2
    when 'evergreen' then 1
    else 0
  end as urgency_rank,
  case
    when s.purchase_event_confirmed
      then 'Review the documented purchasing event, requirements, deadline, and fit before responding.'
    when s.lead_stage = 'outreach_ready' and s.action_window_open
      then 'Contact the resolved buyer promptly and qualify the service need; describe the timing signal without presenting it as confirmed demand.'
    when s.lead_stage = 'outreach_ready'
      then 'Contact the resolved buyer with an evidence-specific qualification question and verify current need, budget, and purchasing path.'
    when s.lead_stage = 'qualification_required'
      and s.buyer_readiness in ('buyer_unresolved','route_or_role_only')
      then 'Resolve the responsible organization, buyer, or durable purchasing route before outreach.'
    when s.lead_stage = 'qualification_required'
      then 'Validate the operational target and current service need, then identify the appropriate buyer or contact.'
    else 'Use this record for market prioritization or enrichment; do not present it as an individual sales lead yet.'
  end as recommended_next_action,
  s.purchase_event_confirmed,
  case when s.purchase_event_confirmed then 'documented_open_purchase' else 'unconfirmed_purchase_intent' end as purchase_confirmation_status,
  s.action_window_open,
  s.actionability_state,
  s.actionability_reason,
  s.buyer_readiness,
  s.buyer_readiness_reason,
  s.specific_service_target,
  'commercial_semantics_shadow_v1'::text as commercial_contract_version
from staged s;

comment on view scout.v_opportunity_commercial_semantics_v1 is
  'Shadow commercial semantics contract separating lead viability, lead stage, urgency, evidence confidence, buyer readiness, purchase confirmation, and next action. It does not alter production opportunity searches. Vertical-specific promotion and suppression rules are intentionally deferred to later reviewed batches.';
comment on column scout.v_opportunity_commercial_semantics_v1.lead_viability_label is
  'Sales usefulness of an individual prospect record, independent of whether an immediate action window exists.';
comment on column scout.v_opportunity_commercial_semantics_v1.urgency_label is
  'Timing posture only. Time-sensitive prospecting does not imply confirmed damage, demand, budget, or purchase intent.';
comment on column scout.v_opportunity_commercial_semantics_v1.purchase_event_confirmed is
  'True only when Scout has both a recognized open procurement state and explicit documented-open-purchase evidence.';

revoke all on scout.v_opportunity_commercial_semantics_v1 from public, anon, authenticated;
grant select on scout.v_opportunity_commercial_semantics_v1 to service_role;

create or replace view scout.v_opportunity_candidates_v3_shadow
with (security_invoker = true)
as
select
  c.*,
  m.lead_viability_label,
  m.lead_viability_rank,
  m.lead_viability_reason,
  m.lead_stage,
  m.urgency_label,
  m.urgency_rank,
  m.recommended_next_action,
  m.purchase_event_confirmed,
  m.purchase_confirmation_status,
  m.specific_service_target,
  m.commercial_contract_version
from scout.v_opportunity_candidates_v2 c
join scout.v_opportunity_commercial_semantics_v1 m using (candidate_key);

comment on view scout.v_opportunity_candidates_v3_shadow is
  'Additive shadow candidate contract for Batch 1 commercial-semantics evaluation. No production search or model-visible surface depends on this view.';

revoke all on scout.v_opportunity_candidates_v3_shadow from public, anon, authenticated;
grant select on scout.v_opportunity_candidates_v3_shadow to service_role;
