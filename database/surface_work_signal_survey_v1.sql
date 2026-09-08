-- Scout by Cadastory
-- Research-only survey of painting/coating work as a cleaning-opportunity signal.
--
-- This is deliberately NOT a production taxonomy, opportunity source, scoring input,
-- or MCP-facing surface.  It exists to compare structure/business families before
-- promotion into production decisioning.

create schema if not exists research;

create table if not exists research.surface_work_signal_survey (
  survey_key text primary key,
  business_type text not null,
  structure_type text not null,
  surface_family text not null,
  example_work text[] not null default '{}',
  cleaning_relationship text not null check (cleaning_relationship in (
    'explicit_common',
    'strong_standard_prep',
    'conditional_prep',
    'weak_inference',
    'not_relevant'
  )),
  signal_modes text[] not null default '{}',
  observability text not null check (observability in ('high','medium','low')),
  scout_coverage text not null check (scout_coverage in ('strong','partial','none')),
  current_data_paths text[] not null default '{}',
  opportunity_fit text not null check (opportunity_fit in (
    'strong','testable','conditional','deprioritize','exclude'
  )),
  hazard_flags text[] not null default '{}',
  primary_next_source text,
  evidence_basis text,
  evidence_urls text[] not null default '{}',
  source_gap text,
  notes text,
  survey_rank integer not null check (survey_rank > 0),
  status text not null default 'survey_candidate' check (status in (
    'survey_candidate','hold','negative_control'
  )),
  reviewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table research.surface_work_signal_survey is
  'Research-only cross-sector survey of painting/recoating/coating work as a cleaning or surface-preparation signal. Not authoritative, not customer-facing, and not used in Scout scoring until separately promoted.';

create index if not exists surface_work_signal_survey_rank_idx
  on research.surface_work_signal_survey (survey_rank);
create index if not exists surface_work_signal_survey_fit_idx
  on research.surface_work_signal_survey (opportunity_fit, observability);
create index if not exists surface_work_signal_survey_status_idx
  on research.surface_work_signal_survey (status);

revoke all on table research.surface_work_signal_survey from anon, authenticated;

insert into research.surface_work_signal_survey (
  survey_key, business_type, structure_type, surface_family, example_work,
  cleaning_relationship, signal_modes, observability, scout_coverage,
  current_data_paths, opportunity_fit, hazard_flags, primary_next_source,
  evidence_basis, evidence_urls, source_gap, notes, survey_rank, status
) values
(
  'water_utility:elevated_water_tank_exterior', 'water_utility', 'elevated_water_tank', 'coated_steel_exterior',
  array['paint','repaint','recoat','overcoat','cleaning and painting','blasting and coating'],
  'explicit_common', array['capital_plan','rehabilitation_project','procurement','lifecycle'], 'high', 'strong',
  array['water.tanks','water.tank_projects','scout.v_water_tank_opportunity_candidates','scout.v_opportunity_water_tank_geometry_context'],
  'strong', array['lead_coating_possible','containment_possible','interior_scope_must_be_separated'],
  'KY WRIS project purpose plus utility procurement documents',
  'Existing Scout records already contain explicit cleaning-plus-painting and cleaning-plus-recoating scopes; coating manufacturers and AWWA practice require prepared clean substrates.',
  array['https://industrial.sherwin-williams.com/na/us/en/protective-marine/media-center/articles/awwa-d102-coating-standard-water.html'],
  'Expand beyond Kentucky and resolve project scope to exterior versus interior.',
  'Best initial production candidate because asset identity, utility ownership, morphology, and project evidence already coexist.',
  1, 'survey_candidate'
),
(
  'water_utility:ground_storage_tank_exterior', 'water_utility', 'ground_storage_tank', 'coated_steel_exterior',
  array['repaint','recoat','overcoat','mildew removal before coating'],
  'explicit_common', array['capital_plan','rehabilitation_project','procurement','lifecycle'], 'high', 'strong',
  array['water.tanks','water.tank_projects','water.v_tank_maintenance_candidates'],
  'strong', array['lead_coating_possible','containment_possible'],
  'Water utility capital plans, inspection reports, and coating procurements',
  'Existing tank project language and coating practice support cleaning as a recurring preparation step, including power washing on overcoat projects.',
  array['https://www.tnemec.com/projects/village-oak-lawn-water-tank/'],
  'Need broader non-WRIS tank project feeds.',
  'Geometry differs from elevated towers but the surface-work signal is equally clean.',
  2, 'survey_candidate'
),
(
  'transportation_agency:steel_bridge_superstructure', 'state_transportation_agency', 'steel_bridge', 'protective_coated_structural_steel',
  array['clean and paint structural steel','maintenance painting','overcoating','spot painting','protective coating rehabilitation'],
  'explicit_common', array['element_condition','inspection_condition','stip','letting','procurement'], 'high', 'strong',
  array['transportation.bridges','transportation.bridge_projects','transportation.v_bridge_proposed_work_context','intelligence.business_need_signals'],
  'strong', array['lead_coating_possible','containment_possible','traffic_control','waterway_environmental_controls'],
  'FHWA element 515 plus state DOT bid-item and letting feeds',
  'FHWA maintenance-painting guidance states washing should be included in maintenance painting to remove contaminants that affect coating life.',
  array['https://www.fhwa.dot.gov/publications/research/infrastructure/structures/bridge/overct.cfm','https://www.fhwa.dot.gov/publications/research/infrastructure/structures/98084/intro.cfm'],
  'Add coating-element and pay-item collectors in KY/IN/OH.',
  'Condition evidence can open a pre-procurement window before a clean-and-paint contract is advertised.',
  3, 'survey_candidate'
),
(
  'school_district:exterior_building_painting', 'school_district', 'school_building', 'painted_facade_and_trim',
  array['exterior painting','district-wide painting','Dryvit coating','exterior renovation and painting'],
  'strong_standard_prep', array['capital_plan','procurement','summer_maintenance'], 'high', 'strong',
  array['ingest:indiana-dlgf-school-capital-projects','intelligence.premium_exterior_targets','core.organizations'],
  'strong', array['historic_surface_possible','occupied_campus','substrate_specific_pressure_limits'],
  'School capital plans and district bid postings',
  'Scout already observes explicit future exterior-painting and facade-coating projects in Indiana school capital plans; facade coatings commonly require contaminant removal and power washing.',
  array['https://usa.sika.com/en/construction-products/coatings-water-repellents/building-facade/sika-thorocoat-250.html'],
  'Classify interior versus exterior plan items and resolve each project to a campus/building.',
  'Unexpectedly strong early-warning source because plans identify work years before procurement.',
  4, 'survey_candidate'
),
(
  'commercial_property:roof_recoating', 'property_management_company', 'commercial_roof', 'liquid_applied_roof_coating',
  array['roof coating','silicone coating','acrylic coating','recoat','restoration coating'],
  'strong_standard_prep', array['roof_lifecycle','capital_plan','permit','procurement'], 'high', 'strong',
  array['intelligence.v_roof_lifecycle_pressure','scout.v_property_management_facilities','decisioning.v_building_resolved_attributes'],
  'strong', array['fall_hazard','roof_membrane_damage_risk','asbestos_possible','washoff_controls'],
  'Roofing permits, reroof/coating specifications, portfolio capital plans',
  'Liquid-applied commercial roofing manuals require removal of dirt, dust, grease and contaminants and commonly specify pressure washing before coating.',
  array['https://www.gaf.com/en-us/document-library/documents/manuals/liquid-applied-roofing-manual-comco180.pdf','https://www.gaf.com/en-us/blog/commercial-roofing/when-and-how-to-install-silicone-commercial-roof-coatings-a83c9019-a1fb-4289-99f3-41c3daaa4384'],
  'Need source-specific distinction between replacement roofs and coating/restoration roofs.',
  'Potentially much higher-frequency than bridge painting and directly overlaps existing roof lifecycle data.',
  5, 'survey_candidate'
),
(
  'commercial_property:painted_facade_recoating', 'property_management_company', 'commercial_building_facade', 'concrete_stucco_eifs_coating',
  array['facade coating','elastomeric coating','stucco repaint','EIFS coating','concrete repaint'],
  'strong_standard_prep', array['capital_plan','renovation','permit','procurement'], 'high', 'strong',
  array['intelligence.premium_exterior_targets','scout.v_property_management_facilities','decisioning.v_building_resolved_attributes'],
  'strong', array['substrate_specific_pressure_limits','window_masking','historic_surface_possible'],
  'Renovation scopes, facade-coating bids, property capital plans',
  'Commercial facade coating systems require clean sound substrates and commonly specify high-pressure washing or other surface preparation.',
  array['https://usa.sika.com/en/construction-products/coatings-water-repellents/building-facade/sika-thorocoat-250.html'],
  'Need facade material/coating-state resolution and better renovation-scope text.',
  'Strong horizontal signal across hotels, dealerships, offices, schools, hospitals, venues, and managed portfolios.',
  6, 'survey_candidate'
),
(
  'industrial_operator:aboveground_storage_tank', 'industrial_logistics_operator', 'aboveground_storage_tank', 'coated_steel_exterior',
  array['maintenance painting','tank repaint','protective coating','corrosion coating rehabilitation'],
  'strong_standard_prep', array['inspection_condition','maintenance_plan','procurement','capital_project'], 'medium', 'partial',
  array['scout.v_industrial_logistics_accounts','core.v_asset_business_entity_context'],
  'strong', array['hazardous_contents','process_safety','lead_coating_possible','containment_possible'],
  'Facility permits, SPCC inventories where public, maintenance bids, owner capital plans',
  'Industrial steel-tank coating guidance treats surface preparation and contaminant removal as critical to coating adhesion and service life.',
  array['https://nepis.epa.gov/Exe/ZyPURL.cgi?Dockey=9400801S.TXT'],
  'Scout lacks a normalized aboveground-tank asset layer and public maintenance-event collector.',
  'Very attractive economically but should remain gated by process safety and asset-content context.',
  7, 'survey_candidate'
),
(
  'dam_lock_operator:hydraulic_steel', 'public_utility', 'dam_lock_gate_penstock', 'hydraulic_structural_steel',
  array['gate recoating','protective coating maintenance','corrosion coating repair','sandblast and recoat'],
  'strong_standard_prep', array['inspection_condition','maintenance_plan','capital_project','procurement'], 'medium', 'partial',
  array['scout.v_dam_opportunity_candidates','ingest:usace-nid'],
  'strong', array['water_control_structure','confined_space_possible','lead_coating_possible','lockout_required'],
  'USACE/Reclamation maintenance plans, dam owner capital projects, procurement',
  'USACE and Reclamation guidance treats protective coatings as a primary corrosion-control system for hydraulic steel structures and explicitly plans for future coating repair access.',
  array['https://www.publications.usace.army.mil/portals/76/publications/engineertechnicalletters/etl_1110-2-584.pdf','https://www.usbr.gov/tsc/techreferences/mands/mands-abstracts/manabs19.html'],
  'NID provides asset/owner context but not coating-condition or work-order detail.',
  'High-value structure family; likely lower event volume than roofs/facades but strong work linkage.',
  8, 'survey_candidate'
),
(
  'telecom_operator:aviation_marked_tower', 'telecom_operator', 'communication_tower', 'aviation_marking_coating',
  array['reapply aviation marking','tower repaint','orange-white marking restoration'],
  'strong_standard_prep', array['marking_condition','inspection','owner_maintenance','procurement'], 'medium', 'strong',
  array['telecom.asr_structures','scout.v_telecom_opportunity_candidates','telecom.v_tower_responsibility'],
  'testable', array['rf_exposure','fall_hazard','energized_equipment','critical_surfaces_excluded'],
  'FAA determination/marking requirements plus tower-owner maintenance/procurement',
  'Current FAA marking guidance says outdoor markings deteriorate and should be reapplied when effectiveness is reduced by scaling, oxidation, chipping, or contamination; manufacturer-directed surface preparation applies.',
  array['https://www.faa.gov/documentLibrary/media/Advisory_Circular/2026-07-13_AC_70_7460-1N_Obstruction_Marking_and_Lighting_FINAL_CLEAN.pdf'],
  'ASR does not itself report paint condition; need marking-requirement resolution and maintenance evidence.',
  'Good lifecycle hypothesis, but do not infer an active paint job merely from tower age or registration.',
  9, 'survey_candidate'
),
(
  'sports_venue:stadium_structural_steel', 'amusement_venue_operator', 'stadium_or_arena', 'exposed_structural_steel',
  array['stadium repaint','structural steel recoating','corrosion coating rehabilitation'],
  'strong_standard_prep', array['capital_plan','renovation','event_deadline','procurement'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets','intelligence.marquee_event_paper_trail'],
  'strong', array['public_occupancy','containment_possible','lead_coating_possible'],
  'Venue capital plans, public-owner bids, renovation announcements',
  'Stadium coating rehabilitation commonly uses blast-cleaned or otherwise prepared structural steel before new protective coating systems.',
  array['https://www.tnemec.com/projects/ladd-peeples-stadium/'],
  'Need venue-specific capital-project and procurement collectors.',
  'Marquee event deadlines can create unusually strong timing context around otherwise ordinary coating work.',
  10, 'survey_candidate'
),
(
  'amusement_operator:roller_coaster_and_ride_steel', 'amusement_venue_operator', 'roller_coaster_or_thrill_ride', 'coated_complex_structural_steel',
  array['roller coaster repaint','ride recoating','corrosion remediation and repaint'],
  'strong_standard_prep', array['inspection_condition','offseason_maintenance','rehabilitation','procurement'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets','core.organizations'],
  'strong', array['complex_geometry','lockout_tagout','public_occupancy','specialized_access'],
  'Park maintenance announcements, coating bids, owner capital plans',
  'AMPP describes ride recoating as a corrosion-control rehabilitation workflow in which condition/adhesion testing drives surface preparation and repainting.',
  array['https://blogs.ampp.org/protectperform/recoating-amusement-park-rides'],
  'Need park-project collector and ride-level asset inventory.',
  'Niche but high-dollar, visually compelling, and highly compatible with Scout demo storytelling.',
  11, 'survey_candidate'
),
(
  'railroad:rail_bridge_and_gantry', 'railroad', 'rail_bridge_or_signal_gantry', 'protective_coated_structural_steel',
  array['bridge painting','steel recoating','gantry repaint','corrosion coating repair'],
  'strong_standard_prep', array['capital_plan','bridge_program','procurement','condition'], 'medium', 'partial',
  array['transportation.rail_lines','transportation.rail_yards','scout.v_rail_opportunity_candidates'],
  'testable', array['active_railroad','railroad_protection_required','lead_coating_possible'],
  'Railroad capital plans, public grant project scopes, bridge contracts',
  'Structural-steel coating maintenance follows the same adhesion and surface-preparation mechanics as highway bridge steel.',
  array['https://www.transit.dot.gov/sites/fta.dot.gov/files/2022-03/AASHTO-Transportation-Asset-Management-Guide.pdf'],
  'Current Scout rail candidates are crossing-risk oriented rather than bridge/coating oriented.',
  'Promising account-expansion signal once rail bridge assets and capital projects are better normalized.',
  12, 'survey_candidate'
),
(
  'grain_operator:grain_bin_silo_elevator_exterior', 'grain_operator', 'grain_bin_silo_elevator', 'painted_or_coated_metal_concrete_exterior',
  array['bin painting','silo coating','elevator exterior repaint','aviation marking restoration'],
  'conditional_prep', array['maintenance_plan','procurement','marking_condition','facility_rehab'], 'medium', 'strong',
  array['agriculture.grain_facilities','core.v_asset_portfolio_resolution'],
  'conditional', array['combustible_dust','ignition_control','food_feed_operation','fall_hazard'],
  'Grain operator maintenance scopes, FAA marking context, facility capital projects',
  'OSHA emphasizes strict dust-housekeeping hazards at grain facilities; the same source notes smooth painted surfaces can reduce dust adhesion and improve cleanability. Any work here needs specialized combustible-dust controls.',
  array['https://www.osha.gov/grain-handling/geeit','https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.272'],
  'Need exterior-only maintenance evidence and strong safety gating before promotion.',
  'Useful signal family, but never treat ordinary grain dust as permission for generic pressure washing.',
  13, 'survey_candidate'
),
(
  'hotel_management:facade_repaint_or_brand_refresh', 'hotel_management_company', 'hotel', 'painted_facade_and_exterior_coating',
  array['exterior repaint','brand refresh','facade recoating','stucco coating'],
  'strong_standard_prep', array['renovation','brand_conversion','capital_plan','permit'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets','core.organizations'],
  'testable', array['guest_occupancy','window_masking','substrate_specific_pressure_limits'],
  'Hotel renovation permits, brand conversion/PIP announcements, owner capital plans',
  'Facade coating systems typically require contaminant removal before recoating; hotel renovations can supply a time-bounded trigger if exterior scope is explicit.',
  array['https://usa.sika.com/en/construction-products/coatings-water-repellents/building-facade/sika-thorocoat-200lr.html'],
  'Need structured hotel renovation/rebrand scope rather than generic ownership change.',
  'Strong account-level cross-sell potential for management groups with multiple properties.',
  14, 'survey_candidate'
),
(
  'dealership_group:showroom_facade_refresh', 'dealership_group', 'dealership_showroom', 'painted_facade_metal_panel_canopy',
  array['image refresh','facade repaint','canopy coating','exterior renovation'],
  'strong_standard_prep', array['renovation','brand_image_program','permit','capital_plan'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets','core.organizations'],
  'testable', array['active_customer_traffic','vehicle_overspray_risk','substrate_specific_pressure_limits'],
  'Dealer renovation permits and OEM image-program project scopes',
  'The underlying facade/coating preparation relationship is strong, but the dealer-specific trigger should require explicit exterior scope.',
  array['https://usa.sika.com/en/construction-products/coatings-water-repellents/building-facade/sika-thorocoat-250.html'],
  'Need dealer renovation/image-program data source.',
  'Portfolio linkage makes one validated project useful for account expansion.',
  15, 'survey_candidate'
),
(
  'industrial_logistics:metal_warehouse_envelope', 'industrial_logistics_operator', 'warehouse_or_distribution_center', 'metal_roof_and_wall_panel_coating',
  array['metal roof coating','wall panel repaint','warehouse exterior coating','corrosion coating'],
  'strong_standard_prep', array['roof_lifecycle','capital_project','maintenance','procurement'], 'medium', 'partial',
  array['scout.v_industrial_logistics_accounts','intelligence.v_roof_lifecycle_pressure','decisioning.v_building_resolved_attributes'],
  'testable', array['active_logistics_operation','roof_fall_hazard','substrate_specific_pressure_limits'],
  'Roofing/coating permits, facility maintenance bids, owner capital plans',
  'Metal and liquid-applied roof coating systems require clean contaminant-free surfaces and commonly use pressure washing as preparation.',
  array['https://www.gaf.com/en-us/document-library/documents/manuals/liquid-applied-roofing-manual-comco180.pdf'],
  'Industrial portfolio coverage exists but structure-level ownership and project feeds remain sparse.',
  'Potentially high square footage and repeatable across large portfolios.',
  16, 'survey_candidate'
),
(
  'commercial_property:parking_structure_coating', 'property_management_company', 'parking_structure', 'concrete_traffic_and_wall_coatings',
  array['traffic coating replacement','concrete protective coating','wall coating','water repellent treatment'],
  'conditional_prep', array['repair_project','capital_plan','procurement','condition'], 'medium', 'partial',
  array['intelligence.premium_exterior_targets','scout.v_property_management_facilities'],
  'testable', array['vehicle_traffic','oil_contamination','drainage_controls','substrate_profile_requirements'],
  'Parking garage repair/coating bids and capital plans',
  'Concrete protective treatments require clean surfaces, but some parking-deck systems rely on abrasive or shot-blast profiling rather than water washing.',
  array['https://usa.sika.com/en/construction/repair-protection/coatings-water-repellents/silane-siloxane-coatings/sikagard-h-1001.html'],
  'Need parking-structure identification and work-scope parser.',
  'Treat cleaning as conditional because the required surface profile may make standalone washing only one part of prep.',
  17, 'survey_candidate'
),
(
  'university:campus_exterior_painting', 'postsecondary_institution', 'campus_building', 'painted_facade_roof_and_exposed_steel',
  array['exterior painting','facade coating','roof coating','stadium steel painting'],
  'strong_standard_prep', array['capital_plan','summer_maintenance','procurement','renovation'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets','core.organizations'],
  'testable', array['occupied_campus','historic_surface_possible'],
  'University capital plans and public procurement',
  'Multiple campus surface families have strong pre-coating cleaning relationships; procurement is often public for public institutions.',
  array['https://usa.sika.com/en/construction-products/coatings-water-repellents/building-facade/sika-thorocoat-250.html','https://www.gaf.com/en-us/document-library/documents/manuals/liquid-applied-roofing-manual-comco180.pdf'],
  'Need campus capital-plan/procurement collectors and building resolution.',
  'Attractive portfolio account because one institution can contain roofs, facades, garages, stadiums, tanks, and historic structures.',
  18, 'survey_candidate'
),
(
  'health_system:facility_exterior_coating', 'health_system', 'hospital_or_medical_campus', 'facade_roof_parking_coatings',
  array['facade repaint','roof coating','parking structure coating','exterior renovation'],
  'strong_standard_prep', array['capital_plan','renovation','procurement'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets','core.organizations'],
  'testable', array['critical_occupancy','infection_control_coordination','vehicle_traffic'],
  'Health-system capital projects, permits, public procurement where available',
  'Underlying roof, facade and concrete-coating preparation relationships are strong; operating constraints are the main qualifier.',
  array['https://usa.sika.com/en/construction-products/coatings-water-repellents/building-facade/sika-thorocoat-200lr.html','https://www.gaf.com/en-us/document-library/documents/manuals/liquid-applied-roofing-manual-comco180.pdf'],
  'Need private health-system capital-project observability.',
  'Portfolio resolution makes this useful even when project evidence is property-specific.',
  19, 'survey_candidate'
),
(
  'airport_operator:hangar_terminal_parking_exterior', 'municipal_government', 'airport_facility', 'metal_roof_facade_structural_steel_concrete',
  array['hangar repaint','terminal facade coating','parking garage coating','structural steel painting'],
  'strong_standard_prep', array['airport_capital_plan','procurement','renovation'], 'medium', 'partial',
  array['intelligence.premium_exterior_targets'],
  'conditional', array['controlled_airspace','airport_operations','security_access','overspray_fod'],
  'Airport capital improvement plans and bid tabs',
  'The surface preparation relationship is strong across common airport substrates, but operational and airspace constraints require explicit feasibility review.',
  array['https://www.gsa.gov/real-estate/historic-preservation/historic-preservation-policy-tools/preservation-tools-resources/technical-procedures/stripping-and-repainting-iron-and-steel-features'],
  'Need airport facility inventory and capital-project collector.',
  'Potentially valuable, but feasibility should be gated before lead promotion.',
  20, 'survey_candidate'
),
(
  'industrial_operator:smokestack_or_chimney', 'industrial_logistics_operator', 'smokestack_or_chimney', 'aviation_marking_and_protective_coating',
  array['stack repaint','aviation marking restoration','protective coating repair'],
  'strong_standard_prep', array['marking_condition','inspection','outage_maintenance','procurement'], 'medium', 'none',
  array[]::text[],
  'testable', array['process_operation','stack_emissions','fall_hazard','lead_coating_possible'],
  'FAA marking context plus facility outage/maintenance procurement',
  'FAA marking standards explicitly include smokestacks among structures that may use alternating bands, with marking reapplication triggered by deterioration or contamination.',
  array['https://www.faa.gov/documentLibrary/media/Advisory_Circular/2026-07-13_AC_70_7460-1N_Obstruction_Marking_and_Lighting_FINAL_CLEAN.pdf'],
  'Scout lacks a normalized smokestack asset layer.',
  'Good future structure family for industrial accounts because marking condition can be visually inspectable.',
  21, 'survey_candidate'
),
(
  'wind_operator:turbine_tower_exterior', 'public_utility', 'wind_turbine', 'coated_tower_exterior',
  array['tower coating repair','corrosion touch-up','marking restoration'],
  'conditional_prep', array['inspection_condition','scheduled_maintenance','marking_requirement'], 'low', 'strong',
  array['energy.wind_turbines','scout.v_wind_opportunity_candidates'],
  'conditional', array['turbine_lockout','extreme_height','specialized_access'],
  'Owner O&M records and coating/repair procurements',
  'DOE advises turbine owners to inspect for corrosion; FAA marking rules can also apply in specific marking configurations, but a corrosion observation alone does not imply a cleaning job.',
  array['https://www.energy.gov/cmei/systems/windexchange/small-wind-guidebook','https://www.faa.gov/documentLibrary/media/Advisory_Circular/2026-07-13_AC_70_7460-1N_Obstruction_Marking_and_Lighting_FINAL_CLEAN.pdf'],
  'Current pilot area has very limited wind asset volume and no coating event feed.',
  'Keep as a future national-expansion signal rather than near-term priority.',
  22, 'survey_candidate'
),
(
  'racetrack_operator:grandstand_and_exposed_steel', 'racetrack_operator', 'racetrack_grandstand', 'structural_steel_and_concrete_exterior',
  array['grandstand repaint','steel recoating','exterior renovation'],
  'strong_standard_prep', array['capital_plan','offseason_maintenance','event_deadline','renovation'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets','core.organizations'],
  'testable', array['public_occupancy','event_schedule','containment_possible'],
  'Venue capital plans, renovation announcements, procurement',
  'Underlying structural-steel and facade coating workflows require prepared surfaces; event calendars can sharpen timing.',
  array['https://www.tnemec.com/projects/ladd-peeples-stadium/'],
  'Need racetrack project/maintenance source.',
  'Useful extension of the sports-venue pattern already represented in Scout.',
  23, 'survey_candidate'
),
(
  'casino_resort:facade_roof_dome_recoating', 'integrated_real_estate_operator', 'casino_resort_complex', 'facade_roof_and_specialty_exterior_coating',
  array['facade repaint','roof coating','dome recoating','exterior restoration'],
  'strong_standard_prep', array['renovation','capital_plan','brand_refresh'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets'],
  'testable', array['continuous_occupancy','overspray_control','specialized_access'],
  'Resort renovation announcements, permits, owner capital plans',
  'Large specialty exteriors can require washing/cleaning before recoating; the opportunity is strongest when exterior scope is explicit.',
  array['https://www.basepainters.com/'],
  'Need renovation-project collector for private resort properties.',
  'High-value but lower-volume class.',
  24, 'survey_candidate'
),
(
  'convention_center:facade_and_structural_steel', 'facilities_management_company', 'convention_or_exposition_center', 'facade_and_exposed_structural_steel',
  array['facade coating','structural steel repaint','exterior restoration'],
  'strong_standard_prep', array['capital_plan','renovation','event_deadline','procurement'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets'],
  'testable', array['event_schedule','public_occupancy','specialized_access'],
  'Public authority capital plans and facility procurement',
  'Facade and steel coating workflows have strong preparation requirements; scheduled event calendars can create hard completion windows.',
  array['https://usa.sika.com/en/construction-products/coatings-water-repellents/building-facade/sika-thorocoat-250.html'],
  'Need public-facility capital plan and procurement normalization.',
  'Good fit for facilities-management account expansion.',
  25, 'survey_candidate'
),
(
  'historic_religious:painted_exterior', 'nonprofit_land_manager', 'historic_religious_or_civic_building', 'painted_wood_stucco_masonry_metal',
  array['historic exterior repaint','wood trim repaint','stucco repaint','metal feature repaint'],
  'strong_standard_prep', array['preservation_project','grant','capital_campaign','procurement'], 'medium', 'strong',
  array['intelligence.premium_exterior_targets','intelligence.v_building_historic_context'],
  'conditional', array['historic_material','lead_paint_possible','high_pressure_damage_risk'],
  'Preservation grants, capital campaigns, public historic-project bids',
  'NPS preservation guidance notes that dirt and organic deposits can block paint adhesion, but emphasizes gentle cleaning and warns against damaging historic substrates.',
  array['https://www.nps.gov/orgs/1739/upload/preservation-brief-10-paint-problems-exterior-woodwork.pdf','https://www.nps.gov/orgs/1739/upload/preservation-brief-47-exteriors-small-medium-buildings.pdf'],
  'Need preservation-project signals and substrate-specific service compatibility.',
  'Strong signal for cleaning need, but drone pressure-washing suitability can be poor; service method must be constrained.',
  26, 'survey_candidate'
),
(
  'municipal_public_works:park_and_civic_structures', 'municipal_public_works', 'park_civic_pedestrian_structure', 'painted_facade_structural_steel_and_roof',
  array['shelter repaint','pedestrian bridge painting','civic facade coating','roof coating'],
  'strong_standard_prep', array['capital_plan','maintenance_budget','procurement'], 'medium', 'partial',
  array['core.organizations','environment.managed_land_areas'],
  'testable', array['public_access','historic_surface_possible'],
  'Municipal capital plans, parks maintenance bids, public works procurements',
  'Underlying coating workflows are well supported; public ownership makes project observability comparatively good.',
  array['https://www.gsa.gov/real-estate/historic-preservation/historic-preservation-policy-tools/preservation-tools-resources/technical-procedures/stripping-and-repainting-iron-and-steel-features'],
  'Need structure inventory inside managed-land areas and capital-project linkage.',
  'Worth surveying because Scout already has unusually broad land-manager resolution.',
  27, 'survey_candidate'
),
(
  'federal_military:facility_painting_and_coating', 'military_installation', 'federal_facility', 'hangar_tank_facade_roof_structural_steel',
  array['exterior painting','hangar coating','tank painting','roof coating','structural steel painting'],
  'strong_standard_prep', array['sam_opportunity','capital_project','maintenance_contract'], 'high', 'partial',
  array['ingest:sam-opportunities','core.organizations'],
  'testable', array['security_access','airfield_controls','hazardous_materials_possible'],
  'SAM.gov contract opportunities and agency forecasts',
  'Federal facility painting/coating scopes often expose surface preparation directly in procurement documents, making source text more useful than generic permits.',
  array['https://www.gsa.gov/real-estate/historic-preservation/historic-preservation-policy-tools/preservation-tools-resources/technical-procedures/stripping-and-repainting-iron-and-steel-features'],
  'SAM source is registered but current local opportunity coverage should be verified/expanded.',
  'Strong source architecture candidate because procurement is explicit and nationally scalable.',
  28, 'survey_candidate'
),
(
  'wastewater_utility:process_tank_exterior', 'special_district_utility', 'wastewater_process_tank_or_digester', 'coated_steel_or_concrete_exterior',
  array['tank repaint','digester coating','clarifier steel coating','concrete protective coating'],
  'strong_standard_prep', array['capital_plan','rehabilitation','procurement','inspection'], 'medium', 'partial',
  array['core.organizations','ingest:kentucky-dow-kpdes-outfalls'],
  'testable', array['biological_process','chemical_exposure','confined_space_possible','odor_controls'],
  'Utility capital plans, SRF projects, engineering reports, coating procurements',
  'Steel and concrete protective coating systems require contaminant removal and prepared substrates, but process environment and interior/exterior scope must be separated.',
  array['https://usa.sika.com/en/construction-products/coatings-water-repellents/building-facade/sika-thorocoat-250.html'],
  'Scout has regulatory facility context but no normalized wastewater-structure/coating layer.',
  'Natural extension of the water-utility account model.',
  29, 'survey_candidate'
),
(
  'billboard_operator:painted_sign_support', 'service_provider', 'billboard_or_large_sign_structure', 'painted_sign_support_and_face',
  array['support repaint','sign structure recoating','face repaint'],
  'conditional_prep', array['maintenance','brand_refresh'], 'low', 'none',
  array[]::text[],
  'deprioritize', array['roadside_work_zone','electrical_signage','small_addressable_market'],
  'Owner maintenance contracts and sign permits',
  'Surface preparation is technically relevant, but signal value and Scout asset coverage are currently weak.',
  array['https://www.gsa.gov/real-estate/historic-preservation/historic-preservation-policy-tools/preservation-tools-resources/technical-procedures/stripping-and-repainting-iron-and-steel-features'],
  'No asset or project layer.',
  'Keep as a comparison case; not worth near-term collector work.',
  30, 'hold'
),
(
  'electric_utility:substation_steel', 'public_utility', 'electrical_substation', 'galvanized_or_coated_steel',
  array['steel coating repair','equipment enclosure repaint'],
  'conditional_prep', array['maintenance','corrosion_inspection'], 'low', 'strong',
  array['energy.utility_substations'],
  'deprioritize', array['energized_high_voltage','clearance_constraints','specialized_utility_access'],
  'Utility maintenance/procurement only if explicitly scoped',
  'Some coated components can require surface preparation, but energized-yard constraints and prevalent galvanized steel make painting a poor generic cleaning signal.',
  array[]::text[],
  'No coating-condition source and poor service fit.',
  'Useful negative control: asset abundance alone should not cause promotion.',
  31, 'negative_control'
),
(
  'electric_utility:transmission_tower', 'public_utility', 'transmission_tower', 'galvanized_or_coated_lattice_steel',
  array['tower painting','marking restoration'],
  'conditional_prep', array['maintenance','aviation_marking'], 'low', 'strong',
  array['energy.transmission_lines'],
  'deprioritize', array['energized_high_voltage','induction','extreme_height','specialized_access'],
  'Explicit utility maintenance or FAA marking project only',
  'Painting can occur, especially for marking or corrosion work, but generic transmission-asset presence is not a useful cleaning signal.',
  array['https://www.faa.gov/documentLibrary/media/Advisory_Circular/2026-07-13_AC_70_7460-1N_Obstruction_Marking_and_Lighting_FINAL_CLEAN.pdf'],
  'No tower-level coating condition or work-order source.',
  'Do not promote based on existing 2,754 transmission-line records.',
  32, 'negative_control'
),
(
  'pipeline_operator:aboveground_pipe_coating', 'industrial_logistics_operator', 'pipeline_or_meter_station_piping', 'protective_coated_pipe',
  array['pipeline coating repair','station piping repaint'],
  'conditional_prep', array['integrity_maintenance','procurement'], 'low', 'partial',
  array['scout.v_pipeline_opportunity_candidates'],
  'deprioritize', array['flammable_product_possible','process_safety','specialized_surface_prep'],
  'Explicit integrity-maintenance scope only',
  'Protective coating maintenance exists, but the work is specialized and often dominated by abrasive preparation rather than standalone exterior washing.',
  array[]::text[],
  'Current pipeline context is county/operator level rather than precise maintenance assets.',
  'Keep outside cleaning promotion unless an explicit compatible scope appears.',
  33, 'negative_control'
),
(
  'solar_operator:solar_asset_paint_signal', 'public_utility', 'solar_array', 'panel_and_racking_system',
  array['paint','repaint'],
  'not_relevant', array['none'], 'low', 'strong',
  array['energy.eia_solar_generators','cleaning.solar_soiling_context','scout.v_solar_opportunity_candidates'],
  'exclude', array['electrical_system'],
  null,
  'Solar cleaning is independently valuable, but painting/repainting is not a natural primary maintenance signal for module cleaning.',
  array[]::text[],
  'No gap; this is intentionally a negative control.',
  'Do not contaminate the established solar-soiling logic with paint keywords.',
  34, 'negative_control'
),
(
  'generic_building:interior_painting', 'property_management_company', 'building_interior', 'interior_wall_ceiling_floor_finish',
  array['interior paint','gym paint','hallway painting'],
  'not_relevant', array['capital_plan','renovation'], 'high', 'strong',
  array['ingest:indiana-dlgf-school-capital-projects','intelligence.construction_projects'],
  'exclude', array['indoor_work'],
  null,
  'Interior painting can be highly observable in capital plans but does not imply an exterior drone-cleaning opportunity.',
  array[]::text[],
  'Parser must explicitly suppress interior-only scopes.',
  'Important false-positive control because school capital plans contain many interior paint items.',
  35, 'negative_control'
),
(
  'site_surface:pavement_sealcoat_or_striping', 'property_management_company', 'parking_lot_or_athletic_surface', 'pavement_and_surface_marking',
  array['seal coating','striping','court repaint','track recoat'],
  'not_relevant', array['capital_plan','maintenance'], 'high', 'strong',
  array['ingest:indiana-dlgf-school-capital-projects'],
  'exclude', array['ground_surface_work'],
  null,
  'These scopes can contain paint/coating vocabulary but belong to a different service family and should not feed exterior-structure cleaning logic.',
  array[]::text[],
  'Parser must distinguish structural coatings from pavement/athletic-surface work.',
  'Prevents obvious keyword false positives such as sealcoating and court repainting.',
  36, 'negative_control'
),
(
  'new_construction:shop_coated_structural_steel', 'real_estate_developer_manager', 'new_building_structural_steel', 'new_structural_steel_coating',
  array['shop primer','new steel coating','field touch-up'],
  'weak_inference', array['new_construction'], 'medium', 'strong',
  array['intelligence.construction_projects'],
  'deprioritize', array['construction_site','shop_coating_common'],
  'Only explicit field-cleaning or field-painting scopes',
  'New structural steel is often prepared/coated in fabrication, so generic new-construction painting is a weak proxy for a standalone exterior cleaning opportunity.',
  array['https://www.fhwa.dot.gov/publications/research/infrastructure/structures/bridge/20065/20065.pdf'],
  'Generic permit/project feeds lack field-versus-shop coating detail.',
  'Do not let a painting taxonomy accidentally turn every new construction project into a cleaning lead.',
  37, 'negative_control'
),
(
  'facilities_management:multi_asset_paint_contract', 'facilities_management_company', 'managed_facility_portfolio', 'mixed_exterior_surfaces',
  array['on-call painting','exterior coatings','facility painting contract','surface preparation'],
  'conditional_prep', array['master_service_contract','procurement','capital_plan'], 'medium', 'strong',
  array['core.organizations','scout.v_property_management_service_specific_vendor_entries'],
  'strong', array['scope_may_mix_interior_and_exterior'],
  'Facilities-management RFPs and on-call maintenance contracts',
  'The account-level signal can be more valuable than a single structure: a master painting/coating contract can reveal recurring exterior maintenance demand across a managed portfolio.',
  array['https://www.gsa.gov/real-estate/historic-preservation/historic-preservation-policy-tools/preservation-tools-resources/technical-procedures/stripping-and-repainting-iron-and-steel-features'],
  'Need contract-scope normalization and exterior/interior decomposition.',
  'This is the business-structure analogue of the asset signal and may be especially useful for portfolio sales.',
  38, 'survey_candidate'
)
on conflict (survey_key) do update set
  business_type = excluded.business_type,
  structure_type = excluded.structure_type,
  surface_family = excluded.surface_family,
  example_work = excluded.example_work,
  cleaning_relationship = excluded.cleaning_relationship,
  signal_modes = excluded.signal_modes,
  observability = excluded.observability,
  scout_coverage = excluded.scout_coverage,
  current_data_paths = excluded.current_data_paths,
  opportunity_fit = excluded.opportunity_fit,
  hazard_flags = excluded.hazard_flags,
  primary_next_source = excluded.primary_next_source,
  evidence_basis = excluded.evidence_basis,
  evidence_urls = excluded.evidence_urls,
  source_gap = excluded.source_gap,
  notes = excluded.notes,
  survey_rank = excluded.survey_rank,
  status = excluded.status,
  reviewed_at = now(),
  updated_at = now();

create or replace view research.v_surface_work_signal_survey_priority as
select
  survey_key,
  business_type,
  structure_type,
  surface_family,
  cleaning_relationship,
  observability,
  scout_coverage,
  opportunity_fit,
  signal_modes,
  current_data_paths,
  primary_next_source,
  source_gap,
  hazard_flags,
  notes,
  survey_rank,
  status,
  reviewed_at
from research.surface_work_signal_survey
order by
  case opportunity_fit
    when 'strong' then 1
    when 'testable' then 2
    when 'conditional' then 3
    when 'deprioritize' then 4
    else 5
  end,
  case observability when 'high' then 1 when 'medium' then 2 else 3 end,
  survey_rank;

revoke all on research.v_surface_work_signal_survey_priority from anon, authenticated;
