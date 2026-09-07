-- Make OSM snapshot finalization bounded and recoverable.
--
-- The row-by-row ingest RPCs are already independent transactions.  This
-- migration keeps finalization short, moves deletion work into resumable
-- batches, and only exposes the new control RPCs to service_role.

create table if not exists decisioning.site_access_snapshot_cleanup_jobs (
  import_id uuid primary key
    references decisioning.site_access_snapshot_imports(id) on delete cascade,
  region_slug text not null
    references decisioning.site_access_snapshot_regions(region_slug) on delete cascade,
  state text not null default 'pending'
    check (state in ('pending', 'pruning', 'orphan_cleanup', 'complete', 'superseded')),
  removed_memberships integer not null default 0 check (removed_memberships >= 0),
  deleted_orphan_features integer not null default 0 check (deleted_orphan_features >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists site_access_snapshot_cleanup_jobs_state_idx
  on decisioning.site_access_snapshot_cleanup_jobs(state, updated_at);

create table if not exists decisioning.site_access_snapshot_cleanup_candidates (
  import_id uuid not null
    references decisioning.site_access_snapshot_cleanup_jobs(import_id) on delete cascade,
  feature_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (import_id, feature_id)
);

alter table decisioning.site_access_snapshot_cleanup_jobs enable row level security;
alter table decisioning.site_access_snapshot_cleanup_candidates enable row level security;

revoke all on table decisioning.site_access_snapshot_cleanup_jobs
  from public, anon, authenticated;
revoke all on table decisioning.site_access_snapshot_cleanup_candidates
  from public, anon, authenticated;

create or replace function decisioning.snapshot_access_ready()
returns boolean
language sql
stable
set search_path to ''
as $function$
  select count(*) filter(where r.enabled)>0
     and bool_and(
       r.status='ready'
       and r.last_successful_import_id is not null
       and r.current_source_timestamp is not null
       and not exists (
         select 1
         from decisioning.site_access_snapshot_cleanup_jobs j
         where j.import_id=r.last_successful_import_id
           and j.state<>'complete'
       )
     )
  from decisioning.site_access_snapshot_regions r
  where r.enabled;
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
declare
  im decisioning.site_access_snapshot_imports%rowtype;
  v_count integer:=0;
  v_counts jsonb:='{}'::jsonb;
begin
  select *
    into im
    from decisioning.site_access_snapshot_imports
   where id=p_import_id
     and status='loading'
   for update;

  if not found then
    raise exception 'loading snapshot import not found';
  end if;

  select coalesce(sum(n),0)::integer,
         coalesce(jsonb_object_agg(feature_class,n),'{}'::jsonb)
    into v_count,v_counts
    from (
      select f.feature_class,count(*)::integer n
      from decisioning.site_access_snapshot_feature_regions fr
      join decisioning.site_access_features f on f.id=fr.feature_id
      where fr.region_slug=im.region_slug
        and fr.last_seen_import_id=im.id
      group by f.feature_class
    ) x;

  insert into decisioning.site_access_snapshot_cleanup_jobs(
    import_id,region_slug,state,created_at,updated_at
  )
  values(im.id,im.region_slug,'pending',now(),now())
  on conflict(import_id) do update
    set region_slug=excluded.region_slug,
        state=case
          when decisioning.site_access_snapshot_cleanup_jobs.state='complete'
            then 'complete'
          else 'pending'
        end,
        last_error=null,
        updated_at=now();

  update decisioning.site_access_snapshot_imports
     set status='complete',
         feature_count=coalesce(v_count,0),
         class_counts=coalesce(v_counts,'{}'::jsonb),
         completed_at=now(),
         attributes=coalesce(attributes,'{}'::jsonb)
           || coalesce(p_attributes,'{}'::jsonb)
           || jsonb_build_object(
             'negative_evidence_allowed',false,
             'snapshot_cleanup_state','pending'
           )
   where id=im.id;

  update decisioning.site_access_snapshot_regions
     set status='ready',
         current_source_timestamp=im.source_timestamp,
         last_imported_at=now(),
         last_successful_import_id=im.id,
         last_feature_count=coalesce(v_count,0),
         updated_at=now()
   where region_slug=im.region_slug;

  return jsonb_build_object(
    'ok',true,
    'import_id',im.id,
    'region_slug',im.region_slug,
    'feature_count',coalesce(v_count,0),
    'class_counts',coalesce(v_counts,'{}'::jsonb),
    'cleanup_state','pending',
    'cleanup_pending',true,
    'link_refresh_pending',true
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
begin
  select i.*
    into im
    from decisioning.site_access_snapshot_imports i
   where i.region_slug=lower(btrim(p_region_slug))
     and i.status='failed'
     and coalesce(i.error_text,'') ilike '%internal_finish_site_access_snapshot_import%'
     and coalesce(i.error_text,'') ilike '%statement timeout%'
     and exists (
       select 1
       from decisioning.site_access_snapshot_feature_regions fr
       where fr.region_slug=i.region_slug
         and fr.last_seen_import_id=i.id
     )
   order by i.started_at desc
   limit 1
   for update;

  if not found then
    raise exception 'no resumable finalizer-timeout import found for region %',lower(btrim(p_region_slug));
  end if;

  if exists (
    select 1
    from decisioning.site_access_snapshot_imports newer
    where newer.region_slug=im.region_slug
      and newer.started_at>im.started_at
  ) then
    raise exception 'resumable import % is no longer the latest import for region %',
      im.id,im.region_slug;
  end if;

  if exists (
    select 1
    from decisioning.site_access_snapshot_imports active
    where active.region_slug=im.region_slug
      and active.status='loading'
      and active.id<>im.id
  ) then
    raise exception 'another snapshot import is loading for region %',im.region_slug;
  end if;

  update decisioning.site_access_snapshot_imports
     set status='loading',
         completed_at=null,
         error_text=null,
         attributes=coalesce(attributes,'{}'::jsonb)
           || coalesce(p_attributes,'{}'::jsonb)
           || jsonb_build_object(
             'recovered_from_finalizer_timeout_at',now()
           )
   where id=im.id;

  update decisioning.site_access_snapshot_regions
     set status='loading',
         updated_at=now()
   where region_slug=im.region_slug;

  return public.internal_finish_site_access_snapshot_import(
    im.id,
    jsonb_build_object('recovered_from_finalizer_timeout',true)
  );
end
$function$;

create or replace function public.internal_process_site_access_snapshot_cleanup(
  p_import_id uuid,
  p_batch_size integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  j decisioning.site_access_snapshot_cleanup_jobs%rowtype;
  im decisioning.site_access_snapshot_imports%rowtype;
  rg decisioning.site_access_snapshot_regions%rowtype;
  v_source_id uuid;
  v_removed integer:=0;
  v_deleted integer:=0;
  v_retired integer:=0;
  v_has_more boolean:=false;
begin
  if p_batch_size is null or p_batch_size<1 or p_batch_size>5000 then
    raise exception 'p_batch_size must be between 1 and 5000';
  end if;

  select *
    into j
    from decisioning.site_access_snapshot_cleanup_jobs
   where import_id=p_import_id
   for update;

  if not found then
    raise exception 'snapshot cleanup job not found for import %',p_import_id;
  end if;

  if j.state in ('complete','superseded') then
    return jsonb_build_object(
      'ok',true,
      'import_id',j.import_id,
      'region_slug',j.region_slug,
      'state',j.state,
      'complete',j.state='complete',
      'skipped',j.state='superseded'
    );
  end if;

  select *
    into im
    from decisioning.site_access_snapshot_imports
   where id=j.import_id
   for update;

  select *
    into rg
    from decisioning.site_access_snapshot_regions
   where region_slug=j.region_slug
   for update;

  if exists (
    select 1
    from decisioning.site_access_snapshot_imports active
    where active.region_slug=j.region_slug
      and active.status='loading'
      and active.id<>j.import_id
  ) then
    update decisioning.site_access_snapshot_cleanup_jobs
       set state='pending',
           last_error='deferred while a newer import is loading',
           updated_at=now()
     where import_id=j.import_id;

    return jsonb_build_object(
      'ok',true,
      'import_id',j.import_id,
      'region_slug',j.region_slug,
      'state','pending',
      'skipped',true,
      'reason','newer_import_loading'
    );
  end if;

  if rg.last_successful_import_id is distinct from j.import_id then
    update decisioning.site_access_snapshot_cleanup_jobs
       set state='superseded',
           completed_at=now(),
           last_error=null,
           updated_at=now()
     where import_id=j.import_id;

    return jsonb_build_object(
      'ok',true,
      'import_id',j.import_id,
      'region_slug',j.region_slug,
      'state','superseded',
      'complete',false,
      'skipped',true,
      'reason','newer_import_complete'
    );
  end if;

  select id
    into v_source_id
    from ingest.sources
   where slug='openstreetmap-geofabrik-access-snapshot';

  if v_source_id is null then
    raise exception 'snapshot source missing';
  end if;

  if j.state in ('pending','pruning') then
    with removed as (
      delete from decisioning.site_access_snapshot_feature_regions fr
       where fr.ctid in (
         select stale.ctid
         from decisioning.site_access_snapshot_feature_regions stale
         where stale.region_slug=j.region_slug
           and stale.last_seen_import_id<>j.import_id
         order by stale.feature_id
         limit p_batch_size
       )
       returning fr.feature_id
    ),
    queued as (
      insert into decisioning.site_access_snapshot_cleanup_candidates(import_id,feature_id)
      select j.import_id,feature_id
      from removed
      on conflict(import_id,feature_id) do nothing
    )
    select count(*)::integer
      into v_removed
      from removed;

    update decisioning.site_access_snapshot_cleanup_jobs
       set state='pruning',
           removed_memberships=removed_memberships+v_removed,
           started_at=coalesce(started_at,now()),
           last_error=null,
           updated_at=now()
     where import_id=j.import_id;

    if v_removed>0 then
      return jsonb_build_object(
        'ok',true,
        'import_id',j.import_id,
        'region_slug',j.region_slug,
        'state','pruning',
        'removed_memberships_in_batch',v_removed,
        'removed_memberships_total',j.removed_memberships+v_removed,
        'has_more',true
      );
    end if;

    if j.removed_memberships=0 then
      update decisioning.site_access_snapshot_cleanup_jobs
         set state='complete',
             completed_at=now(),
             last_error=null,
             updated_at=now()
       where import_id=j.import_id;

      update decisioning.site_access_snapshot_imports
         set attributes=coalesce(attributes,'{}'::jsonb)
           || jsonb_build_object(
             'snapshot_cleanup_state','complete',
             'snapshot_cleanup_completed_at',now()
           )
       where id=j.import_id;

      return jsonb_build_object(
        'ok',true,
        'import_id',j.import_id,
        'region_slug',j.region_slug,
        'state','complete',
        'complete',true,
        'removed_memberships_total',0,
        'deleted_orphan_features_total',0
      );
    end if;

    update decisioning.site_access_snapshot_cleanup_jobs
       set state='orphan_cleanup',
           updated_at=now()
     where import_id=j.import_id;

    return jsonb_build_object(
      'ok',true,
      'import_id',j.import_id,
      'region_slug',j.region_slug,
      'state','orphan_cleanup',
      'removed_memberships_total',j.removed_memberships,
      'has_more',true
    );
  end if;

  if j.state='orphan_cleanup' then
    with selected as (
      select c.import_id,c.feature_id
      from decisioning.site_access_snapshot_cleanup_candidates c
      where c.import_id=j.import_id
      order by c.feature_id
      limit p_batch_size
      for update skip locked
    ),
    deleted as (
      delete from decisioning.site_access_features f
      using selected s
      where f.id=s.feature_id
        and f.source_id=v_source_id
        and not exists (
          select 1
          from decisioning.site_access_snapshot_feature_regions fr
          where fr.feature_id=f.id
        )
      returning f.id
    ),
    retired as (
      delete from decisioning.site_access_snapshot_cleanup_candidates c
      using selected s
      where c.import_id=s.import_id
        and c.feature_id=s.feature_id
      returning c.feature_id
    )
    select
      (select count(*)::integer from deleted),
      (select count(*)::integer from retired)
      into v_deleted,v_retired;

    update decisioning.site_access_snapshot_cleanup_jobs
       set deleted_orphan_features=deleted_orphan_features+v_deleted,
           last_error=null,
           updated_at=now()
     where import_id=j.import_id;

    select exists (
      select 1
      from decisioning.site_access_snapshot_cleanup_candidates
      where import_id=j.import_id
    )
    into v_has_more;

    if not v_has_more then
      update decisioning.site_access_snapshot_cleanup_jobs
         set state='complete',
             completed_at=now(),
             updated_at=now()
       where import_id=j.import_id;

      update decisioning.site_access_snapshot_imports
         set attributes=coalesce(attributes,'{}'::jsonb)
           || jsonb_build_object(
             'snapshot_cleanup_state','complete',
             'snapshot_cleanup_completed_at',now()
           )
       where id=j.import_id;

      return jsonb_build_object(
        'ok',true,
        'import_id',j.import_id,
        'region_slug',j.region_slug,
        'state','complete',
        'complete',true,
        'removed_memberships_total',j.removed_memberships,
        'deleted_orphan_features_in_batch',v_deleted,
        'deleted_orphan_features_total',j.deleted_orphan_features+v_deleted
      );
    end if;

    return jsonb_build_object(
      'ok',true,
      'import_id',j.import_id,
      'region_slug',j.region_slug,
      'state','orphan_cleanup',
      'candidate_features_processed',v_retired,
      'deleted_orphan_features_in_batch',v_deleted,
      'deleted_orphan_features_total',j.deleted_orphan_features+v_deleted,
      'has_more',true
    );
  end if;

  raise exception 'unexpected snapshot cleanup state % for import %',j.state,j.import_id;
end
$function$;

revoke all on function public.internal_finish_site_access_snapshot_import(uuid,jsonb)
  from public, anon, authenticated;
revoke all on function public.internal_resume_latest_site_access_snapshot_import(text,jsonb)
  from public, anon, authenticated;
revoke all on function public.internal_process_site_access_snapshot_cleanup(uuid,integer)
  from public, anon, authenticated;

grant execute on function public.internal_finish_site_access_snapshot_import(uuid,jsonb)
  to postgres, service_role;
grant execute on function public.internal_resume_latest_site_access_snapshot_import(text,jsonb)
  to postgres, service_role;
grant execute on function public.internal_process_site_access_snapshot_cleanup(uuid,integer)
  to postgres, service_role;
