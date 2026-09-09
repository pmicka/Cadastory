-- Scout contact trust derived inheritance v1
-- Mirrors production migration contact_trust_derived_inheritance_v1.
-- Derived/timing-amplified opportunities inherit buyer/contact trust from their canonical base candidate.
-- Trust semantics remain conservative; this does not promote public routes to verified-direct contacts.

create or replace view scout.v_opportunity_contact_trust_v1 as
with route_source as (
  select
    s.candidate_key,
    coalesce(s.derived_from_candidate_key,s.candidate_key) as route_candidate_key,
    s.buyer_organization_id as spine_buyer_organization_id,
    s.buyer_name as spine_buyer_name,
    s.buyer_resolution_status as spine_buyer_resolution_status,
    s.procurement_status as spine_procurement_status
  from scout.opportunity_search_spine s
), resolved as (
  select
    rs.candidate_key,
    coalesce(rs.spine_buyer_organization_id,r.organization_id) as buyer_organization_id,
    coalesce(rs.spine_buyer_name,r.organization_name) as buyer_name,
    coalesce(nullif(rs.spine_buyer_resolution_status,'unresolved'),r.resolution_status,'unresolved') as buyer_resolution_status,
    r.contact_point_id,
    r.contact_scope,
    r.contact_channel_type,
    r.contact_stability_class,
    r.contact_confidence,
    r.contact_value,
    r.contact_verify_after,
    r.procurement_contact_point_id,
    r.procurement_contact_value,
    coalesce(nullif(rs.spine_procurement_status,'unresolved'),r.procurement_status,'unresolved') as procurement_status,
    r.refreshed_at
  from route_source rs
  left join scout.opportunity_buyer_routes r on r.candidate_key=rs.route_candidate_key
)
select
  r.candidate_key,
  r.buyer_organization_id,
  r.buyer_name,
  r.buyer_resolution_status,
  r.contact_point_id,
  r.contact_scope,
  r.contact_channel_type,
  r.contact_stability_class,
  r.contact_confidence,
  cp.source_authority as contact_source_authority,
  cp.source_url as contact_source_url,
  cp.observed_on as contact_observed_on,
  coalesce(r.contact_verify_after,cp.verify_after) as contact_verify_after,
  case
    when r.contact_point_id is not null
      and nullif(r.contact_value,'') is not null
      and r.contact_channel_type in ('email','phone')
      and coalesce(r.contact_stability_class,cp.stability_class)='role_holder'
      and coalesce(r.contact_scope,cp.contact_scope) not in ('general_switchboard','supplier_registration')
      and coalesce(r.contact_confidence,cp.confidence,0)>=0.90
      and nullif(cp.source_authority,'') is not null
      and nullif(cp.source_url,'') is not null
      and (coalesce(r.contact_verify_after,cp.verify_after) is null or coalesce(r.contact_verify_after,cp.verify_after)>=current_date)
      then 'VERIFIED DIRECT'
    when r.contact_point_id is not null
      or nullif(r.contact_value,'') is not null
      or r.procurement_contact_point_id is not null
      or nullif(r.procurement_contact_value,'') is not null
      or r.buyer_resolution_status in ('organization_resolved','named_responsibility','possible_route','role_only')
      then 'PUBLIC / UNVERIFIED'
    else 'UNRESOLVED'
  end as contact_trust_badge,
  case
    when r.contact_point_id is not null
      and nullif(r.contact_value,'') is not null
      and r.contact_channel_type in ('email','phone')
      and coalesce(r.contact_stability_class,cp.stability_class)='role_holder'
      and coalesce(r.contact_scope,cp.contact_scope) not in ('general_switchboard','supplier_registration')
      and coalesce(r.contact_confidence,cp.confidence,0)>=0.90
      and nullif(cp.source_authority,'') is not null
      and nullif(cp.source_url,'') is not null
      and (coalesce(r.contact_verify_after,cp.verify_after) is null or coalesce(r.contact_verify_after,cp.verify_after)>=current_date)
      then 'current source-backed role-holder email/phone with >=0.90 contact confidence'
    when r.contact_point_id is not null
      or nullif(r.contact_value,'') is not null
      or r.procurement_contact_point_id is not null
      or nullif(r.procurement_contact_value,'') is not null
      then 'public contact or procurement route exists but does not satisfy direct-contact verification criteria'
    when r.buyer_resolution_status in ('organization_resolved','named_responsibility','possible_route','role_only')
      then 'buyer responsibility is partially resolved but no qualifying direct contact is established'
    else 'no usable buyer contact route is established'
  end as contact_trust_basis,
  case when coalesce(r.contact_verify_after,cp.verify_after) is not null and coalesce(r.contact_verify_after,cp.verify_after)<current_date then true else false end as contact_verification_stale,
  r.procurement_status,
  r.refreshed_at
from resolved r
left join core.organization_contact_points cp on cp.id=r.contact_point_id;
