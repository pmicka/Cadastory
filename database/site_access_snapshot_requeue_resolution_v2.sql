-- Fast state resolution and bounded late requeue for local site-access snapshots.
-- Bridge/rail targets use direct source keys before falling back to geometry.

create or replace function decisioning.site_access_target_state_code(p_target_key text)
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_prefix text:=split_part(coalesce(p_target_key,''),':',1);
  v_native text:=split_part(coalesce(p_target_key,''),':',2);
  v_state text;
  v_geom extensions.geometry;
begin
  if v_prefix='bridge'
     and v_native ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    select case b.state_fips
      when '18' then 'IN' when '21' then 'KY' when '39' then 'OH' else null
    end
    into v_state
    from transportation.bridges b
    where b.id=v_native::uuid
    limit 1;
    if v_state is not null then return v_state; end if;
  elsif v_prefix='rail_crossing' then
    select upper(nullif(btrim(r.state),''))
    into v_state
    from transportation.rail_crossings r
    where r.crossing_id=v_native
    limit 1;
    if v_state is not null then return v_state; end if;
  end if;

  select t.geometry into v_geom
  from decisioning.v_operational_targets t
  where t.target_key=p_target_key
  limit 1;
  if v_geom is null then return null; end if;

  select c.state_code into v_state
  from scout.county_lookup c
  where extensions.ST_Intersects(c.geometry,v_geom)
  order by c.state_code,c.geoid
  limit 1;
  return v_state;
end
$function$;

create or replace function public.internal_requeue_site_access_snapshot_targets(
  p_region_slug text,
  p_batch_size integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  rg decisioning.site_access_snapshot_regions%rowtype;
  v_requeued integer:=0;
  v_remaining integer:=0;
begin
  if p_batch_size is null or p_batch_size<1 or p_batch_size>5000 then
    raise exception 'p_batch_size must be between 1 and 5000';
  end if;

  select * into rg
  from decisioning.site_access_snapshot_regions
  where region_slug=lower(btrim(p_region_slug)) and enabled
  for update;
  if not found then raise exception 'enabled snapshot region not found'; end if;
  if rg.status<>'ready' or rg.last_successful_import_id is null then
    return jsonb_build_object(
      'ok',true,'skipped',true,'reason','region_not_ready','region_slug',rg.region_slug
    );
  end if;

  if not pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended('site_access_snapshot_requeue:'||rg.region_slug,0)
  ) then
    return jsonb_build_object(
      'ok',true,'already_requeueing',true,'region_slug',rg.region_slug
    );
  end if;

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
               'snapshot_requeued_at',now(),'snapshot_region',rg.region_slug,
               'snapshot_import_id',rg.last_successful_import_id
             ),
           updated_at=now()
    from selected s
    where q.id=s.id
    returning q.id
  )
  select count(*)::integer into v_requeued from upd;

  select count(*)::integer into v_remaining
  from decisioning.site_access_queue q
  where q.state='blocked'
    and q.request_reason='awaiting_local_snapshot'
    and coalesce(q.source_context->>'blocked_reason','')='awaiting_local_snapshot'
    and decisioning.site_access_target_state_code(q.target_key)=rg.state_code;

  return jsonb_build_object(
    'ok',true,'region_slug',rg.region_slug,'state_code',rg.state_code,
    'requeued',v_requeued,'remaining',v_remaining,'complete',v_remaining=0
  );
end
$function$;

-- Correct feature_count to mean total linked features, not number of classes.
create or replace function decisioning.resolve_site_access_target_from_snapshot(
  p_target_key text,
  p_reason text default 'local_snapshot'::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_source_id uuid; v_type text; v_geom extensions.geometry; v_buffer integer;
  v_timestamp timestamptz; v_feature_count integer:=0; v_counts jsonb:='{}'::jsonb;
  v_jit_days integer:=180; v_age_days numeric; v_jit boolean:=false;
begin
  if not decisioning.snapshot_access_ready() then
    return jsonb_build_object('ok',false,'resolved',false,'reason','local_snapshot_not_ready');
  end if;
  select g.target_type,g.geometry into v_type,v_geom
  from decisioning.get_site_access_target_geometry(p_target_key) g limit 1;
  if v_geom is null then
    return jsonb_build_object(
      'ok',false,'resolved',false,'reason','target_missing_or_no_geometry',
      'target_key',p_target_key
    );
  end if;

  select id into v_source_id from ingest.sources
  where slug='openstreetmap-geofabrik-access-snapshot';
  if v_source_id is null then raise exception 'snapshot source missing'; end if;
  select min(current_source_timestamp) into v_timestamp
  from decisioning.site_access_snapshot_regions where enabled and status='ready';
  v_buffer:=case when v_type='job_site' then 220
                 else decisioning.default_site_access_buffer(v_type) end;
  select coalesce(jit_after_days,180) into v_jit_days
  from decisioning.site_access_freshness_policies where target_type=v_type;
  if not found then v_jit_days:=180; end if;

  delete from decisioning.site_access_feature_targets l
  using decisioning.site_access_features f
  where l.target_key=p_target_key and l.feature_id=f.id and f.source_id=v_source_id;

  insert into decisioning.site_access_feature_targets(
    feature_id,target_key,target_type,distance_to_target_m,relation,last_linked_at
  )
  select f.id,p_target_key,v_type,
         extensions.ST_Distance(
           f.geometry::extensions.geography,v_geom::extensions.geography
         ),
         case when extensions.ST_Intersects(f.geometry,v_geom) then 'intersects'
              when extensions.ST_Distance(
                f.geometry::extensions.geography,v_geom::extensions.geography
              )<=15 then 'adjacent'
              else 'nearby' end,
         now()
  from decisioning.site_access_features f
  where f.source_id=v_source_id
    and extensions.ST_DWithin(
      f.geometry::extensions.geography,v_geom::extensions.geography,v_buffer
    )
  on conflict(feature_id,target_key) do update set
    target_type=excluded.target_type,
    distance_to_target_m=excluded.distance_to_target_m,
    relation=excluded.relation,last_linked_at=now();

  select coalesce(sum(n),0)::integer,
         coalesce(jsonb_object_agg(feature_class,n),'{}'::jsonb)
    into v_feature_count,v_counts
  from (
    select f.feature_class,count(*)::integer n
    from decisioning.site_access_feature_targets l
    join decisioning.site_access_features f on f.id=l.feature_id
    where l.target_key=p_target_key and f.source_id=v_source_id
    group by f.feature_class
  ) x;

  insert into decisioning.site_access_target_enrichment_runs(
    target_key,target_type,source_id,requested_buffer_m,status,
    feature_count,feature_counts,source_timestamp,started_at,completed_at,attributes
  ) values(
    p_target_key,v_type,v_source_id,v_buffer,'complete',
    coalesce(v_feature_count,0),coalesce(v_counts,'{}'::jsonb),v_timestamp,now(),now(),
    jsonb_build_object(
      'collector','local-geofabrik-snapshot-v1',
      'reason',left(coalesce(p_reason,'local_snapshot'),120),
      'negative_evidence_allowed',false,'snapshot_kind','geofabrik_osm_pbf'
    )
  );

  update decisioning.site_access_queue
     set state='complete',completed_at=now(),last_error=null,
         source_context=source_context||jsonb_build_object(
           'resolved_from','local_snapshot','last_source_timestamp',v_timestamp,
           'last_feature_count',coalesce(v_feature_count,0)
         ),updated_at=now()
   where target_key=p_target_key and state<>'processing';

  v_age_days:=extract(epoch from (now()-v_timestamp))/86400.0;
  v_jit:=v_age_days>v_jit_days;
  return jsonb_build_object(
    'ok',true,'resolved',true,'target_key',p_target_key,'target_type',v_type,
    'feature_count',coalesce(v_feature_count,0),
    'feature_counts',coalesce(v_counts,'{}'::jsonb),
    'source_timestamp',v_timestamp,'snapshot_age_days',round(v_age_days,1),
    'jit_after_days',v_jit_days,'provider_jit_recommended',v_jit,
    'negative_evidence_allowed',false
  );
end
$function$;

revoke all on function public.internal_requeue_site_access_snapshot_targets(text,integer)
  from public,anon,authenticated;
grant execute on function public.internal_requeue_site_access_snapshot_targets(text,integer)
  to postgres,service_role;
