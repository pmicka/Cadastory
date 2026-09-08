-- Scout by Cadastory
-- Experimental organic-growth-pressure backbone.
-- This migration intentionally creates feature/validation infrastructure only.
-- It does NOT create a production lead-ranking rule or claim observed growth.

create table if not exists cleaning.organic_growth_feature_source_policy (
  feature_key text not null,
  source_slug text not null,
  usage text not null check (usage in ('allowed_input','label_only','excluded')),
  rationale text not null,
  updated_at timestamptz not null default now(),
  primary key (feature_key, source_slug)
);

alter table cleaning.organic_growth_feature_source_policy enable row level security;
revoke all on cleaning.organic_growth_feature_source_policy from anon, authenticated;
grant select,insert,update,delete on cleaning.organic_growth_feature_source_policy to service_role;

insert into cleaning.organic_growth_feature_source_policy(feature_key,source_slug,usage,rationale)
values
  ('facade_material','openstreetmap-geofabrik-building-attributes','allowed_input','Exogenous/source-reported material evidence; does not require observing current surface condition.'),
  ('facade_material','overture-buildings','allowed_input','Exogenous building-attribute source; material classification is permitted as an experimental predictor.'),
  ('facade_material','scout-facade-visual-verification','label_only','Excluded from predictor construction to prevent visual-condition/biological-staining leakage. Visual evidence may be used only as independent validation/ground truth.')
on conflict(feature_key,source_slug) do update set
  usage=excluded.usage,
  rationale=excluded.rationale,
  updated_at=now();

create table if not exists cleaning.organic_growth_material_receptivity (
  facade_material text primary key,
  surface_class text not null,
  receptivity_band text not null check (receptivity_band in ('low','medium','high')),
  receptivity_ordinal smallint not null check (receptivity_ordinal between 0 and 2),
  basis text not null,
  model_version text not null default 'organic-growth-material-v1',
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table cleaning.organic_growth_material_receptivity enable row level security;
revoke all on cleaning.organic_growth_material_receptivity from anon, authenticated;
grant select,insert,update,delete on cleaning.organic_growth_material_receptivity to service_role;

insert into cleaning.organic_growth_material_receptivity(facade_material,surface_class,receptivity_band,receptivity_ordinal,basis)
values
  ('brick','porous_masonry','high',2,'Coarse intrinsic-surface prior: porous/rough masonry tends to retain moisture and support colonization more readily than smooth nonporous surfaces.'),
  ('stone','porous_masonry','high',2,'Coarse intrinsic-surface prior; stone type and finish are intentionally not simulated in v1.'),
  ('limestone','porous_carbonate_masonry','high',2,'Coarse intrinsic-surface prior for porous carbonate masonry.'),
  ('masonry','porous_masonry','high',2,'Generic masonry prior; no condition or visible staining evidence is used.'),
  ('plaster','render_or_stucco','high',2,'Coarse render/stucco-like prior; texture/finish condition is intentionally not inferred from imagery.'),
  ('cement_block','porous_cementitious','high',2,'Coarse porous cementitious prior.'),
  ('concrete','cementitious','medium',1,'Concrete receptivity varies substantially with finish/coating/weathering; v1 deliberately uses a neutral-middle prior rather than inferring condition.'),
  ('wood','wood_or_coated_wood','medium',1,'Coarse material prior; coating and maintenance state are intentionally not inferred.'),
  ('plastic','smooth_polymer','low',0,'Coarse smooth-polymer prior.'),
  ('metal','smooth_nonporous','low',0,'Coarse smooth-metal prior; coating condition is intentionally not inferred.'),
  ('glass','smooth_nonporous','low',0,'Coarse glass prior for biological-growth pressure, not general cleaning need.')
on conflict(facade_material) do update set
  surface_class=excluded.surface_class,
  receptivity_band=excluded.receptivity_band,
  receptivity_ordinal=excluded.receptivity_ordinal,
  basis=excluded.basis,
  model_version=excluded.model_version,
  active=true,
  updated_at=now();

create table if not exists cleaning.organic_growth_pressure_features (
  building_source_record_id uuid primary key references ingest.raw_records(id) on delete cascade,
  model_version text not null default 'organic-growth-pressure-backbone-v1',
  feature_status text not null check (feature_status in ('collecting_history','partial_inputs','ready_for_coarse_validation','insufficient_inputs','retired')),

  facade_material_input text,
  facade_material_status text,
  facade_material_source_slug text,
  facade_material_confidence numeric check (facade_material_confidence is null or (facade_material_confidence between 0 and 1)),
  surface_class text,
  material_receptivity_band text check (material_receptivity_band is null or material_receptivity_band in ('low','medium','high')),
  material_receptivity_ordinal smallint check (material_receptivity_ordinal is null or material_receptivity_ordinal between 0 and 2),

  tree_canopy_pct numeric,
  annual_rh_pct numeric,
  warm_season_rh_pct numeric,
  humidity_climate_period text,

  qpe_sample_key text,
  qpe_sample_distance_m numeric,
  qpe_first_date date,
  qpe_last_date date,
  qpe_days_30 integer not null default 0 check (qpe_days_30 >= 0),
  qpe_days_90 integer not null default 0 check (qpe_days_90 >= 0),
  qpe_days_365 integer not null default 0 check (qpe_days_365 >= 0),
  precip_total_30d_inches numeric,
  precip_total_90d_inches numeric,
  precip_total_365d_inches numeric,
  wet_days_30d integer not null default 0 check (wet_days_30d >= 0),
  wet_days_90d integer not null default 0 check (wet_days_90d >= 0),
  wet_days_365d integer not null default 0 check (wet_days_365d >= 0),

  aspect_signal text,
  aspect_confidence numeric check (aspect_confidence is null or (aspect_confidence between 0 and 1)),
  solar_drying_signal text,
  solar_drying_confidence numeric check (solar_drying_confidence is null or (solar_drying_confidence between 0 and 1)),

  direct_observation_used boolean not null default false check (direct_observation_used = false),
  validation_label_used boolean not null default false check (validation_label_used = false),
  input_completeness jsonb not null default '{}'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now()
);

alter table cleaning.organic_growth_pressure_features enable row level security;
revoke all on cleaning.organic_growth_pressure_features from anon, authenticated;
grant select,insert,update,delete on cleaning.organic_growth_pressure_features to service_role;

create index if not exists organic_growth_pressure_features_status_idx
  on cleaning.organic_growth_pressure_features(feature_status, refreshed_at desc);
create index if not exists organic_growth_pressure_features_material_idx
  on cleaning.organic_growth_pressure_features(facade_material_input, material_receptivity_band);

create table if not exists cleaning.organic_growth_validation_labels (
  id uuid primary key default gen_random_uuid(),
  building_source_record_id uuid not null references ingest.raw_records(id) on delete cascade,
  observed_at timestamptz not null,
  label_source_kind text not null check (label_source_kind in ('operator','visual_verification','maintenance_record','other')),
  observed_need_band text not null check (observed_need_band in ('clean','light','moderate','heavy','unknown')),
  visible_biological_staining boolean,
  notes text,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table cleaning.organic_growth_validation_labels enable row level security;
revoke all on cleaning.organic_growth_validation_labels from anon, authenticated;
grant select,insert,update,delete on cleaning.organic_growth_validation_labels to service_role;

create index if not exists organic_growth_validation_labels_building_idx
  on cleaning.organic_growth_validation_labels(building_source_record_id, observed_at desc);

comment on table cleaning.organic_growth_pressure_features is
'Experimental exogenous feature matrix for biological-soiling pressure. It must not include direct visual condition, biological staining observations, or validation labels and is not a production lead-ranking rule.';
comment on table cleaning.organic_growth_validation_labels is
'Independent ground-truth labels for evaluating the organic-growth-pressure hypothesis. These labels MUST NOT feed the feature builder.';
comment on column cleaning.organic_growth_pressure_features.direct_observation_used is
'Hard guardrail: constrained false so observed staining/condition cannot silently enter predictor features.';
comment on column cleaning.organic_growth_pressure_features.validation_label_used is
'Hard guardrail: constrained false so evaluation labels cannot silently enter predictor features.';

create or replace function cleaning.refresh_organic_growth_pressure_features()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_rows integer := 0;
  v_ready integer := 0;
  v_collecting integer := 0;
  v_partial integer := 0;
  v_insufficient integer := 0;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('cleaning.refresh_organic_growth_pressure_features',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;

  create temporary table _organic_growth_features on commit drop as
  with targets as (
    select distinct s.canonical_asset_id as building_source_record_id
    from scout.opportunity_search_spine s
    where s.service_slugs @> array['exterior-cleaning']::text[]
      and s.target_class='building'
      and s.canonical_namespace='decisioning.building_candidates'
      and s.canonical_asset_id is not null
  )
  select
    t.building_source_record_id,
    'organic-growth-pressure-backbone-v1'::text as model_version,
    case
      when b.location is null or qpt.sample_key is null then 'insufficient_inputs'
      when coalesce(qpe.qpe_days_30,0) < 30 then 'collecting_history'
      when e.building_source_record_id is null then 'partial_inputs'
      else 'ready_for_coarse_validation'
    end::text as feature_status,

    mat.facade_material as facade_material_input,
    mat.facade_material_status,
    mat.source_slug as facade_material_source_slug,
    mat.material_confidence as facade_material_confidence,
    mr.surface_class,
    mr.receptivity_band as material_receptivity_band,
    mr.receptivity_ordinal as material_receptivity_ordinal,

    e.tree_canopy_pct,
    case when jsonb_typeof(e.humidity_context->'annual_rh_pct')='number'
      then (e.humidity_context->>'annual_rh_pct')::numeric else null end as annual_rh_pct,
    case when jsonb_typeof(e.humidity_context->'warm_season_rh_pct')='number'
      then (e.humidity_context->>'warm_season_rh_pct')::numeric else null end as warm_season_rh_pct,
    e.humidity_context->>'climate_period' as humidity_climate_period,

    qpt.sample_key as qpe_sample_key,
    qpt.distance_m as qpe_sample_distance_m,
    qpe.qpe_first_date,
    qpe.qpe_last_date,
    coalesce(qpe.qpe_days_30,0)::integer as qpe_days_30,
    coalesce(qpe.qpe_days_90,0)::integer as qpe_days_90,
    coalesce(qpe.qpe_days_365,0)::integer as qpe_days_365,
    qpe.precip_total_30d_inches,
    qpe.precip_total_90d_inches,
    qpe.precip_total_365d_inches,
    coalesce(qpe.wet_days_30d,0)::integer as wet_days_30d,
    coalesce(qpe.wet_days_90d,0)::integer as wet_days_90d,
    coalesce(qpe.wet_days_365d,0)::integer as wet_days_365d,

    jsonb_build_object(
      'facade_material',mat.facade_material is not null,
      'material_is_exogenous',mat.source_slug is not null,
      'tree_canopy',e.tree_canopy_pct is not null,
      'humidity_climatology',e.humidity_context is not null,
      'qpe_30d',coalesce(qpe.qpe_days_30,0) >= 30,
      'qpe_90d',coalesce(qpe.qpe_days_90,0) >= 90,
      'qpe_365d',coalesce(qpe.qpe_days_365,0) >= 365,
      'aspect','not_yet_wired',
      'solar_drying','not_yet_wired',
      'direct_observation',false,
      'validation_label',false
    ) as input_completeness,
    jsonb_strip_nulls(jsonb_build_object(
      'semantics','Experimental feature backbone only. Environmental and material inputs estimate conditions favorable to biological soiling; they do not establish visible growth or cleaning need.',
      'leakage_guardrail','Direct visual condition, observed staining, and validation labels are excluded from feature construction. Scout visual-verification material is label-only for this experiment.',
      'material_source_policy',coalesce(mat.source_slug,'unknown'),
      'environment_context_refreshed_at',e.refreshed_at,
      'qpe_wet_day_threshold_inches',0.01,
      'qpe_history_currently_available_days',coalesce(qpe.qpe_days_365,0),
      'not_production_ranked',true
    )) as evidence
  from targets t
  join decisioning.building_candidates b on b.source_record_id=t.building_source_record_id
  left join cleaning.exterior_environment_context e on e.building_source_record_id=t.building_source_record_id
  left join lateral (
    select
      o.facade_material,
      o.facade_material_status,
      src.slug as source_slug,
      least(1::numeric,greatest(0::numeric,coalesce(m.confidence,0::numeric) * coalesce(o.confidence,0::numeric))) as material_confidence
    from decisioning.building_attribute_matches m
    join decisioning.building_attribute_observations o on o.id=m.observation_id
    join ingest.sources src on src.id=o.source_id
    join cleaning.organic_growth_feature_source_policy pol
      on pol.feature_key='facade_material'
     and pol.source_slug=src.slug
     and pol.usage='allowed_input'
    where m.building_source_record_id=t.building_source_record_id
      and o.facade_material is not null
    order by
      case o.facade_material_status when 'documented' then 4 when 'source_reported' then 3 when 'normalized' then 2 else 1 end desc,
      case o.source_feature_kind when 'building' then 2 else 1 end desc,
      m.confidence desc,
      o.confidence desc,
      o.observed_at desc
    limit 1
  ) mat on true
  left join cleaning.organic_growth_material_receptivity mr
    on mr.facade_material=mat.facade_material and mr.active
  left join lateral (
    select p.sample_key,
      extensions.ST_Distance(b.location,p.location)::numeric as distance_m
    from hydrology.precip_sample_points p
    where p.active
      and p.location is not null
      and b.location is not null
    order by extensions.ST_Distance(b.location,p.location)
    limit 1
  ) qpt on true
  left join lateral (
    select
      min(d.snapshot_date) as qpe_first_date,
      max(d.snapshot_date) as qpe_last_date,
      count(*) filter(where d.snapshot_date >= current_date-29)::integer as qpe_days_30,
      count(*) filter(where d.snapshot_date >= current_date-89)::integer as qpe_days_90,
      count(*) filter(where d.snapshot_date >= current_date-364)::integer as qpe_days_365,
      sum(d.precipitation_24h_inches) filter(where d.snapshot_date >= current_date-29) as precip_total_30d_inches,
      sum(d.precipitation_24h_inches) filter(where d.snapshot_date >= current_date-89) as precip_total_90d_inches,
      sum(d.precipitation_24h_inches) filter(where d.snapshot_date >= current_date-364) as precip_total_365d_inches,
      count(*) filter(where d.snapshot_date >= current_date-29 and coalesce(d.precipitation_24h_inches,0) >= 0.01)::integer as wet_days_30d,
      count(*) filter(where d.snapshot_date >= current_date-89 and coalesce(d.precipitation_24h_inches,0) >= 0.01)::integer as wet_days_90d,
      count(*) filter(where d.snapshot_date >= current_date-364 and coalesce(d.precipitation_24h_inches,0) >= 0.01)::integer as wet_days_365d
    from hydrology.precip_daily_snapshots d
    where d.sample_key=qpt.sample_key
      and d.snapshot_date >= current_date-364
  ) qpe on true;

  insert into cleaning.organic_growth_pressure_features(
    building_source_record_id,model_version,feature_status,
    facade_material_input,facade_material_status,facade_material_source_slug,facade_material_confidence,
    surface_class,material_receptivity_band,material_receptivity_ordinal,
    tree_canopy_pct,annual_rh_pct,warm_season_rh_pct,humidity_climate_period,
    qpe_sample_key,qpe_sample_distance_m,qpe_first_date,qpe_last_date,qpe_days_30,qpe_days_90,qpe_days_365,
    precip_total_30d_inches,precip_total_90d_inches,precip_total_365d_inches,
    wet_days_30d,wet_days_90d,wet_days_365d,
    direct_observation_used,validation_label_used,input_completeness,evidence,refreshed_at
  )
  select
    building_source_record_id,model_version,feature_status,
    facade_material_input,facade_material_status,facade_material_source_slug,facade_material_confidence,
    surface_class,material_receptivity_band,material_receptivity_ordinal,
    tree_canopy_pct,annual_rh_pct,warm_season_rh_pct,humidity_climate_period,
    qpe_sample_key,qpe_sample_distance_m,qpe_first_date,qpe_last_date,qpe_days_30,qpe_days_90,qpe_days_365,
    precip_total_30d_inches,precip_total_90d_inches,precip_total_365d_inches,
    wet_days_30d,wet_days_90d,wet_days_365d,
    false,false,input_completeness,evidence,v_now
  from _organic_growth_features
  on conflict(building_source_record_id) do update set
    model_version=excluded.model_version,
    feature_status=excluded.feature_status,
    facade_material_input=excluded.facade_material_input,
    facade_material_status=excluded.facade_material_status,
    facade_material_source_slug=excluded.facade_material_source_slug,
    facade_material_confidence=excluded.facade_material_confidence,
    surface_class=excluded.surface_class,
    material_receptivity_band=excluded.material_receptivity_band,
    material_receptivity_ordinal=excluded.material_receptivity_ordinal,
    tree_canopy_pct=excluded.tree_canopy_pct,
    annual_rh_pct=excluded.annual_rh_pct,
    warm_season_rh_pct=excluded.warm_season_rh_pct,
    humidity_climate_period=excluded.humidity_climate_period,
    qpe_sample_key=excluded.qpe_sample_key,
    qpe_sample_distance_m=excluded.qpe_sample_distance_m,
    qpe_first_date=excluded.qpe_first_date,
    qpe_last_date=excluded.qpe_last_date,
    qpe_days_30=excluded.qpe_days_30,
    qpe_days_90=excluded.qpe_days_90,
    qpe_days_365=excluded.qpe_days_365,
    precip_total_30d_inches=excluded.precip_total_30d_inches,
    precip_total_90d_inches=excluded.precip_total_90d_inches,
    precip_total_365d_inches=excluded.precip_total_365d_inches,
    wet_days_30d=excluded.wet_days_30d,
    wet_days_90d=excluded.wet_days_90d,
    wet_days_365d=excluded.wet_days_365d,
    direct_observation_used=false,
    validation_label_used=false,
    input_completeness=excluded.input_completeness,
    evidence=excluded.evidence,
    refreshed_at=excluded.refreshed_at;

  update cleaning.organic_growth_pressure_features f
  set feature_status='retired', refreshed_at=v_now
  where f.feature_status <> 'retired'
    and not exists(select 1 from _organic_growth_features x where x.building_source_record_id=f.building_source_record_id);

  select count(*),
         count(*) filter(where feature_status='ready_for_coarse_validation'),
         count(*) filter(where feature_status='collecting_history'),
         count(*) filter(where feature_status='partial_inputs'),
         count(*) filter(where feature_status='insufficient_inputs')
    into v_rows,v_ready,v_collecting,v_partial,v_insufficient
  from _organic_growth_features;

  return jsonb_build_object(
    'model_version','organic-growth-pressure-backbone-v1',
    'refreshed_at',v_now,
    'rows',v_rows,
    'ready_for_coarse_validation',v_ready,
    'collecting_history',v_collecting,
    'partial_inputs',v_partial,
    'insufficient_inputs',v_insufficient,
    'production_ranking_enabled',false,
    'direct_observation_used',false,
    'validation_labels_used',false
  );
end;
$$;

revoke all on function cleaning.refresh_organic_growth_pressure_features() from public,anon,authenticated;
grant execute on function cleaning.refresh_organic_growth_pressure_features() to service_role;

create or replace view cleaning.v_organic_growth_pressure_experiment_matrix
with (security_invoker=true)
as
select
  f.building_source_record_id,
  b.property_address,
  b.property_city,
  b.state_code,
  b.county_name,
  b.footprint_sqft,
  f.model_version,
  f.feature_status,
  f.facade_material_input,
  f.facade_material_status,
  f.facade_material_source_slug,
  f.facade_material_confidence,
  f.surface_class,
  f.material_receptivity_band,
  f.material_receptivity_ordinal,
  f.tree_canopy_pct,
  f.annual_rh_pct,
  f.warm_season_rh_pct,
  f.humidity_climate_period,
  f.qpe_sample_key,
  f.qpe_sample_distance_m,
  f.qpe_first_date,
  f.qpe_last_date,
  f.qpe_days_30,
  f.qpe_days_90,
  f.qpe_days_365,
  f.precip_total_30d_inches,
  f.precip_total_90d_inches,
  f.precip_total_365d_inches,
  f.wet_days_30d,
  f.wet_days_90d,
  f.wet_days_365d,
  f.aspect_signal,
  f.aspect_confidence,
  f.solar_drying_signal,
  f.solar_drying_confidence,
  f.input_completeness,
  f.evidence,
  f.refreshed_at
from cleaning.organic_growth_pressure_features f
join decisioning.building_candidates b on b.source_record_id=f.building_source_record_id
where f.feature_status <> 'retired';

revoke all on cleaning.v_organic_growth_pressure_experiment_matrix from public,anon,authenticated;
grant select on cleaning.v_organic_growth_pressure_experiment_matrix to service_role;
