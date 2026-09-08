-- Incremental classification updates for facade visual verification.
-- Facade verification changes masonry/glazing evidence only; avoid rebuilding the full classifier on each write.

CREATE OR REPLACE FUNCTION scout.apply_facade_verification_classification_delta(
  p_building_source_record_id uuid,
  p_facade_material text,
  p_glazing_signal text,
  p_confidence numeric,
  p_source_slug text default 'scout-facade-visual-verification'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
declare
  v_masonry_id uuid;
  v_glass_id uuid;
  v_effective_conf numeric:=least(0.99,greatest(0::numeric,coalesce(p_confidence,0)*0.99));
  v_masonry_rows integer:=0;
  v_glass_rows integer:=0;
begin
  select id into v_masonry_id from commerce.service_types where slug='masonry-restoration-cleaning' and active limit 1;
  select id into v_glass_id from commerce.service_types where slug='pure-water-window-cleaning' and active limit 1;

  if v_masonry_id is not null and lower(coalesce(p_facade_material,'')) in ('brick','stone','masonry','limestone') then
    insert into scout.opportunity_service_classifications(
      candidate_key,building_source_record_id,service_type_id,classification_state,
      classification_confidence,reason,evidence,classifier_version,evidence_refreshed_at,refreshed_at
    )
    select s.candidate_key,p_building_source_record_id,v_masonry_id,'supported',v_effective_conf,
      'Resolved facade/material evidence supports investigating this existing cleaning opportunity for masonry or limestone restoration cleaning.',
      jsonb_strip_nulls(jsonb_build_object(
        'resolved_facade_material',p_facade_material,
        'resolved_facade_evidence_confidence',v_effective_conf,
        'resolved_facade_evidence_source_slug',p_source_slug,
        'guardrail','Verified masonry material supports service investigation; it does not establish treatment compatibility, cleaning need, customer demand, or suitability of any specific restoration chemical.'
      )),
      'exterior-service-classifier-v1',now(),now()
    from scout.opportunity_search_spine s
    where s.canonical_asset_id=p_building_source_record_id
      and s.target_class='building'
      and s.canonical_namespace='decisioning.building_candidates'
      and s.service_slugs @> array['exterior-cleaning']::text[]
    on conflict(candidate_key,service_type_id) do update set
      building_source_record_id=excluded.building_source_record_id,
      classification_state='supported',
      classification_confidence=greatest(coalesce(scout.opportunity_service_classifications.classification_confidence,0),excluded.classification_confidence),
      reason=excluded.reason,
      evidence=coalesce(scout.opportunity_service_classifications.evidence,'{}'::jsonb)||excluded.evidence,
      classifier_version=excluded.classifier_version,
      evidence_refreshed_at=excluded.evidence_refreshed_at,
      refreshed_at=excluded.refreshed_at;
    get diagnostics v_masonry_rows=row_count;
  end if;

  if v_glass_id is not null and (
    lower(coalesce(p_facade_material,''))='glass' or
    lower(coalesce(p_glazing_signal,'')) in ('glass_facade_present','confirmed_glazed')
  ) then
    insert into scout.opportunity_service_classifications(
      candidate_key,building_source_record_id,service_type_id,classification_state,
      classification_confidence,reason,evidence,classifier_version,evidence_refreshed_at,refreshed_at
    )
    select s.candidate_key,p_building_source_record_id,v_glass_id,'supported',v_effective_conf,
      'Direct/resolved glazing evidence supports investigating this existing cleaning opportunity specifically for pure-water exterior glass cleaning.',
      jsonb_strip_nulls(jsonb_build_object(
        'resolved_glazing_signal',coalesce(p_glazing_signal,case when lower(coalesce(p_facade_material,''))='glass' then 'glass_facade_present' end),
        'resolved_glazing_confidence',v_effective_conf,
        'resolved_glazing_source_slug',p_source_slug,
        'guardrail','Verified glazing presence does not establish exterior glass area, cleanability, access, coating compatibility, or customer demand.'
      )),
      'exterior-service-classifier-v1',now(),now()
    from scout.opportunity_search_spine s
    where s.canonical_asset_id=p_building_source_record_id
      and s.target_class='building'
      and s.canonical_namespace='decisioning.building_candidates'
      and s.service_slugs @> array['exterior-cleaning']::text[]
    on conflict(candidate_key,service_type_id) do update set
      building_source_record_id=excluded.building_source_record_id,
      classification_state='supported',
      classification_confidence=greatest(coalesce(scout.opportunity_service_classifications.classification_confidence,0),excluded.classification_confidence),
      reason=excluded.reason,
      evidence=coalesce(scout.opportunity_service_classifications.evidence,'{}'::jsonb)||excluded.evidence,
      classifier_version=excluded.classifier_version,
      evidence_refreshed_at=excluded.evidence_refreshed_at,
      refreshed_at=excluded.refreshed_at;
    get diagnostics v_glass_rows=row_count;
  end if;

  return jsonb_build_object(
    'building_source_record_id',p_building_source_record_id,
    'masonry_rows',v_masonry_rows,
    'glass_rows',v_glass_rows,
    'effective_confidence',v_effective_conf,
    'mode','incremental_facade_delta'
  );
end;
$function$;

REVOKE ALL ON FUNCTION scout.apply_facade_verification_classification_delta(uuid,text,text,numeric,text) FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION scout.apply_facade_verification_classification_delta(uuid,text,text,numeric,text) TO service_role;

-- The production visual-verification RPC now calls the incremental delta function
-- after persisting the canonical building observation and direct match, rather than
-- rebuilding the full opportunity-service classifier synchronously.
