-- Additive replacement for documented site-responsibility materialization.
-- Leaves the earlier candidate view in place but unused so deployment does not
-- require destructive DDL. Matching is performed against a bounded indexed
-- transaction-local cache of documented facilities.

create or replace function scout.materialize_documented_site_responsibility_v1(
  p_candidate_keys text[] default null::text[]
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_inserted integer:=0;
  v_managers integer:=0;
  v_operators integer:=0;
begin
  drop table if exists pg_temp.site_responsibility_facilities;
  create temporary table site_responsibility_facilities on commit drop as
  select 'property_manager'::text party_role,
         f.organization_id,
         f.management_company_name party_name,
         f.site_name,
         f.site_address_text,
         scout.normalize_address_key_v2(f.site_address_text) address_key,
         scout.normalize_state_code(f.state) state_code,
         f.confidence,f.source_url,f.source_authority,
         f.organization_facility_id,f.source_record_id,
         f.first_observed_at,f.last_observed_at
  from scout.v_property_management_facilities f
  where f.confidence>=0.95
    and f.relationship_status in ('observed','current')
    and (f.valid_to is null or f.valid_to>=current_date)
    and f.portfolio_asset_status in ('operating','lease_up')
    and f.organization_id is not null
    and nullif(btrim(f.management_company_name),'') is not null
    and nullif(btrim(f.source_url),'') is not null
    and scout.normalize_address_key_v2(f.site_address_text)<>''
  union all
  select 'operator'::text,
         f.organization_id,f.account_name,f.site_name,f.site_address_text,
         scout.normalize_address_key_v2(f.site_address_text),f.state_code,
         f.confidence,f.source_url,f.source_authority,
         f.organization_facility_id,f.source_record_id,
         f.first_observed_at,f.last_observed_at
  from scout.v_portfolio_account_facilities f
  where f.relationship_type='operates'
    and f.confidence>=0.95
    and f.relationship_status in ('observed','current')
    and f.portfolio_asset_status in ('operating','lease_up')
    and f.organization_id is not null
    and nullif(btrim(f.account_name),'') is not null
    and nullif(btrim(f.source_url),'') is not null
    and scout.normalize_address_key_v2(f.site_address_text)<>'';

  create index site_responsibility_facilities_addr_idx
    on site_responsibility_facilities(address_key,state_code,party_role);

  drop table if exists pg_temp.site_responsibility_candidates;
  create temporary table site_responsibility_candidates on commit drop as
  with unresolved as (
    select q.candidate_key,q.source_kind,q.address_hint,
           scout.normalize_address_key_v2(q.address_hint) address_key,
           s.state_code
    from scout.buyer_resolution_queue q
    join scout.opportunity_search_spine s using(candidate_key)
    where q.state in ('pending','researching')
      and q.next_attempt_at<=now()
      and q.missing_steps @> array['organization_resolution']::text[]
      and nullif(btrim(q.buyer_hint),'') is null
      and q.source_kind in ('construction_window','exterior_cleaning','roof_lifecycle')
      and coalesce(s.global_suppressed,false)=false
      and scout.normalize_address_key_v2(q.address_hint)<>''
      and (p_candidate_keys is null or q.candidate_key=any(p_candidate_keys))
  ), manager_linked as (
    select u.candidate_key,u.source_kind,'property_manager'::text party_role,
           p.organization_id,p.management_company_name party_name,
           p.managed_property_name site_name,u.address_hint site_address_text,
           p.link_confidence confidence,p.source_url,p.source_authority,
           null::uuid organization_facility_id,
           p.property_source_record_id source_record_id,
           'canonical_building_or_property_link'::text match_basis,
           1 match_rank,null::timestamptz first_observed_at,null::timestamptz last_observed_at
    from unresolved u
    join scout.v_opportunity_property_manager_links p using(candidate_key)
    where p.link_confidence>=0.95
      and p.organization_id is not null
      and nullif(btrim(p.management_company_name),'') is not null
      and nullif(btrim(p.source_url),'') is not null
  ), address_matched as (
    select u.candidate_key,u.source_kind,f.party_role,
           f.organization_id,f.party_name,f.site_name,f.site_address_text,
           f.confidence,f.source_url,f.source_authority,
           f.organization_facility_id,f.source_record_id,
           'exact_normalized_site_address_and_state'::text match_basis,
           2 match_rank,f.first_observed_at,f.last_observed_at
    from unresolved u
    join site_responsibility_facilities f
      on f.address_key=u.address_key and f.state_code=u.state_code
  ), raw as (
    select * from manager_linked
    union all
    select * from address_matched
  ), role_roll as (
    select candidate_key,party_role,count(distinct organization_id) distinct_organization_count
    from raw group by candidate_key,party_role
  ), ranked as (
    select r.*,
           row_number() over(
             partition by r.candidate_key,r.party_role
             order by r.match_rank,r.confidence desc,r.last_observed_at desc nulls last,r.source_url
           ) rn
    from raw r join role_roll x using(candidate_key,party_role)
    where x.distinct_organization_count=1
  )
  select candidate_key,source_kind,party_role,organization_id,party_name,site_name,
         site_address_text,confidence,source_url,source_authority,
         organization_facility_id,source_record_id,match_basis,
         first_observed_at,last_observed_at
  from ranked where rn=1;

  insert into scout.opportunity_responsible_party_evidence(
    candidate_key,party_role,party_name,party_name_normalized,party_kind,
    organization_id,site_address_text,evidence_class,confidence,
    source_url,source_authority,observed_on,attributes,updated_at
  )
  select c.candidate_key,c.party_role,c.party_name,
         public.scout_normalize_business_name(c.party_name),'organization',
         c.organization_id,c.site_address_text,'documented',c.confidence,
         c.source_url,c.source_authority,
         coalesce(c.last_observed_at,c.first_observed_at)::date,
         jsonb_build_object(
           'resolution_scope','documented_site_responsibility',
           'match_basis',c.match_basis,'source_kind',c.source_kind,
           'site_name',c.site_name,
           'organization_facility_id',c.organization_facility_id,
           'source_record_id',c.source_record_id,
           'buyer_authority_not_implied',true,'ownership_not_implied',true,
           'operator_not_implied',c.party_role<>'operator',
           'property_manager_not_implied',c.party_role<>'property_manager',
           'outbound_contact_performed',false
         ),now()
  from site_responsibility_candidates c
  on conflict(candidate_key,party_role,party_name_normalized,source_url) do update set
    organization_id=excluded.organization_id,
    site_address_text=excluded.site_address_text,
    evidence_class=excluded.evidence_class,
    confidence=greatest(scout.opportunity_responsible_party_evidence.confidence,excluded.confidence),
    source_authority=excluded.source_authority,
    observed_on=coalesce(excluded.observed_on,scout.opportunity_responsible_party_evidence.observed_on),
    attributes=excluded.attributes,updated_at=now();
  get diagnostics v_inserted=row_count;

  select count(*) filter(where party_role='property_manager'),
         count(*) filter(where party_role='operator')
  into v_managers,v_operators from site_responsibility_candidates;

  return jsonb_build_object(
    'evidence_upserted',v_inserted,'manager_candidates',v_managers,
    'operator_evidence_candidates',v_operators,
    'cached_facilities',(select count(*) from site_responsibility_facilities)
  );
end
$$;

revoke all on function scout.materialize_documented_site_responsibility_v1(text[])
  from public,anon,authenticated;
grant execute on function scout.materialize_documented_site_responsibility_v1(text[]) to service_role;

do $$
declare v_def text;
begin
  select pg_get_functiondef('scout.materialize_documented_site_responsibility_v1(text[])'::regprocedure) into v_def;
  if v_def not like '%create temporary table site_responsibility_facilities%'
     or v_def not like '%buyer_authority_not_implied%true%'
     or v_def not like '%outbound_contact_performed%false%' then
    raise exception 'documented site-responsibility matching guard regression';
  end if;
end
$$;
