-- Batch 9: make bridge condition delta signal refresh idempotent.
-- Legacy rows were created without the generated_by marker that the refresh
-- cleanup expected, so subsequent runs collided with the durable unique key.

create or replace function intelligence.refresh_bridge_delta_signals()
returns jsonb
language plpgsql
set search_path to 'intelligence', 'transportation', 'commerce', 'ingest', 'pg_catalog'
as $function$
declare
  v_deterioration integer:=0;
  v_status integer:=0;
begin
  -- Remove both correctly tagged rows and legacy rows produced by the same
  -- generator before the marker was written.
  delete from intelligence.business_need_signals b
  using commerce.service_types st,
        intelligence.indicator_definitions ind
  where st.slug='bridge-inspection'
    and ind.slug='poor_condition'
    and b.service_type_id=st.id
    and b.indicator_id=ind.id
    and b.subject_type='bridge'
    and (
      b.evidence->>'generated_by'='bridge_condition_delta_v1'
      or (
        b.evidence->>'current_official_observation'='true'
        and b.evidence ? 'event_id'
        and (
          b.signal_type='bridge_condition_band_worsened'
          or b.signal_type like 'bridge\_%\_rating\_drop' escape '\'
          or b.signal_type='bridge_operational_status_change'
        )
      )
    );

  insert into intelligence.business_need_signals(
    service_type_id,indicator_id,subject_type,subject_key,source_record_id,location,
    signal_type,signal_strength,confidence,observed_at,valid_from,ideal_until,
    expires_at,can_open_window,reason,evidence,source_slugs,status
  )
  select st.id,ind.id,'bridge',e.state_fips||':'||e.structure_number,
    s.source_record_id,s.location,
    case when e.component is null
      then 'bridge_condition_band_worsened'
      else 'bridge_'||e.component||'_rating_drop' end,
    e.severity,e.confidence,s.observed_at,e.event_date::timestamptz,
    e.event_date::timestamptz+interval '90 days',
    e.event_date::timestamptz+interval '365 days',
    e.can_open_window,e.reason,
    e.evidence || jsonb_build_object(
      'event_id',e.id,
      'old_value',e.old_value,
      'new_value',e.new_value,
      'current_source_slug',src.slug,
      'current_official_observation',true,
      'generated_by','bridge_condition_delta_v1'
    ),
    array[src.slug],'active'
  from transportation.bridge_condition_events e
  join transportation.bridge_condition_snapshots s on s.id=e.to_snapshot_id
  join ingest.sources src on src.id=s.source_id
  join commerce.service_types st on st.slug='bridge-inspection'
  join intelligence.indicator_definitions ind on ind.slug='poor_condition'
  where e.direction='deterioration'
    and e.event_type in ('condition_band_worsened','component_rating_drop')
    and s.source_standard in ('state_current','snbi')
  on conflict(service_type_id,indicator_id,subject_type,subject_key,signal_type)
  do update set
    source_record_id=excluded.source_record_id,
    location=excluded.location,
    signal_strength=excluded.signal_strength,
    confidence=excluded.confidence,
    observed_at=excluded.observed_at,
    valid_from=excluded.valid_from,
    ideal_until=excluded.ideal_until,
    expires_at=excluded.expires_at,
    can_open_window=excluded.can_open_window,
    reason=excluded.reason,
    evidence=excluded.evidence,
    source_slugs=excluded.source_slugs,
    status=excluded.status;
  get diagnostics v_deterioration=row_count;

  insert into intelligence.business_need_signals(
    service_type_id,indicator_id,subject_type,subject_key,source_record_id,location,
    signal_type,signal_strength,confidence,observed_at,valid_from,ideal_until,
    expires_at,can_open_window,reason,evidence,source_slugs,status
  )
  select st.id,ind.id,'bridge',e.state_fips||':'||e.structure_number,
    s.source_record_id,s.location,
    'bridge_operational_status_change','medium',e.confidence,s.observed_at,
    e.event_date::timestamptz,
    e.event_date::timestamptz+interval '30 days',
    e.event_date::timestamptz+interval '180 days',
    e.can_open_window,e.reason,
    e.evidence || jsonb_build_object(
      'event_id',e.id,
      'old_value',e.old_value,
      'new_value',e.new_value,
      'current_source_slug',src.slug,
      'current_official_observation',true,
      'generated_by','bridge_condition_delta_v1'
    ),
    array[src.slug],'active'
  from transportation.bridge_condition_events e
  join transportation.bridge_condition_snapshots s on s.id=e.to_snapshot_id
  join ingest.sources src on src.id=s.source_id
  join commerce.service_types st on st.slug='bridge-inspection'
  join intelligence.indicator_definitions ind on ind.slug='poor_condition'
  where e.event_type in ('posting_status_changed','operational_status_changed')
    and s.source_standard in ('state_current','snbi')
  on conflict(service_type_id,indicator_id,subject_type,subject_key,signal_type)
  do update set
    source_record_id=excluded.source_record_id,
    location=excluded.location,
    signal_strength=excluded.signal_strength,
    confidence=excluded.confidence,
    observed_at=excluded.observed_at,
    valid_from=excluded.valid_from,
    ideal_until=excluded.ideal_until,
    expires_at=excluded.expires_at,
    can_open_window=excluded.can_open_window,
    reason=excluded.reason,
    evidence=excluded.evidence,
    source_slugs=excluded.source_slugs,
    status=excluded.status;
  get diagnostics v_status=row_count;

  return jsonb_build_object(
    'deterioration_signals',v_deterioration,
    'status_change_signals',v_status,
    'generator','bridge_condition_delta_v1'
  );
end
$function$;