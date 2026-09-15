create or replace view scout.v_documented_site_responsibility_candidates_v1
with (security_invoker=true)
as
with manager_facilities as materialized (
  select f.organization_id,f.management_company_name party_name,f.site_name,f.site_address_text,
         scout.normalize_address_key_v2(f.site_address_text) address_key,
         scout.normalize_state_code(f.state) state_code,f.confidence,f.source_url,f.source_authority,
         f.organization_facility_id,f.source_record_id,f.first_observed_at,f.last_observed_at
  from scout.v_property_management_facilities f
  where f.confidence>=0.95 and f.relationship_status in ('observed','current')
    and (f.valid_to is null or f.valid_to>=current_date)
    and f.portfolio_asset_status in ('operating','lease_up')
    and f.organization_id is not null and nullif(btrim(f.management_company_name),'') is not null
    and nullif(btrim(f.source_url),'') is not null
    and scout.normalize_address_key_v2(f.site_address_text)<>''
), operator_facilities as materialized (
  select f.organization_id,f.account_name party_name,f.site_name,f.site_address_text,
         scout.normalize_address_key_v2(f.site_address_text) address_key,f.state_code,
         f.confidence,f.source_url,f.source_authority,f.organization_facility_id,
         f.source_record_id,f.first_observed_at,f.last_observed_at
  from scout.v_portfolio_account_facilities f
  where f.relationship_type='operates' and f.confidence>=0.95
    and f.relationship_status in ('observed','current')
    and f.portfolio_asset_status in ('operating','lease_up')
    and f.organization_id is not null and nullif(btrim(f.account_name),'') is not null
    and nullif(btrim(f.source_url),'') is not null
    and scout.normalize_address_key_v2(f.site_address_text)<>''
), unresolved as materialized (
  select q.candidate_key,q.source_kind,q.address_hint,
         scout.normalize_address_key_v2(q.address_hint) address_key,s.state_code
  from scout.buyer_resolution_queue q
  join scout.opportunity_search_spine s using(candidate_key)
  where q.state in ('pending','researching') and q.next_attempt_at<=now()
    and q.missing_steps @> array['organization_resolution']::text[]
    and nullif(btrim(q.buyer_hint),'') is null
    and q.source_kind in ('construction_window','exterior_cleaning','roof_lifecycle')
    and coalesce(s.global_suppressed,false)=false
    and scout.normalize_address_key_v2(q.address_hint)<>''
), raw as (
  select u.candidate_key,u.source_kind,'property_manager'::text party_role,
         f.organization_id,f.party_name,f.site_name,f.site_address_text,f.confidence,
         f.source_url,f.source_authority,f.organization_facility_id,f.source_record_id,
         'exact_normalized_site_address_and_state'::text match_basis,2 match_rank,
         f.first_observed_at,f.last_observed_at
  from unresolved u join manager_facilities f on f.address_key=u.address_key and f.state_code=u.state_code
  union all
  select u.candidate_key,u.source_kind,'operator'::text,f.organization_id,f.party_name,
         f.site_name,f.site_address_text,f.confidence,f.source_url,f.source_authority,
         f.organization_facility_id,f.source_record_id,'exact_normalized_site_address_and_state',
         2,f.first_observed_at,f.last_observed_at
  from unresolved u join operator_facilities f on f.address_key=u.address_key and f.state_code=u.state_code
), role_roll as (
  select candidate_key,party_role,count(distinct organization_id) n from raw group by candidate_key,party_role
), ranked as (
  select r.*,row_number() over(partition by r.candidate_key,r.party_role
    order by r.match_rank,r.confidence desc,r.last_observed_at desc nulls last,r.source_url) rn
  from raw r join role_roll x using(candidate_key,party_role) where x.n=1
)
select candidate_key,source_kind,party_role,organization_id,party_name,site_name,
       site_address_text,confidence,source_url,source_authority,
       organization_facility_id,source_record_id,match_basis,first_observed_at,last_observed_at
from ranked where rn=1;
