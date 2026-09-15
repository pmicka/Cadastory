-- Materialize strong documented site-manager/operator evidence from Scout's
-- existing first-party/current portfolio relationships.
--
-- A property manager is an organization with documented site responsibility,
-- but is not automatically the buyer. An operator is evidence only in this
-- release and is never auto-promoted into buyer research.

create or replace view scout.v_documented_site_responsibility_candidates_v1
with (security_invoker=true)
as
with unresolved as (
  select q.candidate_key,q.source_kind,q.address_hint,s.state_code,s.source_id,
         s.canonical_asset_id,s.global_suppressed
  from scout.buyer_resolution_queue q
  join scout.opportunity_search_spine s using(candidate_key)
  where q.state in ('pending','researching')
    and q.next_attempt_at<=now()
    and q.missing_steps @> array['organization_resolution']::text[]
    and nullif(btrim(q.buyer_hint),'') is null
    and q.source_kind in ('construction_window','exterior_cleaning','roof_lifecycle')
    and coalesce(s.global_suppressed,false)=false
), manager_linked as (
  select u.candidate_key,u.source_kind,'property_manager'::text party_role,
         p.organization_id,p.management_company_name party_name,
         p.managed_property_name site_name,
         u.address_hint site_address_text,
         p.link_confidence confidence,p.source_url,p.source_authority,
         null::uuid organization_facility_id,
         p.property_source_record_id source_record_id,
         'canonical_building_or_property_link'::text match_basis,
         1 match_rank,
         null::timestamptz first_observed_at,
         null::timestamptz last_observed_at
  from unresolved u
  join scout.v_opportunity_property_manager_links p using(candidate_key)
  where p.link_confidence>=0.95
    and p.organization_id is not null
    and nullif(btrim(p.management_company_name),'') is not null
    and nullif(btrim(p.source_url),'') is not null
), manager_exact as (
  select u.candidate_key,u.source_kind,'property_manager'::text party_role,
         f.organization_id,f.management_company_name party_name,
         f.site_name,f.site_address_text,
         f.confidence,f.source_url,f.source_authority,
         f.organization_facility_id,f.source_record_id,
         'exact_normalized_site_address_and_state'::text match_basis,
         2 match_rank,
         f.first_observed_at,f.last_observed_at
  from unresolved u
  join scout.v_property_management_facilities f
    on scout.normalize_address_key_v2(u.address_hint)<>''
   and scout.normalize_address_key_v2(f.site_address_text)=scout.normalize_address_key_v2(u.address_hint)
   and scout.normalize_state_code(f.state)=u.state_code
  where f.confidence>=0.95
    and f.relationship_status in ('observed','current')
    and (f.valid_to is null or f.valid_to>=current_date)
    and f.portfolio_asset_status in ('operating','lease_up')
    and f.organization_id is not null
    and nullif(btrim(f.management_company_name),'') is not null
    and nullif(btrim(f.source_url),'') is not null
), operator_exact as (
  select u.candidate_key,u.source_kind,'operator'::text party_role,
         f.organization_id,f.account_name party_name,
         f.site_name,f.site_address_text,
         f.confidence,f.source_url,f.source_authority,
         f.organization_facility_id,f.source_record_id,
         'exact_normalized_site_address_and_state'::text match_basis,
         2 match_rank,
         f.first_observed_at,f.last_observed_at
  from unresolved u
  join scout.v_portfolio_account_facilities f
    on f.relationship_type='operates'
   and scout.normalize_address_key_v2(u.address_hint)<>''
   and scout.normalize_address_key_v2(f.site_address_text)=scout.normalize_address_key_v2(u.address_hint)
   and f.state_code=u.state_code
  where f.confidence>=0.95
    and f.relationship_status in ('observed','current')
    and f.portfolio_asset_status in ('operating','lease_up')
    and f.organization_id is not null
    and nullif(btrim(f.account_name),'') is not null
    and nullif(btrim(f.source_url),'') is not null
), raw as (
  select * from manager_linked
  union all select * from manager_exact
  union all select * from operator_exact
), role_roll as (
  select candidate_key,party_role,count(distinct organization_id) distinct_organization_count
  from raw
  group by candidate_key,party_role
), ranked as (
  select r.*,
         row_number() over(
           partition by r.candidate_key,r.party_role
           order by r.match_rank,r.confidence desc,r.last_observed_at desc nulls last,r.source_url
         ) rn
  from raw r
  join role_roll x using(candidate_key,party_role)
  where x.distinct_organization_count=1
)
select candidate_key,source_kind,party_role,organization_id,party_name,site_name,
       site_address_text,confidence,source_url,source_authority,
       organization_facility_id,source_record_id,match_basis,
       first_observed_at,last_observed_at
from ranked
where rn=1;

revoke all on scout.v_documented_site_responsibility_candidates_v1 from public,anon,authenticated;
grant select on scout.v_documented_site_responsibility_candidates_v1 to service_role;

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
           'match_basis',c.match_basis,
           'source_kind',c.source_kind,
           'site_name',c.site_name,
           'organization_facility_id',c.organization_facility_id,
           'source_record_id',c.source_record_id,
           'buyer_authority_not_implied',true,
           'ownership_not_implied',true,
           'operator_not_implied',c.party_role<>'operator',
           'property_manager_not_implied',c.party_role<>'property_manager',
           'outbound_contact_performed',false
         ),now()
  from scout.v_documented_site_responsibility_candidates_v1 c
  where p_candidate_keys is null or c.candidate_key=any(p_candidate_keys)
  on conflict(candidate_key,party_role,party_name_normalized,source_url) do update set
    organization_id=excluded.organization_id,
    site_address_text=excluded.site_address_text,
    evidence_class=excluded.evidence_class,
    confidence=greatest(scout.opportunity_responsible_party_evidence.confidence,excluded.confidence),
    source_authority=excluded.source_authority,
    observed_on=coalesce(excluded.observed_on,scout.opportunity_responsible_party_evidence.observed_on),
    attributes=excluded.attributes,
    updated_at=now();
  get diagnostics v_inserted=row_count;

  select count(*) filter(where party_role='property_manager'),
         count(*) filter(where party_role='operator')
  into v_managers,v_operators
  from scout.v_documented_site_responsibility_candidates_v1
  where p_candidate_keys is null or candidate_key=any(p_candidate_keys);

  return jsonb_build_object(
    'evidence_upserted',v_inserted,
    'manager_candidates',v_managers,
    'operator_evidence_candidates',v_operators
  );
end
$$;

revoke all on function scout.materialize_documented_site_responsibility_v1(text[])
  from public,anon,authenticated;
grant execute on function scout.materialize_documented_site_responsibility_v1(text[]) to service_role;

create or replace function scout.restore_responsible_party_buyer_candidates_v1(
  p_candidate_keys text[] default null::text[]
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_materialized jsonb;
  v_restored integer:=0;
  v_queue integer:=0;
begin
  v_materialized:=scout.materialize_documented_site_responsibility_v1(p_candidate_keys);

  create temporary table responsible_party_restore on commit drop as
  select * from (
    select e.candidate_key,e.party_name,e.party_role,e.organization_id,e.observed_on,
      case when e.party_role='property_manager' then 'property_manager_candidate'
           else 'property_owner_candidate' end role_code,
      case when e.party_role='property_manager' then 'facility_manager'
           else 'responsible_owner' end identity_kind,
      case when e.party_role='property_manager' then 'documented_site_manager'
           else 'authoritative_parcel_owner' end identity_basis,
      case when e.party_role='property_manager' then .97::numeric else .96::numeric end restore_confidence,
      row_number() over(
        partition by e.candidate_key
        order by case e.party_role when 'property_manager' then 1 else 2 end,
                 e.confidence desc,e.observed_on desc nulls last,e.updated_at desc
      ) rn
    from scout.opportunity_responsible_party_evidence e
    where e.party_kind='organization'
      and (
        (e.party_role='property_manager' and e.evidence_class in ('documented','corroborated') and e.confidence>=.95)
        or
        (e.party_role='property_owner' and e.evidence_class='authoritative_record' and e.confidence>=.95)
      )
      and (p_candidate_keys is null or e.candidate_key=any(p_candidate_keys))
  ) x where rn=1;

  update scout.opportunity_buyer_identities b set
    buyer_name=r.party_name,
    role_code=r.role_code,
    identity_kind=r.identity_kind,
    resolution_status='named_responsibility',
    confidence=greatest(b.confidence,r.restore_confidence),
    identity_basis=r.identity_basis,
    observed_at=coalesce(r.observed_on::timestamptz,b.observed_at),
    last_normalized_at=now()
  from responsible_party_restore r
  where b.candidate_key=r.candidate_key
    and b.organization_id is null
    and (
      b.buyer_name is null
      or b.resolution_status in ('role_only','unresolved')
      or b.identity_basis in ('decision_profile_role_only','unresolved','authoritative_parcel_owner','documented_site_manager')
    );
  get diagnostics v_restored=row_count;

  update scout.buyer_resolution_queue q set
    buyer_hint=r.party_name,
    role_code=r.role_code,
    state=case when q.state='researching' then 'researching' else 'pending' end,
    next_attempt_at=case when q.state='researching' then q.next_attempt_at else now() end,
    last_error=null,
    updated_at=now()
  from responsible_party_restore r
  where q.candidate_key=r.candidate_key
    and q.missing_steps @> array['organization_resolution']::text[]
    and nullif(btrim(q.buyer_hint),'') is null;
  get diagnostics v_queue=row_count;

  return jsonb_build_object(
    'materialized',v_materialized,
    'restored',v_restored,
    'queue_promoted',v_queue
  );
end
$$;

-- Contract guards: manager evidence may seed organization research; operator
-- evidence must remain evidence-only in this release.
do $$
declare
  v_restore text;
  v_mat text;
begin
  select pg_get_functiondef('scout.restore_responsible_party_buyer_candidates_v1(text[])'::regprocedure)
    into v_restore;
  select pg_get_functiondef('scout.materialize_documented_site_responsibility_v1(text[])'::regprocedure)
    into v_mat;

  if v_restore not like '%property_manager_candidate%'
     or v_restore not like '%documented_site_manager%'
     or v_restore like '%party_role=''operator''%property_manager_candidate%' then
    raise exception 'documented manager restore contract regression';
  end if;
  if v_mat not like '%outbound_contact_performed%false%'
     or v_mat not like '%buyer_authority_not_implied%true%' then
    raise exception 'site-responsibility evidence guard regression';
  end if;
end
$$;
