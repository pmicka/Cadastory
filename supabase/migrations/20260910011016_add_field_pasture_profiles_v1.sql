-- Scout livestock pasture classification v1.
--
-- CSB/CDL history is source evidence; the classifications below are deterministic
-- derived facts and do not establish observed grazing, ownership, or operation.

create materialized view if not exists agriculture.field_pasture_profiles_v1 as
with field_history as (
  select
    h.field_id,
    count(*)::integer as observed_years,
    count(*) filter (where h.crop_code='176')::integer as pasture_years,
    count(*) filter (where h.crop_code in ('36','37'))::integer as hay_years,
    count(*) filter (where h.crop_code in ('36','37','176'))::integer as forage_years,
    min(h.crop_year) filter (where h.crop_code in ('36','37','176'))::integer as first_forage_year,
    max(h.crop_year) filter (where h.crop_code in ('36','37','176'))::integer as last_forage_year
  from agriculture.field_crop_history h
  group by h.field_id
), base as (
  select
    f.id as field_id,
    f.source_id,
    f.source_native_id,
    f.state_fips,
    f.county_name,
    f.county_fips,
    f.acres as gross_acres,
    coalesce(h.observed_years,0)::integer as observed_years,
    coalesce(h.pasture_years,0)::integer as pasture_years,
    coalesce(h.hay_years,0)::integer as hay_years,
    coalesce(h.forage_years,0)::integer as forage_years,
    h.first_forage_year,
    h.last_forage_year,
    f.latest_crop_year,
    f.latest_crop_code,
    f.source_confidence
  from agriculture.field_boundaries f
  left join field_history h on h.field_id=f.id
  where f.source_present
    and f.boundary_source_kind='usda_nass_csb'
)
select
  b.field_id,b.source_id,b.source_native_id,b.state_fips,b.county_name,b.county_fips,b.gross_acres,
  b.observed_years,b.pasture_years,b.hay_years,b.forage_years,b.first_forage_year,b.last_forage_year,
  b.latest_crop_year,b.latest_crop_code,
  case when b.observed_years>0 then round(b.pasture_years::numeric/b.observed_years::numeric,4) else 0::numeric end as pasture_persistence_score,
  case when b.observed_years>0 then round(b.forage_years::numeric/b.observed_years::numeric,4) else 0::numeric end as forage_persistence_score,
  case
    when b.pasture_years>=6 then 'persistent_pasture'
    when b.hay_years>=6 then 'persistent_hay'
    when b.forage_years>=6 then 'persistent_mixed_forage'
    when b.latest_crop_code=176 and b.pasture_years>=2 then 'recent_pasture'
    when b.latest_crop_code in (36,37) and b.hay_years>=2 then 'recent_hay'
    when b.forage_years>=2 then 'rotational_forage'
    else 'non_forage'
  end as profile_class,
  (b.pasture_years>=2 or b.latest_crop_code=176) as pasture_candidate,
  (b.forage_years>=2 or b.latest_crop_code in (36,37,176)) as forage_candidate,
  (b.pasture_years>=6) as persistent_pasture,
  (b.forage_years>=6) as persistent_forage,
  case
    when b.pasture_years>=6 then 'high'
    when b.pasture_years>=3
      or (b.latest_crop_code=176 and b.pasture_years>=2)
      or (b.forage_years>=6 and b.pasture_years>=2) then 'moderate'
    when b.forage_years>=2 then 'low'
    else 'none'
  end as grazing_relevance,
  least(1::numeric,greatest(0::numeric,coalesce(b.source_confidence,0::numeric))*least(b.observed_years,8)::numeric/8::numeric) as classification_confidence,
  b.source_confidence,
  jsonb_build_object(
    'profile_version','csb_cdl_sequence_v1',
    'classification_basis','USDA NASS Crop Sequence Boundaries / normalized CDL history 2018-2025',
    'pasture_codes',jsonb_build_array(176),
    'hay_codes',jsonb_build_array(36,37),
    'inference_scope','land-cover/forage classification only; does not establish grazing, ownership, or operation'
  ) as evidence_summary,
  now() as derived_at
from base b;

create unique index if not exists field_pasture_profiles_v1_field_uidx
  on agriculture.field_pasture_profiles_v1(field_id);
create index if not exists field_pasture_profiles_v1_class_idx
  on agriculture.field_pasture_profiles_v1(profile_class,grazing_relevance);
create index if not exists field_pasture_profiles_v1_state_county_idx
  on agriculture.field_pasture_profiles_v1(state_fips,county_name);
create index if not exists field_pasture_profiles_v1_candidate_idx
  on agriculture.field_pasture_profiles_v1(pasture_candidate,persistent_pasture)
  where pasture_candidate is true;

comment on materialized view agriculture.field_pasture_profiles_v1 is
  'Deterministic derived pasture/forage profile from USDA NASS CSB/CDL field history. Profile classes describe land-cover persistence, not observed grazing or operator attribution. Refresh after field_crop_history/field_boundaries CSB updates.';
