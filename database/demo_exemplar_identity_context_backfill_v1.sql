-- Backfill already-resolved buyer/geography context onto manually pinned demo exemplars.
-- This gives evidence workers corroborating identity terms without changing buyer
-- assignments, opportunity scores, or public exposure.

update research.demo_exemplar_priorities_v1 p
set organization_name = coalesce(p.organization_name,s.buyer_name),
    context = p.context || jsonb_strip_nulls(jsonb_build_object(
      'buyer_name',s.buyer_name,
      'state_code',s.state_code,
      'county_name',s.county_name,
      'buyer_resolution_status',s.buyer_resolution_status,
      'buyer_contact_status',s.buyer_contact_status,
      'procurement_status',s.procurement_status,
      'identity_context_version','demo_exemplar_identity_context_v1'
    )),
    updated_at = now()
from scout.v_opportunity_spine_cards s
where p.candidate_key=s.candidate_key
  and p.active;
