-- Scout by Cadastory
-- Surface-work signal survey v2.
-- Research-only. No production opportunity/scoring/MCP integration.

create schema if not exists research;

create table if not exists research.surface_work_source_capabilities (
  capability_key text primary key,
  selector_type text not null check (selector_type in ('source_slug','source_class')),
  selector_value text not null,
  asset_identity_resolution text not null check (asset_identity_resolution in ('strong','partial','weak','none')),
  buyer_resolution text not null check (buyer_resolution in ('strong','partial','weak','none')),
  project_scope_resolution text not null check (project_scope_resolution in ('strong','partial','weak','none')),
  timing_resolution text not null check (timing_resolution in ('strong','partial','weak','none')),
  prep_relationship_resolution text not null check (prep_relationship_resolution in ('strong','partial','weak','none')),
  semantic_noise_risk text not null check (semantic_noise_risk in ('low','medium','high')),
  observed_strength text not null check (observed_strength in ('strong','testable','context_only','not_suitable')),
  evidence_summary text not null,
  limitations text,
  reviewed_at timestamptz not null default now()
);

insert into research.surface_work_source_capabilities (
  capability_key, selector_type, selector_value,
  asset_identity_resolution, buyer_resolution, project_scope_resolution,
  timing_resolution, prep_relationship_resolution, semantic_noise_risk,
  observed_strength, evidence_summary, limitations
) values
('wris_water_projects','source_slug','ky-kia-proposed-water-improvements','strong','strong','strong','strong','strong','low','strong',
 'WRIS project purpose text contains repaint/recoat/coating/cleaning/blasting language and most observed coating rows resolve to physical tanks and utilities.',
 'Interior versus exterior scope is frequently unresolved; do not promote all tank coating work as exterior cleaning.'),
('kytc_bridge_condition','source_slug','kydot-trak-bridge-condition-current','strong','partial','partial','strong','none','medium','testable',
 'KYTC TRAK identifies physical bridges and often enough description to distinguish painted steel, unpainted steel, and steel with unresolved coating status.',
 'Condition feed does not itself prove a current repaint project or surface-prep requirement.'),
('indiana_school_capital','source_slug','indiana-dlgf-school-capital-projects','partial','strong','strong','strong','weak','medium','strong',
 'Capital-plan rows expose explicit future exterior painting/Dryvit coating scopes with district identity and plan year/cost when available.',
 'Project rows frequently mix exterior, interior, pavement, and athletic work; prep cleaning is usually not explicit.'),
('kentucky_school_facility_plans','source_slug','kde-district-facility-plans','partial','strong','partial','partial','partial','medium','strong',
 'Facility-plan document text contains explicit lifecycle scopes including clean EIFS, exterior painting/sealant, and clean brick + repair/repaint EIFS.',
 'Relevant scope is currently often document-level rather than normalized to a specific project/facility row; proper nouns can create naive keyword false positives.'),
('louisville_active_permits','source_slug','louisville-active-construction-permits','strong','weak','weak','strong','none','high','context_only',
 'Active permits provide address, permit/work type, contractor, value, square footage, and issue timing.',
 'No free-text work-description field; cannot distinguish repaint/recoat/restoration from generic renovation by semantics.'),
('louisville_historical_permits','source_slug','louisville-historical-finaled-commercial-permits','strong','weak','weak','partial','none','high','context_only',
 'Historical finaled permits provide address-based lifecycle anchors useful for corroboration.',
 'Current roof lifecycle anchors from this source are new-construction age proxies, not observed roof replacements/recoats.'),
('kentucky_transparency','source_slug','kentucky-transparency-contracts','partial','strong','partial','strong','weak','high','testable',
 'State contract records can expose agency, vendor, dates, amounts, and occasionally detailed modification/scope text.',
 'Vendor/legal/place names can contain paint/coating terms without proving structure-maintenance scope; contractDescriptionTexts is often absent.'),
('official_operator_portfolios','source_class','official_operator_portfolio','strong','strong','none','partial','none','low','context_only',
 'First-party hotel, dealership, multifamily, and industrial/logistics portfolio rosters strongly resolve managed assets and account-level buyers.',
 'These rosters generally do not expose renovation/repaint/recoat timing or prep scope; separate project/maintenance feeds are required.')
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

create or replace view research.v_public_facade_surface_work_probe as
with indiana as (
  select
    'indiana-dlgf-school-capital-projects'::text as source_slug,
    r.source_native_id,
    r.raw_payload->>'unit_name' as buyer_name,
    r.raw_payload->>'project_title' as project_label,
    r.raw_payload->>'plan_year' as timing_text,
    r.raw_payload->>'estimated_cost' as amount_text,
    lower(concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block')) as scope_lc,
    left(concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block'),1200) as evidence_excerpt,
    'project_row'::text as evidence_granularity
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='indiana-dlgf-school-capital-projects'
    and r.source_native_id like 'candidate|%'
    and lower(concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block')) ~
      '(exterior[^a-z]{0,40}(paint|coat|coating|repaint)|dryvit[^a-z]{0,40}(coat|coating|paint|repaint)|eifs[^a-z]{0,40}(coat|coating|paint|repaint))'
), kde_docs as (
  select
    'kde-district-facility-plans'::text as source_slug,
    r.source_native_id,
    r.raw_payload->>'district_label' as buyer_name,
    coalesce(r.raw_payload->>'document_name',r.source_native_id) as project_label,
    coalesce(r.raw_payload->>'schedule_bucket',r.raw_payload->>'kde_approval_date_text') as timing_text,
    r.raw_payload->>'estimated_cost' as amount_text,
    lower(coalesce(r.raw_payload->>'extracted_text','')) as scope_lc,
    r.raw_payload->>'extracted_text' as full_text,
    'document_text'::text as evidence_granularity
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='kde-district-facility-plans'
    and coalesce(r.raw_payload->>'extracted_text','')<>''
    and lower(r.raw_payload->>'extracted_text') ~
      '(clean eifs|clean brick|clean masonry|exterior painting|exterior paint|repaint eifs|eifs panel repair|eifs repairs|dryvit)'
), kde as (
  select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,scope_lc,evidence_granularity,
         substring(full_text from greatest(
           least(
             coalesce(nullif(strpos(scope_lc,'clean eifs'),0),2147483647),
             coalesce(nullif(strpos(scope_lc,'clean brick'),0),2147483647),
             coalesce(nullif(strpos(scope_lc,'clean masonry'),0),2147483647),
             coalesce(nullif(strpos(scope_lc,'exterior painting'),0),2147483647),
             coalesce(nullif(strpos(scope_lc,'exterior paint'),0),2147483647),
             coalesce(nullif(strpos(scope_lc,'repaint eifs'),0),2147483647),
             coalesce(nullif(strpos(scope_lc,'eifs panel repair'),0),2147483647),
             coalesce(nullif(strpos(scope_lc,'eifs repairs'),0),2147483647),
             coalesce(nullif(strpos(scope_lc,'dryvit'),0),2147483647)
           )-260,1) for 1100) as evidence_excerpt
  from kde_docs
)
select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,evidence_granularity,evidence_excerpt,
       (scope_lc ~ '(exterior[^a-z]{0,40}(paint|painting|coat|coating|repaint)|repaint eifs|dryvit[^a-z]{0,40}(coat|coating|paint|repaint)|eifs[^a-z]{0,40}(coat|coating|paint|repaint))') as coating_or_paint_explicit,
       (scope_lc ~ '(clean eifs|clean brick|clean masonry|pressure wash|power wash|wash exterior)') as cleaning_explicit,
       case
         when scope_lc ~ '(clean eifs|clean brick|clean masonry|pressure wash|power wash|wash exterior)'
          and scope_lc ~ '(exterior[^a-z]{0,40}(paint|painting|coat|coating|repaint)|repaint eifs|dryvit[^a-z]{0,40}(coat|coating|paint|repaint)|eifs[^a-z]{0,40}(coat|coating|paint|repaint))'
           then case when evidence_granularity='project_row' then 'explicit_same_project' else 'same_document_requires_facility_resolution' end
         when scope_lc ~ '(clean eifs|clean brick|clean masonry|pressure wash|power wash|wash exterior)' then 'cleaning_explicit_downstream_treatment_unresolved'
         else 'coating_or_paint_explicit_prep_unresolved'
       end as cleaning_relationship_semantics
from (
  select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,scope_lc,evidence_excerpt,evidence_granularity from indiana
  union all
  select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,scope_lc,evidence_excerpt,evidence_granularity from kde
) x;

create or replace view research.v_roof_treatment_observability_probe as
with raw as (
  select s.slug, lower(r.raw_payload::text) as lc
  from ingest.raw_records r join ingest.sources s on s.id=r.source_id
  where s.slug in ('kde-district-facility-plans','indiana-dlgf-school-capital-projects','kentucky-transparency-contracts')
), source_counts as (
  select
    count(*) filter(where lc ~ '(roof restoration|restore[^a-z]{0,20}roof|roof recover|roof re-cover|recover[^a-z]{0,20}roof|roof resurfacing|roof membrane coating|fluid[- ]applied roof|silicone[^a-z]{0,20}roof|acrylic[^a-z]{0,20}roof|elastomeric[^a-z]{0,20}roof)')::bigint as explicit_restoration_scope,
    count(*) filter(where lc ~ '(roof replacement|replace[^a-z]{0,20}roof|re-roof|reroof)')::bigint as explicit_replacement_scope,
    count(*) filter(where lc ~ '(roof repair|roofing repair|repair[^a-z]{0,20}roof)')::bigint as explicit_repair_scope
  from raw
), pm as (
 select lower(regexp_replace(regexp_replace(trim(site_address_text),'[.,]','','g'),'\s+',' ','g')) as a0
 from scout.v_property_management_facilities
 where state='KY' and site_address_text is not null
), pmn as (
 select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(a0,
 '\bstreet\b','st','g'),'\broad\b','rd','g'),'\bdrive\b','dr','g'),'\blane\b','ln','g'),'\bavenue\b','ave','g'),'\bboulevard\b','blvd','g'),'\bparkway\b','pky','g'),'\bhighway\b','hwy','g') as an from pm
), ra as (
 select lower(regexp_replace(regexp_replace(trim(subject_key),'[.,]','','g'),'\s+',' ','g')) as a0
 from intelligence.v_roof_lifecycle_pressure where subject_type='address'
), ran as (
 select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(a0,
 '\bstreet\b','st','g'),'\broad\b','rd','g'),'\bdrive\b','dr','g'),'\blane\b','ln','g'),'\bavenue\b','ave','g'),'\bboulevard\b','blvd','g'),'\bparkway\b','pky','g'),'\bhighway\b','hwy','g') as an from ra
), overlap as (
 select count(*)::bigint as n from pmn where exists(select 1 from ran where ran.an=pmn.an)
)
select 'active_roof_lifecycle_age_anchors'::text as metric, count(*)::bigint as records,
       'All current roof lifecycle pressure records are address-level new-construction age proxies; useful as corroboration, not coating evidence.'::text as interpretation
from intelligence.v_roof_lifecycle_pressure
union all
select 'explicit_roof_restoration_or_recoat_scope', explicit_restoration_scope,
       'No explicit restoration/recoat scope currently observed in the surveyed school/procurement feeds; roof recoating remains under-observed.'
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
       'Direct normalized-address overlap is currently absent; portfolio-aware roof inference needs a building/property crosswalk rather than string matching.'
from overlap;

update research.surface_work_signal_survey
set observability='medium', scout_coverage='partial', opportunity_fit='testable',
    source_gap='Current Scout sources expose roof age, replacement, and repair context but no explicit roof restoration/recoat scopes in the surveyed feeds; add treatment-aware roofing procurement/specification sources and a building/property crosswalk.',
    notes=concat_ws(' ',notes,'2026-09-07 survey: 1,253 roof lifecycle records are new-construction age proxies; surveyed public capital/procurement feeds showed replacement/repair but zero explicit restoration/recoat scope.'),
    reviewed_at=now()
where survey_key='commercial_property:roof_recoating';

update research.surface_work_signal_survey
set observability='medium', scout_coverage='partial', opportunity_fit='testable',
    source_gap='Public school facility plans prove that exterior paint/EIFS cleaning-repaint scopes are observable, but private commercial portfolio feeds currently resolve ownership more reliably than renovation scope/timing.',
    notes=concat_ws(' ',notes,'2026-09-07 survey: Kentucky facility plans include clean EIFS, exterior painting/sealant, and clean brick + repair/repaint EIFS; private portfolio treatment timing remains a source gap.'),
    reviewed_at=now()
where survey_key='commercial_property:painted_facade_recoating';

update research.surface_work_signal_survey
set source_gap='Classify mixed interior/exterior/ground scopes, resolve document-level Kentucky facility-plan text to specific buildings, and distinguish explicit cleaning prep from coating-only scopes.',
    notes=concat_ws(' ',notes,'2026-09-07 survey confirmed explicit public-facility scopes including clean EIFS, exterior painting/sealant, and clean brick + repair/repaint EIFS.'),
    reviewed_at=now()
where survey_key='school_district:exterior_building_painting';

revoke all on research.surface_work_source_capabilities from anon,authenticated;
revoke all on research.v_public_facade_surface_work_probe from anon,authenticated;
revoke all on research.v_roof_treatment_observability_probe from anon,authenticated;

comment on table research.surface_work_source_capabilities is 'Research-only matrix describing what current Scout sources can prove about surface-work signals. Not production decisioning.';
comment on view research.v_public_facade_surface_work_probe is 'Research-only public-facility facade paint/coating/cleaning evidence probe across Indiana and Kentucky school planning sources.';
comment on view research.v_roof_treatment_observability_probe is 'Research-only measurement of roof restoration/recoat observability and current portfolio/lifecycle gaps.';
