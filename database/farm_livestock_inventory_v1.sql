create or replace view agriculture.farm_livestock_inventory_v1 as
with base as (
  select
    o.candidate_id,
    max(o.farm_name) as farm_name,
    max(o.organization_id::text)::uuid as organization_id,
    max(o.state_code) as state_code,
    max(o.county_name) as county_name,
    max(o.observed_address) as observed_address,
    jsonb_agg(
      jsonb_build_object(
        'animal_class', o.animal_class,
        'enterprise_kind', o.enterprise_kind,
        'count', o.animal_count,
        'count_status', o.count_status,
        'count_basis', o.count_basis,
        'effective_date', o.effective_date,
        'source_slug', o.source_slug,
        'source_url', o.source_url,
        'source_evidence_id', o.source_evidence_id,
        'confidence', o.confidence,
        'is_current', o.is_current,
        'attributes', o.attributes
      ) order by o.enterprise_kind, o.animal_class
    ) filter (where o.is_current) as structured_observations,
    array_agg(distinct o.enterprise_kind order by o.enterprise_kind) filter (where o.is_current) as enterprise_kinds,
    bool_or(o.is_current and o.count_status='reported' and o.animal_count is not null) as has_structured_count
  from agriculture.farm_livestock_observations_v1 o
  group by o.candidate_id
), doc_findings as (
  select
    j.subject_id as candidate_id,
    jsonb_agg(
      jsonb_build_object(
        'decision_state', f.decision_state,
        'animal_types', coalesce(f.extracted_values->'animal_types','[]'::jsonb),
        'animal_counts', coalesce(f.extracted_values->'animal_counts','[]'::jsonb),
        'count_semantics', f.extracted_values->>'count_semantics',
        'source_url', f.source_url,
        'document_title', f.document_title,
        'page_number', f.page_number,
        'evidence_excerpt', f.evidence_excerpt,
        'confidence', f.confidence,
        'identity_confidence', f.identity_confidence,
        'observed_at', f.observed_at
      ) order by f.confidence desc, f.observed_at desc
    ) as document_findings,
    bool_or(
      f.decision_state='documented'
      and jsonb_array_length(coalesce(f.extracted_values->'animal_counts','[]'::jsonb)) > 0
    ) as has_documented_explicit_count,
    max(f.observed_at) as latest_document_evidence_at
  from research.document_evidence_jobs j
  join research.document_evidence_findings f on f.job_id=j.id
  where j.rule_pack='livestock_inventory_v1'
  group by j.subject_id
), loc as (
  select distinct on (d.candidate_id)
    d.candidate_id,
    d.location,
    d.county_name as geocoded_county_name,
    d.matched_address,
    d.confidence as location_confidence,
    d.geocode_source_id as location_source_id,
    d.updated_at as location_updated_at
  from agriculture.farm_directory_locations d
  where d.location is not null
  order by d.candidate_id, d.confidence desc nulls last, d.updated_at desc
)
select
  b.candidate_id,
  b.farm_name,
  b.organization_id,
  b.state_code,
  coalesce(loc.geocoded_county_name,b.county_name) as county_name,
  coalesce(loc.matched_address,b.observed_address) as best_address,
  loc.location,
  loc.location_confidence,
  b.enterprise_kinds,
  coalesce(b.structured_observations,'[]'::jsonb) as structured_observations,
  coalesce(df.document_findings,'[]'::jsonb) as document_findings,
  coalesce(b.has_structured_count,false) as has_structured_count,
  coalesce(df.has_documented_explicit_count,false) as has_documented_explicit_count,
  case
    when coalesce(b.has_structured_count,false) then 'structured_reported_count'
    when coalesce(df.has_documented_explicit_count,false) then 'documented_explicit_count'
    else 'type_known_count_unknown'
  end as count_coverage,
  case
    when coalesce(b.has_structured_count,false) then false
    when coalesce(df.has_documented_explicit_count,false) then false
    else true
  end as needs_count_enrichment,
  (loc.location is null) as needs_location_enrichment,
  df.latest_document_evidence_at,
  now() as evaluated_at
from base b
left join doc_findings df on df.candidate_id=b.candidate_id
left join loc on loc.candidate_id=b.candidate_id;

comment on view agriculture.farm_livestock_inventory_v1 is
'Evidence-first per-farm livestock inventory. Structured permit-reported counts and explicit public-document counts remain separate evidence classes; neither is asserted to be a live aerial headcount. Exposes type/count/location enrichment gaps without inference-as-fact.';
