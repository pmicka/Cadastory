-- Scout OSM access snapshot finalization v2.
-- Adds durable checkpoints, immutable per-import membership, atomic activation,
-- and a bounded/idempotent finalizer. Historical data backfills are not part
-- of this migration; production incident telemetry is handled separately.

alter table decisioning.site_access_snapshot_imports
  add column if not exists finalization_phase text,
  add column if not exists finalization_cursor uuid,
  add column if not exists finalization_processed_count integer not null default 0,
  add column if not exists finalization_requeued_count integer not null default 0,
  add column if not exists finalization_started_at timestamptz,
  add column if not exists finalization_completed_at timestamptz,
  add column if not exists finalization_last_attempted_at timestamptz,
  add column if not exists finalization_error_code text,
  add column if not exists finalization_error_text text,
  add column if not exists submitted_count integer,
  add column if not exists accepted_count integer,
  add column if not exists deduplicated_count integer,
  add column if not exists skipped_count integer,
  add column if not exists skip_counts jsonb not null default '{}'::jsonb;

alter table decisioning.site_access_snapshot_imports
  drop constraint if exists site_access_snapshot_imports_status_check;
alter table decisioning.site_access_snapshot_imports
  add constraint site_access_snapshot_imports_status_check
  check (status in ('loading','finalizing','complete','failed','superseded'));

alter table decisioning.site_access_snapshot_imports
  drop constraint if exists site_access_snapshot_imports_finalization_phase_check;
alter table decisioning.site_access_snapshot_imports
  add constraint site_access_snapshot_imports_finalization_phase_check
  check (finalization_phase is null or finalization_phase in (
    'normalizing','materializing','validating','activating','requeueing','complete'
  ));

alter table decisioning.site_access_snapshot_imports
  drop constraint if exists site_access_snapshot_imports_finalization_counts_check;
alter table decisioning.site_access_snapshot_imports
  add constraint site_access_snapshot_imports_finalization_counts_check check (
    finalization_processed_count>=0 and finalization_requeued_count>=0
    and (submitted_count is null or submitted_count>=0)
    and (accepted_count is null or accepted_count>=0)
    and (deduplicated_count is null or deduplicated_count>=0)
    and (skipped_count is null or skipped_count>=0)
  );

drop index if exists decisioning.site_access_snapshot_imports_one_loading_idx;
create unique index if not exists site_access_snapshot_imports_one_inflight_idx
  on decisioning.site_access_snapshot_imports(region_slug)
  where status in ('loading','finalizing');

create index if not exists site_access_snapshot_feature_regions_import_region_feature_idx
  on decisioning.site_access_snapshot_feature_regions(last_seen_import_id,region_slug,feature_id);

create table if not exists decisioning.site_access_snapshot_import_features (
  import_id uuid not null references decisioning.site_access_snapshot_imports(id) on delete cascade,
  region_slug text not null references decisioning.site_access_snapshot_regions(region_slug) on delete cascade,
  feature_id uuid not null references decisioning.site_access_features(id) on delete cascade,
  feature_class text not null,
  created_at timestamptz not null default now(),
  primary key(import_id,feature_id)
);
create index if not exists site_access_snapshot_import_features_region_import_idx
  on decisioning.site_access_snapshot_import_features(region_slug,import_id,feature_id);
create index if not exists site_access_snapshot_import_features_feature_idx
  on decisioning.site_access_snapshot_import_features(feature_id,import_id);
alter table decisioning.site_access_snapshot_import_features enable row level security;
revoke all on table decisioning.site_access_snapshot_import_features from public,anon,authenticated;

create or replace function public.internal_finish_site_access_snapshot_import_step(
  p_import_id uuid,
  p_batch_size integer default 5000,
  p_attributes jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  im decisioning.site_access_snapshot_imports%rowtype;
  rg decisioning.site_access_snapshot_regions%rowtype;
  v_selected integer:=0; v_inserted integer:=0; v_last uuid;
  v_count integer:=0; v_counts jsonb:='{}'::jsonb;
  v_requeued integer:=0; v_total_requeue integer:=0; v_dedup integer:=0;
  v_cleanup_state text;
begin
  if p_batch_size is null or p_batch_size<1 or p_batch_size>20000 then
    raise exception 'p_batch_size must be between 1 and 20000';
  end if;

  select * into im from decisioning.site_access_snapshot_imports where id=p_import_id;
  if not found then raise exception 'snapshot import not found'; end if;

  if im.status='complete' and im.finalization_phase='complete' then
    return jsonb_build_object(
      'ok',true,'complete',true,'no_op',true,'import_id',im.id,
      'region_slug',im.region_slug,'phase','complete','feature_count',im.feature_count,
      'submitted',im.submitted_count,'accepted',im.accepted_count,
      'deduplicated',im.deduplicated_count,'skipped',im.skipped_count,
      'skip_counts',im.skip_counts,'requeued',im.finalization_requeued_count
    );
  end if;

  if im.status not in ('loading','finalizing') then
    raise exception 'snapshot import % is not resumable from status %',im.id,im.status;
  end if;

  if not pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended('site_access_snapshot_finalizer:'||im.region_slug,0)
  ) then
    return jsonb_build_object(
      'ok',true,'complete',false,'already_finalizing',true,
      'import_id',im.id,'region_slug',im.region_slug,
      'phase',coalesce(im.finalization_phase,'normalizing')
    );
  end if;

  select * into im from decisioning.site_access_snapshot_imports
   where id=p_import_id for update;
  select * into rg from decisioning.site_access_snapshot_regions
   where region_slug=im.region_slug for update;

  if exists(
    select 1 from decisioning.site_access_snapshot_imports newer
    where newer.region_slug=im.region_slug
      and newer.started_at>im.started_at
      and newer.status in ('loading','finalizing','complete')
  ) then
    update decisioning.site_access_snapshot_imports
       set status='superseded',completed_at=now(),
           finalization_error_code='newer_import_exists',
           finalization_error_text='A newer import exists for this region.',
           finalization_last_attempted_at=now()
     where id=im.id;
    return jsonb_build_object(
      'ok',true,'complete',false,'superseded',true,
      'import_id',im.id,'region_slug',im.region_slug
    );
  end if;

  if im.status='loading' then
    update decisioning.site_access_snapshot_imports
       set status='finalizing',
           finalization_phase=coalesce(finalization_phase,'normalizing'),
           finalization_started_at=coalesce(finalization_started_at,now()),
           finalization_last_attempted_at=now(),
           finalization_error_code=null,finalization_error_text=null,
           attributes=coalesce(attributes,'{}'::jsonb)||coalesce(p_attributes,'{}'::jsonb)
     where id=im.id;
    im.status:='finalizing';
    im.finalization_phase:=coalesce(im.finalization_phase,'normalizing');
  end if;

  if im.finalization_phase is null then
    update decisioning.site_access_snapshot_imports
       set finalization_phase='normalizing',
           finalization_started_at=coalesce(finalization_started_at,now())
     where id=im.id;
    im.finalization_phase:='normalizing';
  end if;

  if im.finalization_phase='normalizing' then
    with selected as (
      select fr.feature_id,f.feature_class
      from decisioning.site_access_snapshot_feature_regions fr
      join decisioning.site_access_features f on f.id=fr.feature_id
      where fr.region_slug=im.region_slug
        and fr.last_seen_import_id=im.id
        and (im.finalization_cursor is null or fr.feature_id>im.finalization_cursor)
      order by fr.feature_id
      limit p_batch_size
    ), ins as (
      insert into decisioning.site_access_snapshot_import_features(
        import_id,region_slug,feature_id,feature_class
      )
      select im.id,im.region_slug,s.feature_id,s.feature_class from selected s
      on conflict(import_id,feature_id) do update set feature_class=excluded.feature_class
      returning feature_id
    )
    select (select count(*)::integer from selected),
           (select count(*)::integer from ins),
           (select feature_id from selected order by feature_id desc limit 1)
      into v_selected,v_inserted,v_last;

    if v_selected>0 then
      update decisioning.site_access_snapshot_imports
         set finalization_cursor=v_last,
             finalization_processed_count=finalization_processed_count+v_selected,
             finalization_last_attempted_at=now(),
             finalization_error_code=null,finalization_error_text=null
       where id=im.id;
      return jsonb_build_object(
        'ok',true,'complete',false,'import_id',im.id,'region_slug',im.region_slug,
        'phase','normalizing','batch_processed',v_selected,
        'batch_materialized',v_inserted,
        'total_processed',im.finalization_processed_count+v_selected,'has_more',true
      );
    end if;

    select coalesce(sum(n),0)::integer,
           coalesce(jsonb_object_agg(feature_class,n),'{}'::jsonb)
      into v_count,v_counts
    from (
      select feature_class,count(*)::integer n
      from decisioning.site_access_snapshot_import_features
      where import_id=im.id
      group by feature_class
    ) x;

    update decisioning.site_access_snapshot_imports
       set feature_count=v_count,class_counts=v_counts,
           finalization_phase='materializing',finalization_cursor=null,
           finalization_last_attempted_at=now()
     where id=im.id;
    return jsonb_build_object(
      'ok',true,'complete',false,'import_id',im.id,'region_slug',im.region_slug,
      'phase','materializing','feature_count',v_count,'class_counts',v_counts,
      'has_more',true
    );
  end if;

  if im.finalization_phase='materializing' then
    update decisioning.site_access_snapshot_imports
       set finalization_phase='validating',finalization_last_attempted_at=now()
     where id=im.id;
    return jsonb_build_object(
      'ok',true,'complete',false,'import_id',im.id,'region_slug',im.region_slug,
      'phase','validating','has_more',true
    );
  end if;

  if im.finalization_phase='validating' then
    select count(*)::integer into v_count
    from decisioning.site_access_snapshot_import_features where import_id=im.id;
    if v_count<>im.feature_count then
      raise exception 'snapshot validation failed: materialized count % differs from recorded count %',v_count,im.feature_count;
    end if;
    if im.accepted_count is not null and im.accepted_count<v_count then
      raise exception 'snapshot validation failed: accepted count % is below canonical count %',im.accepted_count,v_count;
    end if;
    if im.submitted_count is not null and im.accepted_count is not null
       and im.skipped_count is not null
       and im.submitted_count<>(im.accepted_count+im.skipped_count) then
      raise exception 'snapshot validation failed: submitted % != accepted % + skipped %',im.submitted_count,im.accepted_count,im.skipped_count;
    end if;
    if im.accepted_count is not null then
      v_dedup:=greatest(im.accepted_count-v_count,0);
    else
      v_dedup:=coalesce(im.deduplicated_count,0);
    end if;
    update decisioning.site_access_snapshot_imports
       set deduplicated_count=v_dedup,
           finalization_phase='activating',finalization_last_attempted_at=now()
     where id=im.id;
    return jsonb_build_object(
      'ok',true,'complete',false,'import_id',im.id,'region_slug',im.region_slug,
      'phase','activating','submitted',im.submitted_count,'accepted',im.accepted_count,
      'deduplicated',v_dedup,'skipped',im.skipped_count,'canonical',v_count,
      'skip_counts',im.skip_counts,'has_more',true
    );
  end if;

  if im.finalization_phase='activating' then
    insert into decisioning.site_access_snapshot_cleanup_jobs(
      import_id,region_slug,state,created_at,updated_at
    ) values(im.id,im.region_slug,'pending',now(),now())
    on conflict(import_id) do update
      set region_slug=excluded.region_slug,
          state=case when decisioning.site_access_snapshot_cleanup_jobs.state='complete'
                     then 'complete' else 'pending' end,
          last_error=null,updated_at=now();

    update decisioning.site_access_snapshot_regions
       set status='ready',current_source_timestamp=im.source_timestamp,
           last_imported_at=now(),last_successful_import_id=im.id,
           last_feature_count=im.feature_count,updated_at=now()
     where region_slug=im.region_slug;

    update decisioning.site_access_snapshot_imports
       set finalization_phase='requeueing',finalization_last_attempted_at=now(),
           attributes=coalesce(attributes,'{}'::jsonb)||jsonb_build_object(
             'negative_evidence_allowed',false,
             'snapshot_cleanup_state','pending','activated_at',now()
           )
     where id=im.id;
    return jsonb_build_object(
      'ok',true,'complete',false,'import_id',im.id,'region_slug',im.region_slug,
      'phase','requeueing','activated',true,'feature_count',im.feature_count,
      'has_more',true
    );
  end if;

  if im.finalization_phase='requeueing' then
    with selected as (
      select q.id
      from decisioning.site_access_queue q
      where q.state='blocked'
        and q.request_reason='awaiting_local_snapshot'
        and coalesce(q.source_context->>'blocked_reason','')='awaiting_local_snapshot'
        and decisioning.site_access_target_state_code(q.target_key)=rg.state_code
      order by q.created_at,q.id
      limit p_batch_size
      for update skip locked
    ), upd as (
      update decisioning.site_access_queue q
         set state='pending',request_reason='local_snapshot_available',
             next_attempt_at=now(),claimed_at=null,completed_at=null,last_error=null,
             source_context=(coalesce(q.source_context,'{}'::jsonb)-'blocked_reason')
               ||jsonb_build_object(
                 'snapshot_requeued_at',now(),'snapshot_region',im.region_slug,
                 'snapshot_import_id',im.id
               ),
             updated_at=now()
      from selected s where q.id=s.id
      returning q.id
    )
    select count(*)::integer into v_requeued from upd;

    update decisioning.site_access_snapshot_imports
       set finalization_requeued_count=finalization_requeued_count+v_requeued,
           finalization_last_attempted_at=now()
     where id=im.id;
    if v_requeued>0 then
      return jsonb_build_object(
        'ok',true,'complete',false,'import_id',im.id,'region_slug',im.region_slug,
        'phase','requeueing','batch_requeued',v_requeued,
        'total_requeued',im.finalization_requeued_count+v_requeued,'has_more',true
      );
    end if;

    select state into v_cleanup_state
    from decisioning.site_access_snapshot_cleanup_jobs where import_id=im.id;
    update decisioning.site_access_snapshot_imports
       set status='complete',completed_at=now(),finalization_phase='complete',
           finalization_completed_at=now(),finalization_last_attempted_at=now(),
           finalization_error_code=null,finalization_error_text=null
     where id=im.id;
    select finalization_requeued_count into v_total_requeue
    from decisioning.site_access_snapshot_imports where id=im.id;

    return jsonb_build_object(
      'ok',true,'complete',true,'import_id',im.id,'region_slug',im.region_slug,
      'phase','complete','feature_count',im.feature_count,'class_counts',im.class_counts,
      'submitted',im.submitted_count,'accepted',im.accepted_count,
      'deduplicated',im.deduplicated_count,'skipped',im.skipped_count,
      'skip_counts',im.skip_counts,'requeued',v_total_requeue,
      'cleanup_state',coalesce(v_cleanup_state,'pending'),'link_refresh_pending',true
    );
  end if;

  raise exception 'unexpected snapshot finalization phase % for import %',im.finalization_phase,im.id;
end
$function$;

create or replace function public.internal_finish_site_access_snapshot_import(
  p_import_id uuid,
  p_attributes jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  return public.internal_finish_site_access_snapshot_import_step(
    p_import_id,2000,p_attributes
  );
end
$function$;

create or replace function public.internal_resume_latest_site_access_snapshot_import(
  p_region_slug text,
  p_attributes jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  im decisioning.site_access_snapshot_imports%rowtype;
  rg decisioning.site_access_snapshot_regions%rowtype;
begin
  select i.* into im
  from decisioning.site_access_snapshot_imports i
  where i.region_slug=lower(btrim(p_region_slug))
    and (
      i.status='finalizing'
      or (
        i.status='failed'
        and coalesce(i.error_text,'') ilike '%internal_finish_site_access_snapshot_import%'
        and coalesce(i.error_text,'') ilike '%statement timeout%'
      )
    )
    and exists (
      select 1 from decisioning.site_access_snapshot_feature_regions fr
      where fr.region_slug=i.region_slug and fr.last_seen_import_id=i.id
    )
  order by i.started_at desc limit 1 for update;

  if not found then
    raise exception 'no resumable finalizer import found for region %',lower(btrim(p_region_slug));
  end if;
  if exists(
    select 1 from decisioning.site_access_snapshot_imports newer
    where newer.region_slug=im.region_slug and newer.started_at>im.started_at
  ) then
    raise exception 'resumable import % is no longer the latest import for region %',im.id,im.region_slug;
  end if;

  select * into rg from decisioning.site_access_snapshot_regions
   where region_slug=im.region_slug for update;
  update decisioning.site_access_snapshot_imports
     set status='finalizing',completed_at=null,error_text=null,
         finalization_phase=coalesce(finalization_phase,'normalizing'),
         finalization_started_at=coalesce(finalization_started_at,now()),
         finalization_last_attempted_at=now(),
         finalization_error_code=null,finalization_error_text=null,
         attributes=coalesce(attributes,'{}'::jsonb)||coalesce(p_attributes,'{}'::jsonb)
           ||jsonb_build_object('recovered_from_finalizer_timeout_at',now())
   where id=im.id;

  if rg.last_successful_import_id is null then
    update decisioning.site_access_snapshot_regions
       set status='loading',updated_at=now() where region_slug=im.region_slug;
  else
    update decisioning.site_access_snapshot_regions
       set status='ready',updated_at=now() where region_slug=im.region_slug;
  end if;

  return jsonb_build_object(
    'ok',true,'import_id',im.id,'region_slug',im.region_slug,
    'status','finalizing','phase',coalesce(im.finalization_phase,'normalizing'),
    'previous_active_import_id',rg.last_successful_import_id,'resume_ready',true
  );
end
$function$;

revoke all on function public.internal_finish_site_access_snapshot_import_step(uuid,integer,jsonb)
  from public,anon,authenticated;
revoke all on function public.internal_finish_site_access_snapshot_import(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function public.internal_resume_latest_site_access_snapshot_import(text,jsonb)
  from public,anon,authenticated;
grant execute on function public.internal_finish_site_access_snapshot_import_step(uuid,integer,jsonb)
  to postgres,service_role;
grant execute on function public.internal_finish_site_access_snapshot_import(uuid,jsonb)
  to postgres,service_role;
grant execute on function public.internal_resume_latest_site_access_snapshot_import(text,jsonb)
  to postgres,service_role;
