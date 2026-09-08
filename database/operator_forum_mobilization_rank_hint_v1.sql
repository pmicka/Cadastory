-- Scout operator-forum mobilization ranking hint v1
-- Keeps the forum-derived mobilization heuristic bounded and inspectable.
-- This is an internal ranking input, not a validated conversion predictor.

create or replace function scout.opportunity_mobilization_rank_hint_v1(
  p_provider_organization_id uuid,
  p_candidate_key text
)
returns table(
  candidate_key text,
  provider_organization_id uuid,
  base_distance_miles numeric,
  within_declared_travel_radius boolean,
  nearby_same_service_count integer,
  nearby_same_buyer_count integer,
  same_buyer_pushable_portfolio_count integer,
  mobilization_signal text,
  rank_adjustment_hint integer,
  rank_hint_reason text,
  evidence_state text,
  formula_version text
)
language sql
stable
set search_path to pg_catalog, public, extensions, scout, commerce, research
as $$
select m.candidate_key,
       m.provider_organization_id,
       m.base_distance_miles,
       m.within_declared_travel_radius,
       m.nearby_same_service_count,
       m.nearby_same_buyer_count,
       m.same_buyer_pushable_portfolio_count,
       m.mobilization_signal,
       case
         when m.within_declared_travel_radius is false then -1
         when m.nearby_same_buyer_count>=2 then 1
         when m.nearby_same_service_count>=3 and coalesce(m.base_distance_miles,0)<=75 then 1
         when m.nearby_same_service_count=0 and coalesce(m.base_distance_miles,0)>75 then -1
         else 0
       end as rank_adjustment_hint,
       case
         when m.within_declared_travel_radius is false then 'Outside the provider declared travel radius; apply a small mobilization penalty.'
         when m.nearby_same_buyer_count>=2 then 'Multiple nearby opportunities share the buyer, supporting account/route leverage.'
         when m.nearby_same_service_count>=3 and coalesce(m.base_distance_miles,0)<=75 then 'At least three nearby same-service destinations can share mobilization.'
         when m.nearby_same_service_count=0 and coalesce(m.base_distance_miles,0)>75 then 'Long straight-line mobilization with no nearby same-service destination documented.'
         else 'Mobilization evidence is mixed or neutral; do not alter rank from this hypothesis alone.'
       end as rank_hint_reason,
       'forum_derived_hypothesis'::text as evidence_state,
       'mobilization_rank_hint_v1'::text as formula_version
from scout.opportunity_mobilization_context_v1(p_provider_organization_id,p_candidate_key) m;
$$;

comment on function scout.opportunity_mobilization_rank_hint_v1(uuid,text) is
'Internal bounded mobilization ranking hint derived from operator-forum hypotheses. Returns only -1, 0, or +1 and is not a validated conversion predictor.';

revoke all on function scout.opportunity_mobilization_rank_hint_v1(uuid,text) from public;
revoke all on function scout.opportunity_mobilization_rank_hint_v1(uuid,text) from anon;
revoke all on function scout.opportunity_mobilization_rank_hint_v1(uuid,text) from authenticated;
grant execute on function scout.opportunity_mobilization_rank_hint_v1(uuid,text) to service_role;
