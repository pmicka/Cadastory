create or replace view agriculture.v_livestock_pasture_corroboration_v1 as
with parcel_evidence as (
  select
    c.candidate_id,
    c.field_id,
    count(p.id)::integer as parcel_overlap_records,
    bool_or(
      agriculture.normalize_match_text(c.best_address) is not null
      and agriculture.normalize_match_text(c.best_address) = agriculture.normalize_match_text(concat_ws(' ',p.mailing_address_raw,p.mailing_city_state_zip_raw))
    ) as exact_farm_address_matches_parcel_mailing,
    max(p.field_overlap_pct) as max_field_parcel_overlap_pct,
    max(p.overlap_acres) as max_parcel_overlap_acres
  from agriculture.v_livestock_pasture_field_candidates_v1 c
  left join agriculture.field_parcel_overlaps p on p.field_id=c.field_id
  group by c.candidate_id,c.field_id
), bridge as (
  select
    b.operator_candidate_id as candidate_id,
    b.field_id,
    b.match_basis,
    b.match_confidence,
    b.bridge_state,
    b.supporting_landholder_candidate_ids,
    b.source_evidence_ids,
    b.evidence_summary as bridge_evidence_summary
  from agriculture.farm_operator_field_bridge_candidates b
)
select
  c.*,
  coalesce(pe.exact_farm_address_matches_parcel_mailing,false) as exact_farm_address_matches_parcel_mailing,
  pe.max_field_parcel_overlap_pct,
  pe.max_parcel_overlap_acres,
  b.match_basis as existing_bridge_match_basis,
  b.match_confidence as existing_bridge_confidence,
  b.bridge_state as existing_bridge_state,
  coalesce(b.supporting_landholder_candidate_ids,array[]::uuid[]) as supporting_landholder_candidate_ids,
  coalesce(b.source_evidence_ids,array[]::uuid[]) as source_evidence_ids,
  case
    when b.field_id is not null then 'existing_operator_field_candidate'
    when coalesce(pe.exact_farm_address_matches_parcel_mailing,false) then 'same_address_parcel_corroborated'
    when coalesce(pe.parcel_overlap_records,0)>0 and c.distance_m<=250 then 'nearby_parcel_backed_candidate'
    when c.distance_m<=250 then 'nearby_spatial_candidate'
    when coalesce(pe.parcel_overlap_records,0)>0 then 'parcel_backed_spatial_candidate'
    else 'spatial_candidate_only'
  end as corroboration_state,
  case
    when b.field_id is not null then greatest(0.0::numeric,least(1.0::numeric,b.match_confidence))
    when coalesce(pe.exact_farm_address_matches_parcel_mailing,false) then 0.70::numeric
    when coalesce(pe.parcel_overlap_records,0)>0 and c.distance_m<=250 then 0.45::numeric
    when c.distance_m<=250 then 0.30::numeric
    when coalesce(pe.parcel_overlap_records,0)>0 then 0.25::numeric
    else 0.15::numeric
  end as corroboration_strength,
  (b.field_id is not null or coalesce(pe.exact_farm_address_matches_parcel_mailing,false)) as landholding_corroborated,
  case
    when b.field_id is not null then 'candidate'
    else 'unconfirmed'
  end as operation_attribution_state,
  c.evidence_summary || jsonb_build_object(
    'corroboration_version','livestock_pasture_corroboration_v1',
    'corroboration_scope','evidence ladder only; proximity and parcel overlap do not establish operation',
    'exact_farm_address_matches_parcel_mailing',coalesce(pe.exact_farm_address_matches_parcel_mailing,false),
    'existing_bridge_match_basis',b.match_basis,
    'existing_bridge_state',b.bridge_state
  ) as corroboration_evidence_summary
from agriculture.v_livestock_pasture_field_candidates_v1 c
left join parcel_evidence pe on pe.candidate_id=c.candidate_id and pe.field_id=c.field_id
left join bridge b on b.candidate_id=c.candidate_id and b.field_id=c.field_id;

comment on view agriculture.v_livestock_pasture_corroboration_v1 is
'Ranks livestock-to-pasture hypotheses by independent corroborating evidence. No proximity-only or parcel-overlap-only row establishes farm operation; existing bridge rows remain candidates unless separately confirmed.';

create or replace view agriculture.v_livestock_pasture_portfolio_v1 as
with x as (
  select * from agriculture.v_livestock_pasture_corroboration_v1
), agg as (
  select
    candidate_id,
    max(farm_name) as farm_name,
    max(organization_id::text)::uuid as organization_id,
    max(state_code) as state_code,
    max(farm_county_name) as county_name,
    max(best_address) as best_address,
    max(location_confidence) as location_confidence,
    max(enterprise_kinds::text)::text[] as enterprise_kinds,
    count(*)::integer as pasture_candidate_fields,
    count(*) filter (where distance_m<=250)::integer as candidate_fields_within_250m,
    count(*) filter (where grazing_relevance='high')::integer as high_grazing_relevance_fields,
    count(*) filter (where landholding_corroborated)::integer as landholding_corroborated_fields,
    coalesce(sum(gross_acres) filter (where landholding_corroborated),0)::numeric as landholding_corroborated_candidate_acres,
    min(distance_m)::integer as nearest_candidate_distance_m,
    max(corroboration_strength) as max_corroboration_strength,
    bool_or(existing_bridge_state is not null) as has_existing_operator_field_candidate,
    bool_or(exact_farm_address_matches_parcel_mailing) as has_same_address_parcel_corroboration,
    bool_or(parcel_overlap_records>0) as has_any_parcel_backed_candidate,
    count(*) filter (where parcel_overlap_records>0 and distance_m<=250)::integer as nearby_parcel_backed_fields
  from x
  group by candidate_id
), best as (
  select distinct on (candidate_id)
    candidate_id,field_id as best_field_id,profile_class as best_field_profile_class,
    grazing_relevance as best_field_grazing_relevance,gross_acres as best_field_acres,
    distance_m as best_field_distance_m,corroboration_state as best_field_corroboration_state,
    corroboration_strength as best_field_corroboration_strength
  from x
  order by candidate_id,corroboration_strength desc,ranking_score_v1 desc,candidate_rank asc
)
select
  a.*,b.best_field_id,b.best_field_profile_class,b.best_field_grazing_relevance,b.best_field_acres,
  b.best_field_distance_m,b.best_field_corroboration_state,b.best_field_corroboration_strength,
  case
    when a.has_existing_operator_field_candidate then 'existing_operator_field_candidates'
    when a.has_same_address_parcel_corroboration then 'same_address_parcel_corroboration'
    when a.nearby_parcel_backed_fields>0 then 'parcel_corroboration_research_priority'
    when a.candidate_fields_within_250m>0 then 'nearby_pasture_research_priority'
    else 'spatial_candidates_unconfirmed'
  end as portfolio_evidence_state,
  case
    when a.has_existing_operator_field_candidate then 1
    when a.has_same_address_parcel_corroboration then 2
    when a.nearby_parcel_backed_fields>0 then 3
    when a.candidate_fields_within_250m>0 then 4
    else 5
  end as research_priority_tier
from agg a join best b using(candidate_id);

comment on view agriculture.v_livestock_pasture_portfolio_v1 is
'Livestock-farm pasture research portfolio summary. Acreage labeled landholding_corroborated_candidate_acres remains candidate acreage and must not be described as operated/managed acreage without operator evidence.';