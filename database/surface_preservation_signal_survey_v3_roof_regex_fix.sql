-- Follow-up correction for surface_preservation_signal_survey_v3.sql.
-- Keeps explicit roof recoat/restoration detection whitespace-neutral.
-- Research-only.

create or replace view research.v_roof_treatment_observability_probe as
with raw as (
  select s.slug, lower(r.raw_payload::text) as lc
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug in ('kde-district-facility-plans','indiana-dlgf-school-capital-projects','kentucky-transparency-contracts')
), source_counts as (
  select
    count(*) filter(where lc ~ '(roof restoration|restore[^a-z]{0,20}roof|roof recover|roof re-cover|recover[^a-z]{0,20}roof|roof resurfacing|roof membrane coating|fluid[- ]applied roof|silicone[^a-z]{0,20}roof|acrylic[^a-z]{0,20}roof|elastomeric[^a-z]{0,20}roof|recoat(ing)?[^a-z]{0,45}(metal )?roof|roof[^a-z]{0,45}recoat(ing)?)')::bigint as explicit_restoration_scope,
    count(*) filter(where lc ~ '(roof replacement|replace[^a-z]{0,20}roof|re-roof|reroof)')::bigint as explicit_replacement_scope,
    count(*) filter(where lc ~ '(roof repair|roofing repair|repair[^a-z]{0,20}roof)')::bigint as explicit_repair_scope
  from raw
), pm as (
 select lower(regexp_replace(regexp_replace(trim(site_address_text),'[.,]','','g'),'\s+',' ','g')) as a0
 from scout.v_property_management_facilities where state='KY' and site_address_text is not null
), pmn as (
 select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(a0,'\bstreet\b','st','g'),'\broad\b','rd','g'),'\bdrive\b','dr','g'),'\blane\b','ln','g'),'\bavenue\b','ave','g'),'\bboulevard\b','blvd','g'),'\bparkway\b','pky','g'),'\bhighway\b','hwy','g') as an from pm
), ra as (
 select lower(regexp_replace(regexp_replace(trim(subject_key),'[.,]','','g'),'\s+',' ','g')) as a0
 from intelligence.v_roof_lifecycle_pressure where subject_type='address'
), ran as (
 select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(a0,'\bstreet\b','st','g'),'\broad\b','rd','g'),'\bdrive\b','dr','g'),'\blane\b','ln','g'),'\bavenue\b','ave','g'),'\bboulevard\b','blvd','g'),'\bparkway\b','pky','g'),'\bhighway\b','hwy','g') as an from ra
), overlap as (
 select count(*)::bigint as n from pmn where exists(select 1 from ran where ran.an=pmn.an)
)
select 'active_roof_lifecycle_age_anchors'::text as metric,count(*)::bigint as records,
       'Current roof lifecycle pressure records are address-level new-construction age proxies; useful as corroboration, not coating evidence.'::text as interpretation
from intelligence.v_roof_lifecycle_pressure
union all select 'explicit_roof_restoration_or_recoat_scope',explicit_restoration_scope,'Roof restoration/recoat scope is now observed but rare in surveyed feeds; Oldham County KDE planning text explicitly includes recoating a metal gym roof.' from source_counts
union all select 'explicit_roof_replacement_scope',explicit_replacement_scope,'Replacement is observable and must be separated from restoration/recoat because prep-cleaning economics differ.' from source_counts
union all select 'explicit_roof_repair_scope',explicit_repair_scope,'Repair is observable but is not sufficient to infer a restoration coating or exterior-cleaning subtask.' from source_counts
union all select 'property_management_facilities_directly_overlapping_roof_age_anchors',n,'Direct normalized-address overlap remains insufficient; portfolio-aware roof inference needs a building/property crosswalk rather than string matching.' from overlap;

revoke all on research.v_roof_treatment_observability_probe from anon,authenticated;
