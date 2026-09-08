-- Physical facilities-management program + awardee resolution queues v1
-- Research-only. Collapses individual awards into program families, extracts conservative
-- vendor-name candidates, and makes the remaining site-scope work explicit.

create or replace view research.v_physical_fm_program_families as
with awarded as (
  select
    a.*,
    regexp_replace(lower(a.title),'[^a-z0-9]+',' ','g') as normalized_program_title
  from research.v_physical_portfolio_unlock_acquisitions a
  where a.procurement_stage='awarded'
    and a.is_physical_portfolio_unlock_candidate
), grouped as (
  select
    md5(concat_ws('|',source_slug,coalesce(buyer_office,buyer_subtier,buyer_name,'unknown'),normalized_program_title)) as program_key,
    source_slug,
    buyer_name,
    buyer_subtier,
    buyer_office,
    normalized_program_title,
    (array_agg(title order by latest_posted_at desc nulls last))[1] as program_title,
    count(*) as acquisition_award_count,
    array_remove(array_agg(distinct solicitation_number),null) as solicitation_numbers,
    array_remove(array_agg(distinct acquisition_family_key),null) as acquisition_family_keys,
    array_remove(array_agg(distinct x.award_number),null) as award_numbers,
    array_remove(array_agg(distinct y.awardee),null) as awardees,
    bool_or(has_broad_physical_facilities_scope) as has_broad_physical_facilities_scope,
    bool_or(has_multi_site_physical_trade_scope) as has_multi_site_physical_trade_scope,
    bool_or(has_surface_work_scope) as has_surface_work_scope,
    min(first_posted_at) as first_posted_at,
    max(latest_posted_at) as latest_posted_at,
    max(latest_archive_at) as latest_archive_at
  from awarded a
  left join lateral unnest(coalesce(a.award_numbers,array[]::text[])) x(award_number) on true
  left join lateral unnest(coalesce(a.awardees,array[]::text[])) y(awardee) on true
  group by source_slug,buyer_name,buyer_subtier,buyer_office,normalized_program_title
)
select
  g.*,
  cardinality(g.awardees) as distinct_awardee_count,
  case
    when g.normalized_program_title ~ '(commander fleet activities yokosuka|cfay).*(atsugi)|atsugi.*(commander fleet activities yokosuka|cfay)'
      then 'named_installations_explicit'
    when g.normalized_program_title ~ 'aor [0-9].*aor [0-9]'
      then 'aor_scope_requires_authoritative_site_list'
    when g.normalized_program_title ~ 'various government installations'
      then 'regional_scope_requires_installation_crosswalk'
    when g.normalized_program_title ~ 'various locations'
      then 'various_locations_require_site_crosswalk'
    else 'site_scope_unresolved'
  end as site_scope_status,
  case
    when g.has_surface_work_scope and g.has_multi_site_physical_trade_scope then 'surface_trade_portfolio'
    when g.has_multi_site_physical_trade_scope then 'multi_site_physical_trade'
    when g.has_broad_physical_facilities_scope then 'broad_facilities_om'
    else 'physical_portfolio_scope_unresolved'
  end as program_scope_class,
  false as child_propagation_authorized,
  'Program evidence can resolve winning contractors and broad scope, but specific Scout facilities/assets require an authoritative site crosswalk.'::text as propagation_note
from grouped g;

comment on view research.v_physical_fm_program_families is
  'Research-only grouping of awarded physical-FM acquisition families into underlying programs/vehicles. It prevents one MATOC with many awardees from appearing as many unrelated portfolio events.';

create or replace view research.v_physical_fm_awardee_resolution_queue as
with awardee_rows as (
  select
    p.program_key,
    p.program_title,
    p.program_scope_class,
    p.site_scope_status,
    p.buyer_name,
    p.buyer_subtier,
    p.buyer_office,
    p.solicitation_numbers,
    unnest(p.awardees) as awardee_raw
  from research.v_physical_fm_program_families p
), parsed as (
  select
    a.*,
    coalesce(
      substring(a.awardee_raw from '^(.+?(LLC|INC\.?|LIMITED LIABILITY COMPANY|CO\.,? LTD\.?|CO\.? LTD\.?|CORPORATION|CORP\.?|COMPANY))([[:space:]]|$)'),
      a.awardee_raw
    ) as vendor_name_candidate
  from awardee_rows a
), normalized as (
  select
    p.*,
    regexp_replace(lower(p.vendor_name_candidate),'[^a-z0-9]+','','g') as normalized_vendor_candidate,
    (p.vendor_name_candidate <> p.awardee_raw) as parser_confident
  from parsed p
), org_terms as (
  select
    o.id as organization_id,
    o.canonical_name,
    o.organization_type,
    regexp_replace(lower(o.canonical_name),'[^a-z0-9]+','','g') as normalized_org_name
  from core.organizations o
  where o.status='active'
  union all
  select
    o.id,
    o.canonical_name,
    o.organization_type,
    regexp_replace(lower(a.alias),'[^a-z0-9]+','','g')
  from core.organizations o
  join core.organization_aliases a on a.organization_id=o.id
  where o.status='active'
), matches as (
  select distinct on (n.program_key,n.awardee_raw)
    n.*,
    t.organization_id,
    t.canonical_name as matched_organization_name,
    t.organization_type as matched_organization_type
  from normalized n
  left join org_terms t on t.normalized_org_name=n.normalized_vendor_candidate
  order by n.program_key,n.awardee_raw,t.organization_id nulls last
)
select
  m.*,
  (m.organization_id is not null) as organization_resolved,
  case
    when m.organization_id is not null then 'exact_normalized_org_or_alias_match'
    when not m.parser_confident then 'awardee_name_parser_review'
    else 'unresolved_awardee_identity'
  end as resolution_status,
  case
    when m.organization_id is not null then 'none'
    when not m.parser_confident then 'review_vendor_name_boundary_then_resolve'
    else 'resolve_vendor_to_canonical_organization'
  end as next_action,
  false as auto_create_organization_authorized
from matches m;

comment on view research.v_physical_fm_awardee_resolution_queue is
  'Research-only winning-contractor identity queue. Exact matches are surfaced, unresolved awardees remain queued, and automatic core organization creation is explicitly disabled.';

create or replace view research.v_physical_fm_site_scope_queue as
select
  p.program_key,
  p.program_title,
  p.program_scope_class,
  p.site_scope_status,
  p.buyer_name,
  p.buyer_subtier,
  p.buyer_office,
  p.solicitation_numbers,
  p.award_numbers,
  p.awardees,
  p.distinct_awardee_count,
  p.has_surface_work_scope,
  p.has_broad_physical_facilities_scope,
  p.has_multi_site_physical_trade_scope,
  case p.site_scope_status
    when 'named_installations_explicit' then 'resolve named installations to Scout organization/facility graph and verify exact contract inclusion'
    when 'aor_scope_requires_authoritative_site_list' then 'obtain authoritative AOR/site list from solicitation/contract attachments, then intersect with Scout institutions'
    when 'regional_scope_requires_installation_crosswalk' then 'extract authoritative installation list from solicitation/award documents; state-level scope alone is insufficient'
    when 'various_locations_require_site_crosswalk' then 'extract authoritative location/site schedule from solicitation/award documents'
    else 'inspect authoritative solicitation/award attachments for explicit site scope'
  end as next_collection_action,
  case
    when p.has_surface_work_scope and p.site_scope_status='named_installations_explicit' then 1
    when p.has_surface_work_scope then 2
    when p.has_broad_physical_facilities_scope then 3
    else 4
  end as resolution_priority,
  false as child_propagation_authorized
from research.v_physical_fm_program_families p;

comment on view research.v_physical_fm_site_scope_queue is
  'Research-only queue for the exact site/installation crosswalk required before an awarded FM or physical-trade vehicle may propagate to Scout facilities/assets.';

create or replace view research.v_physical_fm_program_resolution_summary as
select
  (select count(*) from research.v_physical_fm_program_families) as awarded_programs,
  (select coalesce(sum(distinct_awardee_count),0) from research.v_physical_fm_program_families) as program_awardee_slots,
  (select count(*) from research.v_physical_fm_awardee_resolution_queue) as awardee_rows,
  (select count(*) from research.v_physical_fm_awardee_resolution_queue where organization_resolved) as awardees_resolved_to_existing_org,
  (select count(*) from research.v_physical_fm_awardee_resolution_queue where resolution_status='awardee_name_parser_review') as awardee_parser_reviews,
  (select count(*) from research.v_physical_fm_site_scope_queue where site_scope_status='named_installations_explicit') as programs_with_named_installations,
  (select count(*) from research.v_physical_fm_site_scope_queue where site_scope_status<>'named_installations_explicit') as programs_requiring_site_crosswalk;

comment on view research.v_physical_fm_program_resolution_summary is
  'Research-only closure metrics for physical-FM awarded programs, contractor identity resolution, and remaining site-scope crosswalks.';

revoke all on research.v_physical_fm_program_families from anon,authenticated;
revoke all on research.v_physical_fm_awardee_resolution_queue from anon,authenticated;
revoke all on research.v_physical_fm_site_scope_queue from anon,authenticated;
revoke all on research.v_physical_fm_program_resolution_summary from anon,authenticated;

grant select on research.v_physical_fm_program_families to service_role;
grant select on research.v_physical_fm_awardee_resolution_queue to service_role;
grant select on research.v_physical_fm_site_scope_queue to service_role;
grant select on research.v_physical_fm_program_resolution_summary to service_role;
