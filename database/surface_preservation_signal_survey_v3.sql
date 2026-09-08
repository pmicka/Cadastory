-- Scout by Cadastory
-- Surface preservation signal survey v3.
-- Research-only: no production opportunity scoring or MCP exposure.
-- Broadens painting/coating research into envelope/surface-preservation work.

create schema if not exists research;

-- Correct the roof observability probe: KDE facility plans now provide an
-- explicit metal-roof recoating example (Oldham County), so restoration/recoat
-- is rare in current sources rather than absent.
create or replace view research.v_roof_treatment_observability_probe as
with raw as (
  select s.slug, lower(r.raw_payload::text) as lc
  from ingest.raw_records r
  join ingest.sources s on s.id = r.source_id
  where s.slug in (
    'kde-district-facility-plans',
    'indiana-dlgf-school-capital-projects',
    'kentucky-transparency-contracts'
  )
), source_counts as (
  select
    count(*) filter(where lc ~ '(
      roof restoration|restore[^a-z]{0,20}roof|roof recover|roof re-cover|
      recover[^a-z]{0,20}roof|roof resurfacing|roof membrane coating|
      fluid[- ]applied roof|silicone[^a-z]{0,20}roof|acrylic[^a-z]{0,20}roof|
      elastomeric[^a-z]{0,20}roof|recoat(ing)?[^a-z]{0,45}(metal )?roof|
      roof[^a-z]{0,45}recoat(ing)?
    )')::bigint as explicit_restoration_scope,
    count(*) filter(where lc ~ '(roof replacement|replace[^a-z]{0,20}roof|re-roof|reroof)')::bigint as explicit_replacement_scope,
    count(*) filter(where lc ~ '(roof repair|roofing repair|repair[^a-z]{0,20}roof)')::bigint as explicit_repair_scope
  from raw
), pm as (
  select lower(regexp_replace(regexp_replace(trim(site_address_text),'[.,]','','g'),'\s+',' ','g')) as a0
  from scout.v_property_management_facilities
  where state='KY' and site_address_text is not null
), pmn as (
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(a0,
    '\bstreet\b','st','g'),'\broad\b','rd','g'),'\bdrive\b','dr','g'),'\blane\b','ln','g'),
    '\bavenue\b','ave','g'),'\bboulevard\b','blvd','g'),'\bparkway\b','pky','g'),'\bhighway\b','hwy','g') as an
  from pm
), ra as (
  select lower(regexp_replace(regexp_replace(trim(subject_key),'[.,]','','g'),'\s+',' ','g')) as a0
  from intelligence.v_roof_lifecycle_pressure
  where subject_type='address'
), ran as (
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(a0,
    '\bstreet\b','st','g'),'\broad\b','rd','g'),'\bdrive\b','dr','g'),'\blane\b','ln','g'),
    '\bavenue\b','ave','g'),'\bboulevard\b','blvd','g'),'\bparkway\b','pky','g'),'\bhighway\b','hwy','g') as an
  from ra
), overlap as (
  select count(*)::bigint as n
  from pmn
  where exists(select 1 from ran where ran.an=pmn.an)
)
select 'active_roof_lifecycle_age_anchors'::text as metric,
       count(*)::bigint as records,
       'Current roof lifecycle pressure records are address-level new-construction age proxies; useful as corroboration, not coating evidence.'::text as interpretation
from intelligence.v_roof_lifecycle_pressure
union all
select 'explicit_roof_restoration_or_recoat_scope', explicit_restoration_scope,
       'Roof restoration/recoat scope is now observed but rare in surveyed feeds; Oldham County KDE planning text explicitly includes recoating a metal gym roof.'
from source_counts
union all
select 'explicit_roof_replacement_scope', explicit_replacement_scope,
       'Replacement is observable and must be separated from restoration/recoat because prep-cleaning economics differ.'
from source_counts
union all
select 'explicit_roof_repair_scope', explicit_repair_scope,
       'Repair is observable but is not sufficient to infer a restoration coating or exterior-cleaning subtask.'
from source_counts
union all
select 'property_management_facilities_directly_overlapping_roof_age_anchors', n,
       'Direct normalized-address overlap remains insufficient; portfolio-aware roof inference needs a building/property crosswalk rather than string matching.'
from overlap;

comment on view research.v_roof_treatment_observability_probe is
  'Research-only roof treatment observability probe. Distinguishes rare observed restoration/recoat scope from replacement/repair and age-only context.';

-- Source-scoped semantic probe. It intentionally avoids global raw-payload keyword
-- matching and uses scope-bearing project/document fields from authoritative planning feeds.
create or replace view research.v_surface_preservation_semantic_probe as
with scope_rows as (
  select
    'indiana-dlgf-school-capital-projects'::text as source_slug,
    r.source_native_id,
    r.raw_payload->>'unit_name' as buyer_name,
    r.raw_payload->>'project_title' as project_label,
    r.raw_payload->>'plan_year' as timing_text,
    r.raw_payload->>'estimated_cost' as amount_text,
    'project_row'::text as evidence_granularity,
    concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block') as scope_text
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='indiana-dlgf-school-capital-projects'
    and r.source_native_id like 'candidate|%'

  union all

  select
    'kde-district-facility-plans',
    r.source_native_id,
    r.raw_payload->>'district_label',
    coalesce(r.raw_payload->>'document_name',r.source_native_id),
    coalesce(r.raw_payload->>'schedule_bucket',r.raw_payload->>'kde_approval_date_text'),
    r.raw_payload->>'estimated_cost',
    'document_text',
    r.raw_payload->>'extracted_text'
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='kde-district-facility-plans'
    and coalesce(r.raw_payload->>'extracted_text','')<>''

  union all

  select
    'ky-cpab-2024-2030-projects',
    r.source_native_id,
    r.raw_payload->>'agency_name',
    coalesce(r.raw_payload->>'project_title',r.raw_payload->>'document_name',r.source_native_id),
    coalesce(r.raw_payload->>'biennium',r.raw_payload->>'plan_year'),
    r.raw_payload->>'estimated_budget',
    case when coalesce(r.raw_payload->>'project_title','')<>'' then 'project_or_document_text' else 'document_text' end,
    coalesce(r.raw_payload->>'extracted_text',r.raw_payload->>'raw_line',r.raw_payload::text)
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='ky-cpab-2024-2030-projects'
), normalized as (
  select *, lower(coalesce(scope_text,'')) as scope_lc
  from scope_rows
), matched as (
  select n.*,
         f.signal_family,
         f.family_regex
  from normalized n
  cross join lateral (values
    ('masonry_restoration_tuckpoint_seal'::text, '(clean(ing)?[^a-z]{0,35}(brick|masonry|stone)|tuck[ -]?point|repoint|masonry restoration|masonry repair[^a-z]{0,35}(seal|clean)|seal(ing)?[^a-z]{0,30}(masonry|brick|stone))'::text),
    ('joint_sealant_caulk', '(joint sealant|exterior sealant|sealant replacement|caulk|caulking)'),
    ('waterproofing', '(waterproofing|water proofing|waterproof[^a-z]{0,30}(wall|masonry|concrete|exterior|roof structure))'),
    ('eifs_dryvit_preservation', '(eifs|dryvit|dri-it)'),
    ('concrete_clean_repair_coat', '(concrete cleaning|clean(ing)?[^a-z]{0,25}concrete|concrete[^a-z]{0,30}(repair|coat|coating|sealant|sealer))'),
    ('roof_recoat_restoration', '(roof restoration|restore[^a-z]{0,20}roof|roof recover|roof re-cover|recover[^a-z]{0,20}roof|roof resurfacing|roof membrane coating|fluid[- ]applied roof|silicone[^a-z]{0,20}roof|acrylic[^a-z]{0,20}roof|elastomeric[^a-z]{0,20}roof|recoat(ing)?[^a-z]{0,45}(metal )?roof|roof[^a-z]{0,45}recoat(ing)?)'),
    ('exterior_paint_recoat', '(exterior[^a-z]{0,40}(paint|painting|repaint|coat|coating)|repaint[^a-z]{0,30}(exterior|eifs|dryvit)|recoat[^a-z]{0,30}(exterior|eifs|dryvit))')
  ) as f(signal_family,family_regex)
  where n.scope_lc ~ f.family_regex
), flags as (
  select *,
    (scope_lc ~ '(pressure wash|power wash|wash(ing)?[^a-z]{0,35}(exterior|brick|masonry|concrete|eifs|surface)|clean(ing)?[^a-z]{0,35}(brick|masonry|stone|concrete|eifs|exterior))') as cleaning_explicit,
    case signal_family
      when 'masonry_restoration_tuckpoint_seal' then (scope_lc ~ '(tuck[ -]?point|repoint|masonry restoration|seal(ing)?[^a-z]{0,30}(masonry|brick|stone))')
      when 'joint_sealant_caulk' then true
      when 'waterproofing' then true
      when 'eifs_dryvit_preservation' then (scope_lc ~ '(paint|repaint|coat|coating|repair|resurface)')
      when 'concrete_clean_repair_coat' then (scope_lc ~ '(repair|coat|coating|sealant|sealer)')
      when 'roof_recoat_restoration' then true
      when 'exterior_paint_recoat' then true
      else false
    end as downstream_treatment_explicit
  from matched
)
select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,
       evidence_granularity,signal_family,cleaning_explicit,downstream_treatment_explicit,
       case
         when cleaning_explicit and downstream_treatment_explicit then
           case when evidence_granularity='project_row' then 'explicit_cleaning_plus_treatment_same_project_row'
                else 'cleaning_plus_treatment_same_document_requires_scope_resolution' end
         when cleaning_explicit then 'explicit_cleaning_downstream_treatment_unresolved'
         when downstream_treatment_explicit then 'downstream_treatment_explicit_prep_unresolved'
         else 'adjacent_envelope_work_only'
       end as cleaning_relationship_semantics,
       left(scope_text,1800) as evidence_excerpt
from flags;

comment on view research.v_surface_preservation_semantic_probe is
  'Research-only semantic probe across scope-bearing public capital/facility plan fields. Broadens paint research to masonry, sealants, waterproofing, EIFS, concrete and roof restoration.';

create or replace view research.v_surface_preservation_semantic_summary as
select source_slug,signal_family,cleaning_relationship_semantics,count(*)::bigint as records
from research.v_surface_preservation_semantic_probe
group by source_slug,signal_family,cleaning_relationship_semantics;

comment on view research.v_surface_preservation_semantic_summary is
  'Research-only counts for surface-preservation semantic evidence. Not an opportunity feed.';

-- Current Kentucky statewide/postsecondary capital plans now have proven envelope
-- preservation scope (e.g. UofL concrete cleaning/repairs + joint sealants).
insert into research.surface_work_source_capabilities (
  capability_key,selector_type,selector_value,
  asset_identity_resolution,buyer_resolution,project_scope_resolution,
  timing_resolution,prep_relationship_resolution,semantic_noise_risk,
  observed_strength,evidence_summary,limitations
) values (
  'kentucky_cpab_capital_plans','source_slug','ky-cpab-2024-2030-projects',
  'partial','strong','partial','partial','partial','medium','strong',
  'Kentucky CPAB project listings expose public-agency/postsecondary capital work; observed University of Louisville exterior-envelope scope includes joint sealants plus concrete cleaning and repairs.',
  'Document/project granularity varies; resolve relevant text to a specific facility and avoid assuming every envelope project contains drone-compatible cleaning.'
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
  reviewed_at=now();

-- Strong newly-observed family: cleaning is often explicitly paired with masonry
-- restoration, tuckpointing and sealing in multi-year public facility plans.
insert into research.surface_work_signal_survey (
 survey_key,business_type,structure_type,surface_family,example_work,cleaning_relationship,
 signal_modes,observability,scout_coverage,current_data_paths,opportunity_fit,hazard_flags,
 primary_next_source,evidence_basis,evidence_urls,source_gap,notes,survey_rank,status
) values
('institutional:masonry_clean_tuckpoint_seal','school_district','masonry_building_envelope','masonry_envelope_preservation',
 array['clean exterior brick','clean and tuckpoint masonry','tuckpoint and seal exterior walls','masonry restoration and waterproofing'],
 'explicit_common',array['facility_plan','capital_plan','renovation','procurement'],'high','strong',
 array['kde-district-facility-plans','indiana-dlgf-school-capital-projects'],'strong',
 array['historic_masonry_method_sensitivity','water_intrusion_diagnosis'],
 'KDE district facility plans and Indiana school capital plans',
 'Existing authoritative plans repeatedly contain cleaning, tuckpointing, masonry repair, sealing and waterproofing scopes.',
 array[]::text[],
 'Resolve document-level KDE scopes to exact facility/project rows and distinguish compatible washing from preservation-sensitive cleaning.',
 'This is a broader and often cleaner signal than paint alone because exterior cleaning is frequently explicit in the preservation scope.',5,'survey_candidate'),

('institutional:joint_sealant_caulk','school_district','building_envelope_joints','joint_sealant_renewal',
 array['exterior sealant replacement','caulking repair','joint sealant replacement'],
 'conditional_prep',array['facility_plan','capital_plan','renovation'],'medium','strong',
 array['kde-district-facility-plans','indiana-dlgf-school-capital-projects','ky-cpab-2024-2030-projects'],'testable',
 array['joint_failure_water_intrusion','substrate_specific_prep'],
 'Public facility plans and capital project listings',
 'Current authoritative planning feeds contain exterior sealant and caulking renewal scopes.',
 array[]::text[],
 'Cleaning may be localized joint preparation rather than a broad wash; only promote when compatible exterior cleaning scope or adjacent envelope work is evidenced.',
 'Useful as an adjacency/timing signal, not automatically a standalone drone-cleaning lead.',39,'survey_candidate'),

('institutional:waterproofing_masonry_envelope','postsecondary_institution','masonry_or_concrete_envelope','waterproofing_and_water_repellent_treatment',
 array['masonry restoration and waterproofing','water-repellent treatment','parking structure waterproofing'],
 'strong_standard_prep',array['facility_plan','capital_plan','renovation','procurement'],'medium','partial',
 array['kde-district-facility-plans','ky-cpab-2024-2030-projects'],'testable',
 array['historic_masonry_method_sensitivity','moisture_diagnosis','product_specific_surface_requirements'],
 'KDE facility plans plus public capital plans',
 'Current plans explicitly include masonry restoration/waterproofing and parking-structure waterproofing.',
 array[]::text[],
 'Need treatment specifications and substrate/material context before inferring a compatible cleaning method.',
 'Waterproofing is commercially relevant because clean/dry substrate preparation matters, but treatment-specific guardrails are essential.',40,'survey_candidate'),

('institutional:concrete_clean_repair_coating','postsecondary_institution','exterior_concrete_envelope_or_structure','concrete_preservation',
 array['concrete cleaning and repairs','concrete protective coating','concrete sealing'],
 'explicit_common',array['capital_plan','renovation','procurement'],'medium','partial',
 array['ky-cpab-2024-2030-projects','kde-district-facility-plans'],'testable',
 array['spalling_or_structural_damage','coating_system_compatibility'],
 'Public university/state capital plans',
 'University of Louisville capital-plan text explicitly combines exterior-envelope work, joint sealants, concrete cleaning and repairs.',
 array[]::text[],
 'Expand concrete preservation project feeds and resolve whether cleaning is broad-area preparation or localized repair preparation.',
 'Strong semantic fit; current record count is small but evidence quality is high.',41,'survey_candidate'),

('cultural_venue:museum_performing_arts_envelope','facilities_management_company','museum_or_performing_arts_facility','high_visibility_cultural_envelope',
 array['facade repaint','masonry restoration','architectural metal recoating','sealant renewal'],
 'strong_standard_prep',array['capital_plan','renovation','procurement','preservation_plan'],'medium','strong',
 array['intelligence.premium_exterior_targets'],'testable',
 array['historic_preservation','public_access','sensitive_finishes'],
 'Museum/arts capital plans, public procurement and preservation projects',
 'Scout already has museum/performing-arts physical targets but no normalized surface-preservation timing feed.',
 array[]::text[],
 'Add project/capital-plan evidence before using target presence as timing evidence.',
 'Missing facility class from the original survey; high-visibility envelope upkeep makes it worth testing.',42,'survey_candidate'),

('public_recreation:park_lodge_facility_envelope','state_land_manager','park_lodge_recreation_facility','public_recreation_asset_preservation',
 array['lodge exterior painting','masonry sealing','historic structure repaint','shelter and facility coating'],
 'conditional_prep',array['capital_plan','procurement','deferred_maintenance'],'medium','partial',
 array['kentucky-transparency-contracts','environment.managed_land_areas'],'testable',
 array['historic_preservation','public_access','remote_site_access'],
 'State park capital plans, procurement and facilities maintenance contracts',
 'Scout resolves public land managers and parks; Kentucky procurement also contains parks/facility maintenance vendors, but detailed surface scope is inconsistent.',
 array[]::text[],
 'Need facility-level park/lodge assets plus scope-bearing maintenance/project records.',
 'Potential repeat public buyer; keep separate from generic land management because the opportunity is on built facilities.',43,'survey_candidate'),

('cemetery:mausoleum_masonry_preservation','cemetery_organization','mausoleum_or_memorial_masonry','masonry_preservation',
 array['mausoleum cleaning','stone repointing','water-repellent treatment'],
 'conditional_prep',array['capital_project','preservation','procurement'],'low','partial',
 array['cemetery organizations','historic resource context'],'conditional',
 array['historic_stone_sensitivity','memorial_site_sensitivity','low_pressure_cleaning_requirement'],
 'Cemetery capital/preservation projects and mausoleum inventories',
 'Scout has cemetery organizations/locations, but current surface-preservation timing evidence is sparse.',
 array[]::text[],
 'Need asset scale, material and active project evidence; many sites will not meet commercial scale.',
 'Worth retaining as a narrow preservation case, not a broad lead family.',44,'survey_candidate'),

('industrial_port:crane_gantry_structural_steel','industrial_logistics_operator','port_crane_or_industrial_gantry','protective_steel_coating',
 array['crane repaint','gantry protective coating','corrosion-control coating'],
 'strong_standard_prep',array['maintenance_contract','capital_project','procurement'],'low','none',
 array[]::text[],'testable',
 array['active_industrial_site','fall_hazard','lead_or_legacy_coating','containment'],
 'Port authority/terminal capital plans and coating procurements',
 'Large painted steel structures have a strong surface-preparation relationship, but Scout currently lacks a normalized port/crane asset and project layer.',
 array[]::text[],
 'Add authoritative port/terminal assets and maintenance procurement before promotion.',
 'Commercially plausible missing structure family; deliberately held below proven bridge/tank families.',45,'hold'),

('industrial_facility:cooling_tower_exterior','industrial_logistics_operator','cooling_tower','tower_envelope_coating',
 array['cooling tower exterior coating','concrete tower coating','FRP surface restoration'],
 'conditional_prep',array['capital_project','maintenance','procurement'],'low','partial',
 array['school capital plans mention cooling towers but do not normalize coating need'],'conditional',
 array['industrial_process','chemical_exposure','material_specific_cleaning','operational_shutdown'],
 'Utility/industrial facility maintenance and cooling-tower rehab projects',
 'Cooling towers appear in capital plans as assets but current Scout sources do not establish a recurring exterior coating/cleaning signal.',
 array[]::text[],
 'Need asset material, process safety, outage and coating-scope evidence.',
 'Keep as a guarded research family; not equivalent to a water tower.',46,'hold'),

('fuel_retail:canopy_facade_reimage','corporate_parent','fuel_station_canopy_or_cstore','brand_reimage_exterior_finish',
 array['canopy repaint','brand reimage','facade repaint','metal panel refresh'],
 'strong_standard_prep',array['reimage_program','renovation','permit','portfolio_capex'],'low','none',
 array[]::text[],'testable',
 array['fuel_site','traffic','electrical_canopy'],
 'Fuel-retail reimage programs, permits and portfolio capital projects',
 'Brand-driven exterior refreshes are a plausible repeat portfolio signal but are not represented in current Scout project sources.',
 array[]::text[],
 'Need operator portfolio and reimage/permit source before promotion; site values may be small individually.',
 'Potential account-level play rather than a premium single-site lead.',47,'hold'),

('self_storage:metal_envelope_roof','property_management_company','self_storage_facility','metal_envelope_and_roof_preservation',
 array['metal wall repaint','roof recoat','door and trim repaint'],
 'strong_standard_prep',array['portfolio_capex','roof_lifecycle','renovation'],'low','none',
 array[]::text[],'testable',
 array['occupied_site_access'],
 'Self-storage operator portfolios, roofing/coating permits and capital projects',
 'Large repetitive metal envelopes can create scalable maintenance economics, but Scout has no dedicated self-storage portfolio/timing layer yet.',
 array[]::text[],
 'Validate operator concentration, building scale and observable treatment timing before building coverage.',
 'Worth a later portfolio experiment; not enough current evidence for production.',48,'hold')
on conflict (survey_key) do update set
  business_type=excluded.business_type,
  structure_type=excluded.structure_type,
  surface_family=excluded.surface_family,
  example_work=excluded.example_work,
  cleaning_relationship=excluded.cleaning_relationship,
  signal_modes=excluded.signal_modes,
  observability=excluded.observability,
  scout_coverage=excluded.scout_coverage,
  current_data_paths=excluded.current_data_paths,
  opportunity_fit=excluded.opportunity_fit,
  hazard_flags=excluded.hazard_flags,
  primary_next_source=excluded.primary_next_source,
  evidence_basis=excluded.evidence_basis,
  evidence_urls=excluded.evidence_urls,
  source_gap=excluded.source_gap,
  notes=excluded.notes,
  survey_rank=excluded.survey_rank,
  status=excluded.status,
  reviewed_at=now(),
  updated_at=now();

-- Churchill Downs demonstrates that racetrack preservation is broader than exposed
-- steel: painted masonry, grandstand facades, entrances, railings, bleachers,
-- architectural finishes and recurring capital upgrades all matter.
update research.surface_work_signal_survey
set surface_family='high_visibility_venue_envelope_and_structural_finish',
    example_work=array['grandstand facade repaint','painted masonry preservation','railings and exposed steel coating','architectural entrance/finish renewal','bleacher/grandstand preservation'],
    signal_modes=array['capital_project','renovation','marquee_event_cycle','facilities_maintenance','procurement'],
    source_gap='Scout resolves racetrack/venue assets, but needs scope-bearing facilities/capital project feeds to distinguish surface-preservation work from generic venue renovation.',
    notes='Churchill Downs is the anchor case: the historic grandstand has a long-lived painted-white exterior and CDI undertakes recurring major capital renovations. Treat this as a high-visibility recurring asset-preservation account pattern, not as proof that every renovation contains exterior cleaning.',
    reviewed_at=now(),updated_at=now()
where survey_key='racetrack_operator:grandstand_and_exposed_steel';

update research.surface_work_signal_survey
set source_gap='Current Scout sources expose roof age, replacement and repair context plus a rare explicit metal-roof recoating scope in KDE facility plans; private portfolio treatment timing and property/building crosswalks remain gaps.',
    notes='Potentially high-frequency across portfolios. 2026-09-07 survey now has an explicit Oldham County metal gym roof recoating example; roof restoration is observable but rare, while current lifecycle pressure remains based on new-construction age proxies.',
    reviewed_at=now(),updated_at=now()
where survey_key='commercial_property:roof_recoating';

revoke all on research.v_roof_treatment_observability_probe from anon,authenticated;
revoke all on research.v_surface_preservation_semantic_probe from anon,authenticated;
revoke all on research.v_surface_preservation_semantic_summary from anon,authenticated;
revoke all on research.surface_work_source_capabilities from anon,authenticated;
revoke all on research.surface_work_signal_survey from anon,authenticated;
