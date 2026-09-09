-- Scout manual-access displacement + agricultural acute-need context v1
--
-- Two bounded, explainable ranking hypotheses:
-- 1) estimate conventional visual-access burden from documented structure geometry,
--    scale, and normalized access context without claiming a specific access method/cost;
-- 2) prioritize agricultural leads with current crop/problem evidence over generic
--    seasonal eligibility while preserving Extension/moisture epistemic limits.
--
-- These are internal ranking contexts. Numeric rank hints are not public methodology.

insert into research.operator_field_hypotheses(
  hypothesis_slug, claim, evidence_basis, confidence_status, testability_status,
  applicable_services, source_urls, attributes
)
values
(
  'manual_access_displacement',
  'Where visual inspection or exterior work would otherwise involve difficult work-at-height or large/complex structural access, drones can displace part of the conventional access burden; Scout can estimate that opportunity from documented height, geometry, scale, and site-access context without claiming a specific lift, scaffold, rope-access, climber, lane-closure, or labor cost.',
  'FHWA guidance says UAS can reduce bridge access-equipment use and time adjacent to live traffic but cannot replace tactile inspection requirements; professional operators also report value where exterior structure access would otherwise require rope or crane access.',
  'corroborated',
  'proxy_testable',
  array['exterior-cleaning','building-envelope-cleaning','building-envelope-inspection','roof-inspection','bridge-inspection','water-tower-inspection','telecom-tower-inspection'],
  jsonb_build_array(
    'https://www.fhwa.dot.gov/bridge/nbis2022/qanda/08.cfm',
    'https://www.fhwa.dot.gov/innovation/everydaycounts/edcnews/20190808.cfm',
    'https://commercialdronepilots.com/threads/advice-for-getting-into-the-industry.88/latest'
  ),
  jsonb_build_object(
    'origin','professional_operator_research_plus_federal_guidance',
    'first_test','documented structure height/geometry/scale plus normalized site-access context',
    'interpretation','Estimate conventional-access burden and potential visual-access displacement only. Do not infer actual contractor access method, price, personnel count, regulatory inspection completeness, or physical-contact replacement.',
    'formula_version','manual_access_displacement_v1',
    'bridge_guardrail','Bridge UAS use is supplemental; tactile/sounding requirements remain when applicable.'
  )
),
(
  'agricultural_acute_need_filter',
  'Agricultural drone prospects with a current field-linked or crop-matched problem context such as pest/disease relevance or unusual moisture should outrank generic seasonal farm prospects, while imagery remains a scouting/diagnostic aid rather than proof of diagnosis or treatment need.',
  'Extension guidance supports using drones to identify in-season production issues, moisture stress, pest damage and disease pressure while emphasizing ground-truthing before diagnosis or treatment. Scout currently distinguishes regional crop relevance from truly local/field evidence and does not treat a statewide Extension alert as a field observation.',
  'corroborated',
  'proxy_testable',
  array['agricultural-crop-scouting','agricultural-imaging','agricultural-multispectral-imaging','agricultural-aerial-application','agricultural-drainage-mapping'],
  jsonb_build_array(
    'https://www.udel.edu/academics/colleges/canr/cooperative-extension/fact-sheets/drones-crop-scouting/',
    'https://www.udel.edu/content/dam/udelImages/canr/pdfs/extension/factsheets/Types-of-Drones-for-Field-Crop-Production.pdf',
    'https://extension.k-state.edu/news-and-publications/news/stories/2026/06/agriculture-drones-crop-scouting.html',
    'https://www.reddit.com/r/drones/comments/1rtlglg/is_there_real_demand_for_dronebased_crop_health/'
  ),
  jsonb_build_object(
    'origin','extension_guidance_plus_operator_community_research',
    'first_test','current seasonal crop/service window plus crop-matched field extension signals and field moisture context where available',
    'interpretation','Acute context prioritizes scouting/diagnostic relevance. Statewide crop alerts are weaker than local/field evidence and do not prove field occurrence, diagnosis, treatment necessity, label fit, application legality, operator identity, or customer intent.',
    'formula_version','farm_acute_need_v1'
  )
)
on conflict (hypothesis_slug) do update
set claim=excluded.claim,
    evidence_basis=excluded.evidence_basis,
    confidence_status=excluded.confidence_status,
    testability_status=excluded.testability_status,
    applicable_services=excluded.applicable_services,
    source_urls=excluded.source_urls,
    attributes=research.operator_field_hypotheses.attributes || excluded.attributes,
    updated_at=now();

create table if not exists scout.manual_access_displacement_stats_v1(
  candidate_key text primary key,
  source_kind text not null,
  structural_burden_points integer not null default 0,
  access_friction_points integer not null default 0,
  rank_adjustment_hint smallint not null default 0 check(rank_adjustment_hint between 0 and 2),
  burden_signal text not null,
  substitution_scope text not null,
  context jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now()
);
create index if not exists manual_access_displacement_stats_v1_rank_idx
  on scout.manual_access_displacement_stats_v1(rank_adjustment_hint desc,candidate_key);

create table if not exists scout.farm_acute_need_stats_v1(
  candidate_key text primary key,
  service_slug text not null,
  rank_adjustment_hint smallint not null default 0 check(rank_adjustment_hint between 0 and 2),
  acute_signal text not null,
  extension_signal_count integer not null default 0,
  moisture_field_count integer not null default 0,
  context jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now()
);
create index if not exists farm_acute_need_stats_v1_rank_idx
  on scout.farm_acute_need_stats_v1(rank_adjustment_hint desc,candidate_key);

revoke all on scout.manual_access_displacement_stats_v1 from public,anon,authenticated;
revoke all on scout.farm_acute_need_stats_v1 from public,anon,authenticated;
grant select on scout.manual_access_displacement_stats_v1 to service_role;
grant select on scout.farm_acute_need_stats_v1 to service_role;

create or replace view scout.v_manual_access_displacement_context_v1 as
with access as (
  select candidate_key,
         max(coalesce(barrier_count,0)) as barrier_count,
         max(coalesce(gate_count,0)) as gate_count,
         max(nearest_staging_m) as nearest_staging_m,
         bool_or(site_enrichment_status in ('mapped','scanned_no_mapped_features')) as access_resolved
  from scout.opportunity_service_access
  group by candidate_key
), scale as (
  select candidate_key,
         max(value_numeric) filter(where metric_key='structure_height_agl' and unit='m') as telecom_height_m,
         max(value_numeric) filter(where metric_key='tank_capacity' and unit='gallons') as tank_capacity_gallons
  from scout.opportunity_scale_metrics
  group by candidate_key
), base as (
  select s.candidate_key,s.source_kind,s.service_slugs,s.canonical_asset_id,
         a.barrier_count,a.gate_count,a.nearest_staging_m,a.access_resolved,
         bc.height_m,bc.footprint_sqft,
         br.structure_length_m,br.deck_area_m2,
         wg.context as water_geometry,
         sc.telecom_height_m,sc.tank_capacity_gallons
  from scout.opportunity_search_spine s
  left join access a on a.candidate_key=s.candidate_key
  left join scale sc on sc.candidate_key=s.candidate_key
  left join decisioning.v_building_site_access_context bc on bc.source_record_id=s.canonical_asset_id
  left join transportation.bridges br on br.id=s.canonical_asset_id
  left join scout.v_opportunity_water_tank_geometry_context wg on wg.candidate_key=s.candidate_key
  where s.pushable and not s.global_suppressed
    and s.source_kind in ('exterior_cleaning','event_detailing','storm_roof','bridge','water_tank_maintenance','telecom_change')
), scored as (
  select b.*,
    case
      when b.source_kind in ('exterior_cleaning','event_detailing','storm_roof') then
        (case when b.height_m>=45 then 3 when b.height_m>=25 then 2 when b.height_m>=12 then 1 else 0 end)
        +(case when b.footprint_sqft>=100000 then 2 when b.footprint_sqft>=25000 then 1 else 0 end)
      when b.source_kind='telecom_change' then
        case when coalesce(b.telecom_height_m,0)>=90 then 4 when coalesce(b.telecom_height_m,0)>=45 then 3 when coalesce(b.telecom_height_m,0)>=20 then 2 else 0 end
      when b.source_kind='bridge' then
        (case when b.structure_length_m>=100 then 3 when b.structure_length_m>=50 then 2 when b.structure_length_m>=25 then 1 else 0 end)
        +(case when b.deck_area_m2>=1500 then 2 when b.deck_area_m2>=500 then 1 else 0 end)
      when b.source_kind='water_tank_maintenance' then
        (case when coalesce(b.water_geometry->>'morphology_class','') in ('pedesphere','composite_elevated','multi_column_cross_braced','elevated_unknown') then 3
              when coalesce(b.water_geometry->>'morphology_class','')='standpipe' then 1 else 0 end)
        +(case when coalesce(b.tank_capacity_gallons,0)>=1000000 then 1 else 0 end)
      else 0
    end as structural_burden_points,
    case when coalesce(b.access_resolved,false)
              and (coalesce(b.barrier_count,0)+coalesce(b.gate_count,0)>=2 or coalesce(b.nearest_staging_m,0)>150)
         then 1 else 0 end as access_friction_points
  from base b
), final as (
  select x.*,
    case
      when x.source_kind='water_tank_maintenance' and coalesce(x.water_geometry->>'morphology_class','') in ('pedesphere','composite_elevated') then 2
      when x.source_kind='water_tank_maintenance' and coalesce(x.water_geometry->>'morphology_class','') in ('multi_column_cross_braced','elevated_unknown') then 1
      when x.source_kind='water_tank_maintenance' and coalesce(x.water_geometry->>'morphology_class','')='standpipe' and coalesce(x.tank_capacity_gallons,0)>=1000000 then 1
      when x.source_kind='bridge' and x.structural_burden_points>=2 then 1
      when x.source_kind='storm_roof' and x.structural_burden_points>=2 then 1
      when x.source_kind='telecom_change' and coalesce(x.telecom_height_m,0)>=60 then 2
      when x.source_kind='telecom_change' and coalesce(x.telecom_height_m,0)>=20 then 1
      when x.source_kind in ('exterior_cleaning','event_detailing') and x.structural_burden_points>=4 then 2
      when x.source_kind in ('exterior_cleaning','event_detailing') and x.structural_burden_points>=3 and coalesce(x.access_resolved,false) and x.access_friction_points=1 then 2
      when x.source_kind in ('exterior_cleaning','event_detailing') and x.structural_burden_points>=2 then 1
      else 0
    end::smallint as rank_adjustment_hint
  from scored x
)
select candidate_key,source_kind,structural_burden_points,access_friction_points,rank_adjustment_hint,
  case when structural_burden_points>=4 then 'very_high_conventional_access_burden'
       when structural_burden_points>=2 then 'high_conventional_access_burden'
       when structural_burden_points=1 then 'some_conventional_access_burden'
       else 'limited_documented_access_burden' end as burden_signal,
  case when source_kind='bridge' then 'supplemental_visual_access_only'
       when source_kind='storm_roof' then 'visual_condition_documentation_only'
       when source_kind='water_tank_maintenance' then 'elevated_tank_visual_access_proxy'
       when source_kind='telecom_change' then 'tower_climb_visual_access_proxy'
       else 'building_height_access_proxy' end as substitution_scope,
  jsonb_strip_nulls(jsonb_build_object(
    'evidence_state','documented_geometry_scale_access_proxy',
    'height_m',height_m,'footprint_sqft',footprint_sqft,
    'bridge_length_m',structure_length_m,'bridge_deck_area_m2',deck_area_m2,
    'telecom_height_m',telecom_height_m,
    'water_morphology',water_geometry->>'morphology_class',
    'water_support_geometry',water_geometry->>'support_geometry',
    'tank_capacity_gallons',tank_capacity_gallons,
    'access_resolved',access_resolved,'barrier_count',barrier_count,'gate_count',gate_count,
    'nearest_staging_m',nearest_staging_m,
    'structural_burden_points',structural_burden_points,
    'access_friction_points',access_friction_points,
    'interpretation','Higher values mean Scout has more evidence that conventional visual access could be unpleasant, equipment-intensive, or disruptive. This is not a contractor access plan or price estimate.',
    'guardrail',case when source_kind='bridge'
      then 'FHWA permits UAS to supplement portions of bridge inspection and potentially reduce access-equipment/live-traffic exposure, but tactile/sounding and other physical examination requirements still apply when required.'
      else 'Scout does not know which lift, scaffold, ladder, rope system, climber, lane closure, or crew would actually be used. The signal estimates visual-access displacement opportunity only.' end,
    'formula_version','manual_access_displacement_v1'
  )) as context
from final;

create or replace function scout.refresh_manual_access_displacement_stats_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_rows integer:=0; v_now timestamptz:=clock_timestamp();
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_manual_access_displacement_stats_v1',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;
  truncate scout.manual_access_displacement_stats_v1;
  insert into scout.manual_access_displacement_stats_v1(candidate_key,source_kind,structural_burden_points,access_friction_points,rank_adjustment_hint,burden_signal,substitution_scope,context,refreshed_at)
  select candidate_key,source_kind,structural_burden_points,access_friction_points,rank_adjustment_hint,burden_signal,substitution_scope,context,v_now
  from scout.v_manual_access_displacement_context_v1;
  get diagnostics v_rows=row_count;
  return jsonb_build_object('rows',v_rows,'refreshed_at',v_now,'formula_version','manual_access_displacement_v1','mode','full_refresh');
end;
$$;

create or replace function scout.refresh_manual_access_displacement_source_v1(p_source_kind text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_deleted integer:=0; v_inserted integer:=0; v_now timestamptz:=clock_timestamp();
begin
  if p_source_kind is null or p_source_kind not in ('exterior_cleaning','event_detailing','storm_roof','bridge','water_tank_maintenance','telecom_change') then
    raise exception 'unsupported manual-access source kind: %',p_source_kind using errcode='22023';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_manual_access_displacement_source_v1:'||p_source_kind,0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running','source_kind',p_source_kind);
  end if;
  delete from scout.manual_access_displacement_stats_v1 where source_kind=p_source_kind;
  get diagnostics v_deleted=row_count;
  insert into scout.manual_access_displacement_stats_v1(candidate_key,source_kind,structural_burden_points,access_friction_points,rank_adjustment_hint,burden_signal,substitution_scope,context,refreshed_at)
  select candidate_key,source_kind,structural_burden_points,access_friction_points,rank_adjustment_hint,burden_signal,substitution_scope,context,v_now
  from scout.v_manual_access_displacement_context_v1 where source_kind=p_source_kind;
  get diagnostics v_inserted=row_count;
  return jsonb_build_object('source_kind',p_source_kind,'deleted_rows',v_deleted,'inserted_rows',v_inserted,'refreshed_at',v_now,'formula_version','manual_access_displacement_v1','mode','source_scoped_refresh');
end;
$$;

create or replace function scout.refresh_farm_acute_need_stats_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_rows integer:=0;
  v_now timestamptz:=clock_timestamp();
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_farm_acute_need_stats_v1',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;
  truncate scout.farm_acute_need_stats_v1;
  with moisture_distribution as (
    select percentile_cont(.25) within group(order by rootzone_vwc)::numeric as p25_vwc,
           percentile_cont(.75) within group(order by rootzone_vwc)::numeric as p75_vwc
    from hydrology.field_soil_moisture_context
    where expires_at is null or expires_at>=now()
  ), farm_candidates as (
    select s.candidate_key,s.source_id as candidate_id,s.service_slugs[1] as service_slug,
           s.state_code,s.location,s.signal_strength,s.details,
           array(select jsonb_array_elements_text(coalesce(s.details->'crops','[]'::jsonb)))::text[] as crops
    from scout.opportunity_search_spine s
    where s.source_kind='farm_seasonal' and s.pushable and not s.global_suppressed
      and (s.expires_at is null or s.expires_at>=now())
  ), farm_fields as (
    select fc.candidate_key,fc.candidate_id,fc.service_slug,fc.crops,r.field_id
    from farm_candidates fc
    join agriculture.v_resolved_field_owner_links r on r.candidate_id=fc.candidate_id
  ), extension_agg as (
    select ff.candidate_key,
           count(*)::integer as extension_signal_count,
           count(distinct e.field_id)::integer as extension_field_count,
           max(e.confidence) as max_extension_confidence,
           bool_or(e.signal_kind='pest_activity') as pest_activity_present,
           bool_or(e.signal_kind='disease_observation') as disease_observation_present,
           bool_or(e.treatment_authority) as treatment_authority_present,
           bool_or(coalesce(e.match_scope,'') not in ('state_crop_relevance','regional_crop_relevance')) as local_extension_match_present,
           max(e.published_at) as latest_extension_published_at,
           array_agg(distinct e.match_scope order by e.match_scope) filter(where e.match_scope is not null) as extension_match_scopes,
           array_agg(distinct e.signal_kind order by e.signal_kind) filter(where e.signal_kind is not null) as extension_signal_kinds,
           array_agg(distinct e.title order by e.title) filter(where e.title is not null) as extension_titles,
           array_agg(distinct e.source_url order by e.source_url) filter(where e.source_url is not null) as extension_source_urls
    from farm_fields ff
    join agriculture.v_candidate_field_extension_signals e on e.field_id=ff.field_id
      and (e.expires_at is null or e.expires_at>=now())
      and exists(select 1 from unnest(ff.crops) c where lower(c)=lower(e.crop_name))
    group by ff.candidate_key
  ), latest_moisture as (
    select distinct on (field_id) field_id,rootzone_vwc,observed_at,expires_at,model_version
    from hydrology.field_soil_moisture_context
    where expires_at is null or expires_at>=now()
    order by field_id,observed_at desc
  ), moisture_agg as (
    select ff.candidate_key,
           count(distinct m.field_id)::integer as moisture_field_count,
           min(m.rootzone_vwc) as min_rootzone_vwc,
           max(m.rootzone_vwc) as max_rootzone_vwc,
           avg(m.rootzone_vwc) as avg_rootzone_vwc,
           max(m.observed_at) as latest_moisture_observed_at
    from farm_fields ff join latest_moisture m on m.field_id=ff.field_id
    group by ff.candidate_key
  ), field_counts as (
    select candidate_key,count(distinct field_id)::integer as owner_linked_field_count
    from farm_fields group by candidate_key
  ), drought as (
    select fc.candidate_key,max(d.severity) as drought_severity,max(d.drought_class) as drought_class,max(d.valid_date) as drought_valid_date
    from farm_candidates fc
    left join hydrology.v_drought_current d on fc.location is not null and extensions.st_intersects(d.geometry,fc.location::extensions.geometry)
    group by fc.candidate_key
  ), assembled as (
    select fc.*,coalesce(fcnt.owner_linked_field_count,0) as owner_linked_field_count,
           coalesce(ea.extension_signal_count,0) as extension_signal_count,
           coalesce(ea.extension_field_count,0) as extension_field_count,
           ea.max_extension_confidence,coalesce(ea.pest_activity_present,false) as pest_activity_present,
           coalesce(ea.disease_observation_present,false) as disease_observation_present,
           coalesce(ea.treatment_authority_present,false) as treatment_authority_present,
           coalesce(ea.local_extension_match_present,false) as local_extension_match_present,
           ea.latest_extension_published_at,ea.extension_match_scopes,ea.extension_signal_kinds,ea.extension_titles,ea.extension_source_urls,
           coalesce(ma.moisture_field_count,0) as moisture_field_count,
           ma.min_rootzone_vwc,ma.max_rootzone_vwc,ma.avg_rootzone_vwc,ma.latest_moisture_observed_at,
           md.p25_vwc,md.p75_vwc,d.drought_severity,d.drought_class,d.drought_valid_date,
           sf.week_ending as state_fieldwork_week_ending,
           (coalesce(sf.topsoil_very_short_pct,0)+coalesce(sf.topsoil_short_pct,0))::integer as state_topsoil_short_pct
    from farm_candidates fc cross join moisture_distribution md
    left join field_counts fcnt on fcnt.candidate_key=fc.candidate_key
    left join extension_agg ea on ea.candidate_key=fc.candidate_key
    left join moisture_agg ma on ma.candidate_key=fc.candidate_key
    left join drought d on d.candidate_key=fc.candidate_key
    left join agriculture.v_state_fieldwork_current sf on sf.state_code=fc.state_code
  ), scored as (
    select a.*,
      (moisture_field_count>0 and (min_rootzone_vwc<=p25_vwc or max_rootzone_vwc>=p75_vwc)) as moisture_anomaly_present,
      case
        when service_slug in ('agricultural-crop-scouting','agricultural-imaging','agricultural-multispectral-imaging') and extension_signal_count>0 and local_extension_match_present then 2
        when service_slug in ('agricultural-crop-scouting','agricultural-imaging','agricultural-multispectral-imaging') and extension_signal_count>0 and moisture_field_count>0 and (min_rootzone_vwc<=p25_vwc or max_rootzone_vwc>=p75_vwc) then 2
        when service_slug in ('agricultural-crop-scouting','agricultural-imaging','agricultural-multispectral-imaging') and extension_signal_count>0 then 1
        when service_slug='agricultural-aerial-application' and extension_signal_count>0 then 1
        when service_slug='agricultural-drainage-mapping' and moisture_field_count>0 and max_rootzone_vwc>=p75_vwc then 1
        when service_slug in ('agricultural-crop-scouting','agricultural-imaging','agricultural-multispectral-imaging') and moisture_field_count>0 and (min_rootzone_vwc<=p25_vwc or max_rootzone_vwc>=p75_vwc) then 1
        when service_slug in ('agricultural-crop-scouting','agricultural-imaging','agricultural-multispectral-imaging') and coalesce(drought_severity,0)>=1 then 1
        else 0
      end::smallint as rank_adjustment_hint
    from assembled a
  )
  insert into scout.farm_acute_need_stats_v1(candidate_key,service_slug,rank_adjustment_hint,acute_signal,extension_signal_count,moisture_field_count,context,refreshed_at)
  select candidate_key,service_slug,rank_adjustment_hint,
    case
      when extension_signal_count>0 and service_slug='agricultural-aerial-application' then 'crop_specific_extension_application_relevance'
      when extension_signal_count>0 and local_extension_match_present then 'crop_specific_local_pest_or_disease_relevance'
      when extension_signal_count>0 and moisture_anomaly_present then 'crop_specific_extension_plus_moisture_context'
      when extension_signal_count>0 then 'crop_specific_regional_pest_or_disease_relevance'
      when service_slug='agricultural-drainage-mapping' and moisture_field_count>0 and max_rootzone_vwc>=p75_vwc then 'field_wetness_context'
      when moisture_anomaly_present then 'field_moisture_anomaly_context'
      when coalesce(drought_severity,0)>=1 then 'drought_stress_context'
      else 'seasonal_window_only'
    end,
    extension_signal_count,moisture_field_count,
    jsonb_strip_nulls(jsonb_build_object(
      'evidence_state',case when extension_signal_count>0 and local_extension_match_present then 'local_crop_matched_extension_context'
                            when extension_signal_count>0 then 'regional_crop_matched_extension_context'
                            when moisture_field_count>0 then 'field_linked_moisture_context'
                            when coalesce(drought_severity,0)>=1 then 'geographic_drought_context'
                            else 'seasonal_crop_timing_only' end,
      'service_slug',service_slug,'crops',to_jsonb(crops),'seasonal_signal_strength',signal_strength,
      'opportunity_windows',details->'opportunity_windows','owner_linked_field_count',owner_linked_field_count,
      'extension_signal_count',extension_signal_count,'extension_field_count',extension_field_count,
      'extension_match_scopes',to_jsonb(extension_match_scopes),'extension_signal_kinds',to_jsonb(extension_signal_kinds),
      'extension_titles',to_jsonb(extension_titles),'extension_source_urls',to_jsonb(extension_source_urls),
      'pest_activity_present',pest_activity_present,'disease_observation_present',disease_observation_present,
      'max_extension_confidence',max_extension_confidence,'latest_extension_published_at',latest_extension_published_at,
      'local_extension_match_present',local_extension_match_present,'treatment_authority_present',treatment_authority_present,
      'moisture_field_count',moisture_field_count,'moisture_anomaly_present',moisture_anomaly_present,
      'min_rootzone_vwc',min_rootzone_vwc,'max_rootzone_vwc',max_rootzone_vwc,'avg_rootzone_vwc',avg_rootzone_vwc,
      'latest_moisture_observed_at',latest_moisture_observed_at,
      'current_moisture_cohort_p25_vwc',p25_vwc,'current_moisture_cohort_p75_vwc',p75_vwc,
      'drought_class',drought_class,'drought_severity',drought_severity,'drought_valid_date',drought_valid_date,
      'state_fieldwork_week_ending',state_fieldwork_week_ending,'state_topsoil_short_pct',state_topsoil_short_pct,
      'identity_guardrail',details->>'identity_guardrail',
      'extension_guardrail','Extension relevance is preserved at its actual geographic scope. A statewide or regional crop alert does not prove pest or disease presence in this field.',
      'moisture_guardrail','Root-zone VWC is contextual. Current-cohort percentiles flag unusual observations but do not diagnose crop water stress without soil, crop, and agronomic validation.',
      'treatment_guardrail','Extension pest/disease relevance and imagery may justify scouting. They do not establish diagnosis, treatment necessity, label fit, chemical choice, legal application authority, or customer intent.',
      'operator_guardrail','Owner-linked fields support prospecting context; land ownership does not by itself prove the current crop operator or customer.',
      'formula_version','farm_acute_need_v1'
    )),v_now
  from scored;
  get diagnostics v_rows=row_count;
  return jsonb_build_object('rows',v_rows,'refreshed_at',v_now,'formula_version','farm_acute_need_v1');
end;
$$;

revoke all on function scout.refresh_manual_access_displacement_stats_v1() from public,anon,authenticated;
revoke all on function scout.refresh_manual_access_displacement_source_v1(text) from public,anon,authenticated;
revoke all on function scout.refresh_farm_acute_need_stats_v1() from public,anon,authenticated;
grant execute on function scout.refresh_manual_access_displacement_stats_v1() to service_role;
grant execute on function scout.refresh_manual_access_displacement_source_v1(text) to service_role;
grant execute on function scout.refresh_farm_acute_need_stats_v1() to service_role;

select scout.refresh_manual_access_displacement_stats_v1();
select scout.refresh_farm_acute_need_stats_v1();
