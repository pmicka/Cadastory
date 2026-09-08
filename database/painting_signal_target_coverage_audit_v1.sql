-- Scout by Cadastory
-- Painting/coating signal coverage audit v1.
-- Research-only: evaluates whether currently targetable asset classes can yield
-- repeatable confirmed painting/coating hits and/or defensible forecasts.
-- No production scoring, MCP exposure, or customer-facing opportunity creation.

create schema if not exists research;

create table if not exists research.painting_signal_target_readiness (
  survey_key text primary key,
  confirmed_hit_readiness text not null check (confirmed_hit_readiness in (
    'systematic_now',
    'observed_in_current_sources',
    'source_registered_needs_validation',
    'asset_only',
    'source_gap'
  )),
  forecast_readiness text not null check (forecast_readiness in (
    'treatment_specific_now',
    'partial_proxy',
    'applicability_only',
    'source_gap'
  )),
  confirmed_hit_sources text[] not null default '{}'::text[],
  forecast_sources text[] not null default '{}'::text[],
  confirmed_hit_basis text,
  forecast_basis text,
  observed_confirmed_scope_units integer,
  observation_note text,
  blocker text,
  next_action text,
  priority smallint not null default 3 check (priority between 1 and 4),
  reviewed_at timestamptz not null default now()
);

comment on table research.painting_signal_target_readiness is
  'Research-only readiness assessment for systematic painting/coating confirmed-hit extraction and forecast extraction across Scout-targetable asset classes.';

-- Conservative readiness semantics:
-- systematic_now = an existing repeatable source already exposes parseable explicit painting/coating scope.
-- observed_in_current_sources = a real hit exists in current data, but source coverage is too sparse or unresolved to call systematic.
-- asset_only = Scout can target/resolve the asset, but current sources do not expose paint/coating work scope.
-- partial_proxy = current condition/lifecycle/context can move repaint probability but is not treatment-specific.
-- applicability_only = current data can establish that a paint/coating regime applies, but not when work is due.

insert into research.painting_signal_target_readiness (
  survey_key,confirmed_hit_readiness,forecast_readiness,
  confirmed_hit_sources,forecast_sources,
  confirmed_hit_basis,forecast_basis,observed_confirmed_scope_units,observation_note,
  blocker,next_action,priority
) values
('water_utility:elevated_water_tank_exterior','systematic_now','partial_proxy',
 array['water.tank_projects','ky-kia-proposed-water-improvements','kentucky-transparency-contracts'],
 array['water.v_tank_maintenance_candidates','water.tank_projects'],
 'WRIS project purpose text repeatedly exposes repaint/recoat/coating/cleaning/blasting scopes; Kentucky transparency also contains a scoped Water Tower Painting/Repairs contract modification.',
 'Tank maintenance-due context and project history provide timing pressure, but exterior-vs-interior and treatment-specific lifecycle remain incomplete.',
 32,'32 coating-related WRIS project rows observed; 8 explicitly combine prep plus coating. Exterior/interior scope remains unresolved in many rows.',
 'Resolve exterior versus interior scope and broaden beyond Kentucky WRIS.',
 'Normalize exterior/interior tank treatment scope and add utility procurement/inspection feeds.',1),

('water_utility:ground_storage_tank_exterior','systematic_now','partial_proxy',
 array['water.tank_projects','ky-kia-proposed-water-improvements'],
 array['water.v_tank_maintenance_candidates','water.tank_projects'],
 'The same WRIS treatment parser applies to ground-storage tank projects when the physical tank is resolved.',
 'Maintenance/project chronology is useful timing pressure but not yet a coating-specific deterioration model.',
 null,'Shares the 32-row WRIS coating corpus with elevated tanks; structure subtype resolution is required before per-class counts are treated as independent.',
 'Need broader tank-project feeds and reliable treatment-scope decomposition.',
 'Resolve structure subtype plus exterior treatment scope, then add non-WRIS utility procurement sources.',1),

('transportation_agency:steel_bridge_superstructure','source_gap','partial_proxy',
 array[]::text[],
 array['transportation.bridges','transportation.bridge_condition_snapshots','kydot-trak-bridge-condition-current'],
 'Current normalized bridge-project corpus does not yet provide a repeatable paint/coating hit stream.',
 'Steel material plus current condition can narrow the universe; current TRAK probe has explicit painted/unpainted evidence but lacks coating-condition timing.',
 0,'Current applicability probe: 5 explicit painted-steel, 26 explicit unpainted-steel, 559 steel with paint status unresolved. These are applicability facts, not repaint projects.',
 'Missing coating-element condition and DOT pay-item/letting normalization.',
 'Ingest FHWA Element 515 where available and KY/IN/OH bridge paint/coating pay items, then backtest condition-to-project lead time.',1),

('school_district:exterior_building_painting','systematic_now','partial_proxy',
 array['indiana-dlgf-school-capital-projects','kde-district-facility-plans'],
 array['indiana-dlgf-school-capital-projects','kde-district-facility-plans'],
 'Capital/facility plans already expose explicit exterior painting, mixed exterior painting, EIFS coating and repaint scopes.',
 'Facility condition/capital-plan context can identify buildings entering preservation cycles, but there is not yet a repaint-lifecycle model independent of explicit planned scope.',
 9,'Indiana probe has 4 exterior-explicit plus 5 mixed-scope-containing-exterior paint rows; Kentucky plans add document-level paint/EIFS evidence.',
 'Kentucky evidence is often document-level and mixed scopes need decomposition.',
 'Resolve facility/project rows, classify exterior versus interior/ground scope, and preserve plan year/cost as timing.',1),

('commercial_property:roof_recoating','observed_in_current_sources','partial_proxy',
 array['kde-district-facility-plans'],
 array['intelligence.v_roof_lifecycle_pressure','louisville-historical-finaled-commercial-permits'],
 'A current KDE facility plan explicitly includes recoating a metal gym roof, proving the phrase family is observable.',
 'Scout has 920 address-level roof age anchors, but they are new-construction lifecycle proxies rather than treatment-specific coating condition.',
 1,'One explicit roof recoat/restoration evidence unit is currently observed; 76 replacement and 15 repair scopes are separately detectable and must not be conflated.',
 'Private commercial roof treatment timing and property/building crosswalks are weak.',
 'Add treatment-aware roofing permit/spec/bid sources and resolve roof age anchors to managed properties.',2),

('commercial_property:painted_facade_recoating','asset_only','source_gap',
 array[]::text[],array['decisioning.v_building_resolved_attributes','intelligence.premium_exterior_targets'],
 'Scout resolves many commercial targets but current private-property sources do not systematically expose facade repaint/recoat scope.',
 'Building attributes improve applicability but do not currently predict repaint timing.',
 null,null,
 'Missing scope-bearing renovation/capital-maintenance sources for private commercial properties.',
 'Prioritize permits/specifications/capital-maintenance feeds that include actual work descriptions rather than ownership-only portfolio data.',2),

('industrial_operator:aboveground_storage_tank','asset_only','source_gap',
 array[]::text[],array['scout.v_industrial_logistics_accounts','core.v_asset_business_entity_context'],
 'Industrial owner/account context exists, but there is no normalized aboveground-storage-tank coating project feed.',
 'No current treatment-specific condition or lifecycle layer.',null,null,
 'Missing normalized tank assets and maintenance/procurement events.',
 'Add public facility tank inventories where defensible, then owner/permit/procurement coating events.',2),

('dam_lock_operator:hydraulic_steel','asset_only','partial_proxy',
 array[]::text[],array['scout.v_dam_opportunity_candidates','usace-nid'],
 'Dam assets and owners are targetable, but NID does not expose gate/penstock coating work orders.',
 'Dam condition and inspection cadence can prioritize aging assets, but not specifically predict coating work.',null,null,
 'Missing hydraulic-steel component inventory and maintenance/procurement scope.',
 'Add USACE/Reclamation/state owner maintenance and procurement records for gates, penstocks and structural steel.',2),

('telecom_operator:aviation_marked_tower','asset_only','applicability_only',
 array[]::text[],array['telecom.asr_structures','telecom.v_tower_responsibility'],
 'ASR resolves towers/operators but does not report repaint work.',
 'FAA marking requirements can establish which structures require maintained painted markings; current Scout data does not yet resolve marking requirement plus deterioration timing.',null,null,
 'Missing marking-requirement normalization and maintenance evidence.',
 'Resolve FAA marking regime per ASR structure, then seek owner maintenance/procurement or inspection evidence.',2),

('sports_venue:stadium_structural_steel','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets','intelligence.marquee_event_paper_trail'],
 'Scout targets stadiums/arenas but has no systematic paint/coating capital-work extractor for them.',
 'Event timing is useful commercial context but is not a repaint forecast by itself.',null,null,
 'Missing venue capital-plan/procurement scopes.',
 'Reuse public capital/procurement parsing against stadium/arena owners and venue authorities.',2),

('amusement_operator:roller_coaster_and_ride_steel','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets','core.organizations'],
 'Park/operator targeting exists, but ride-level recoating work is not in a current systematic feed.',
 'No current ride coating-condition/lifecycle evidence.',null,null,
 'Missing ride-level assets and owner maintenance/capital-project signals.',
 'Add operator capital/maintenance announcements or procurements before attempting a forecast.',3),

('railroad:rail_bridge_and_gantry','asset_only','source_gap',
 array[]::text[],array['transportation.rail_lines','transportation.rail_yards','scout.v_rail_opportunity_candidates'],
 'Rail candidates are currently crossing/risk oriented, not coating-work oriented.',
 'Rail asset presence alone is not a repaint forecast.',null,null,
 'Missing rail bridge/gantry coating projects and component condition.',
 'Use public grant/project scopes and railroad procurement/capital sources where obtainable.',3),

('grain_operator:grain_bin_silo_elevator_exterior','asset_only','applicability_only',
 array[]::text[],array['agriculture.grain_facilities','core.v_asset_portfolio_resolution'],
 'Grain assets/operators are resolved, but exterior repaint/coating maintenance is not a current systematic source.',
 'Asset geometry/material and possible aviation marking can establish applicability; work timing remains absent.',null,null,
 'Missing exterior-only maintenance evidence and safety-qualified scope.',
 'Add operator/facility capital or maintenance scopes and preserve strict combustible-dust/process safety gating.',3),

('hotel_management:facade_repaint_or_brand_refresh','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets','official_operator_portfolios'],
 'Hotel assets and management groups are targetable; portfolio rosters do not expose repaint scope.',
 'No current paint-specific timing model. Sales/acquisition/rebrand event intelligence is intentionally parked for later.',null,null,
 'Missing scope-bearing renovation/PIP/capital-maintenance feeds.',
 'Use renovation permits and publicly observable capital/PIP scope when available, without building a transaction layer yet.',2),

('dealership_group:showroom_facade_refresh','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets','official_operator_portfolios'],
 'Dealership assets/groups are resolved but no systematic facade repaint/image-program work feed is present.',
 'No current paint-specific forecast source.',null,null,
 'Missing OEM image-program/renovation work scope.',
 'Add renovation permit/project scopes and OEM/facility image-program evidence where systematic.',2),

('industrial_logistics:metal_warehouse_envelope','asset_only','partial_proxy',
 array[]::text[],array['scout.v_industrial_logistics_accounts','intelligence.v_roof_lifecycle_pressure','decisioning.v_building_resolved_attributes'],
 'Industrial/logistics portfolios resolve accounts but not coating work.',
 'Building/roof age and envelope attributes can provide weak lifecycle pressure where linked, but treatment timing is unresolved.',null,null,
 'Weak structure-level ownership/project linkage and no coating-specific condition feed.',
 'Build account-to-building crosswalks, then add roof/wall-panel maintenance project sources.',2),

('commercial_property:parking_structure_coating','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets','scout.v_property_management_facilities'],
 'Property targets exist, but parking structures and coating scopes are not normalized as a repeatable project stream.',
 'No current waterproofing/coating condition forecast at the private parking-structure level.',null,null,
 'Missing parking-structure inventory and repair/coating capital work.',
 'Identify parking structures and ingest public/private repair, waterproofing and coating scopes where observable.',2),

('university:campus_exterior_painting','observed_in_current_sources','source_gap',
 array['ky-cpab-2024-2030-projects'],array['intelligence.premium_exterior_targets','core.organizations'],
 'Kentucky CPAB currently exposes real university exterior-envelope preservation scope, demonstrating the source path, but explicit campus painting coverage is not yet broad enough to call systematic.',
 'Campus/organization resolution exists; there is no treatment-specific repaint forecast independent of explicit capital projects.',null,'UofL exterior-envelope evidence includes joint sealants plus concrete cleaning/repairs; this proves project observability, not broad campus paint coverage.',
 'Need broader university capital/procurement ingestion and building-level scope resolution.',
 'Expand CPAB/university capital and procurement parsing, preserving building/project identity.',2),

('health_system:facility_exterior_coating','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets','core.organizations'],
 'Health-system campuses are targetable, but private capital-maintenance scope is not systematically visible.',
 'No current coating-specific condition/timing source.',null,null,
 'Missing health-system project/capital observability.',
 'Use public-system capital plans and scope-bearing permits where available before private-source expansion.',3),

('airport_operator:hangar_terminal_parking_exterior','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets'],
 'Airport facilities are targetable at site level, but painting/coating scopes are not normalized.',
 'No current treatment-specific forecast.',null,null,
 'Missing airport facility inventory plus CIP/bid scope linkage.',
 'Add airport capital improvement plans and public bid/procurement scopes.',2),

('wind_operator:turbine_tower_exterior','asset_only','applicability_only',
 array[]::text[],array['energy.wind_turbines','scout.v_wind_opportunity_candidates'],
 'Wind assets are resolved but there is no coating event feed.',
 'Tower coating is an applicable maintained system, but current pilot volume and condition evidence are insufficient for timing.',null,null,
 'Low local asset volume and no coating O&M feed.',
 'Keep targetable but low priority until geographic expansion or owner O&M evidence improves.',4),

('racetrack_operator:grandstand_and_exposed_steel','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets','core.organizations'],
 'Racetrack/venue assets are targetable; Churchill Downs research proves recurring preservation is plausible but is not a systematic Scout project feed.',
 'No current treatment-specific forecast. Marquee-event cadence alone should not be treated as paint evidence.',null,null,
 'Missing scope-bearing venue facilities/capital-project source.',
 'Reuse venue capital/procurement collectors; keep event cadence as corroboration only.',2),

('casino_resort:facade_roof_dome_recoating','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets'],
 'Casino/resort targets exist, but no current systematic coating-project source.',
 'No current paint/coating forecast source.',null,null,
 'Missing private resort renovation/capital scope.',
 'Use permits and public renovation/capital announcements where systematically obtainable.',3),

('convention_center:facade_and_structural_steel','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets'],
 'Convention/exposition facilities are targetable but not yet connected to coating project scopes.',
 'No current treatment-specific forecast.',null,null,
 'Missing public authority capital/procurement linkage.',
 'Reuse public-facility capital plan and procurement parser against convention-center owners.',2),

('historic_religious:painted_exterior','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets','intelligence.v_building_historic_context'],
 'Historic/religious assets are targetable, but preservation-project painting is not systematically observed.',
 'Historic/material context is compatibility evidence, not repaint timing.',null,null,
 'Missing preservation grants/capital campaigns/project scopes and substrate-safe method evidence.',
 'Add public preservation grant/project feeds; keep service compatibility conservative.',3),

('municipal_public_works:park_and_civic_structures','asset_only','source_gap',
 array[]::text[],array['core.organizations','environment.managed_land_areas','kentucky-transparency-contracts'],
 'Municipal/park buyers can be resolved, but current contracts generally lack enough facility/surface scope for systematic paint hits.',
 'No current treatment-specific forecast.',null,'Kentucky Parks has a painting-contractor contract record, but it is buyer/category evidence only because structure/work scope is absent.',
 'Missing built-asset inventory inside managed land plus scope-bearing capital/maintenance projects.',
 'Add municipal/state parks capital plans and maintenance bid scopes, resolving each to a built facility.',3),

('federal_military:facility_painting_and_coating','source_registered_needs_validation','source_gap',
 array['sam-opportunities'],array['core.organizations'],
 'SAM.gov is registered as the appropriate procurement source, but current local raw opportunity coverage is empty and therefore not yet a functioning hit extractor.',
 'No current forecast layer beyond facility targeting.',0,'sam-opportunities currently has 0 raw records in the local source inventory.',
 'Collector coverage must be made real before calling this systematic.',
 'Populate/verify SAM opportunity collection for painting/coating/surface-prep scopes and agency forecasts.',1),

('wastewater_utility:process_tank_exterior','asset_only','source_gap',
 array[]::text[],array['core.organizations','kentucky-dow-kpdes-outfalls'],
 'Utility/regulatory context exists, but wastewater process tanks/digesters are not normalized with coating work.',
 'Regulatory facility presence does not predict exterior coating timing.',null,null,
 'Missing structure inventory, capital plans and coating procurement.',
 'Add SRF/utility capital plans, engineering reports and tank/digester coating bids.',2),

('facilities_management:multi_asset_paint_contract','asset_only','source_gap',
 array[]::text[],array['core.organizations','scout.v_property_management_service_specific_vendor_entries'],
 'Facilities-management accounts are resolved, but on-call painting/coating scope is not normalized from RFP/master-contract sources.',
 'Portfolio membership alone is not a repaint forecast.',null,null,
 'Missing contract-scope normalization and exterior/interior decomposition.',
 'Target facilities-management RFPs/on-call maintenance contracts because one hit can cover multiple assets.',1),

('cultural_venue:museum_performing_arts_envelope','asset_only','source_gap',
 array[]::text[],array['intelligence.premium_exterior_targets'],
 'Museums/performing-arts facilities are already targetable, but no systematic finish-preservation project feed is connected.',
 'No current coating-specific forecast.',null,null,
 'Missing capital-plan/procurement/preservation project linkage.',
 'Reuse public cultural-facility capital/procurement sources before adding bespoke collection.',3),

('public_recreation:park_lodge_facility_envelope','asset_only','source_gap',
 array[]::text[],array['environment.managed_land_areas','kentucky-transparency-contracts'],
 'Park/land-manager context exists, but lodge/recreation facilities and paint scopes are not reliably resolved.',
 'No current paint-specific forecast.',null,null,
 'Missing facility-level assets and scope-bearing project records.',
 'Add state park capital/facility maintenance records and resolve projects to lodges/buildings.',3)

on conflict (survey_key) do update set
  confirmed_hit_readiness=excluded.confirmed_hit_readiness,
  forecast_readiness=excluded.forecast_readiness,
  confirmed_hit_sources=excluded.confirmed_hit_sources,
  forecast_sources=excluded.forecast_sources,
  confirmed_hit_basis=excluded.confirmed_hit_basis,
  forecast_basis=excluded.forecast_basis,
  observed_confirmed_scope_units=excluded.observed_confirmed_scope_units,
  observation_note=excluded.observation_note,
  blocker=excluded.blocker,
  next_action=excluded.next_action,
  priority=excluded.priority,
  reviewed_at=now();

-- Strictly scope-bearing Kentucky transparency probe. Deliberately ignores
-- vendor names, addresses and commodity descriptions to avoid Paintsville,
-- painter-company-name and paint-supply false positives.
create or replace view research.v_kentucky_transparency_surface_work_probe as
with scoped as (
  select
    r.source_native_id,
    r.raw_payload->>'departmentName' as department_name,
    r.raw_payload->>'legalName' as vendor_name,
    r.raw_payload->>'effectiveBeginDate' as begin_date,
    r.raw_payload->>'effectiveEndDate' as end_date,
    r.raw_payload->>'documentActualAmount' as actual_amount,
    concat_ws(' ',
      nullif(r.raw_payload->>'contractDescriptionTexts',''),
      nullif(r.raw_payload->>'reasonForModifyingDocumentation','')
    ) as scope_text
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='kentucky-transparency-contracts'
), matched as (
  select *, lower(scope_text) as scope_lc
  from scoped
  where scope_text <> ''
    and scope_text ~* '(paint|painting|repaint|coating|tuck[ -]?point|waterproof|sealant|caulk|pressure wash|power wash|sandblast|abrasive blast)'
)
select
  source_native_id,department_name,vendor_name,begin_date,end_date,actual_amount,
  case
    when scope_lc ~ '(water tower|tank)' and scope_lc ~ '(paint|painting|repaint|coating)' then 'water_tower_or_tank_painting'
    when scope_lc ~ 'tuck[ -]?point' then 'masonry_tuckpointing'
    when scope_lc ~ '(paint|painting|repaint|coating)' then 'painting_or_coating_other'
    when scope_lc ~ '(waterproof|sealant|caulk)' then 'envelope_sealant_or_waterproofing'
    when scope_lc ~ '(pressure wash|power wash|sandblast|abrasive blast)' then 'surface_preparation_other'
    else 'surface_work_other'
  end as signal_family,
  left(scope_text,1800) as evidence_excerpt
from matched;

comment on view research.v_kentucky_transparency_surface_work_probe is
  'Research-only surface-work probe over Kentucky transparency contract scope/modification text only. Excludes names, addresses and commodity fields from semantic matching.';

create or replace view research.v_painting_signal_target_coverage_audit as
select
  s.survey_key,
  s.business_type,
  s.structure_type,
  s.surface_family,
  s.opportunity_fit,
  s.observability,
  s.scout_coverage,
  r.confirmed_hit_readiness,
  r.forecast_readiness,
  case
    when r.confirmed_hit_readiness='systematic_now' and r.forecast_readiness='treatment_specific_now' then 'A_both_systematic'
    when r.confirmed_hit_readiness='systematic_now' then 'B_confirmed_systematic_forecast_incomplete'
    when r.confirmed_hit_readiness in ('observed_in_current_sources','source_registered_needs_validation') then 'C_observed_or_registered_not_systematic'
    when r.forecast_readiness in ('partial_proxy','applicability_only') then 'D_forecast_scaffold_confirmed_gap'
    else 'E_under_instrumented'
  end as coverage_tier,
  r.confirmed_hit_sources,
  r.forecast_sources,
  r.confirmed_hit_basis,
  r.forecast_basis,
  r.observed_confirmed_scope_units,
  r.observation_note,
  r.blocker,
  r.next_action,
  r.priority,
  r.reviewed_at
from research.painting_signal_target_readiness r
join research.surface_work_signal_survey s using (survey_key)
where s.status='survey_candidate'
  and s.scout_coverage <> 'none';

comment on view research.v_painting_signal_target_coverage_audit is
  'Research-only per-target painting/coating readiness matrix. Separates explicit confirmed-hit extraction from treatment forecast extraction.';

create or replace view research.v_painting_signal_source_gap_queue as
select
  priority,
  coverage_tier,
  survey_key,
  business_type,
  structure_type,
  confirmed_hit_readiness,
  forecast_readiness,
  blocker,
  next_action
from research.v_painting_signal_target_coverage_audit
order by priority, coverage_tier, survey_key;

comment on view research.v_painting_signal_source_gap_queue is
  'Research-only prioritized queue for closing painting/coating signal instrumentation gaps across already-targetable Scout asset classes.';

update research.surface_work_source_capabilities
set evidence_summary = evidence_summary || ' Scope-only matching over contractDescriptionTexts/reasonForModifyingDocumentation has produced true project evidence including DOC - Various - Water Tower Painting/Repairs and Northpoint Training Center exterior dorm masonry tuckpointing.',
    limitations = 'Use only scope/modification text for semantic extraction; vendor names, addresses and commodity descriptions are not valid project-scope evidence. ' || limitations,
    reviewed_at = now()
where capability_key='kentucky_transparency'
  and evidence_summary not like '%Scope-only matching%';

revoke all on research.painting_signal_target_readiness from anon, authenticated;
revoke all on research.v_kentucky_transparency_surface_work_probe from anon, authenticated;
revoke all on research.v_painting_signal_target_coverage_audit from anon, authenticated;
revoke all on research.v_painting_signal_source_gap_queue from anon, authenticated;
