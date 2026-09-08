-- Bounded local-snapshot site-access queue worker.
--
-- The Geofabrik access snapshots are already loaded regionally. Do not use the
-- expensive all-target refresh as the normal cron path; it attempts to link
-- every operational target in one statement and can hit statement_timeout.
-- Instead, drain decisioning.site_access_queue in small batches from the local
-- PostGIS snapshot. External Overpass-compatible providers remain exception
-- paths only.

create or replace function decisioning.process_site_access_queue_from_snapshot(
  p_limit integer default 25,
  p_target_types text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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
begin
  v_limit := coalesce(p_limit, 25);
  if v_limit < 1 or v_limit > 250 then
    raise exception 'p_limit must be between 1 and 250';
  end if;

  if not v_snapshot_ready then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'local_snapshot_not_ready',
      'selected', 0,
      'completed', 0,
      'failed', 0
    );
  end if;

  if not pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended('decisioning.process_site_access_queue_from_snapshot', 0)
  ) then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'worker_already_running',
      'selected', 0,
      'completed', 0,
      'failed', 0
    );
  end if;

  for rec in
    with selected as (
      select q.id, q.target_key, q.target_type
      from decisioning.site_access_queue q
      where q.state in ('pending', 'failed')
        and q.next_attempt_at <= now()
        and (p_target_types is null or q.target_type = any(p_target_types))
      order by q.priority desc, q.created_at, q.id
      limit v_limit
      for update skip locked
    ), claimed as (
      update decisioning.site_access_queue q
         set state = 'processing',
             claimed_at = now(),
             attempt_count = attempt_count + 1,
             last_error = null,
             source_context = coalesce(q.source_context, '{}'::jsonb)
               || jsonb_build_object('local_snapshot_worker_claimed_at', now()),
             updated_at = now()
      from selected s
      where q.id = s.id
      returning q.id, q.target_key, q.target_type
    )
    select * from claimed
  loop
    v_selected := v_selected + 1;

    begin
      v_result := decisioning.resolve_site_access_target_from_snapshot(
        rec.target_key,
        'local_snapshot_queue_worker'
      );

      if coalesce((v_result->>'ok')::boolean, false)
         and coalesce((v_result->>'resolved')::boolean, false) then
        update decisioning.site_access_queue q
           set state = 'complete',
               completed_at = now(),
               claimed_at = null,
               last_error = null,
               source_context = coalesce(q.source_context, '{}'::jsonb)
                 || jsonb_build_object(
                   'resolved_from', 'local_snapshot',
                   'local_snapshot_worker_completed_at', now(),
                   'last_source_timestamp', v_result->>'source_timestamp',
                   'last_feature_count', coalesce((v_result->>'feature_count')::integer, 0),
                   'negative_evidence_allowed', false
                 ),
               updated_at = now()
         where q.id = rec.id;
        v_completed := v_completed + 1;
      else
        v_reason := coalesce(v_result->>'reason', 'unresolved_without_reason');

        update decisioning.site_access_queue q
           set state = 'failed',
               claimed_at = null,
               completed_at = null,
               last_error = left(v_reason, 1000),
               next_attempt_at = case
                 when v_reason = 'target_missing_or_no_geometry' then now() + interval '30 days'
                 else now() + interval '1 day'
               end,
               source_context = coalesce(q.source_context, '{}'::jsonb)
                 || jsonb_build_object(
                   'local_snapshot_worker_failed_at', now(),
                   'local_snapshot_worker_reason', v_reason,
                   'negative_evidence_allowed', false
                 ),
               updated_at = now()
         where q.id = rec.id;
        v_failed := v_failed + 1;
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'target_key', rec.target_key,
          'reason', v_reason
        ));
      end if;
    exception when others then
      v_error_text := left(SQLSTATE || ': ' || SQLERRM, 1000);

      update decisioning.site_access_queue q
         set state = 'failed',
             claimed_at = null,
             completed_at = null,
             last_error = v_error_text,
             next_attempt_at = now() + interval '1 day',
             source_context = coalesce(q.source_context, '{}'::jsonb)
               || jsonb_build_object(
                 'local_snapshot_worker_failed_at', now(),
                 'local_snapshot_worker_error_code', SQLSTATE,
                 'negative_evidence_allowed', false
               ),
             updated_at = now()
       where q.id = rec.id;
      v_failed := v_failed + 1;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'target_key', rec.target_key,
        'error', v_error_text
      ));
    end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'snapshot_ready', v_snapshot_ready,
    'selected', v_selected,
    'completed', v_completed,
    'failed', v_failed,
    'limit', v_limit,
    'target_types', coalesce(to_jsonb(p_target_types), 'null'::jsonb),
    'started_at', v_started_at,
    'completed_at', now(),
    'errors', v_errors,
    'negative_evidence_allowed', false
  );
end
$function$;

revoke all on function decisioning.process_site_access_queue_from_snapshot(integer, text[])
  from public, anon, authenticated;
grant execute on function decisioning.process_site_access_queue_from_snapshot(integer, text[])
  to postgres, service_role;

create or replace function decisioning.refresh_site_access_queue()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_blocked integer := 0;
  v_ready integer := 0;
  v_snapshot boolean := decisioning.snapshot_access_ready();
  v_worker jsonb := null;
begin
  if not v_snapshot then
    update decisioning.site_access_queue
       set state = 'blocked',
           request_reason = 'awaiting_local_snapshot',
           next_attempt_at = now() + interval '365 days',
           source_context = coalesce(source_context, '{}'::jsonb)
             || jsonb_build_object('blocked_reason', 'awaiting_local_snapshot', 'snapshot_first', true),
           updated_at = now()
     where state in ('pending', 'failed')
       and not coalesce((source_context->>'jit')::boolean, false)
       and request_reason not ilike '%job%'
       and request_reason not ilike '%jit%';
    get diagnostics v_blocked = row_count;
  end if;

  select count(*) into v_ready
  from decisioning.site_access_queue
  where state in ('pending', 'failed')
    and next_attempt_at <= now();

  if v_snapshot and v_ready > 0 then
    v_worker := decisioning.process_site_access_queue_from_snapshot(50, null);

    select count(*) into v_ready
    from decisioning.site_access_queue
    where state in ('pending', 'failed')
      and next_attempt_at <= now();
  end if;

  return jsonb_build_object(
    'refreshed_at', now(),
    'snapshot_ready', v_snapshot,
    'blocked_awaiting_snapshot', v_blocked,
    'provider_exception_work_ready', v_ready,
    'local_snapshot_worker', v_worker,
    'policy', 'local_snapshot_first_v2_bounded_queue_worker',
    'routine_stale_provider_polling', false
  );
end
$function$;

create or replace function decisioning.refresh_due_site_access_snapshot_links()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_pending integer := 0;
  v_bulk_target_count integer := 0;
begin
  if not decisioning.snapshot_access_ready() then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'snapshot_not_ready');
  end if;

  select count(*) into v_pending
  from decisioning.site_access_queue
  where state in ('pending', 'failed')
    and next_attempt_at <= now();

  if v_pending > 0 then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'bounded_queue_worker_active_elsewhere',
      'pending_queue_work', v_pending,
      'bulk_link_refresh_deferred', true,
      'negative_evidence_allowed', false
    );
  end if;

  if not exists(
    select 1
    from decisioning.site_access_snapshot_regions
    where enabled
      and last_linked_import_id is distinct from last_successful_import_id
  ) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'snapshot_links_current');
  end if;

  select count(*) into v_bulk_target_count
  from decisioning.v_operational_targets
  where geometry is not null;

  return jsonb_build_object(
    'ok', true,
    'skipped', true,
    'reason', 'bulk_link_refresh_disabled_pending_bounded_design',
    'bulk_target_count', v_bulk_target_count,
    'bulk_link_refresh_deferred', true,
    'negative_evidence_allowed', false
  );
end
$function$;
