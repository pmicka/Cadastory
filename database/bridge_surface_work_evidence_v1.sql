-- Scout by Cadastory
-- Bridge surface-work evidence v1.
-- Research-only. Normalizes confirmed DOT bridge painting/coating/cleaning evidence
-- separately from condition-based forecast scaffolds. No production scoring or MCP exposure.

create schema if not exists research;

-- Register the authoritative source families needed to close the bridge paint/coating gap.
insert into ingest.sources (
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,homepage_url,license_notes,
  commercial_use_status,notes
) values
(
  'kytc-unit-bid-tabulations',
  'Kentucky Transportation Cabinet Unit Bid Tabulations',
  'Kentucky Transportation Cabinet',
  'transportation_bid_items',
  'Kentucky',
  'official letting archive / PDF and contract-item extraction',
  'per letting',
  'state',
  'source_identified',
  'https://transportation.ky.gov/Construction-Procurement/Pages/Unit-Bid-Tabulations.aspx',
  'Official public procurement records.',
  'reviewed_public_record',
  'Confirmed bridge surface-work items include CLEAN & PAINT STRUCTURAL STEEL (08434), BLAST CLEANING (08549), BRIDGE CLEANING (24981EC), and CONCRETE COATING (24982EC). Pavement striping paint must be excluded.'
),
(
  'indot-bridge-bid-tabs',
  'Indiana DOT Bridge Letting Bid Tabulations',
  'Indiana Department of Transportation',
  'transportation_bid_items',
  'Indiana',
  'official letting archive / bid-tab extraction',
  'per letting',
  'state',
  'source_identified',
  'https://www.in.gov/indot/doing-business-with-indot/home/contracts/',
  'Official public procurement records.',
  'reviewed_public_record',
  'Confirmed bridge-painting contracts expose item codes such as 619-11052 CLEAN STEEL BRIDGE and 619-51859 COAT STEEL BRIDGE plus bidder and price information.'
),
(
  'indot-notice-to-highway-contractors',
  'Indiana DOT Notice to Highway Contractors',
  'Indiana Department of Transportation',
  'transportation_project_notice',
  'Indiana',
  'official letting notice extraction',
  'per letting',
  'state',
  'source_identified',
  'https://www.in.gov/indot/doing-business-with-indot/home/contracts/',
  'Official public procurement records.',
  'reviewed_public_record',
  'Provides project/DES number, work type, route, county and location needed to resolve contract-level bid items to physical Scout bridge records.'
)
on conflict (slug) do update set
  name=excluded.name,
  authority=excluded.authority,
  source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,
  acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,
  authority_level=excluded.authority_level,
  homepage_url=excluded.homepage_url,
  license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,
  notes=excluded.notes,
  updated_at=now();

create table if not exists research.bridge_surface_work_evidence (
  evidence_key text primary key,
  source_slug text not null,
  source_native_id text,
  source_url text,
  state_code text not null check (state_code in ('KY','IN','OH')),
  contract_id text,
  project_id text,
  letting_date date,
  completion_date date,
  bridge_reference text,
  matched_bridge_id uuid references transportation.bridges(id) on delete set null,
  match_method text,
  match_confidence numeric check (match_confidence is null or (match_confidence between 0 and 1)),
  surface_work_family text not null check (surface_work_family in (
    'steel_clean_and_paint',
    'steel_cleaning_prep',
    'steel_coating',
    'abrasive_blast_prep',
    'bridge_cleaning',
    'concrete_coating',
    'concrete_sealing',
    'bearing_clean_and_coat'
  )),
  item_code text,
  item_description text not null,
  quantity numeric,
  unit text,
  unit_price numeric,
  extended_amount numeric,
  vendor_name text,
  project_stage text not null default 'confirmed_scope' check (project_stage in (
    'planned','solicitation','bid_tab','awarded','construction','completed','confirmed_scope'
  )),
  prep_relationship text not null check (prep_relationship in (
    'cleaning_and_treatment_same_item',
    'prep_item_explicit',
    'treatment_item_explicit',
    'cleaning_item_explicit',
    'adjacent_prep_and_treatment_same_contract',
    'not_applicable_or_unresolved'
  )),
  evidence_strength text not null default 'confirmed_explicit',
  evidence_granularity text not null,
  evidence jsonb not null default '{}'::jsonb,
  observed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table research.bridge_surface_work_evidence is
  'Research-only confirmed bridge surface-work evidence from authoritative DOT project/bid records. Kept distinct from condition-based repaint forecasting.';

-- Hand-verified anchors from official DOT records. These validate semantics and the
-- matching/backtest design before the automated collectors are allowed to influence production.
insert into research.bridge_surface_work_evidence (
  evidence_key,source_slug,source_native_id,source_url,state_code,contract_id,project_id,
  letting_date,completion_date,bridge_reference,matched_bridge_id,match_method,match_confidence,
  surface_work_family,item_code,item_description,quantity,unit,unit_price,extended_amount,
  vendor_name,project_stage,prep_relationship,evidence_strength,evidence_granularity,evidence,observed_at
)
select
  'ky:261124:056B00089R:24981EC',
  'kytc-unit-bid-tabulations','261124:056B00089R:24981EC',
  'https://transportation.ky.gov/Construction-Procurement/Proposals/200-JEFFERSON-26-1124%20Addendum%202.pdf',
  'KY','261124',null,date '2026-05-21',null,'056B00089R',b.id,
  'exact_kytc_structure_number',1.0,
  'bridge_cleaning','24981EC','BRIDGE CLEANING - 056B00089R',1,'LS',null,null,null,
  'solicitation','cleaning_item_explicit','confirmed_explicit','bridge_bid_item',
  jsonb_build_object('contract_scope','deck restoration and waterproofing','related_item','24982EC CONCRETE COATING','verification','official KYTC proposal'),
  timestamptz '2026-05-12 00:00:00+00'
from transportation.bridges b
where b.state_fips='21'
  and regexp_replace(upper(b.structure_number),'[^A-Z0-9]','','g')=regexp_replace('056B00089R','[^A-Z0-9]','','g')
limit 1
on conflict (evidence_key) do update set
  matched_bridge_id=excluded.matched_bridge_id,
  match_method=excluded.match_method,
  match_confidence=excluded.match_confidence,
  updated_at=now();

insert into research.bridge_surface_work_evidence (
  evidence_key,source_slug,source_native_id,source_url,state_code,contract_id,project_id,
  letting_date,completion_date,bridge_reference,matched_bridge_id,match_method,match_confidence,
  surface_work_family,item_code,item_description,quantity,unit,unit_price,extended_amount,
  vendor_name,project_stage,prep_relationship,evidence_strength,evidence_granularity,evidence,observed_at
)
select
  'ky:261124:056B00089R:24982EC',
  'kytc-unit-bid-tabulations','261124:056B00089R:24982EC',
  'https://transportation.ky.gov/Construction-Procurement/Proposals/200-JEFFERSON-26-1124%20Addendum%202.pdf',
  'KY','261124',null,date '2026-05-21',null,'056B00089R',b.id,
  'exact_kytc_structure_number',1.0,
  'concrete_coating','24982EC','CONCRETE COATING - 056B00089R',1,'LS',null,null,null,
  'solicitation','treatment_item_explicit','confirmed_explicit','bridge_bid_item',
  jsonb_build_object('contract_scope','deck restoration and waterproofing','related_item','24981EC BRIDGE CLEANING','verification','official KYTC proposal'),
  timestamptz '2026-05-12 00:00:00+00'
from transportation.bridges b
where b.state_fips='21'
  and regexp_replace(upper(b.structure_number),'[^A-Z0-9]','','g')=regexp_replace('056B00089R','[^A-Z0-9]','','g')
limit 1
on conflict (evidence_key) do update set
  matched_bridge_id=excluded.matched_bridge_id,
  match_method=excluded.match_method,
  match_confidence=excluded.match_confidence,
  updated_at=now();

-- Historic KY anchor demonstrating the explicit steel-paint item code. It is intentionally
-- retained even though the current NBI bridge row does not resolve by this identifier.
insert into research.bridge_surface_work_evidence (
  evidence_key,source_slug,source_native_id,source_url,state_code,contract_id,project_id,
  letting_date,bridge_reference,surface_work_family,item_code,item_description,quantity,unit,
  unit_price,project_stage,prep_relationship,evidence_strength,evidence_granularity,evidence,observed_at
) values (
  'ky:212950:033B00016N:08434','kytc-unit-bid-tabulations','212950:033B00016N:08434',
  'https://transportation.ky.gov/Construction/Contract%20Items/212950items03065.html',
  'KY','212950',null,date '2021-05-26','033B00016N','steel_clean_and_paint','08434',
  'CLEAN & PAINT STRUCTURAL STEEL - 033B00016N',1,'LS',1650526,
  'awarded','cleaning_and_treatment_same_item','confirmed_explicit','bridge_contract_item',
  jsonb_build_object('related_prep_item','08549 BLAST CLEANING','related_cleaning_item','24981EC BRIDGE CLEANING','related_treatment_item','24982EC CONCRETE COATING'),
  timestamptz '2021-05-26 00:00:00+00'
)
on conflict (evidence_key) do update set updated_at=now();

-- INDOT B-43740-A is especially valuable as a backtest: both bridge-painting projects
-- resolve to Scout steel bridges whose superstructure condition is 6/7, showing that
-- preventive coating work cannot be forecast from poor structural condition alone.
insert into research.bridge_surface_work_evidence (
  evidence_key,source_slug,source_native_id,source_url,state_code,contract_id,project_id,
  letting_date,completion_date,bridge_reference,matched_bridge_id,match_method,match_confidence,
  surface_work_family,item_code,item_description,vendor_name,project_stage,prep_relationship,
  evidence_strength,evidence_granularity,evidence,observed_at
)
select
  'in:B-43740-A:2100585:bridge-painting','indot-bridge-bid-tabs','B-43740-A:2100585',
  'https://www.in.gov/indot/doing-business-with-indot/files/Bid-Tabs-7.9.25_revised9.2.pdf',
  'IN','B-43740-A','2100585',date '2025-07-09',date '2026-07-31','US 50 over Hogan Creek, 0.09 E SR 56',
  b.id,'project_route_location_exact',0.99,'steel_coating','619-51859',
  'BRIDGE PAINTING; contract includes CLEAN STEEL BRIDGE and COAT STEEL BRIDGE',
  'OLYMPUS PAINTING LLC','bid_tab','adjacent_prep_and_treatment_same_contract',
  'confirmed_explicit','project_contract_join',
  jsonb_build_object('contract_description','BRIDGE PAINTING','clean_item','619-11052 CLEAN STEEL BRIDGE, QP-2','coat_item','619-51859 COAT STEEL BRIDGE','route','US 50','location','over HOGAN CREEK, 00.09 E SR 56','scout_structure_number','018770'),
  timestamptz '2025-07-09 00:00:00+00'
from transportation.bridges b
where b.state_fips='18' and b.structure_number='018770'
limit 1
on conflict (evidence_key) do update set
  matched_bridge_id=excluded.matched_bridge_id,match_method=excluded.match_method,
  match_confidence=excluded.match_confidence,updated_at=now();

insert into research.bridge_surface_work_evidence (
  evidence_key,source_slug,source_native_id,source_url,state_code,contract_id,project_id,
  letting_date,completion_date,bridge_reference,matched_bridge_id,match_method,match_confidence,
  surface_work_family,item_code,item_description,vendor_name,project_stage,prep_relationship,
  evidence_strength,evidence_granularity,evidence,observed_at
)
select
  'in:B-43740-A:2100644:bridge-painting','indot-bridge-bid-tabs','B-43740-A:2100644',
  'https://www.in.gov/indot/doing-business-with-indot/files/Bid-Tabs-7.9.25_revised9.2.pdf',
  'IN','B-43740-A','2100644',date '2025-07-09',date '2026-07-31','SR 101 over I-74, 0.62 N SR 46',
  b.id,'project_route_location_exact',0.99,'steel_coating','619-51859',
  'BRIDGE PAINTING; contract includes CLEAN STEEL BRIDGE and COAT STEEL BRIDGE',
  'OLYMPUS PAINTING LLC','bid_tab','adjacent_prep_and_treatment_same_contract',
  'confirmed_explicit','project_contract_join',
  jsonb_build_object('contract_description','BRIDGE PAINTING','clean_item','619-11052 CLEAN STEEL BRIDGE, QP-2','coat_item','619-51859 COAT STEEL BRIDGE','route','SR 101','location','Bridge OVER I-74, 0.62 miles N of SR 46','scout_structure_number','025090'),
  timestamptz '2025-07-09 00:00:00+00'
from transportation.bridges b
where b.state_fips='18' and b.structure_number='025090'
limit 1
on conflict (evidence_key) do update set
  matched_bridge_id=excluded.matched_bridge_id,match_method=excluded.match_method,
  match_confidence=excluded.match_confidence,updated_at=now();

-- Future automated collectors write normalized item/project records to ingest.raw_records.
-- This view only admits explicit bridge surface-work semantics and explicitly rejects
-- pavement striping and coated reinforcing-steel false positives.
create or replace view research.v_bridge_surface_work_raw_evidence as
select
  r.id as source_record_id,
  s.slug as source_slug,
  r.source_native_id,
  r.source_url,
  r.observed_at,
  r.raw_payload->>'state_code' as state_code,
  r.raw_payload->>'contract_id' as contract_id,
  r.raw_payload->>'project_id' as project_id,
  nullif(r.raw_payload->>'letting_date','')::date as letting_date,
  nullif(r.raw_payload->>'completion_date','')::date as completion_date,
  r.raw_payload->>'bridge_reference' as bridge_reference,
  r.raw_payload->>'item_code' as item_code,
  r.raw_payload->>'item_description' as item_description,
  r.raw_payload->>'vendor_name' as vendor_name,
  case
    when upper(coalesce(r.raw_payload->>'item_description','')) ~ 'CLEAN[[:space:]]*&[[:space:]]*PAINT[[:space:]]+STRUCTURAL[[:space:]]+STEEL'
      then 'steel_clean_and_paint'
    when upper(coalesce(r.raw_payload->>'item_description','')) ~ 'CLEAN[[:space:]]+STEEL[[:space:]]+BRIDGE'
      then 'steel_cleaning_prep'
    when upper(coalesce(r.raw_payload->>'item_description','')) ~ 'COAT[[:space:]]+STEEL[[:space:]]+BRIDGE'
      then 'steel_coating'
    when upper(coalesce(r.raw_payload->>'item_description','')) ~ 'BLAST[[:space:]]+CLEANING'
      then 'abrasive_blast_prep'
    when upper(coalesce(r.raw_payload->>'item_description','')) ~ 'BRIDGE[[:space:]]+CLEANING'
      then 'bridge_cleaning'
    when upper(coalesce(r.raw_payload->>'item_description','')) ~ 'CONCRETE[[:space:]]+COATING'
      then 'concrete_coating'
    when upper(coalesce(r.raw_payload->>'item_description','')) ~ 'CONCRETE[[:space:]]+SEALING'
      then 'concrete_sealing'
    when upper(coalesce(r.raw_payload->>'item_description','')) ~ 'CLEAN.*COAT.*BEARING|BEARING.*CLEAN.*COAT'
      then 'bearing_clean_and_coat'
  end as surface_work_family,
  r.raw_payload
from ingest.raw_records r
join ingest.sources s on s.id=r.source_id
where s.slug in ('kytc-unit-bid-tabulations','indot-bridge-bid-tabs')
  and upper(coalesce(r.raw_payload->>'item_description','')) ~
      '(CLEAN[[:space:]]*&[[:space:]]*PAINT[[:space:]]+STRUCTURAL[[:space:]]+STEEL|CLEAN[[:space:]]+STEEL[[:space:]]+BRIDGE|COAT[[:space:]]+STEEL[[:space:]]+BRIDGE|BLAST[[:space:]]+CLEANING|BRIDGE[[:space:]]+CLEANING|CONCRETE[[:space:]]+COATING|CONCRETE[[:space:]]+SEALING|CLEAN.*COAT.*BEARING|BEARING.*CLEAN.*COAT)'
  and upper(coalesce(r.raw_payload->>'item_description','')) !~
      '(PAVE[[:space:]]+STRIP|PAVEMENT[[:space:]]+MARK|REINFORCEMENT.*EPOXY[[:space:]-]*COATED|EPOXY[[:space:]-]*COATED.*REINFORCEMENT)';

comment on view research.v_bridge_surface_work_raw_evidence is
  'Research-only parser surface for bridge-specific cleaning/painting/coating bid items. Explicitly excludes pavement paint and epoxy-coated reinforcement false positives.';

create or replace view research.v_bridge_surface_work_backtest as
select
  e.evidence_key,
  e.state_code,
  e.contract_id,
  e.project_id,
  e.letting_date,
  e.surface_work_family,
  e.item_description,
  e.bridge_reference,
  e.matched_bridge_id,
  b.structure_number,
  b.structure_kind_code,
  b.structure_type_code,
  b.superstructure_condition,
  sc.paint_project_search_priority as prior_forecast_priority,
  sc.work_proposed_family as prior_work_proposed_family,
  sc.paint_applicability as prior_paint_applicability,
  case
    when e.matched_bridge_id is null then 'unmatched_validation_evidence'
    when sc.paint_project_search_priority in ('high_project_search_priority','medium_project_search_priority') then 'forecast_scaffold_would_prioritize'
    when sc.paint_project_search_priority='exclude_explicit_unpainted_steel' then 'forecast_conflict_requires_review'
    else 'confirmed_hit_missed_by_condition_scaffold'
  end as backtest_result
from research.bridge_surface_work_evidence e
left join transportation.bridges b on b.id=e.matched_bridge_id
left join research.v_bridge_paint_project_search_scaffold sc on sc.bridge_id=e.matched_bridge_id;

comment on view research.v_bridge_surface_work_backtest is
  'Research-only comparison of confirmed DOT surface-work evidence against the pre-existing condition-based bridge paint project-search scaffold.';

-- Source capability matrix: confirmed-hit feeds are now identified and validated with official examples,
-- but automated collection has not yet been run, so production readiness remains gated.
insert into research.surface_work_source_capabilities (
  capability_key,selector_type,selector_value,
  asset_identity_resolution,buyer_resolution,project_scope_resolution,
  timing_resolution,prep_relationship_resolution,semantic_noise_risk,
  observed_strength,evidence_summary,limitations
) values
(
  'kytc_bridge_surface_work_bid_items','source_slug','kytc-unit-bid-tabulations',
  'strong','strong','strong','strong','strong','low','strong',
  'Official KYTC bid/proposal records expose bridge identifiers and explicit bid-item codes for clean-and-paint structural steel, blast cleaning, bridge cleaning and concrete coating.',
  'Automated archive collector is not yet populated. Pavement striping paint and epoxy-coated reinforcement must remain explicit negative filters.'
),
(
  'indot_bridge_surface_work_bid_items','source_slug','indot-bridge-bid-tabs',
  'partial','strong','strong','strong','strong','low','strong',
  'Official INDOT bid tabs expose BRIDGE PAINTING contracts, CLEAN STEEL BRIDGE and COAT STEEL BRIDGE items, bidders and prices.',
  'Bid tabs can use contract-local Bridge No. identifiers. Physical bridge resolution requires the project/DES route-location context from Notice to Highway Contractors or equivalent project listings.'
),
(
  'indot_bridge_surface_work_project_crosswalk','source_slug','indot-notice-to-highway-contractors',
  'strong','strong','strong','strong','none','low','strong',
  'INDOT project notices/project listings expose DES/project number, bridge-painting work type, county, route and location and can resolve bid-tab contracts to Scout bridge records.',
  'This source establishes project/asset identity but does not by itself enumerate prep/coating pay items.'
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

update research.painting_signal_target_readiness
set confirmed_hit_readiness='source_registered_needs_validation',
    confirmed_hit_sources=array['kytc-unit-bid-tabulations','indot-bridge-bid-tabs','indot-notice-to-highway-contractors'],
    confirmed_hit_basis='Authoritative KYTC and INDOT procurement records expose direct bridge cleaning/painting/coating scope and bridge/project identity. Hand-verified examples are normalized in research; automated archive ingestion remains the final systematic-coverage gate.',
    observed_confirmed_scope_units=5,
    observation_note='Verified anchors include KYTC bridge cleaning + concrete coating on 056B00089R, KYTC clean-and-paint structural steel item 08434, and two INDOT B-43740-A bridge-painting projects. The two resolved INDOT bridges have superstructure conditions 6 and 7, demonstrating that condition-only prioritization misses preventive coating work.',
    blocker='Run and validate the automated KYTC/INDOT letting collectors across multiple letting dates; then measure bridge match coverage and false-positive rate before promotion.',
    next_action='Populate the registered DOT letting sources, resolve project/bid items to bridge IDs, and backtest confirmed paint/coating contracts against the existing forecast scaffold. Add coating-condition/Element 515 only for forecast lift not already captured by project programs.',
    reviewed_at=now()
where survey_key='transportation_agency:steel_bridge_superstructure';

revoke all on research.bridge_surface_work_evidence from public, anon, authenticated;
revoke all on research.v_bridge_surface_work_raw_evidence from public, anon, authenticated;
revoke all on research.v_bridge_surface_work_backtest from public, anon, authenticated;
