-- Restrict facade-evidence confidence reconciliation to supported masonry candidates.
-- Prevents corpus-wide scans on every facade verification write.

CREATE OR REPLACE FUNCTION scout.refresh_exterior_opportunity_service_classifications()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rows integer:=0;
  v_now timestamptz:=clock_timestamp();
  v_bridge jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_exterior_opportunity_service_classifications',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;

  v_bridge:=cleaning.refresh_canonical_exterior_environment_context();

  truncate scout.opportunity_service_classifications;
  insert into scout.opportunity_service_classifications(
    candidate_key,building_source_record_id,service_type_id,classification_state,
    classification_confidence,reason,evidence,classifier_version,evidence_refreshed_at,refreshed_at
  )
  select b.candidate_key,b.building_source_record_id,st.id,b.classification_state,
         b.classification_confidence,b.reason,b.evidence,b.classifier_version,b.evidence_refreshed_at,v_now
  from cleaning.v_exterior_opportunity_service_classification_build b
  join commerce.service_types st on st.slug=b.service_slug and st.active;
  get diagnostics v_rows=row_count;

  -- Reconcile facade evidence confidence only for buildings that actually
  -- became supported masonry candidates in this refresh. Avoid a corpus-wide
  -- scan of all building evidence on every single verification write.
  with masonry as (
    select id from commerce.service_types where slug='masonry-restoration-cleaning' and active limit 1
  ), supported as (
    select distinct c.building_source_record_id
    from scout.opportunity_service_classifications c,masonry ms
    where c.service_type_id=ms.id
      and c.classification_state='supported'
      and c.building_source_record_id is not null
  ), facade as (
    select distinct on (m.building_source_record_id)
      m.building_source_record_id,
      least(0.99,greatest(0::numeric,coalesce(m.confidence,0)*coalesce(o.confidence,0))) facade_evidence_confidence,
      src.slug facade_source_slug,o.facade_material,o.raw_facade_material,o.facade_material_status,o.observed_at
    from supported s
    join decisioning.building_attribute_matches m on m.building_source_record_id=s.building_source_record_id
    join decisioning.building_attribute_observations o on o.id=m.observation_id
    join ingest.sources src on src.id=o.source_id
    where o.facade_material is not null
    order by m.building_source_record_id,
      case o.facade_material_status when 'documented' then 4 when 'source_reported' then 3 when 'normalized' then 2 else 1 end desc,
      case o.source_feature_kind when 'building' then 2 else 1 end desc,
      m.confidence desc,o.confidence desc,o.observed_at desc
  ), masonry2 as (
    select id from commerce.service_types where slug='masonry-restoration-cleaning' and active limit 1
  )
  update scout.opportunity_service_classifications c
  set classification_confidence=greatest(coalesce(c.classification_confidence,0),f.facade_evidence_confidence),
      evidence=coalesce(c.evidence,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
        'resolved_facade_evidence_confidence',f.facade_evidence_confidence,
        'resolved_facade_evidence_source_slug',f.facade_source_slug,
        'resolved_facade_evidence_observed_at',f.observed_at
      ))
  from facade f,masonry2 ms
  where c.building_source_record_id=f.building_source_record_id
    and c.service_type_id=ms.id
    and c.classification_state='supported';

  return jsonb_build_object(
    'refreshed_at',v_now,'rows',v_rows,
    'supported',(select count(*) from scout.opportunity_service_classifications where classification_state='supported'),
    'investigate',(select count(*) from scout.opportunity_service_classifications where classification_state='investigate'),
    'insufficient_evidence',(select count(*) from scout.opportunity_service_classifications where classification_state='insufficient_evidence'),
    'environment_bridge',v_bridge,
    'classifier_version','exterior-service-classifier-v1'
  );
end;
$function$;
