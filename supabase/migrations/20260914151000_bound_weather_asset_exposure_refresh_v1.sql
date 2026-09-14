-- Batch 6: bound weather asset exposure refresh and restore spatial-index use.
--
-- The prior refresh built a global DISTINCT ON over ingest.raw_records and then
-- intersected active weather polygons against COALESCE(geometry, location), which
-- prevented effective use of the source spatial indexes. Snapshot only source
-- families configured for weather exposure, preserve latest-record semantics,
-- materialize one canonical geometry, and index that bounded snapshot for the
-- event overlap pass.

create or replace function intelligence.refresh_weather_windows()
returns jsonb
language plpgsql
security definer
set search_path to 'intelligence','ingest','commerce','public','extensions'
as $function$
declare
  w_count integer := 0;
  e_count integer := 0;
begin
  update intelligence.weather_events
     set status='expired',updated_at=now()
   where status in ('active','upcoming')
     and expires_at is not null
     and expires_at<now();

  insert into intelligence.weather_service_windows(
    event_id,service_type_id,indicator_id,subject_mode,window_status,opens_at,ideal_until,expires_at,confidence,rationale,attributes,updated_at
  )
  select e.id,r.service_type_id,r.indicator_id,r.subject_mode,
    case when e.status='upcoming' then 'upcoming'
         when e.status='active' and (e.hazard_family='tornado' or lower(coalesce(e.severity,'')) in ('extreme','severe')) then 'urgent'
         when e.status='active' then 'open'
         when e.status='expired' and coalesce(e.expires_at,e.ends_at,e.onset_at,e.sent_at,e.first_observed_at)+make_interval(days=>r.decay_days)>now() then 'fading'
         else 'expired' end,
    coalesce(e.onset_at,e.effective_at,e.sent_at,e.first_observed_at),
    coalesce(e.ends_at,e.expires_at,coalesce(e.onset_at,e.effective_at,e.sent_at,e.first_observed_at)+make_interval(days=>r.active_days)),
    coalesce(e.expires_at,e.ends_at,e.onset_at,e.sent_at,e.first_observed_at)+make_interval(days=>r.decay_days),
    case e.evidence_class when 'post_event_footprint' then case when e.hazard_family='hail' then 0.80 else 0.86 end when 'validated_event' then 0.82 else 0.56 end,
    replace(r.rationale_template,'{event}',e.event_type),
    jsonb_build_object('hazard_family',e.hazard_family,'event_severity',e.severity,'evidence_class',e.evidence_class,'source_slug',e.source_slug,'magnitude',e.magnitude,'magnitude_unit',e.magnitude_unit),now()
  from intelligence.weather_events e
  join intelligence.weather_hazard_service_rules r on r.hazard_family=e.hazard_family and r.active
  where e.within_pilot and e.status<>'cancelled'
    and coalesce(e.expires_at,e.ends_at,e.onset_at,e.sent_at,e.first_observed_at)+make_interval(days=>r.decay_days)>now()
    and (r.rule_config->>'min_magnitude' is null or e.magnitude is null or e.magnitude >= (r.rule_config->>'min_magnitude')::numeric)
  on conflict(event_id,service_type_id) do update set
    indicator_id=excluded.indicator_id,subject_mode=excluded.subject_mode,window_status=excluded.window_status,opens_at=excluded.opens_at,
    ideal_until=excluded.ideal_until,expires_at=excluded.expires_at,confidence=excluded.confidence,rationale=excluded.rationale,attributes=excluded.attributes,updated_at=now();
  get diagnostics w_count=row_count;

  drop table if exists pg_temp.weather_latest_assets;
  create temporary table weather_latest_assets on commit drop as
  select distinct on (rr.source_id,rr.source_native_id)
         rr.id as source_record_id,
         rr.source_id,
         rr.source_native_id,
         coalesce(rr.geometry,rr.location::extensions.geometry) as asset_geometry
  from ingest.raw_records rr
  join (
    select distinct s.id
    from intelligence.weather_asset_source_rules wr
    join ingest.sources s on s.slug=wr.source_slug
    where wr.active
  ) configured on configured.id=rr.source_id
  where rr.within_pilot_radius is distinct from false
    and (rr.geometry is not null or rr.location is not null)
  order by rr.source_id,rr.source_native_id,rr.retrieved_at desc,rr.created_at desc;

  create index weather_latest_assets_source_idx
    on pg_temp.weather_latest_assets(source_id);
  create index weather_latest_assets_geometry_gix
    on pg_temp.weather_latest_assets using gist(asset_geometry);
  analyze pg_temp.weather_latest_assets;

  with candidates as (
    select e.id event_id,wr.service_type_id,hr.indicator_id,rr.source_record_id,wr.asset_type,e.evidence_class,e.event_type,e.hazard_family,
      case e.evidence_class when 'post_event_footprint' then case when e.hazard_family='hail' then 0.78 else 0.82 end when 'validated_event' then 0.78 else 0.48 end confidence
    from intelligence.weather_events e
    join intelligence.weather_hazard_service_rules hr on hr.hazard_family=e.hazard_family and hr.active and hr.subject_mode='asset'
    join intelligence.weather_asset_source_rules wr on wr.service_type_id=hr.service_type_id and wr.active
    join ingest.sources s on s.slug=wr.source_slug
    join pg_temp.weather_latest_assets rr
      on rr.source_id=s.id
     and extensions.ST_Intersects(e.geometry,rr.asset_geometry)
    where e.within_pilot and e.geometry is not null and e.status<>'cancelled'
      and coalesce(e.expires_at,e.ends_at,e.onset_at,e.sent_at,e.first_observed_at)+make_interval(days=>hr.decay_days)>now()
      and (hr.rule_config->>'min_magnitude' is null or e.magnitude is null or e.magnitude >= (hr.rule_config->>'min_magnitude')::numeric)
  )
  insert into intelligence.weather_asset_exposures(
    event_id,service_type_id,indicator_id,source_record_id,asset_type,exposure_basis,damage_confirmed,confidence,status,rationale,attributes,updated_at
  )
  select event_id,service_type_id,indicator_id,source_record_id,asset_type,
    case evidence_class when 'post_event_footprint' then 'post_event_hazard_footprint_overlap' else 'nws_alert_polygon_overlap' end,false,confidence,
    case evidence_class when 'post_event_footprint' then 'confirmed_hazard_exposure' else 'candidate' end,
    case evidence_class when 'post_event_footprint' then event_type||' footprint overlaps this asset; hazard exposure is supported, but asset damage is not proven.'
         else event_type||' alert polygon overlaps this asset; this is a provisional exposure candidate, not evidence of damage.' end,
    jsonb_build_object('hazard_family',hazard_family,'evidence_class',evidence_class),now()
  from candidates
  on conflict(event_id,service_type_id,source_record_id) do update set
    indicator_id=excluded.indicator_id,exposure_basis=excluded.exposure_basis,
    confidence=greatest(intelligence.weather_asset_exposures.confidence,excluded.confidence),status=excluded.status,rationale=excluded.rationale,attributes=excluded.attributes,updated_at=now();
  get diagnostics e_count=row_count;

  update intelligence.weather_service_windows
     set window_status='expired',updated_at=now()
   where expires_at<=now() and window_status<>'expired';

  update intelligence.weather_asset_exposures x
     set status='expired',updated_at=now()
   where status in ('candidate','confirmed_hazard_exposure')
     and exists (
       select 1
       from intelligence.weather_service_windows w
       where w.event_id=x.event_id
         and w.service_type_id=x.service_type_id
         and w.expires_at<=now()
     );

  return jsonb_build_object('service_windows_upserted',w_count,'asset_exposures_upserted',e_count);
end
$function$;

comment on function intelligence.refresh_weather_windows() is
  'Refreshes weather service windows and indexed latest-asset exposure overlaps using only configured weather asset source families.';