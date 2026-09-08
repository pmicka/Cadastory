-- Scout by Cadastory
-- Regional federal child-order intelligence + named infrastructure crosswalk v1.
-- Research-only: no production scoring, opportunity promotion, or relationship propagation.

create schema if not exists research;

create table if not exists research.federal_infrastructure_aliases (
  alias_key text primary key,
  canonical_name text not null,
  asset_family text not null,
  target_namespace text not null,
  expected_state_codes text[] not null default '{}'::text[],
  task_order_match_pattern text not null,
  bridge_context_pattern text,
  evidence_basis text not null,
  active boolean not null default true,
  relationship_propagation_authorized boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table research.federal_infrastructure_aliases is
  'Research-only deterministic alias registry for extracting named federal infrastructure from verified task-order descriptions. Aliases support crosswalk research only and never authorize relationship propagation.';

insert into research.federal_infrastructure_aliases (
  alias_key, canonical_name, asset_family, target_namespace, expected_state_codes,
  task_order_match_pattern, bridge_context_pattern, evidence_basis
) values
  ('wolf_creek_dam_bridge','Wolf Creek Dam Bridge','bridge_at_dam','transportation.bridges',array['KY'],
   'wolf[[:space:]]+creek[[:space:]]+dam[[:space:]]+bridge','wolf[[:space:]]+creek[[:space:]]+dam',
   'Verified USAspending child order W912P523F0119: Wolf Creek Dam Bridge Superstructure Painting.'),
  ('mcalpine_locks_and_dam','McAlpine Locks and Dam','lock_and_dam','federal_navigation_asset',array['KY'],
   'mcalpine[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam','mcalpine[[:space:]]+locks',
   'Verified USAspending child order W912QR25FA182 names McAlpine Locks and Dam; current NID raw corpus contains KY03034.'),
  ('john_t_myers_locks_and_dam','John T. Myers Locks and Dam','lock_and_dam','federal_navigation_asset',array['IN'],
   'john[[:space:]]+t\.?[[:space:]]+myers[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam','john[[:space:]]+t\.?[[:space:]]+myers',
   'Verified USAspending child order W912QR25FA167 names John T. Myers Locks and Dam in Mount Vernon, Indiana.'),
  ('cagles_mill_bridge','Cagles Mill Bridge','bridge','transportation.bridges',array['IN'],
   'cagles[[:space:]]+mill[[:space:]]+bridge','cagles[[:space:]]+mill',
   'Verified USAspending child order W912QR25FA123: Cagles Mill Bridge Rehab Construction.'),
  ('greenup_lock_and_dam','Greenup Lock and Dam','lock_and_dam','federal_navigation_asset',array['KY'],
   'greenup[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam','greenup[[:space:]]+lock',
   'Verified USAspending child order W9123725FA074 names Greenup Lock and Dam as the delivery asset.'),
  ('cannelton_locks_and_dam','Cannelton Locks and Dam','lock_and_dam','federal_navigation_asset',array['KY','IN'],
   'cannelton[[:space:]]+locks?[[:space:]]+and[[:space:]]+dam','cannelton[[:space:]]+locks',
   'Verified USAspending child order W912QR25FA056 names Cannelton Locks and Dam; current NID raw corpus contains KY03058.'),
  ('markland_locks_and_dam','Markland Locks and Dam','lock_and_dam','federal_navigation_asset',array['KY'],
   'markland','markland[[:space:]]+dam',
   'Verified USAspending child orders reference Markland; current NID raw corpus contains KY03033.'),
  ('paducah_levee_system','Paducah Levee System','levee_system','federal_flood_control_asset',array['KY'],
   'paducah[[:space:]]+levee[[:space:]]+system',null,
   'Verified USAspending child order W912QR26FA043: Paducah Levee System Phase 3 Reconstruction.')
on conflict (alias_key) do update set
  canonical_name=excluded.canonical_name,
  asset_family=excluded.asset_family,
  target_namespace=excluded.target_namespace,
  expected_state_codes=excluded.expected_state_codes,
  task_order_match_pattern=excluded.task_order_match_pattern,
  bridge_context_pattern=excluded.bridge_context_pattern,
  evidence_basis=excluded.evidence_basis,
  active=true,
  relationship_propagation_authorized=false,
  updated_at=now();

create or replace view research.v_federal_navigation_assets_nid as
select
  r.source_native_id as nid_id,
  r.raw_payload->'attributes'->>'NAME' as asset_name,
  r.raw_payload->'attributes'->>'STATE' as state_name,
  split_part(coalesce(r.raw_payload->'attributes'->>'COUNTYSTATE',''),',',1) as county_name,
  r.raw_payload->'attributes'->>'COUNTYSTATE' as county_state,
  r.raw_payload->'attributes'->>'PRIMARY_PURPOSE' as primary_purpose,
  r.raw_payload->'attributes'->>'PURPOSES' as purposes,
  nullif(r.raw_payload->'attributes'->>'NUMBER_OF_LOCKS','')::numeric as number_of_locks,
  nullif(r.raw_payload->'attributes'->>'LENGTH_OF_LOCKS','')::numeric as lock_length,
  nullif(r.raw_payload->'attributes'->>'WIDTH_OF_LOCKS','')::numeric as lock_width,
  r.raw_payload->'attributes'->>'FED_AGENCY_OWNERS' as federal_owner,
  r.raw_payload->'attributes'->>'OWNER_TYPES' as owner_types,
  r.raw_payload->'attributes'->>'RIVER_OR_STREAM' as river_or_stream,
  nullif(r.raw_payload->'attributes'->>'LATITUDE','')::double precision as latitude,
  nullif(r.raw_payload->'attributes'->>'LONGITUDE','')::double precision as longitude,
  r.raw_payload->'attributes'->>'YEAR_COMPLETED' as year_completed,
  r.retrieved_at,
  r.observed_at,
  false as relationship_propagation_authorized
from ingest.raw_records r
join ingest.sources s on s.id=r.source_id
where s.slug='usace-nid'
  and (
    lower(coalesce(r.raw_payload->'attributes'->>'PRIMARY_PURPOSE',''))='navigation'
    or lower(coalesce(r.raw_payload->'attributes'->>'PURPOSES','')) like '%navigation%'
    or coalesce(nullif(r.raw_payload->'attributes'->>'NUMBER_OF_LOCKS','')::numeric,0)>0
  );

comment on view research.v_federal_navigation_assets_nid is
  'Research-only normalization of navigation/lock-bearing records already present in the authoritative USACE NID raw corpus. Not an opportunity feed.';

create or replace view research.v_regional_federal_child_order_intelligence as
with regional_parents as (
  select distinct parent_piid
  from research.v_usaspending_regional_parent_vehicle_targets
), base as (
  select
    t.*,
    lower(coalesce(t.description,'')) as scope_lc,
    (lower(coalesce(t.description,'')) ~ '(minimum guarantee|guaranteed amount)') as administrative_order,
    (t.place_state_code = any(array['KY','IN','OH'])) as formal_pop_supported_area,
    (lower(coalesce(t.description,'')) ~ '(paint|painting|repaint|recoat|coating|surface[ -]?prep|abrasive[ -]?blast|sandblast|waterproof|sealant|tuckpoint)') as surface_work_explicit,
    (lower(coalesce(t.description,'')) ~ '(fabricat|assembl|test).{0,180}(deliver|shipment|ship)|deliver.{0,180}(lock|dam|bridge|gate|valve|bulkhead)') as fabrication_or_delivery_scope,
    (lower(coalesce(t.description,'')) ~ '(clean|cleaning|wash|washing|pressure wash|power wash|surface[ -]?prep|abrasive[ -]?blast|sandblast)') as prep_or_cleaning_explicit
  from procurement.federal_task_orders t
  join regional_parents p on p.parent_piid=t.parent_piid
), enriched as (
  select
    b.*,
    a.alias_key,
    a.canonical_name as named_asset,
    a.asset_family as named_asset_family,
    a.target_namespace as named_asset_target_namespace,
    a.expected_state_codes as named_asset_expected_state_codes,
    coalesce(a.expected_state_codes && array['KY','IN','OH']::text[],false) as named_asset_supported_area,
    a.evidence_basis as alias_evidence_basis
  from base b
  left join lateral (
    select a.*
    from research.federal_infrastructure_aliases a
    where a.active
      and coalesce(b.description,'') ~* a.task_order_match_pattern
    order by length(a.task_order_match_pattern) desc, a.alias_key
    limit 1
  ) a on true
)
select
  e.parent_piid,
  e.parent_generated_award_id,
  e.child_piid,
  e.child_generated_award_id,
  e.recipient_name,
  e.recipient_uei,
  e.total_obligation,
  e.date_signed,
  e.pop_start_date,
  e.pop_end_date,
  e.pop_potential_end_date,
  e.awarding_agency_name,
  e.awarding_subtier_name,
  e.awarding_office_name,
  e.place_state_code,
  e.place_state_name,
  e.place_city_name,
  e.place_county_name,
  e.place_zip5,
  e.naics_code,
  e.naics_description,
  e.psc_code,
  e.psc_description,
  e.description,
  case when e.administrative_order then 'administrative_guarantee' else 'substantive_order' end as order_class,
  e.formal_pop_supported_area,
  e.fabrication_or_delivery_scope,
  e.alias_key,
  e.named_asset,
  e.named_asset_family,
  e.named_asset_target_namespace,
  e.named_asset_expected_state_codes,
  e.named_asset_supported_area,
  case
    when e.administrative_order then 'administrative_not_geographic_work_evidence'
    when e.formal_pop_supported_area then 'supported_area_formal_place_of_performance'
    when e.named_asset_supported_area and e.fabrication_or_delivery_scope then 'offsite_fabrication_for_supported_asset'
    when e.named_asset_supported_area then 'supported_asset_reference_formal_pop_elsewhere'
    else 'out_of_supported_area_or_unresolved'
  end as geography_interpretation,
  e.surface_work_explicit,
  e.prep_or_cleaning_explicit,
  case
    when e.administrative_order then 'none'
    when e.surface_work_explicit and e.fabrication_or_delivery_scope then 'component_surface_work_offsite_or_delivery'
    when e.surface_work_explicit then 'explicit_surface_preservation_project'
    else 'no_explicit_surface_scope'
  end as surface_work_class,
  case
    when e.administrative_order then 'not_applicable'
    when e.surface_work_explicit and e.prep_or_cleaning_explicit then 'explicit_prep_or_cleaning_language'
    when e.surface_work_explicit and e.fabrication_or_delivery_scope then 'component_surface_prep_relationship_not_local_asset_cleaning'
    when e.surface_work_explicit then 'downstream_surface_treatment_prep_relationship_supported_not_explicit'
    else 'not_applicable'
  end as cleaning_relationship_semantics,
  case
    when e.administrative_order then 'no_operational_opportunity'
    when e.surface_work_explicit and e.formal_pop_supported_area and not e.fabrication_or_delivery_scope then 'confirmed_surface_work_supported_area'
    when e.surface_work_explicit and e.fabrication_or_delivery_scope then 'confirmed_component_surface_work_not_local_on_asset_cleaning'
    when e.formal_pop_supported_area then 'supported_area_asset_work_no_explicit_surface_scope'
    when e.named_asset_supported_area then 'supported_asset_context_no_local_surface_confirmation'
    else 'out_of_supported_area_or_unresolved'
  end as opportunity_interpretation,
  e.alias_evidence_basis,
  false as relationship_propagation_authorized
from enriched e;

comment on view research.v_regional_federal_child_order_intelligence is
  'Research-only semantic layer over verified child awards from regionally proven parent vehicles. Separates administrative guarantees, formal place of performance, named asset destination, offsite fabrication, explicit surface work, and on-asset opportunity interpretation.';

create or replace view research.v_federal_infrastructure_asset_crosswalk_status as
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
), nid as (
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
    where regexp_replace(lower(coalesce(n.asset_name,'')),'[^a-z0-9]+','','g') =
          regexp_replace(lower(coalesce(a.canonical_name,'')),'[^a-z0-9]+','','g')
    order by n.nid_id
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
  coalesce(b.bridge_context_candidate_count,0)::bigint as bridge_context_candidate_count,
  b.bridge_context_structure_numbers,
  case
    when coalesce(o.substantive_task_orders,0)=0 then 'no_current_task_order_reference'
    when a.target_namespace='federal_navigation_asset' and n.nid_id is not null then 'authoritative_nid_exact_name_resolved'
    when a.target_namespace='transportation.bridges' and coalesce(b.bridge_context_candidate_count,0)=1 then 'single_bridge_context_candidate_requires_confirmation'
    when a.target_namespace='transportation.bridges' and coalesce(b.bridge_context_candidate_count,0)>1 then 'multiple_bridge_context_candidates_require_resolution'
    else 'authoritative_asset_unresolved_current_sources'
  end as crosswalk_status,
  case
    when a.target_namespace='federal_navigation_asset' and n.nid_id is not null then 'normalization_only'
    when a.target_namespace='transportation.bridges' and coalesce(b.bridge_context_candidate_count,0)>0 then 'bridge_identifier_confirmation'
    else 'authoritative_collection_or_crosswalk_gap'
  end as gap_kind,
  case
    when a.target_namespace='federal_navigation_asset' and n.nid_id is not null then 'Normalize the existing NID record into the federal navigation-asset layer; do not infer contractor-to-asset relationships beyond the verified child order.'
    when a.target_namespace='transportation.bridges' and coalesce(b.bridge_context_candidate_count,0)>0 then 'Validate the bridge context candidate against authoritative project/location evidence before attaching the task order to a bridge identifier.'
    when a.target_namespace='transportation.bridges' then 'Extend authoritative bridge/project coverage or obtain a deterministic federal-to-NBI/bridge identifier crosswalk.'
    when a.target_namespace='federal_flood_control_asset' then 'Resolve against an authoritative federal levee/flood-control asset inventory before promotion.'
    else 'Extend authoritative federal navigation/infrastructure coverage and resolve a stable asset identifier before promotion.'
  end as next_action,
  a.evidence_basis,
  false as relationship_propagation_authorized
from research.federal_infrastructure_aliases a
left join observed o using(alias_key)
left join nid n using(alias_key)
left join bridge_context b using(alias_key)
where a.active;

comment on view research.v_federal_infrastructure_asset_crosswalk_status is
  'Research-only status of named supported-area federal infrastructure referenced by verified regional parent-vehicle child orders. Exact NID matches are distinguished from bridge context candidates and true source/crosswalk gaps.';

create or replace view research.v_federal_infrastructure_asset_crosswalk_queue as
select *
from research.v_federal_infrastructure_asset_crosswalk_status
where substantive_task_orders > 0
  and crosswalk_status <> 'authoritative_nid_exact_name_resolved'
order by
  explicit_surface_task_orders desc,
  substantive_task_orders desc,
  substantive_obligation desc nulls last,
  canonical_name;

comment on view research.v_federal_infrastructure_asset_crosswalk_queue is
  'Research-only unresolved federal infrastructure crosswalk queue, prioritized by explicit surface-work evidence, task-order count, and obligation. Candidate bridge context is never treated as a resolved asset link.';

revoke all on table research.federal_infrastructure_aliases from anon, authenticated;
revoke all on table research.v_federal_navigation_assets_nid from anon, authenticated;
revoke all on table research.v_regional_federal_child_order_intelligence from anon, authenticated;
revoke all on table research.v_federal_infrastructure_asset_crosswalk_status from anon, authenticated;
revoke all on table research.v_federal_infrastructure_asset_crosswalk_queue from anon, authenticated;
