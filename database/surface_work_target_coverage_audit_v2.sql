-- Scout by Cadastory
-- Surface-work target coverage audit v2.
-- Research-only. Completes readiness rows for the v3 preservation survey and
-- folds verified regional federal child-order evidence into dam/lock coverage.

insert into research.surface_work_source_capabilities (
  capability_key,
  selector_type,
  selector_value,
  asset_identity_resolution,
  buyer_resolution,
  project_scope_resolution,
  timing_resolution,
  prep_relationship_resolution,
  semantic_noise_risk,
  observed_strength,
  evidence_summary,
  limitations,
  reviewed_at
) values (
  'regional_federal_child_orders',
  'source_slug',
  'usaspending',
  'partial',
  'strong',
  'strong',
  'strong',
  'partial',
  'medium',
  'strong',
  'The USAspending-derived federal task-order corpus is normalized through research.v_regional_federal_child_order_intelligence. Verified supported-area parent-vehicle child orders currently contain 31 normalized records, 20 substantive orders and two explicit paint/surface-work orders. Wolf Creek Dam Bridge is a true on-asset superstructure-painting project; McAlpine Locks and Dam is a component fabrication/test/paint/delivery order and is explicitly separated from local asset-cleaning evidence. Named navigation assets can be crosswalked to authoritative NID identities where available.',
  'Award descriptions can name an asset while place of performance reflects fabrication or delivery rather than the asset site. Exact bridge/internal-structure identities are not always present in NBI/NID. Use the normalized regional child-order layer rather than raw USAspending keyword matches. Do not propagate contractor-to-asset relationships beyond the verified child order, and do not infer local cleaning from component painting or generic parent-vehicle eligibility.',
  now()
)
on conflict (capability_key) do update set
  selector_type=excluded.selector_type,
  selector_value=excluded.selector_value,
  asset_identity_resolution=excluded.asset_identity_resolution,
  buyer_resolution=excluded.buyer_resolution,
  project_scope_resolution=excluded.project_scope_resolution,
  timing_resolution=excluded.timing_resolution,
  prep_relationship_resolution=excluded.prep_relationship_resolution,
  semantic_noise_risk=excluded.semantic_noise_risk,
  observed_strength=excluded.observed_strength,
  evidence_summary=excluded.evidence_summary,
  limitations=excluded.limitations,
  reviewed_at=excluded.reviewed_at;

-- Complete the five v3 survey candidates that were added after the original
-- readiness audit was materialized.
insert into research.painting_signal_target_readiness (
  survey_key,
  confirmed_hit_readiness,
  forecast_readiness,
  confirmed_hit_sources,
  forecast_sources,
  confirmed_hit_basis,
  forecast_basis,
  observed_confirmed_scope_units,
  observation_note,
  blocker,
  next_action,
  priority,
  reviewed_at
) values
(
  'institutional:masonry_clean_tuckpoint_seal',
  'systematic_now',
  'partial_proxy',
  array['indiana-dlgf-school-capital-projects','kde-district-facility-plans']::text[],
  array['indiana-dlgf-school-capital-projects','kde-district-facility-plans']::text[],
  'The source-scoped semantic probe currently identifies 29 masonry-restoration/tuckpoint/seal evidence units: 7 Indiana capital-project rows and 22 KDE facility-plan document units. Two KDE units explicitly mention cleaning and 28/29 contain downstream preservation treatment. This is recurring, scope-bearing evidence rather than arbitrary keyword matching.',
  'Capital/facility plans provide future schedule and preservation-cycle context, but there is not yet an independent masonry-treatment lifecycle model that predicts work before planned scope appears.',
  29,
  'Evidence-unit count is not a lead count. KDE units can be document-level and must retain facility/project resolution confidence. Cleaning compatibility remains material-sensitive, especially for historic masonry.',
  'Resolve KDE document-level evidence to exact facilities/projects and preserve material/compatibility constraints before production promotion.',
  'Normalize strong/medium facility resolutions, retain cleaning-vs-treatment semantics, and backtest how far plan timing leads actual procurement.',
  1,
  now()
),
(
  'institutional:joint_sealant_caulk',
  'observed_in_current_sources',
  'partial_proxy',
  array['indiana-dlgf-school-capital-projects','kde-district-facility-plans']::text[],
  array['indiana-dlgf-school-capital-projects','kde-district-facility-plans']::text[],
  'The source-scoped semantic probe contains 6 explicit joint-sealant/caulk preservation evidence units: 4 Indiana capital-project rows and 2 KDE facility-plan units. One KDE unit also contains explicit cleaning language.',
  'Capital/facility plans can forecast envelope-renewal timing, but sealant work often implies localized joint preparation rather than a broad exterior wash.',
  6,
  'Treat as an adjacency/timing signal unless the same project establishes compatible broad-area cleaning or other envelope preservation scope.',
  'Current evidence is real but cleaning scope is often localized; facility resolution and work-area semantics remain necessary.',
  'Resolve facility/project identity and test whether joint-sealant scopes co-occur with broader facade cleaning, painting or masonry preservation often enough to improve lead quality.',
  2,
  now()
),
(
  'institutional:waterproofing_masonry_envelope',
  'observed_in_current_sources',
  'partial_proxy',
  array['kde-district-facility-plans']::text[],
  array['kde-district-facility-plans','ky-cpab-2024-2030-projects']::text[],
  'The source-scoped semantic probe contains 3 KDE waterproofing evidence units with downstream treatment explicit. Separate CPAB envelope projects demonstrate adjacent concrete-cleaning/joint-sealant preservation scope.',
  'Facility and capital plans expose future envelope-treatment windows, but substrate condition and the selected waterproofing/water-repellent system are required before inferring cleaning method or timing.',
  3,
  'Observed treatment evidence supports prospect timing, not automatic drone-cleaning compatibility. Pressure, moisture loading and historic-material constraints can change the appropriate preparation method.',
  'Treatment specifications and substrate/material context are not yet normalized.',
  'Resolve facility/project scope, then add treatment-system and substrate gates before using waterproofing as a cleaning-opportunity signal.',
  2,
  now()
),
(
  'institutional:concrete_clean_repair_coating',
  'observed_in_current_sources',
  'partial_proxy',
  array['indiana-dlgf-school-capital-projects','kde-district-facility-plans','ky-cpab-2024-2030-projects']::text[],
  array['indiana-dlgf-school-capital-projects','kde-district-facility-plans','ky-cpab-2024-2030-projects']::text[],
  'The source-scoped semantic probe contains 8 concrete preservation evidence units: 5 Indiana, 2 KDE and 1 Kentucky CPAB. The CPAB University of Louisville exterior-envelope project explicitly includes concrete cleaning and repairs; the current generic detector does not count that phrase as cleaning_explicit because its cleaning regex is intentionally conservative.',
  'Capital/facility plans provide forward project timing and envelope-renewal context, but there is not yet a concrete-condition/lifecycle model that predicts treatment independent of planned scope.',
  8,
  'Concrete preservation can involve broad-area washing, abrasive preparation or localized repair preparation. Preserve exact specification language rather than inferring a cleaning method from treatment family alone.',
  'Need project/facility resolution plus preparation-method semantics to separate broad cleanable envelope work from localized or specialist preparation.',
  'Improve the concrete-cleaning phrase detector for validated scope text, resolve projects to facilities, and retain prep-method/operator-compatibility gates.',
  2,
  now()
),
(
  'cemetery:mausoleum_masonry_preservation',
  'asset_only',
  'source_gap',
  array[]::text[],
  array['core.organizations','intelligence.premium_exterior_targets']::text[],
  'Scout can identify cemetery organizations and some built exterior targets, but the current validated preservation sources do not provide a systematic mausoleum/memorial cleaning, repointing or water-repellent project stream.',
  'Existing asset/organization context can support applicability screening, but there is no demonstrated treatment-specific forecast source or recurring project cadence.',
  null,
  'Retain as a narrow preservation family. Many cemetery assets will not meet commercial scale and historic stone can require specialist cleaning methods.',
  'Missing scope-bearing cemetery/mausoleum preservation projects, asset scale and material condition.',
  'Only pursue if a reliable capital/procurement/preservation source can be tied to commercial-scale mausoleums or memorial structures; keep material-safety gates mandatory.',
  4,
  now()
)
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
  reviewed_at=excluded.reviewed_at;

-- Dam/lock update: current regional federal child-order evidence proves that
-- surface-work scope is observable, but not yet as a systematic local cleaning
-- stream. McAlpine is specifically an off-site/delivery component-paint order.
update research.painting_signal_target_readiness
set
  confirmed_hit_readiness='observed_in_current_sources',
  confirmed_hit_sources=array['research.v_regional_federal_child_order_intelligence','usace-nid']::text[],
  confirmed_hit_basis='Verified regional federal child orders now provide scope-bearing surface-work evidence for USACE civil works. McAlpine Locks and Dam has a $3.4462M fabricate/test/paint/deliver culvert-valve order that demonstrates hydraulic-component coating procurement, while the normalized semantics correctly classify it as off-site/delivery component work rather than local asset cleaning. Wolf Creek Dam Bridge separately provides a true on-asset $643,560.30 superstructure-painting project at an authoritative USACE dam facility, demonstrating the broader federal civil-works surface-preservation pathway.',
  observed_confirmed_scope_units=1,
  observation_note='Count 1 here for hydraulic-component surface-work evidence (McAlpine). Do not count Wolf Creek Bridge as hydraulic steel, and do not interpret the McAlpine component order as local cleaning. The child-order stream currently has 20 substantive regional orders and two explicit surface-work orders across all federal-infrastructure families.',
  blocker='Confirmed federal civil-works surface scope is now observable, but exact internal-structure identifiers, recurring component inventories, predictive coating condition and local-vs-fabrication geography remain incomplete.',
  next_action='Extend authoritative USACE/Reclamation maintenance/project sources, resolve internal bridge/gate/penstock identifiers, and backtest recurring task-order history to separate true on-asset preservation from fabrication/delivery component work.',
  priority=1,
  reviewed_at=now()
where survey_key='dam_lock_operator:hydraulic_steel';

-- Research objects remain private/non-customer-facing.
revoke all on table research.painting_signal_target_readiness from anon, authenticated;
revoke all on table research.surface_work_source_capabilities from anon, authenticated;
revoke all on table research.v_painting_signal_target_coverage_audit from anon, authenticated;
