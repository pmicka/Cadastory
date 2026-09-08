-- Scout by Cadastory
-- Regional federal child-order infrastructure crosswalk v2.
-- Research-only. Adds authoritative NID naming aliases and facility context
-- without treating a dam/facility identity as an exact bridge identity.

alter table research.federal_infrastructure_aliases
  add column if not exists nid_exact_name_pattern text,
  add column if not exists facility_context_nid_pattern text;

comment on column research.federal_infrastructure_aliases.nid_exact_name_pattern is
  'Regex applied only to authoritative NID asset names for an exact asset-identity crosswalk. This may normalize harmless naming variants such as Lock vs Locks.';
comment on column research.federal_infrastructure_aliases.facility_context_nid_pattern is
  'Regex applied to authoritative NID asset names for enclosing/adjacent facility context only. A facility-context match never resolves the target asset itself.';

update research.federal_infrastructure_aliases
set
  nid_exact_name_pattern = case alias_key
    when 'mcalpine_locks_and_dam' then '^mcalpine[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam$'
    when 'john_t_myers_locks_and_dam' then '^john[[:space:]]+t\.?[[:space:]]+myers[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam$'
    when 'greenup_lock_and_dam' then '^greenup[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam$'
    when 'cannelton_locks_and_dam' then '^cannelton[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam$'
    when 'markland_locks_and_dam' then '^markland[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam$'
    else nid_exact_name_pattern
  end,
  facility_context_nid_pattern = case alias_key
    when 'wolf_creek_dam_bridge' then '^wolf[[:space:]]+creek[[:space:]]+dam$'
    when 'cagles_mill_bridge' then '^cagles[[:space:]]+mill[[:space:]]+dam$'
    else facility_context_nid_pattern
  end,
  expected_state_codes = case alias_key
    -- The lock/dam spans the Ohio River; the authoritative NID record is in KY
    -- while task-order place-of-performance evidence can legitimately be IN.
    when 'john_t_myers_locks_and_dam' then array['KY','IN']::text[]
    else expected_state_codes
  end,
  updated_at = now()
where alias_key in (
  'mcalpine_locks_and_dam','john_t_myers_locks_and_dam','greenup_lock_and_dam',
  'cannelton_locks_and_dam','markland_locks_and_dam','wolf_creek_dam_bridge','cagles_mill_bridge'
);

-- These are research-only views with no production dependency. Recreate rather
-- than CREATE OR REPLACE so the v2 facility-context columns can be inserted
-- without PostgreSQL's positional view-column compatibility restriction.
drop view if exists research.v_federal_infrastructure_asset_crosswalk_queue;
drop view if exists research.v_federal_infrastructure_asset_crosswalk_status;

create view research.v_federal_infrastructure_asset_crosswalk_status as
with observed as (
  select
    i.alias_key,
    count(*) filter (where i.order_class='substantive_order')::bigint as substantive_task_orders,
    count(*) filter (where i.surface_work_explicit and i.order_class='substantive_order')::bigint as explicit_surface_task_orders,
    sum(i.total_obligation) filter (where i.order_class='substantive_order') as substantive_obligation,
    max(i.date_signed) filter (where i.order_class='substantive_order') as latest_task_order_date,
    array_agg(distinct i.child_piid order by i.child_piid) filter (where i.order_class='substantive_order') as child_piids
  from research.v_regional_federal_child_order_intelligence i
  where i.alias_key is not null
  group by i.alias_key
), exact_nid as (
  select
    a.alias_key,
    n.nid_id,
    n.asset_name as nid_asset_name,
    n.state_name as nid_state_name,
    n.county_name as nid_county_name,
    n.federal_owner as nid_federal_owner,
    n.latitude as nid_latitude,
    n.longitude as nid_longitude
  from research.federal_infrastructure_aliases a
  left join lateral (
    select n.*
    from research.v_federal_navigation_assets_nid n
    where a.nid_exact_name_pattern is not null
      and lower(coalesce(n.asset_name,'')) ~ a.nid_exact_name_pattern
      and (
        cardinality(a.expected_state_codes)=0
        or case lower(coalesce(n.state_name,''))
             when 'kentucky' then 'KY'
             when 'indiana' then 'IN'
             when 'ohio' then 'OH'
             else upper(substr(coalesce(n.state_name,''),1,2))
           end = any(a.expected_state_codes)
      )
    order by n.nid_id
    limit 1
  ) n on true
), facility_nid as (
  select
    a.alias_key,
    n.source_record_key as facility_context_source_record_key,
    n.nid_id as facility_context_nid_id,
    n.asset_name as facility_context_name,
    n.state_name as facility_context_state_name,
    n.county_name as facility_context_county_name,
    n.federal_owner as facility_context_federal_owner,
    n.latitude as facility_context_latitude,
    n.longitude as facility_context_longitude
  from research.federal_infrastructure_aliases a
  left join lateral (
    select
      r.source_native_id as source_record_key,
      r.raw_payload->'attributes'->>'NIDID' as nid_id,
      r.raw_payload->'attributes'->>'NAME' as asset_name,
      r.raw_payload->'attributes'->>'STATE' as state_name,
      split_part(coalesce(r.raw_payload->'attributes'->>'COUNTYSTATE',''),',',1) as county_name,
      r.raw_payload->'attributes'->>'FED_AGENCY_OWNERS' as federal_owner,
      nullif(r.raw_payload->'attributes'->>'LATITUDE','')::double precision as latitude,
      nullif(r.raw_payload->'attributes'->>'LONGITUDE','')::double precision as longitude
    from ingest.raw_records r
    join ingest.sources s on s.id=r.source_id
    where s.slug='usace-nid'
      and a.facility_context_nid_pattern is not null
      and lower(coalesce(r.raw_payload->'attributes'->>'NAME','')) ~ a.facility_context_nid_pattern
      and (
        cardinality(a.expected_state_codes)=0
        or case lower(coalesce(r.raw_payload->'attributes'->>'STATE',''))
             when 'kentucky' then 'KY'
             when 'indiana' then 'IN'
             when 'ohio' then 'OH'
             else upper(substr(coalesce(r.raw_payload->'attributes'->>'STATE',''),1,2))
           end = any(a.expected_state_codes)
      )
    order by r.observed_at desc nulls last, r.retrieved_at desc, r.source_native_id
    limit 1
  ) n on true
), bridge_context as (
  select
    a.alias_key,
    coalesce(b.candidate_count,0)::bigint as bridge_context_candidate_count,
    b.structure_numbers as bridge_context_structure_numbers
  from research.federal_infrastructure_aliases a
  left join lateral (
    select count(*)::bigint as candidate_count,
           array_agg(t.structure_number order by t.structure_number) as structure_numbers
    from transportation.bridges t
    where a.bridge_context_pattern is not null
      and concat_ws(' ',coalesce(t.facility_carried,''),coalesce(t.location_text,'')) ~* a.bridge_context_pattern
  ) b on true
)
select
  a.alias_key,
  a.canonical_name,
  a.asset_family,
  a.target_namespace,
  a.expected_state_codes,
  coalesce(o.substantive_task_orders,0)::bigint as substantive_task_orders,
  coalesce(o.explicit_surface_task_orders,0)::bigint as explicit_surface_task_orders,
  o.substantive_obligation,
  o.latest_task_order_date,
  o.child_piids,
  n.nid_id,
  n.nid_asset_name,
  n.nid_state_name,
  n.nid_county_name,
  n.nid_federal_owner,
  n.nid_latitude,
  n.nid_longitude,
  f.facility_context_source_record_key,
  f.facility_context_nid_id,
  f.facility_context_name,
  f.facility_context_state_name,
  f.facility_context_county_name,
  f.facility_context_federal_owner,
  f.facility_context_latitude,
  f.facility_context_longitude,
  case when f.facility_context_nid_id is not null then 'authoritative_nid_facility_context_only' else 'none' end as facility_context_status,
  coalesce(b.bridge_context_candidate_count,0)::bigint as bridge_context_candidate_count,
  b.bridge_context_structure_numbers,
  case
    when coalesce(o.substantive_task_orders,0)=0 then 'no_current_task_order_reference'
    when a.target_namespace='federal_navigation_asset' and n.nid_id is not null then 'authoritative_nid_name_resolved'
    when a.target_namespace='transportation.bridges' and coalesce(b.bridge_context_candidate_count,0)=1 then 'single_bridge_context_candidate_requires_confirmation'
    when a.target_namespace='transportation.bridges' and coalesce(b.bridge_context_candidate_count,0)>1 then 'multiple_bridge_context_candidates_require_resolution'
    when f.facility_context_nid_id is not null then 'authoritative_facility_context_exact_asset_unresolved'
    else 'authoritative_asset_unresolved_current_sources'
  end as crosswalk_status,
  case
    when a.target_namespace='federal_navigation_asset' and n.nid_id is not null then 'normalization_only'
    when a.target_namespace='transportation.bridges' and coalesce(b.bridge_context_candidate_count,0)>0 then 'bridge_identifier_confirmation'
    when f.facility_context_nid_id is not null then 'exact_structure_identifier_gap_with_authoritative_facility_context'
    else 'authoritative_collection_or_crosswalk_gap'
  end as gap_kind,
  case
    when a.target_namespace='federal_navigation_asset' and n.nid_id is not null then 'Normalize the authoritative NID record into the federal navigation-asset layer; retain task-order provenance and do not propagate contractor relationships beyond the verified order.'
    when a.target_namespace='transportation.bridges' and coalesce(b.bridge_context_candidate_count,0)>0 then 'Validate the bridge context candidate against authoritative project/location evidence before attaching the task order to a bridge identifier.'
    when f.facility_context_nid_id is not null then 'Use the resolved NID facility as geographic/owner context only; obtain an authoritative structure-level identifier for the bridge before exact asset attachment.'
    when a.target_namespace='transportation.bridges' then 'Extend authoritative federal bridge/project coverage or obtain a deterministic federal-to-bridge identifier crosswalk.'
    when a.target_namespace='federal_flood_control_asset' then 'Resolve against an authoritative federal levee/flood-control asset inventory before promotion.'
    else 'Extend authoritative federal navigation/infrastructure coverage and resolve a stable asset identifier before promotion.'
  end as next_action,
  a.evidence_basis,
  false as relationship_propagation_authorized
from research.federal_infrastructure_aliases a
left join observed o using(alias_key)
left join exact_nid n using(alias_key)
left join facility_nid f using(alias_key)
left join bridge_context b using(alias_key)
where a.active;

create view research.v_federal_infrastructure_asset_crosswalk_queue as
select *
from research.v_federal_infrastructure_asset_crosswalk_status
where substantive_task_orders > 0
  and crosswalk_status <> 'authoritative_nid_name_resolved'
order by
  explicit_surface_task_orders desc,
  case when facility_context_nid_id is not null then 0 else 1 end,
  substantive_task_orders desc,
  substantive_obligation desc nulls last,
  canonical_name;

comment on view research.v_federal_infrastructure_asset_crosswalk_status is
  'Research-only status of named supported-area federal infrastructure referenced by verified regional parent-vehicle child orders. Exact navigation-asset resolution is distinct from enclosing NID facility context; facility context never resolves a bridge identity.';
comment on view research.v_federal_infrastructure_asset_crosswalk_queue is
  'Research-only unresolved federal infrastructure crosswalk queue. Exact NID facility context can narrow a bridge search but never promotes the bridge as resolved.';

revoke all on table research.federal_infrastructure_aliases from anon, authenticated;
revoke all on table research.v_federal_infrastructure_asset_crosswalk_status from anon, authenticated;
revoke all on table research.v_federal_infrastructure_asset_crosswalk_queue from anon, authenticated;
