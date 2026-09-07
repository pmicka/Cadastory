-- Scout by Cadastory
-- Structured facade/glazing visual verification pipeline.
-- Retains structured observations + provenance only; no image bytes/screenshots.

insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,authority_level,status,
  homepage_url,license_notes,commercial_use_status,notes,updated_at
) values (
  'scout-facade-visual-verification',
  'Scout structured facade visual verification',
  'Curated visual observation with cited source provenance',
  'building_attribute_context',
  'operator-selected canonical buildings',
  'structured_visual_verification_no_media_retention',
  'on_demand',
  'curated_observation',
  'active_reference',
  null,
  'Retain structured findings and source locator only; do not retain image bytes or screenshots after verification.',
  'review_required',
  'Used for facade material and glazing observations verified from public/first-party/operator visual evidence. Visual verification does not by itself establish cleaning need, substrate treatment compatibility, or customer demand.',
  now()
)
on conflict(slug) do update set
  name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,status=excluded.status,
  license_notes=excluded.license_notes,commercial_use_status=excluded.commercial_use_status,
  notes=excluded.notes,updated_at=now();

create or replace view decisioning.v_facade_visual_verification_queue_v1 as
with base as (
  select s.*,
    row_number() over(
      partition by s.canonical_asset_id
      order by (s.source_kind='exterior_cleaning') desc,s.time_sensitive desc,
               s.premium_priority_rank desc,s.confidence desc nulls last,s.observed_at desc nulls last
    ) rn
  from scout.opportunity_search_spine s
  where s.service_slugs @> array['exterior-cleaning']::text[]
    and s.target_class='building'
    and s.canonical_namespace='decisioning.building_candidates'
    and s.canonical_asset_id is not null
), cls as (
  select c.building_source_record_id,
    case when bool_or(st.slug='pure-water-window-cleaning' and c.classification_state='supported') then 'supported'
         when bool_or(st.slug='pure-water-window-cleaning' and c.classification_state='investigate') then 'investigate'
         else 'insufficient_evidence' end pure_water_state,
    case when bool_or(st.slug='masonry-restoration-cleaning' and c.classification_state='supported') then 'supported'
         when bool_or(st.slug='masonry-restoration-cleaning' and c.classification_state='investigate') then 'investigate'
         else 'insufficient_evidence' end masonry_state,
    max(c.classification_confidence) filter(where st.slug='pure-water-window-cleaning') pure_water_confidence,
    max(c.classification_confidence) filter(where st.slug='masonry-restoration-cleaning') masonry_confidence,
    max(nullif(c.evidence->>'resolved_facade_material','')) filter(where st.slug='masonry-restoration-cleaning') resolved_facade_material,
    max(nullif(c.evidence->>'resolved_raw_facade_material','')) filter(where st.slug='masonry-restoration-cleaning') resolved_raw_facade_material,
    max(nullif(c.evidence->>'resolved_facade_material_status','')) filter(where st.slug='masonry-restoration-cleaning') resolved_facade_material_status,
    max(nullif(c.evidence->>'resolved_facade_material_source_slug','')) filter(where st.slug='masonry-restoration-cleaning') resolved_facade_material_source_slug,
    max(nullif(c.evidence->>'resolved_glazing_signal','')) filter(where st.slug='pure-water-window-cleaning') glazing_signal,
    max(nullif(c.evidence->>'resolved_glazing_confidence','')::numeric) filter(where st.slug='pure-water-window-cleaning') glazing_confidence,
    bool_or(coalesce((c.evidence->>'individually_listed_building')::boolean,false)) filter(where st.slug='masonry-restoration-cleaning') individually_listed_building,
    bool_or(coalesce((c.evidence->>'within_listed_district')::boolean,false)) filter(where st.slug='masonry-restoration-cleaning') within_listed_district,
    bool_or(coalesce((c.evidence->>'national_historic_landmark_context')::boolean,false)) filter(where st.slug='masonry-restoration-cleaning') national_historic_landmark_context,
    max(nullif(c.evidence->>'historic_match_confidence','')::numeric) filter(where st.slug='masonry-restoration-cleaning') historic_match_confidence
  from scout.opportunity_service_classifications c
  join commerce.service_types st on st.id=c.service_type_id
  group by c.building_source_record_id
), enriched as (
  select b.candidate_key,b.canonical_asset_id building_source_record_id,b.display_name,b.location,b.state_code,b.county_name,
         b.time_sensitive,b.confidence opportunity_confidence,b.commercial_scale_status,b.commercial_scale_summary,
         b.premium_priority_rank,b.why_now,
         c.resolved_facade_material,c.resolved_raw_facade_material,
         coalesce(c.resolved_facade_material_status,'unknown') resolved_facade_material_status,
         c.resolved_facade_material_source_slug,c.glazing_signal,c.glazing_confidence,
         coalesce(c.pure_water_state,'insufficient_evidence') pure_water_state,
         coalesce(c.masonry_state,'insufficient_evidence') masonry_state,
         c.pure_water_confidence,c.masonry_confidence,
         coalesce(c.individually_listed_building,false) individually_listed_building,
         coalesce(c.within_listed_district,false) within_listed_district,
         coalesce(c.national_historic_landmark_context,false) national_historic_landmark_context,
         c.historic_match_confidence,
         null::text[] historic_resource_names,
         false::boolean premium_confirmed_glazed,
         false::boolean premium_high_glazing_likelihood,
         null::integer facade_opportunity_score,
         null::numeric premium_confidence,
         null::text website_url,
         ((case when coalesce(c.pure_water_state,'insufficient_evidence')='investigate' then 45 else 0 end) +
          (case when coalesce(c.masonry_state,'insufficient_evidence')='investigate' then 50 else 0 end) +
          (case when b.time_sensitive then 10 else 0 end) +
          (case when b.commercial_scale_status='documented' then 10 else 0 end) +
          (case when b.premium_priority_rank>0 then 10 else 0 end) +
          (case when coalesce(c.individually_listed_building,false)
                  or coalesce(c.within_listed_district,false)
                  or coalesce(c.national_historic_landmark_context,false) then 10 else 0 end))::integer verification_score
  from base b
  left join cls c on c.building_source_record_id=b.canonical_asset_id
  where b.rn=1
)
select e.*,
  array_remove(array[
    case when e.pure_water_state='investigate'
           or (e.pure_water_state='insufficient_evidence' and e.glazing_signal is null) then 'glazing' end,
    case when e.masonry_state='investigate'
           or (e.masonry_state='insufficient_evidence' and e.resolved_facade_material is null) then 'facade_material' end
  ],null)::text[] verification_needs,
  case when e.verification_score>=60 then 'high'
       when e.verification_score>=35 then 'medium'
       else 'context' end verification_priority,
  'do_not_retain_image_after_verification'::text media_retention_policy,
  'Verify only visible facade/glazing facts supported by the cited source. Do not infer masonry from historic status, glass extent from building archetype alone, cleaning need from appearance, or chemical suitability from material identity.'::text guardrail
from enriched e
where e.pure_water_state<>'supported' or e.masonry_state<>'supported';

revoke all on decisioning.v_facade_visual_verification_queue_v1 from anon,authenticated;
grant select on decisioning.v_facade_visual_verification_queue_v1 to service_role;

create or replace function public.internal_record_facade_visual_verification(
  p_building_source_record_id uuid,
  p_observation jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_source_id uuid;
  v_geom extensions.geometry;
  v_obs_id uuid;
  v_native_id text;
  v_material text;
  v_raw_material text;
  v_material_status text;
  v_glazing text;
  v_conf numeric;
  v_source_url text;
  v_source_title text;
  v_source_kind text;
  v_note text;
  v_observed_at timestamptz;
  v_bad_key text;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_observation is null or jsonb_typeof(p_observation)<>'object' then raise exception 'p_observation must be a JSON object'; end if;

  select key into v_bad_key
  from jsonb_object_keys(p_observation) key
  where key not in ('facade_material','raw_facade_material','facade_material_status','glazing_signal','confidence','source_url','source_title','source_kind','verification_note','observed_at','view_scope','image_retained')
  limit 1;
  if v_bad_key is not null then raise exception 'unsupported observation field: %',v_bad_key; end if;

  if coalesce((p_observation->>'image_retained')::boolean,false) then
    raise exception 'image retention is not permitted for facade visual verification';
  end if;

  v_material:=nullif(lower(btrim(coalesce(p_observation->>'facade_material',''))),'');
  v_raw_material:=nullif(btrim(coalesce(p_observation->>'raw_facade_material','')),'');
  v_material_status:=coalesce(nullif(lower(btrim(coalesce(p_observation->>'facade_material_status',''))),''),'documented');
  v_glazing:=nullif(lower(btrim(coalesce(p_observation->>'glazing_signal',''))),'');
  v_conf:=coalesce(nullif(p_observation->>'confidence','')::numeric,0.85);
  v_source_url:=nullif(btrim(coalesce(p_observation->>'source_url','')),'');
  v_source_title:=nullif(btrim(coalesce(p_observation->>'source_title','')),'');
  v_source_kind:=coalesce(nullif(lower(btrim(coalesce(p_observation->>'source_kind',''))),''),'public_visual_source');
  v_note:=nullif(btrim(coalesce(p_observation->>'verification_note','')),'');
  v_observed_at:=coalesce(nullif(p_observation->>'observed_at','')::timestamptz,now());

  if v_material is null and v_glazing is null then raise exception 'at least facade_material or glazing_signal is required'; end if;
  if v_material is not null and v_material not in ('brick','concrete','plaster','stone','metal','glass','cement_block','plastic','wood','masonry','limestone','other') then
    raise exception 'unsupported facade_material: %',v_material;
  end if;
  if v_material_status not in ('documented','source_reported') then raise exception 'facade_material_status must be documented or source_reported'; end if;
  if v_glazing is not null and v_glazing not in ('glass_facade_present','confirmed_glazed') then raise exception 'unsupported glazing_signal: %',v_glazing; end if;
  if v_conf<0.5 or v_conf>1 then raise exception 'confidence must be between 0.5 and 1.0'; end if;
  if length(coalesce(v_raw_material,''))>200 or length(coalesce(v_source_url,''))>2000
     or length(coalesce(v_source_title,''))>300 or length(coalesce(v_note,''))>2000 then
    raise exception 'one or more text fields exceed allowed length';
  end if;

  select geometry into v_geom
  from decisioning.building_candidates
  where source_record_id=p_building_source_record_id
  limit 1;
  if v_geom is null then raise exception 'canonical building not found'; end if;

  select id into v_source_id
  from ingest.sources
  where slug='scout-facade-visual-verification' and status in ('active','active_reference')
  limit 1;
  if v_source_id is null then raise exception 'visual verification source not configured'; end if;

  v_native_id:=p_building_source_record_id::text||':'||md5(coalesce(v_source_url,'')||'|'||coalesce(v_source_title,'')||'|'||v_source_kind);

  insert into decisioning.building_attribute_observations(
    source_id,source_native_id,source_feature_kind,observed_at,source_timestamp,geometry,
    facade_material,raw_facade_material,facade_material_status,glazing_signal,confidence,attributes,updated_at
  ) values (
    v_source_id,v_native_id,'building',v_observed_at,v_observed_at,v_geom,
    v_material,v_raw_material,v_material_status,v_glazing,v_conf,
    jsonb_strip_nulls(jsonb_build_object(
      'verification_method','visual_verification',
      'source_kind',v_source_kind,
      'source_url',v_source_url,
      'source_title',v_source_title,
      'verification_note',v_note,
      'view_scope',nullif(p_observation->>'view_scope',''),
      'image_retained',false,
      'media_retention_policy','do_not_retain_image_after_verification',
      'guardrail','Observation records visible material/glazing facts only; it does not establish cleaning need, substrate treatment compatibility, or customer demand.'
    )),now()
  )
  on conflict(source_id,source_native_id,source_feature_kind) do update set
    observed_at=excluded.observed_at,source_timestamp=excluded.source_timestamp,geometry=excluded.geometry,
    facade_material=excluded.facade_material,raw_facade_material=excluded.raw_facade_material,
    facade_material_status=excluded.facade_material_status,glazing_signal=excluded.glazing_signal,
    confidence=excluded.confidence,attributes=excluded.attributes,updated_at=now()
  returning id into v_obs_id;

  insert into decisioning.building_attribute_matches(
    building_source_record_id,observation_id,match_basis,overlap_ratio,centroid_distance_m,confidence,matched_at
  ) values (
    p_building_source_record_id,v_obs_id,'direct_canonical_visual_verification',1,0,0.99,now()
  )
  on conflict(building_source_record_id,observation_id) do update set
    match_basis=excluded.match_basis,overlap_ratio=excluded.overlap_ratio,
    centroid_distance_m=excluded.centroid_distance_m,confidence=excluded.confidence,matched_at=now();

  perform scout.refresh_exterior_opportunity_service_classifications();

  return jsonb_build_object(
    'building_source_record_id',p_building_source_record_id,
    'observation_id',v_obs_id,
    'facade_material',v_material,
    'glazing_signal',v_glazing,
    'confidence',v_conf,
    'image_retained',false,
    'classifier_refreshed',true
  );
end;
$$;

revoke all on function public.internal_record_facade_visual_verification(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.internal_record_facade_visual_verification(uuid,jsonb) to service_role;
