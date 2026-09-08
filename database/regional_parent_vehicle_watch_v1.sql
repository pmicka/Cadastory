-- Scout regional federal parent-vehicle watch v1
-- Research-only. Discovers physical-asset master vehicles that either:
--   1) are explicitly referenced by local KY/IN/OH task-order notices (strongest evidence),
--   2) are open local/regional vehicle solicitations, or
--   3) are local market-research notices for future vehicles.
-- No contractor->facility propagation or production scoring is authorized here.

create or replace view research.v_regional_parent_vehicle_child_references as
with local_notices as (
  select
    o.source_native_id,
    o.solicitation_number,
    o.title,
    o.notice_type,
    o.buyer_name,
    o.buyer_subtier,
    o.buyer_office,
    o.place_city,
    o.place_state,
    o.posted_at,
    o.response_deadline,
    o.description,
    lower(coalesce(o.title,'') || ' ' || coalesce(o.description,'')) as scope_text
  from procurement.opportunities o
  where o.source_slug='sam-opportunities'
    and o.place_state in ('KY','IN','OH')
    and lower(coalesce(o.title,'') || ' ' || coalesce(o.description,''))
        ~ '(matoc|idiq|indefinite delivery|task order|saber|job order|macc)'
    and lower(coalesce(o.title,'') || ' ' || coalesce(o.description,''))
        ~ '(construction|repair|rehab|refurb|fabricat|install|maintenance|lock|dam|bridge|gate|roof|paint|coat|facility|building|civil project|base engineering|utility)'
),
direct_refs as (
  select
    l.*,
    upper(m[1]) as parent_piid,
    'direct_parent_piid_reference'::text as reference_kind
  from local_notices l
  cross join lateral regexp_matches(
    coalesce(l.description,''),
    '\m([A-Z0-9]{6,8}[0-9]{2}D[0-9]{4})\M',
    'g'
  ) m
),
range_matches as (
  select
    l.*,
    upper(r[1]) as range_start,
    upper(r[3]) as range_end
  from local_notices l
  cross join lateral regexp_matches(
    coalesce(l.description,''),
    '\m([A-Z0-9]{6,8}[0-9]{2}D[0-9]{4})\M[[:space:]]*(through|thru|to|-)[[:space:]]*\m([A-Z0-9]{6,8}[0-9]{2}D[0-9]{4})\M',
    'gi'
  ) r
),
expanded_ranges as (
  select
    r.source_native_id,
    r.solicitation_number,
    r.title,
    r.notice_type,
    r.buyer_name,
    r.buyer_subtier,
    r.buyer_office,
    r.place_city,
    r.place_state,
    r.posted_at,
    r.response_deadline,
    r.description,
    r.scope_text,
    left(r.range_start,length(r.range_start)-4) || lpad(gs::text,4,'0') as parent_piid,
    'expanded_parent_piid_range'::text as reference_kind
  from range_matches r
  cross join lateral generate_series(
    right(r.range_start,4)::int,
    right(r.range_end,4)::int
  ) gs
  where left(r.range_start,length(r.range_start)-4)=left(r.range_end,length(r.range_end)-4)
    and right(r.range_end,4)::int >= right(r.range_start,4)::int
    and right(r.range_end,4)::int - right(r.range_start,4)::int <= 50
),
all_refs as (
  select * from direct_refs
  union all
  select * from expanded_ranges
)
select distinct on (source_native_id,parent_piid)
  source_native_id,
  solicitation_number,
  title,
  notice_type,
  buyer_name,
  buyer_subtier,
  buyer_office,
  place_city,
  place_state,
  posted_at,
  response_deadline,
  parent_piid,
  reference_kind,
  (scope_text ~ '(paint|coating|roof|surface prep|masonry|waterproof)') as surface_work_scope_present,
  true as local_child_work_proven,
  false as relationship_propagation_authorized
from all_refs
where parent_piid is not null;

comment on view research.v_regional_parent_vehicle_child_references is
  'Research-only strong evidence: a supported-area KY/IN/OH SAM physical-asset task-order notice explicitly references an awarded parent IDV/MATOC. Parent PIID ranges up to 50 contracts are deterministically expanded.';

create or replace view research.v_regional_parent_vehicle_open_candidates as
with ranked as (
  select
    o.*,
    lower(coalesce(o.title,'') || ' ' || coalesce(o.description,'')) as scope_text,
    row_number() over (
      partition by coalesce(nullif(btrim(o.solicitation_number),''),o.source_native_id)
      order by o.posted_at desc nulls last,o.last_observed_at desc,o.source_native_id desc
    ) as rn
  from procurement.opportunities o
  where o.source_slug='sam-opportunities'
    and o.active
    and (o.response_deadline is null or o.response_deadline >= now())
    and (
      o.place_state in ('KY','IN','OH')
      or lower(coalesce(o.description,''))
         ~ '(kentucky|indiana|ohio|fort knox|wright.?patterson|grissom|blue grass army depot|louisville aor|great lakes and ohio river)'
    )
), qualified as (
  select
    r.*,
    (scope_text ~ '(matoc|macc|saber|job order contract|\mjoc\M|multiple award task order|indefinite delivery indefinite quantity|\midiq\M)') as explicit_vehicle,
    (
      coalesce(naics_code,'') ~ '^(236|237|238)'
      or scope_text ~ '(construction|renovation|repair|base engineering|facility support|facilities support|building maintenance|civil works|roofing|painting|coating|operations and maintenance)'
    ) as physical_scope
  from ranked r
  where rn=1
)
select
  source_native_id,
  solicitation_number,
  title,
  notice_type,
  buyer_name,
  buyer_subtier,
  buyer_office,
  place_city,
  place_state,
  posted_at,
  response_deadline,
  naics_code,
  psc_code,
  case
    when notice_type ilike '%source% sought%' or scope_text ~ '(request for information|\mrfi\M|market research)'
      then 'market_research_vehicle'
    else 'open_vehicle_solicitation'
  end as vehicle_stage,
  case
    when lower(coalesce(place_city,'')) ~ '(grissom|fort knox|wright.?patterson|crane|lexington|louisville)'
      then 'named_supported_installation_or_city'
    when scope_text ~ '(louisville aor|great lakes and ohio river)'
      then 'supported_regional_aor_explicit'
    when place_state in ('KY','IN','OH')
      then 'supported_state_place_of_performance'
    else 'supported_area_text_reference'
  end as geography_evidence,
  (scope_text ~ '(paint|coating|roof|surface prep|masonry|waterproof)') as surface_work_scope_present,
  left(regexp_replace(coalesce(description,''),'[[:space:]]+',' ','g'),1200) as evidence_excerpt,
  false as relationship_propagation_authorized
from qualified
where explicit_vehicle and physical_scope
  and not (
    upper(coalesce(title,'')) ~ '(^|[^A-Z])(NSN|BATTERY|VALVE|FILTER|SHOCK ABSORBER|REPAIR KIT,TANKER|MISSILE|RADAR)([^A-Z]|$)'
    and coalesce(naics_code,'') !~ '^(236|237|238)'
  );

comment on view research.v_regional_parent_vehicle_open_candidates is
  'Research-only prospective regional physical-asset vehicle notices. Keeps open solicitations and market-research stage separate; these are not awarded parent vehicles and cannot propagate relationships.';

create or replace view research.v_usaspending_regional_parent_vehicle_targets as
with grouped as (
  select
    r.parent_piid,
    count(distinct r.source_native_id) as local_child_notice_count,
    max(r.posted_at) as latest_local_child_notice_at,
    array_agg(distinct r.place_state order by r.place_state) filter(where r.place_state is not null) as supported_states,
    array_agg(distinct r.solicitation_number order by r.solicitation_number) filter(where r.solicitation_number is not null) as child_notice_numbers,
    bool_or(r.surface_work_scope_present) as has_surface_work_scope,
    bool_or(upper(coalesce(r.buyer_subtier,'')) like '%ARMY%') as army_parent,
    max(r.title) as example_local_child_title,
    max(r.buyer_office) as example_buyer_office
  from research.v_regional_parent_vehicle_child_references r
  group by r.parent_piid
)
select
  md5('regional-parent-vehicle:' || g.parent_piid) as program_key,
  coalesce(p.description,'Regional parent vehicle referenced by supported-area child work') as program_title,
  'regional_physical_asset_vehicle'::text as program_scope_class,
  'local_child_work_proven'::text as site_scope_status,
  g.has_surface_work_scope,
  g.parent_piid,
  case when g.army_parent then '9700' else null end as fpds_agency_code,
  coalesce(p.generated_award_id,case when g.army_parent then 'CONT_IDV_' || g.parent_piid || '_9700' end) as parent_generated_award_id,
  case
    when p.generated_award_id is not null then 'already_collected_verified'
    when g.army_parent then 'deterministic_verified_dod_army_idv_key'
    else 'usaspending_exact_piid_search_required'
  end as identifier_resolution,
  g.local_child_notice_count,
  g.latest_local_child_notice_at,
  g.supported_states,
  g.child_notice_numbers,
  g.example_local_child_title,
  g.example_buyer_office,
  false as child_propagation_authorized
from grouped g
left join procurement.federal_parent_idvs p on upper(p.piid)=upper(g.parent_piid);

comment on view research.v_usaspending_regional_parent_vehicle_targets is
  'Research-only USAspending target set for awarded parent vehicles already proven to generate KY/IN/OH physical-asset child work. Collection is evidence enrichment only; no contractor/facility propagation is authorized.';

create or replace view research.v_regional_parent_vehicle_watch as
with proven as (
  select
    'parent:' || t.parent_piid as vehicle_key,
    t.parent_piid,
    null::text as solicitation_number,
    t.program_title as vehicle_title,
    'awarded_parent_local_child_proven'::text as lifecycle_stage,
    'strong'::text as local_relevance,
    t.site_scope_status,
    t.supported_states,
    t.local_child_notice_count as evidence_count,
    t.latest_local_child_notice_at as latest_evidence_at,
    t.has_surface_work_scope,
    t.parent_generated_award_id,
    t.identifier_resolution,
    t.example_local_child_title as evidence_example,
    'collect/refresh authoritative parent IDV and child awards; resolve supported-area child work to Scout assets before any relationship propagation'::text as next_action,
    false as relationship_propagation_authorized
  from research.v_usaspending_regional_parent_vehicle_targets t
), prospective as (
  select
    'sam-solicitation:' || coalesce(nullif(btrim(c.solicitation_number),''),c.source_native_id) as vehicle_key,
    null::text as parent_piid,
    c.solicitation_number,
    c.title as vehicle_title,
    c.vehicle_stage as lifecycle_stage,
    case
      when c.geography_evidence in ('named_supported_installation_or_city','supported_regional_aor_explicit') then 'strong'
      else 'medium'
    end as local_relevance,
    c.geography_evidence as site_scope_status,
    array_remove(array[c.place_state],null) as supported_states,
    1::bigint as evidence_count,
    c.posted_at as latest_evidence_at,
    c.surface_work_scope_present as has_surface_work_scope,
    null::text as parent_generated_award_id,
    'not_awarded_parent_yet'::text as identifier_resolution,
    c.evidence_excerpt as evidence_example,
    case
      when c.vehicle_stage='market_research_vehicle' then 'watch for solicitation/award; do not treat as a contractor relationship'
      else 'watch SAM award data; once parent PIIDs are awarded, move winners into USAspending parent/child monitoring'
    end as next_action,
    false as relationship_propagation_authorized
  from research.v_regional_parent_vehicle_open_candidates c
)
select * from proven
union all
select * from prospective;

comment on view research.v_regional_parent_vehicle_watch is
  'Research-only regional parent-vehicle watch spanning proven awarded parents with local child work, open vehicle solicitations, and market research. Lifecycle stages are intentionally separate.';

revoke all on research.v_regional_parent_vehicle_child_references from anon,authenticated;
revoke all on research.v_regional_parent_vehicle_open_candidates from anon,authenticated;
revoke all on research.v_usaspending_regional_parent_vehicle_targets from anon,authenticated;
revoke all on research.v_regional_parent_vehicle_watch from anon,authenticated;
grant select on research.v_regional_parent_vehicle_child_references to service_role;
grant select on research.v_regional_parent_vehicle_open_candidates to service_role;
grant select on research.v_usaspending_regional_parent_vehicle_targets to service_role;
grant select on research.v_regional_parent_vehicle_watch to service_role;
