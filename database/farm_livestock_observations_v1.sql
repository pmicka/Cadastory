create or replace view agriculture.farm_livestock_observations_v1 as
with permit_observations as (
  select
    fec.id as candidate_id,
    fec.display_name as farm_name,
    fec.organization_id,
    coalesce(fee.attributes->>'state_code', fec.attributes->>'state_code') as state_code,
    fee.attributes->>'county' as county_name,
    fee.observed_address,
    case
      when kv.key in ('sows','boars','finishers','nursery_pigs') then 'swine'
      when kv.key in ('beef_calves','beef_cattle') then 'beef'
      when kv.key in ('dairy_calves','dairy_cattle','dairy_heifers') then 'dairy'
      when kv.key in ('layers','poults','pullets','turkeys','broilers','ducks') then 'poultry'
      when kv.key = 'horses' then 'equine'
      when kv.key = 'sheep' then 'other_livestock'
      when kv.key = 'veal_calves' then 'cattle'
      else 'other_livestock'
    end as enterprise_kind,
    kv.key as animal_class,
    kv.value::numeric as animal_count,
    'reported'::text as count_status,
    'state_permit_reported_animal_count'::text as count_basis,
    fee.attributes->>'source_slug' as source_slug,
    src.authority as source_authority,
    fee.source_url,
    fee.id as source_evidence_id,
    fee.observed_at as source_observed_at,
    case
      when coalesce(fee.attributes->>'date_issued','') ~ '^\d{4}-\d{2}-\d{2}$'
        then (fee.attributes->>'date_issued')::date
      else null::date
    end as effective_date,
    coalesce(fec.attributes->>'permit_lifecycle_status' = 'current_record', false) as is_current,
    fee.confidence,
    null::text as source_description,
    jsonb_build_object(
      'source_farm_id', fee.attributes->>'farm_id',
      'project_type', fee.attributes->>'project_type',
      'date_received', fee.attributes->>'date_received',
      'count_semantics', 'permit-reported value; do not interpret as a live on-the-ground headcount without newer evidence'
    ) as attributes
  from agriculture.farm_entity_evidence fee
  join agriculture.farm_entity_candidates fec on fec.id = fee.candidate_id
  left join ingest.sources src on src.id = fee.source_id
  cross join lateral jsonb_each_text(coalesce(fee.attributes->'animal_counts','{}'::jsonb)) kv
  where fee.attributes->>'source_slug' = 'indiana-idem-issued-cfo-cafo'
    and kv.value ~ '^[0-9]+(?:\.[0-9]+)?$'
    and kv.value::numeric > 0
),
directory_observations as (
  select distinct on (fep.candidate_id, fep.enterprise_kind, fep.evidence_id)
    fec.id as candidate_id,
    fec.display_name as farm_name,
    fec.organization_id,
    coalesce(fep.attributes->>'state_code', fee.attributes->>'state_code') as state_code,
    fdl.county_name,
    fee.observed_address,
    fep.enterprise_kind,
    fep.enterprise_kind as animal_class,
    null::numeric as animal_count,
    'unknown'::text as count_status,
    'directory_category_signal_only'::text as count_basis,
    coalesce(fep.attributes->>'source_slug', fee.attributes->>'source_slug') as source_slug,
    src.authority as source_authority,
    fee.source_url,
    fee.id as source_evidence_id,
    fee.observed_at as source_observed_at,
    fee.observed_at::date as effective_date,
    true as is_current,
    fep.confidence,
    fee.attributes->>'description' as source_description,
    jsonb_build_object(
      'directory_category_id', fep.attributes->>'category_id',
      'directory_self_declared', coalesce((fep.attributes->>'directory_self_declared')::boolean, false),
      'type_semantics', 'directory category signal; may be incomplete for mixed-species farms and should be refined from source descriptions or stronger evidence'
    ) as attributes
  from agriculture.farm_enterprise_profiles fep
  join agriculture.farm_entity_candidates fec on fec.id = fep.candidate_id
  left join agriculture.farm_entity_evidence fee on fee.id = fep.evidence_id
  left join ingest.sources src on src.id = fee.source_id
  left join lateral (
    select d.county_name
    from agriculture.farm_directory_locations d
    where d.candidate_id = fep.candidate_id
    order by d.confidence desc nulls last, d.updated_at desc
    limit 1
  ) fdl on true
  where fep.profile_kind = 'evidence_backed'
    and coalesce(fep.attributes->>'state_code', fee.attributes->>'state_code') = 'KY'
)
select * from permit_observations
union all
select * from directory_observations;

comment on view agriculture.farm_livestock_observations_v1 is
'Normalized evidence-first livestock observations. Indiana permit records expose positive reported animal-class counts; Kentucky KDA directory records expose animal-enterprise type signals with unknown counts. Permit-reported counts are not assumed to be live inventory.';

create or replace view agriculture.farm_livestock_count_enrichment_queue_v1 as
select distinct on (candidate_id, enterprise_kind)
  candidate_id,
  farm_name,
  organization_id,
  state_code,
  county_name,
  observed_address,
  enterprise_kind,
  source_slug,
  source_url,
  source_evidence_id,
  source_observed_at,
  confidence,
  source_description,
  case
    when enterprise_kind in ('beef','dairy','equine') then 'pasture_livestock_high_relevance'
    when enterprise_kind in ('swine','poultry','other_livestock') then 'livestock_count_unknown'
    else 'livestock_count_unknown'
  end as enrichment_reason,
  attributes
from agriculture.farm_livestock_observations_v1
where is_current
  and count_status = 'unknown'
order by candidate_id, enterprise_kind, confidence desc nulls last, source_observed_at desc nulls last;

comment on view agriculture.farm_livestock_count_enrichment_queue_v1 is
'Current livestock-type observations that still lack a sourced animal count. Intended for evidence enrichment, not inference-as-fact.';
