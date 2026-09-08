-- Scout physical facilities portfolio resolver v1
-- Research-only precision layer for procurement contracts that may unlock facility portfolios.
-- Separates one-off physical work from broad facilities-management vehicles and refuses
-- to propagate contract relationships to facilities/assets without explicit scope resolution.

create or replace view research.v_physical_facilities_contract_signals as
with base as (
  select
    f.*,
    coalesce(nullif(btrim(f.solicitation_number),''),'notice:' || f.source_native_id) as acquisition_native_key,
    coalesce(nullif(btrim(f.buyer_office),''),nullif(btrim(f.buyer_subtier),''),nullif(btrim(f.buyer_name),''),'unknown') as buyer_family_key,
    (f.corpus ~ '(facility|facilities|building|buildings|installation|installations|campus|campuses|base|bases|barracks|hangar|warehouse|real property|grounds|civil works|roof|roofs|building envelope|utility plant|wastewater treatment|water treatment|parking structure|parking garage|school|hospital|clinic)') as has_physical_asset_context,
    (f.corpus ~ '(maintenance|repair|renovation|construction|painting|repaint|coating|roofing|masonry|waterproof|janitorial|cleaning|groundskeeping|operations and maintenance|facility support|facilities support|base operations support)') as has_physical_work_context,
    (coalesce(f.naics_code,'') ~ '^(236|237|238)' or coalesce(f.naics_code,'') in ('561210','561720','561730')) as has_physical_trade_naics,
    (f.corpus ~ '(base operations support|facilit(y|ies) support services|facility maintenance|facilities maintenance|building maintenance|real property maintenance|medical facilities operations and maintenance|operations and maintenance.{0,60}(facilit(y|ies)|building|real property|installation|base)|(?:facilit(y|ies)|building|real property|installation|base).{0,60}operations and maintenance)') as has_broad_physical_fm_phrase,
    (f.corpus ~ '((construction|renovation|repair|roofing|painting|coating).{0,80}(various|multiple|all).{0,50}(facilit(y|ies)|buildings|installations|sites|locations))|((various|multiple|all).{0,50}(facilit(y|ies)|buildings|installations|sites|locations).{0,80}(construction|renovation|repair|roofing|painting|coating)))') as has_multi_site_physical_trade_phrase,
    (f.corpus ~ '(information technology|software|cyber|network operations|application support|identity management|help desk|cloud services|windows 11|technology upgrade|fire alarm reporting system|aerial target|aircraft maintenance|vehicle maintenance|generator repair|kitchen equipment|medical equipment|weapon systems|training services|administrative support|human resources)') as has_nonphysical_or_equipment_domain,
    (f.corpus ~ '(construction|renovation|roof|roofing|building envelope|real property|civil works|painting|coating|masonry|waterproof)') as has_hard_physical_trade_scope
  from procurement.v_facilities_contract_signals f
), classified as (
  select
    b.*,
    case
      when b.has_nonphysical_or_equipment_domain
           and not (b.has_physical_trade_naics and b.has_hard_physical_trade_scope)
        then 'nonphysical_om_or_equipment'
      when b.is_on_call_vehicle
           and b.has_multi_site_physical_trade_phrase
           and (b.has_physical_trade_naics or b.is_surface_work_scope or b.has_hard_physical_trade_scope)
        then 'multi_site_physical_trade_vehicle'
      when (b.is_on_call_vehicle or b.is_multi_asset_scope)
           and b.has_broad_physical_fm_phrase
           and (b.has_physical_asset_context or b.has_physical_trade_naics)
        then 'broad_physical_facilities_vehicle'
      when b.has_physical_asset_context and b.has_physical_work_context
        then 'specific_physical_facility_work'
      else 'scope_unresolved'
    end as physical_scope_class
  from base b
)
select
  c.*,
  (c.physical_scope_class in ('broad_physical_facilities_vehicle','multi_site_physical_trade_vehicle')) as is_physical_portfolio_unlock_candidate,
  case
    when c.physical_scope_class = 'broad_physical_facilities_vehicle' then 'strong'
    when c.physical_scope_class = 'multi_site_physical_trade_vehicle' then 'strong_trade_vehicle'
    when c.physical_scope_class = 'specific_physical_facility_work' then 'asset_specific_only'
    when c.physical_scope_class = 'nonphysical_om_or_equipment' then 'rejected_nonphysical'
    else 'unresolved'
  end as physical_scope_strength
from classified c;

comment on view research.v_physical_facilities_contract_signals is
  'Research-only procurement classifier. Distinguishes broad physical facilities-management vehicles from one-off physical work and nonphysical/equipment O&M. No portfolio propagation is authorized by this view.';

create or replace view research.v_physical_portfolio_unlock_acquisitions as
with family_flags as (
  select
    p.source_slug,
    p.acquisition_native_key,
    p.buyer_family_key,
    count(*) as classified_notice_versions,
    bool_or(p.is_physical_portfolio_unlock_candidate) as is_physical_portfolio_unlock_candidate,
    bool_or(p.physical_scope_class = 'broad_physical_facilities_vehicle') as has_broad_physical_facilities_scope,
    bool_or(p.physical_scope_class = 'multi_site_physical_trade_vehicle') as has_multi_site_physical_trade_scope,
    bool_or(p.physical_scope_class = 'specific_physical_facility_work') as has_specific_physical_work,
    bool_or(p.has_nonphysical_or_equipment_domain) as has_nonphysical_or_equipment_domain,
    bool_or(p.is_surface_work_scope) as has_surface_work_scope,
    array_agg(distinct p.physical_scope_class order by p.physical_scope_class) as physical_scope_classes
  from research.v_physical_facilities_contract_signals p
  group by p.source_slug,p.acquisition_native_key,p.buyer_family_key
)
select
  a.*,
  ff.classified_notice_versions,
  ff.has_broad_physical_facilities_scope,
  ff.has_multi_site_physical_trade_scope,
  ff.has_specific_physical_work,
  ff.has_nonphysical_or_equipment_domain,
  ff.has_surface_work_scope,
  ff.physical_scope_classes,
  ff.is_physical_portfolio_unlock_candidate,
  case
    when not ff.is_physical_portfolio_unlock_candidate then 'not_eligible_for_portfolio_propagation'
    when a.procurement_stage in ('market_research','presolicitation') then 'preaward_account_signal_only'
    when a.procurement_stage = 'solicitation' then 'solicitation_account_signal_only'
    when a.procurement_stage = 'awarded' and ff.has_multi_site_physical_trade_scope then 'awarded_scope_requires_site_crosswalk'
    when a.procurement_stage = 'awarded' and ff.has_broad_physical_facilities_scope then 'awarded_account_relationship_scope_unresolved'
    else 'scope_requires_review'
  end as propagation_gate,
  case
    when a.procurement_stage = 'awarded' and ff.is_physical_portfolio_unlock_candidate then 'strong_account_evidence'
    when a.procurement_stage = 'solicitation' and ff.is_physical_portfolio_unlock_candidate and a.response_window_open then 'strong_preaward_account_evidence'
    when ff.is_physical_portfolio_unlock_candidate then 'early_or_historical_account_evidence'
    else 'none'
  end as physical_fm_evidence_strength
from procurement.v_acquisition_families a
join family_flags ff
  on ff.source_slug = a.source_slug
 and ff.acquisition_native_key = a.acquisition_native_key
 and ff.buyer_family_key = a.buyer_family_key
where ff.is_physical_portfolio_unlock_candidate
   or ff.has_specific_physical_work;

comment on view research.v_physical_portfolio_unlock_acquisitions is
  'Research-only acquisition-family view. Broad physical FM vehicles may resolve an account relationship, but awarded vehicles still require explicit site/portfolio crosswalk before child facilities/assets can inherit the relationship.';

create or replace view research.v_physical_fm_org_resolution as
with acquisition_corpus as (
  select
    a.acquisition_family_key,
    a.source_slug,
    a.solicitation_number,
    a.title,
    a.procurement_stage,
    a.propagation_gate,
    a.physical_fm_evidence_strength,
    a.has_broad_physical_facilities_scope,
    a.has_multi_site_physical_trade_scope,
    a.has_surface_work_scope,
    a.award_numbers,
    a.awardees,
    regexp_replace(lower(string_agg(distinct left(p.corpus,5000),' ')),'[^a-z0-9]+',' ','g') as normalized_corpus
  from research.v_physical_portfolio_unlock_acquisitions a
  join research.v_physical_facilities_contract_signals p
    on p.source_slug = a.source_slug
   and p.acquisition_native_key = a.acquisition_native_key
   and p.buyer_family_key = a.buyer_family_key
  where a.is_physical_portfolio_unlock_candidate
  group by
    a.acquisition_family_key,a.source_slug,a.solicitation_number,a.title,a.procurement_stage,
    a.propagation_gate,a.physical_fm_evidence_strength,a.has_broad_physical_facilities_scope,
    a.has_multi_site_physical_trade_scope,a.has_surface_work_scope,a.award_numbers,a.awardees
), eligible_orgs as (
  select
    o.id as organization_id,
    o.canonical_name,
    o.organization_type,
    regexp_replace(lower(o.canonical_name),'[^a-z0-9]+',' ','g') as canonical_term
  from core.organizations o
  where o.status = 'active'
    and o.organization_type in (
      'military_installation','federal_healthcare','postsecondary_institution','school_district',
      'health_system','water_utility','municipal_government','county_government',
      'state_transportation_agency','public_utility','special_district_utility'
    )
), term_rows as (
  select e.organization_id,e.canonical_name,e.organization_type,btrim(e.canonical_term) as match_term,'canonical_name'::text as term_basis
  from eligible_orgs e
  union all
  select e.organization_id,e.canonical_name,e.organization_type,
         btrim(regexp_replace(e.canonical_term,'^(u s |us |united states )?(army|air force|navy|marine corps) ','')),
         'military_short_name'::text
  from eligible_orgs e
  where e.organization_type = 'military_installation'
  union all
  select e.organization_id,e.canonical_name,e.organization_type,
         btrim(regexp_replace(lower(a.alias),'[^a-z0-9]+',' ','g')),
         'organization_alias'::text
  from eligible_orgs e
  join core.organization_aliases a on a.organization_id=e.organization_id
), usable_terms as (
  select distinct *
  from term_rows
  where length(match_term) >= 8
    and match_term like '% %'
    and match_term not in ('state of indiana','state of kentucky','state of ohio','united states government')
), matches as (
  select
    ac.*,
    t.organization_id,
    t.canonical_name as organization_name,
    t.organization_type,
    t.match_term,
    t.term_basis,
    case
      when t.term_basis = 'military_short_name' then 0.99::numeric
      when t.term_basis = 'organization_alias' then 0.97::numeric
      else 0.95::numeric
    end as resolution_confidence
  from acquisition_corpus ac
  join usable_terms t
    on position(' ' || t.match_term || ' ' in ' ' || ac.normalized_corpus || ' ') > 0
), child_counts as (
  select
    o.id as organization_id,
    count(distinct f.id) as facility_count,
    count(distinct l.id) as asset_link_count,
    coalesce((
      select jsonb_object_agg(x.facility_class,x.n)
      from (
        select f2.facility_class,count(*) as n
        from core.organization_facilities f2
        where f2.organization_id=o.id
        group by f2.facility_class
      ) x
    ),'{}'::jsonb) as facility_classes,
    coalesce((
      select jsonb_object_agg(x.asset_namespace,x.n)
      from (
        select l2.asset_namespace,count(*) as n
        from core.organization_asset_links l2
        where l2.organization_id=o.id
        group by l2.asset_namespace
      ) x
    ),'{}'::jsonb) as asset_namespaces
  from core.organizations o
  left join core.organization_facilities f on f.organization_id=o.id
  left join core.organization_asset_links l on l.organization_id=o.id
  group by o.id
)
select
  m.acquisition_family_key,
  m.source_slug,
  m.solicitation_number,
  m.title,
  m.procurement_stage,
  m.propagation_gate,
  m.physical_fm_evidence_strength,
  m.has_broad_physical_facilities_scope,
  m.has_multi_site_physical_trade_scope,
  m.has_surface_work_scope,
  m.award_numbers,
  m.awardees,
  m.organization_id,
  m.organization_name,
  m.organization_type,
  m.match_term,
  m.term_basis,
  m.resolution_confidence,
  coalesce(cc.facility_count,0) as facility_count,
  coalesce(cc.asset_link_count,0) as asset_link_count,
  coalesce(cc.facility_count,0) + coalesce(cc.asset_link_count,0) as known_child_count,
  coalesce(cc.facility_classes,'{}'::jsonb) as facility_classes,
  coalesce(cc.asset_namespaces,'{}'::jsonb) as asset_namespaces,
  true as account_resolved,
  (m.has_multi_site_physical_trade_scope or m.has_broad_physical_facilities_scope) as portfolio_scope_candidate,
  ((coalesce(cc.facility_count,0) + coalesce(cc.asset_link_count,0)) > 0) as child_graph_available,
  case
    when m.procurement_stage <> 'awarded' then 'account_match_only_preaward'
    when (coalesce(cc.facility_count,0) + coalesce(cc.asset_link_count,0)) = 0 then 'account_resolved_child_graph_missing'
    when m.has_multi_site_physical_trade_scope then 'site_crosswalk_required_before_child_propagation'
    when m.has_broad_physical_facilities_scope then 'portfolio_scope_resolution_required_before_child_propagation'
    else 'no_child_propagation'
  end as resolution_status
from matches m
left join child_counts cc on cc.organization_id=m.organization_id;

comment on view research.v_physical_fm_org_resolution is
  'Research-only deterministic organization resolver for broad physical-FM procurement families. Name/alias evidence can resolve an account, but does not by itself prove that every child facility/asset is in contract scope.';

create or replace view research.v_physical_fm_child_propagation_probe as
with resolved as (
  select *
  from research.v_physical_fm_org_resolution
  where procurement_stage='awarded'
    and resolution_confidence >= 0.95
    and child_graph_available
), facility_children as (
  select
    r.acquisition_family_key,r.source_slug,r.solicitation_number,r.title,r.organization_id,r.organization_name,
    r.resolution_confidence,r.resolution_status,
    'facility'::text as child_kind,
    f.facility_class as child_namespace,
    f.id as child_id,
    f.site_name as child_name,
    f.site_address_text as child_address,
    f.relationship_type as existing_relationship_type,
    f.confidence as existing_relationship_confidence
  from resolved r
  join core.organization_facilities f on f.organization_id=r.organization_id
), asset_children as (
  select
    r.acquisition_family_key,r.source_slug,r.solicitation_number,r.title,r.organization_id,r.organization_name,
    r.resolution_confidence,r.resolution_status,
    'asset'::text as child_kind,
    l.asset_namespace as child_namespace,
    l.asset_id as child_id,
    null::text as child_name,
    null::text as child_address,
    l.relationship_type as existing_relationship_type,
    l.confidence as existing_relationship_confidence
  from resolved r
  join core.organization_asset_links l on l.organization_id=r.organization_id
)
select *,
  false as propagation_authorized,
  'Probe only: contract scope must be crosswalked to the specific child before any contractor/account relationship is written.'::text as propagation_note
from facility_children
union all
select *,
  false as propagation_authorized,
  'Probe only: contract scope must be crosswalked to the specific child before any contractor/account relationship is written.'::text as propagation_note
from asset_children;

comment on view research.v_physical_fm_child_propagation_probe is
  'Research-only maximum-potential child set for awarded, account-resolved physical-FM contracts. propagation_authorized is always false until explicit contract-to-site scope evidence exists.';

create or replace view research.v_physical_fm_resolution_summary as
select
  count(*) as organization_matches,
  count(distinct acquisition_family_key) as acquisition_families_with_org_match,
  count(*) filter (where procurement_stage='awarded') as awarded_org_matches,
  count(*) filter (where procurement_stage='awarded' and child_graph_available) as awarded_org_matches_with_child_graph,
  count(*) filter (where procurement_stage='awarded' and not child_graph_available) as awarded_org_matches_missing_child_graph,
  coalesce(sum(known_child_count) filter (where procurement_stage='awarded' and child_graph_available),0) as maximum_potential_children_before_scope_crosswalk
from research.v_physical_fm_org_resolution;

comment on view research.v_physical_fm_resolution_summary is
  'Research-only closure metrics for physical-FM account and child-graph resolution. Maximum potential children are not authorized contract relationships.';

revoke all on research.v_physical_facilities_contract_signals from anon,authenticated;
revoke all on research.v_physical_portfolio_unlock_acquisitions from anon,authenticated;
revoke all on research.v_physical_fm_org_resolution from anon,authenticated;
revoke all on research.v_physical_fm_child_propagation_probe from anon,authenticated;
revoke all on research.v_physical_fm_resolution_summary from anon,authenticated;

grant select on research.v_physical_facilities_contract_signals to service_role;
grant select on research.v_physical_portfolio_unlock_acquisitions to service_role;
grant select on research.v_physical_fm_org_resolution to service_role;
grant select on research.v_physical_fm_child_propagation_probe to service_role;
grant select on research.v_physical_fm_resolution_summary to service_role;
