-- Scout regional parent-vehicle watch v2
-- Exclude contradictory place-of-performance evidence from the automated strong parent tier.

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
    -- SAM place-state is not always a reliable worksite field. A current VA Phoenix notice
    -- is tagged OH; fail closed when the scope explicitly names this contradictory location.
    and not (
      lower(coalesce(o.title,'') || ' ' || coalesce(o.description,'')) ~ '(visn 22 phoenix|phoenix[ ,]+arizona|\marizona\M)'
      and lower(coalesce(o.title,'') || ' ' || coalesce(o.description,'')) !~ '(kentucky|indiana|ohio)'
    )
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
  'Research-only strong evidence: supported-area physical-asset SAM task-order notices explicitly reference parent IDVs. Contradictory location evidence fails closed. Parent PIID ranges up to 50 contracts are deterministically expanded.';
