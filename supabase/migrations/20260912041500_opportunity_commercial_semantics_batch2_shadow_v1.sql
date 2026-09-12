-- Batch 2 reviewed commercial policies.
-- Remains shadow-only: production opportunity searches are unchanged.

create or replace view scout.v_opportunity_commercial_semantics_v2_shadow
with (security_invoker = true)
as
with base as (
  select c.source_kind,c.signal_strength,c.contact_available,c.details,c.service_slugs,g.*
  from scout.v_opportunity_commercial_semantics_v1 g
  join scout.v_opportunity_candidates_v2 c using (candidate_key)
), reviewed as (
  select b.*,
    case
      when b.source_kind='water_tank_maintenance'
        then case when b.signal_strength='high' then 'high_potential_prospect' else 'viable_prospect' end
      when b.source_kind='funded_scope_resolved'
        then case when b.signal_strength='high' and b.buyer_readiness='buyer_ready' then 'high_potential_prospect' else 'viable_prospect' end
      when b.source_kind='exterior_cleaning' and b.buyer_readiness='buyer_ready'
        then case when b.signal_strength='high' then 'high_potential_prospect' else 'viable_prospect' end
      when b.source_kind='farm_seasonal'
        then case
          when b.details->>'prospecting_relevance'<>'relevant' then 'market_context_only'
          when b.buyer_readiness in ('buyer_ready','organization_identified') then 'viable_prospect'
          else 'research_candidate'
        end
      else b.lead_viability_label
    end reviewed_viability_label,
    case
      when b.source_kind in ('water_tank_maintenance','funded_scope_resolved') then 'reviewed_batch2'
      when b.source_kind='exterior_cleaning' and b.buyer_readiness='buyer_ready' then 'reviewed_batch2'
      when b.source_kind='farm_seasonal' then 'reviewed_batch2'
      else 'pending_vertical_review'
    end vertical_policy_status
  from base b
), staged as (
  select r.*,
    case r.reviewed_viability_label when 'confirmed_demand' then 4 when 'high_potential_prospect' then 3 when 'viable_prospect' then 2 when 'research_candidate' then 1 else 0 end reviewed_viability_rank,
    case
      when r.purchase_event_confirmed then 'confirmed_opportunity'
      when r.reviewed_viability_label in ('high_potential_prospect','viable_prospect') and r.buyer_readiness='buyer_ready' then 'outreach_ready'
      when r.reviewed_viability_label in ('high_potential_prospect','viable_prospect','research_candidate') then 'qualification_required'
      else 'context_only'
    end reviewed_lead_stage
  from reviewed r
)
select
  s.candidate_key,s.evidence_confidence,
  s.reviewed_viability_label lead_viability_label,
  s.reviewed_viability_rank lead_viability_rank,
  case
    when s.source_kind='water_tank_maintenance' and s.signal_strength='high'
      then 'A specific water-tank asset, resolved utility buyer, usable contact, and documented rehabilitation evidence support targeted qualification outreach; an open job is not confirmed.'
    when s.source_kind='water_tank_maintenance'
      then 'A specific water-tank asset, resolved utility buyer, usable contact, and inspection-cadence proxy support targeted qualification outreach; timing is not a legal overdue determination.'
    when s.source_kind='funded_scope_resolved'
      then 'A public planning or procurement document identifies relevant scope and the responsible organization; the exact facility, project, budget timing, and purchase intent may still require resolution.'
    when s.source_kind='exterior_cleaning' and s.buyer_readiness='buyer_ready'
      then 'A specific property, relevant environmental-exposure proxy, and usable buyer route support qualification outreach; visible staining and present cleaning demand remain unconfirmed.'
    when s.source_kind='farm_seasonal' and s.details->>'prospecting_relevance'='relevant'
      then 'A specific farm prospect and crop-aligned regional timing signal support seasonal qualification; current operator identity, field conditions, and service intent may still require verification.'
    when s.source_kind='farm_seasonal'
      then 'The record is explicitly context-only for the represented farm service and is not eligible for recommendation.'
    else s.lead_viability_reason
  end lead_viability_reason,
  s.reviewed_lead_stage lead_stage,
  case
    when s.source_kind='farm_seasonal' and s.details->>'prospecting_relevance'='relevant' then 'seasonal_prospecting'
    when s.source_kind in ('water_tank_maintenance','funded_scope_resolved')
      or (s.source_kind='exterior_cleaning' and s.buyer_readiness='buyer_ready') then 'evergreen'
    else s.urgency_label
  end urgency_label,
  case
    when s.source_kind='farm_seasonal' and s.details->>'prospecting_relevance'='relevant' then 3
    when s.source_kind in ('water_tank_maintenance','funded_scope_resolved')
      or (s.source_kind='exterior_cleaning' and s.buyer_readiness='buyer_ready') then 1
    else s.urgency_rank
  end urgency_rank,
  case
    when s.source_kind='water_tank_maintenance' and s.signal_strength='high'
      then 'Contact the resolved utility role about the documented rehabilitation history and ask who owns current exterior-cleaning or inspection planning for this tank.'
    when s.source_kind='water_tank_maintenance'
      then 'Contact the resolved utility role to verify the latest inspection, cleaning, coating, and rehabilitation history before proposing work.'
    when s.source_kind='funded_scope_resolved' and s.buyer_readiness='buyer_ready'
      then 'Use the documented scope in outreach to the resolved organization, then identify the exact facility, project phase, budget timing, and purchasing route.'
    when s.source_kind='funded_scope_resolved'
      then 'Resolve a durable facilities or procurement contact, then validate the exact facility and project phase behind the documented scope.'
    when s.source_kind='exterior_cleaning' and s.buyer_readiness='buyer_ready'
      then 'Contact the resolved property buyer with the exposure-specific reason for inspection and verify visible condition before proposing cleaning.'
    when s.source_kind='farm_seasonal' and s.details->>'prospecting_relevance'='relevant' and s.buyer_readiness='buyer_ready'
      then 'Contact the farm prospect with a crop- and service-specific qualification question; verify the current operator, field stage, weather, and any credential or label requirements.'
    when s.source_kind='farm_seasonal' and s.details->>'prospecting_relevance'='relevant'
      then 'Resolve or verify the current farm operator and contact before using the regional crop signal for outreach.'
    when s.source_kind='farm_seasonal'
      then 'Retain as regional or account context; do not recommend this service from the current evidence.'
    else s.recommended_next_action
  end recommended_next_action,
  s.purchase_event_confirmed,s.purchase_confirmation_status,s.action_window_open,s.actionability_state,s.actionability_reason,
  s.buyer_readiness,s.buyer_readiness_reason,s.specific_service_target,s.vertical_policy_status,
  case
    when s.source_kind in ('water_tank_maintenance','funded_scope_resolved') then true
    when s.source_kind='exterior_cleaning' and s.buyer_readiness='buyer_ready' then true
    when s.source_kind='farm_seasonal' and s.details->>'prospecting_relevance'='relevant' and s.buyer_readiness='buyer_ready' then true
    else false
  end recommendation_eligible,
  'commercial_semantics_batch2_shadow_v1'::text commercial_contract_version
from staged s;

comment on view scout.v_opportunity_commercial_semantics_v2_shadow is
  'Shadow commercial semantics with reviewed Batch 2 policies for water tanks, documented funded scope, buyer-resolved exterior cleaning, and buyer-resolved prospecting-relevant farm records. Recommendation eligibility is independent of urgency and is not consumed by production search.';

revoke all on scout.v_opportunity_commercial_semantics_v2_shadow from public, anon, authenticated;
grant select on scout.v_opportunity_commercial_semantics_v2_shadow to service_role;

create or replace view scout.v_opportunity_candidates_v4_shadow
with (security_invoker = true)
as
select c.*,m.lead_viability_label,m.lead_viability_rank,m.lead_viability_reason,m.lead_stage,
       m.urgency_label,m.urgency_rank,m.recommended_next_action,m.purchase_event_confirmed,
       m.purchase_confirmation_status,m.specific_service_target,m.vertical_policy_status,
       m.recommendation_eligible,m.commercial_contract_version
from scout.v_opportunity_candidates_v2 c
join scout.v_opportunity_commercial_semantics_v2_shadow m using (candidate_key);

comment on view scout.v_opportunity_candidates_v4_shadow is
  'Additive Batch 2 shadow candidate contract. Production opportunity functions remain unchanged.';

revoke all on scout.v_opportunity_candidates_v4_shadow from public, anon, authenticated;
grant select on scout.v_opportunity_candidates_v4_shadow to service_role;
