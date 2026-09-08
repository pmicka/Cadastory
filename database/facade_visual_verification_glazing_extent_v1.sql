-- Scout by Cadastory
-- Exact production definition after migration facade_visual_verification_glazing_extent_v1.

CREATE OR REPLACE FUNCTION public.internal_record_facade_visual_verification(p_building_source_record_id uuid, p_observation jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source_id uuid;
  v_geom extensions.geometry;
  v_obs_id uuid;
  v_native_id text;
  v_material text;
  v_raw_material text;
  v_material_status text;
  v_glazing text;
  v_glazing_extent text;
  v_conf numeric;
  v_source_url text;
  v_source_title text;
  v_source_kind text;
  v_note text;
  v_observed_at timestamptz;
  v_bad_key text;
  v_classifier jsonb;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_observation is null or jsonb_typeof(p_observation)<>'object' then raise exception 'p_observation must be a JSON object'; end if;

  select key into v_bad_key
  from jsonb_object_keys(p_observation) key
  where key not in ('facade_material','raw_facade_material','facade_material_status','glazing_signal','glazing_extent','confidence','source_url','source_title','source_kind','verification_note','observed_at','view_scope','image_retained')
  limit 1;
  if v_bad_key is not null then raise exception 'unsupported observation field: %',v_bad_key; end if;
  if coalesce((p_observation->>'image_retained')::boolean,false) then raise exception 'image retention is not permitted for facade visual verification'; end if;

  v_material:=nullif(lower(btrim(coalesce(p_observation->>'facade_material',''))),'');
  v_raw_material:=nullif(btrim(coalesce(p_observation->>'raw_facade_material','')),'');
  v_material_status:=coalesce(nullif(lower(btrim(coalesce(p_observation->>'facade_material_status',''))),''),'documented');
  v_glazing:=nullif(lower(btrim(coalesce(p_observation->>'glazing_signal',''))),'');
  v_glazing_extent:=nullif(lower(btrim(coalesce(p_observation->>'glazing_extent',''))),'');
  v_conf:=coalesce(nullif(p_observation->>'confidence','')::numeric,0.85);
  v_source_url:=nullif(btrim(coalesce(p_observation->>'source_url','')),'');
  v_source_title:=nullif(btrim(coalesce(p_observation->>'source_title','')),'');
  v_source_kind:=coalesce(nullif(lower(btrim(coalesce(p_observation->>'source_kind',''))),''),'public_visual_source');
  v_note:=nullif(btrim(coalesce(p_observation->>'verification_note','')),'');
  v_observed_at:=coalesce(nullif(p_observation->>'observed_at','')::timestamptz,now());

  if v_material is null and v_glazing is null then raise exception 'at least facade_material or glazing_signal is required'; end if;
  if v_material is not null and v_material not in ('brick','concrete','plaster','stone','metal','glass','cement_block','plastic','wood','masonry','limestone','other') then raise exception 'unsupported facade_material: %',v_material; end if;
  if v_material_status not in ('documented','source_reported') then raise exception 'facade_material_status must be documented or source_reported'; end if;
  if v_glazing is not null and v_glazing not in ('glass_facade_present','confirmed_glazed') then raise exception 'unsupported glazing_signal: %',v_glazing; end if;
  if v_glazing_extent is not null and v_glazing_extent not in ('localized','repeated_openings','building_repeated','facade_system') then raise exception 'unsupported glazing_extent: %',v_glazing_extent; end if;
  if v_glazing_extent is not null and v_glazing is null and v_material<>'glass' then raise exception 'glazing_extent requires glazing_signal or facade_material=glass'; end if;
  if v_conf<0.5 or v_conf>1 then raise exception 'confidence must be between 0.5 and 1.0'; end if;
  if length(coalesce(v_raw_material,''))>200 or length(coalesce(v_source_url,''))>2000 or length(coalesce(v_source_title,''))>300 or length(coalesce(v_note,''))>2000 then raise exception 'one or more text fields exceed allowed length'; end if;

  select geometry into v_geom from decisioning.building_candidates where source_record_id=p_building_source_record_id limit 1;
  if v_geom is null then raise exception 'canonical building not found'; end if;
  select id into v_source_id from ingest.sources where slug='scout-facade-visual-verification' and status in ('active','active_reference') limit 1;
  if v_source_id is null then raise exception 'visual verification source not configured'; end if;

  v_native_id:=p_building_source_record_id::text||':'||md5(coalesce(v_source_url,'')||'|'||coalesce(v_source_title,'')||'|'||v_source_kind);

  insert into decisioning.building_attribute_observations(
    source_id,source_native_id,source_feature_kind,observed_at,source_timestamp,geometry,
    facade_material,raw_facade_material,facade_material_status,glazing_signal,glazing_extent,confidence,attributes,updated_at
  ) values (
    v_source_id,v_native_id,'building',v_observed_at,v_observed_at,v_geom,
    v_material,v_raw_material,v_material_status,v_glazing,v_glazing_extent,v_conf,
    jsonb_strip_nulls(jsonb_build_object(
      'verification_method','visual_verification','source_kind',v_source_kind,'source_url',v_source_url,
      'source_title',v_source_title,'verification_note',v_note,'view_scope',nullif(p_observation->>'view_scope',''),
      'glazing_extent',v_glazing_extent,
      'image_retained',false,'media_retention_policy','do_not_retain_image_after_verification',
      'guardrail','Observation records visible material/glazing facts only; glazing extent distinguishes localized openings from building-scale repeated glazing or facade systems. It does not establish cleaning need, cleanability, substrate treatment compatibility, or customer demand.'
    )),now()
  )
  on conflict(source_id,source_native_id,source_feature_kind) do update set
    observed_at=excluded.observed_at,source_timestamp=excluded.source_timestamp,geometry=excluded.geometry,
    facade_material=excluded.facade_material,raw_facade_material=excluded.raw_facade_material,
    facade_material_status=excluded.facade_material_status,glazing_signal=excluded.glazing_signal,
    glazing_extent=excluded.glazing_extent,confidence=excluded.confidence,attributes=excluded.attributes,updated_at=now()
  returning id into v_obs_id;

  insert into decisioning.building_attribute_matches(
    building_source_record_id,observation_id,match_basis,overlap_ratio,centroid_distance_m,confidence,matched_at
  ) values (p_building_source_record_id,v_obs_id,'direct_canonical_visual_verification',1,0,0.99,now())
  on conflict(building_source_record_id,observation_id) do update set
    match_basis=excluded.match_basis,overlap_ratio=excluded.overlap_ratio,centroid_distance_m=excluded.centroid_distance_m,
    confidence=excluded.confidence,matched_at=now();

  v_classifier:=scout.apply_facade_verification_classification_delta(
    p_building_source_record_id,v_material,v_glazing,v_conf,'scout-facade-visual-verification'
  );

  return jsonb_build_object(
    'building_source_record_id',p_building_source_record_id,'observation_id',v_obs_id,
    'facade_material',v_material,'glazing_signal',v_glazing,'glazing_extent',v_glazing_extent,'confidence',v_conf,
    'image_retained',false,'classifier_refreshed',true,'classifier_refresh',v_classifier
  );
end;
$function$;

revoke all on function public.internal_record_facade_visual_verification(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.internal_record_facade_visual_verification(uuid,jsonb) to service_role;
