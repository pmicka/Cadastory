-- Scout cleaning-access scenario refresh hook v1
-- Keeps OSM-derived cleaning_access_scenarios current as the local snapshot queue advances.

create or replace function decisioning.process_site_access_queue_from_snapshot(p_limit integer default 25, p_target_types text[] default null::text[])
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  rec record;
  v_result jsonb;
  v_limit integer;
  v_selected integer := 0;
  v_completed integer := 0;
  v_failed integer := 0;
  v_snapshot_ready boolean := decisioning.snapshot_access_ready();
  v_errors jsonb := '[]'::jsonb;
  v_started_at timestamptz := now();
  v_error_text text;
  v_reason text;
  v_cleaning_scenarios jsonb := null;
begin
  v_limit := coalesce(p_limit, 25);
  if v_limit < 1 or v_limit > 250 then
    raise exception 'p_limit must be between 1 and 250';
  end if;

  if not v_snapshot_ready then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'local_snapshot_not_ready', 'selected', 0, 'completed', 0, 'failed', 0);
  end if;

  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('decisioning.process_site_access_queue_from_snapshot', 0)) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'worker_already_running', 'selected', 0, 'completed', 0, 'failed', 0);
  end if;

  for rec in
    with selected as (
      select q.id, q.target_key, q.target_type
      from decisioning.site_access_queue q
      where q.state in ('pending','failed')
        and q.next_attempt_at <= now()
        and (p_target_types is null or q.target_type = any(p_target_types))
      order by q.priority desc, q.created_at, q.id
      limit v_limit
      for update skip locked
    ), claimed as (
      update decisioning.site_access_queue q
         set state = 'processing', claimed_at = now(), attempt_count = attempt_count + 1, last_error = null,
             source_context = coalesce(q.source_context, '{}'::jsonb) || jsonb_build_object('local_snapshot_worker_claimed_at', now()),
             updated_at = now()
      from selected s
      where q.id = s.id
      returning q.id, q.target_key, q.target_type
    )
    select * from claimed
  loop
    v_selected := v_selected + 1;
    begin
      v_result := decisioning.resolve_site_access_target_from_snapshot(rec.target_key, 'local_snapshot_queue_worker');
      if coalesce((v_result->>'ok')::boolean, false) and coalesce((v_result->>'resolved')::boolean, false) then
        update decisioning.site_access_queue q
           set state = 'complete', completed_at = now(), claimed_at = null, last_error = null,
               source_context = coalesce(q.source_context, '{}'::jsonb) || jsonb_build_object(
                 'resolved_from', 'local_snapshot','local_snapshot_worker_completed_at', now(),
                 'last_source_timestamp', v_result->>'source_timestamp',
                 'last_feature_count', coalesce((v_result->>'feature_count')::integer, 0),
                 'negative_evidence_allowed', false
               ),updated_at = now()
         where q.id = rec.id;
        v_completed := v_completed + 1;
      else
        v_reason := coalesce(v_result->>'reason', 'unresolved_without_reason');
        update decisioning.site_access_queue q
           set state = 'failed', claimed_at = null, completed_at = null, last_error = left(v_reason, 1000),
               next_attempt_at = case when v_reason = 'target_missing_or_no_geometry' then now() + interval '30 days' else now() + interval '1 day' end,
               source_context = coalesce(q.source_context, '{}'::jsonb) || jsonb_build_object(
                 'local_snapshot_worker_failed_at', now(),'local_snapshot_worker_reason', v_reason,'negative_evidence_allowed', false
               ),updated_at = now()
         where q.id = rec.id;
        v_failed := v_failed + 1;
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('target_key', rec.target_key, 'reason', v_reason));
      end if;
    exception when others then
      v_error_text := left(SQLSTATE || ': ' || SQLERRM, 1000);
      update decisioning.site_access_queue q
         set state = 'failed', claimed_at = null, completed_at = null, last_error = v_error_text,
             next_attempt_at = now() + interval '1 day',
             source_context = coalesce(q.source_context, '{}'::jsonb) || jsonb_build_object(
               'local_snapshot_worker_failed_at', now(),'local_snapshot_worker_error_code', SQLSTATE,'negative_evidence_allowed', false
             ),updated_at = now()
       where q.id = rec.id;
      v_failed := v_failed + 1;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('target_key', rec.target_key, 'error', v_error_text));
    end;
  end loop;

  if v_completed > 0 then
    v_cleaning_scenarios := decisioning.refresh_cleaning_access_scenarios(3);
  end if;

  return jsonb_build_object(
    'ok', true,'snapshot_ready', v_snapshot_ready,'selected', v_selected,'completed', v_completed,'failed', v_failed,
    'limit', v_limit,'target_types', coalesce(to_jsonb(p_target_types), 'null'::jsonb),
    'started_at', v_started_at,'completed_at', now(),'errors', v_errors,'negative_evidence_allowed', false,
    'cleaning_scenario_materialization', v_cleaning_scenarios
  );
end
$$;

create or replace function decisioning.refresh_all_site_access_links_from_snapshot()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_source_id uuid; v_timestamp timestamptz; v_targets integer:=0; v_links integer:=0; v_runs integer:=0;
  v_cleaning_scenarios jsonb:=null;
begin
  if not decisioning.snapshot_access_ready() then
    return jsonb_build_object('ok',false,'reason','local_snapshot_not_ready');
  end if;
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('decisioning.refresh_all_site_access_links_from_snapshot',0)) then
    return jsonb_build_object('ok',true,'skipped',true,'reason','refresh_already_running');
  end if;
  select id into v_source_id from ingest.sources where slug='openstreetmap-geofabrik-access-snapshot';
  select min(current_source_timestamp) into v_timestamp from decisioning.site_access_snapshot_regions where enabled and status='ready';

  create temporary table _scout_snapshot_targets on commit drop as
  select t.target_key,t.target_type,t.geometry,
         case when t.target_type='job_site' then 220 else decisioning.default_site_access_buffer(t.target_type) end buffer_m
  from decisioning.v_operational_targets t
  where t.geometry is not null;
  create unique index on _scout_snapshot_targets(target_key);
  select count(*) into v_targets from _scout_snapshot_targets;

  delete from decisioning.site_access_feature_targets l
  using decisioning.site_access_features f,_scout_snapshot_targets t
  where l.target_key=t.target_key and l.feature_id=f.id and f.source_id=v_source_id;

  insert into decisioning.site_access_feature_targets(feature_id,target_key,target_type,distance_to_target_m,relation,last_linked_at)
  select f.id,t.target_key,t.target_type,
         extensions.ST_Distance(f.geometry::extensions.geography,t.geometry::extensions.geography),
         case when extensions.ST_Intersects(f.geometry,t.geometry) then 'intersects'
              when extensions.ST_Distance(f.geometry::extensions.geography,t.geometry::extensions.geography)<=15 then 'adjacent'
              else 'nearby' end,
         now()
  from _scout_snapshot_targets t
  join decisioning.site_access_features f
    on f.source_id=v_source_id
   and extensions.ST_DWithin(f.geometry::extensions.geography,t.geometry::extensions.geography,t.buffer_m)
  on conflict(feature_id,target_key) do update set target_type=excluded.target_type,distance_to_target_m=excluded.distance_to_target_m,relation=excluded.relation,last_linked_at=now();
  get diagnostics v_links=row_count;

  with class_counts as (
    select l.target_key,f.feature_class,count(*)::integer n
    from decisioning.site_access_feature_targets l
    join decisioning.site_access_features f on f.id=l.feature_id and f.source_id=v_source_id
    join _scout_snapshot_targets t on t.target_key=l.target_key
    group by l.target_key,f.feature_class
  ), agg as (
    select target_key,sum(n)::integer feature_count,jsonb_object_agg(feature_class,n) feature_counts
    from class_counts group by target_key
  )
  insert into decisioning.site_access_target_enrichment_runs(target_key,target_type,source_id,requested_buffer_m,status,feature_count,feature_counts,source_timestamp,started_at,completed_at,attributes)
  select t.target_key,t.target_type,v_source_id,t.buffer_m,'complete',coalesce(a.feature_count,0),coalesce(a.feature_counts,'{}'::jsonb),v_timestamp,now(),now(),
         jsonb_build_object('collector','local-geofabrik-snapshot-v1','reason','bulk_snapshot_link_refresh','negative_evidence_allowed',false,'snapshot_kind','geofabrik_osm_pbf')
  from _scout_snapshot_targets t left join agg a on a.target_key=t.target_key;
  get diagnostics v_runs=row_count;

  update decisioning.site_access_queue q set state='complete',completed_at=now(),last_error=null,
    source_context=q.source_context||jsonb_build_object('resolved_from','local_snapshot','last_source_timestamp',v_timestamp),updated_at=now()
  where q.target_key in (select target_key from _scout_snapshot_targets) and q.state<>'processing';

  update decisioning.site_access_snapshot_regions
     set last_linked_import_id=last_successful_import_id,last_linked_at=now(),updated_at=now()
   where enabled and status='ready';

  v_cleaning_scenarios:=decisioning.refresh_cleaning_access_scenarios(3);

  return jsonb_build_object(
    'ok',true,'source_timestamp',v_timestamp,'targets',v_targets,'feature_links_written',v_links,'target_runs_written',v_runs,
    'negative_evidence_allowed',false,'normalized_opportunity_refresh_pending',true,
    'cleaning_scenario_materialization',v_cleaning_scenarios
  );
end
$$;
