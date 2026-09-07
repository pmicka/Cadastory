-- Persist OSM access snapshot reconciliation telemetry during upload so a
-- finalizer interruption cannot erase submitted/accepted/skipped accounting.

create or replace function public.internal_start_site_access_snapshot_import(
  p_region_slug text,
  p_source_timestamp timestamptz,
  p_upstream_etag text default null,
  p_upstream_last_modified text default null,
  p_upstream_checksum text default null,
  p_attributes jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r decisioning.site_access_snapshot_regions%rowtype;
  v_id uuid;
begin
  select * into r
  from decisioning.site_access_snapshot_regions
  where region_slug=lower(btrim(p_region_slug)) and enabled
  for update;
  if not found then raise exception 'enabled snapshot region not found'; end if;
  if r.coverage_geometry is null then
    raise exception 'snapshot region has no bounded Scout coverage geometry';
  end if;
  if p_source_timestamp is null or p_source_timestamp>now()+interval '1 day' then
    raise exception 'invalid source timestamp';
  end if;

  update decisioning.site_access_snapshot_imports
     set status='failed',completed_at=now(),error_text='superseded stale loading import'
   where region_slug=r.region_slug
     and status='loading'
     and started_at<now()-interval '6 hours';

  if exists(
    select 1 from decisioning.site_access_snapshot_imports
    where region_slug=r.region_slug and status in ('loading','finalizing')
  ) then
    raise exception 'snapshot import already in flight for region %',r.region_slug;
  end if;

  insert into decisioning.site_access_snapshot_imports(
    region_slug,source_timestamp,upstream_url,upstream_etag,upstream_last_modified,
    upstream_checksum,attributes,submitted_count,accepted_count,skipped_count,
    deduplicated_count,skip_counts
  ) values (
    r.region_slug,p_source_timestamp,r.upstream_pbf_url,nullif(p_upstream_etag,''),
    nullif(p_upstream_last_modified,''),nullif(p_upstream_checksum,''),
    coalesce(p_attributes,'{}'::jsonb)||jsonb_build_object(
      'negative_evidence_allowed',false,'snapshot_kind','geofabrik_osm_pbf'
    ),0,0,0,0,'{}'::jsonb
  ) returning id into v_id;

  -- Keep an already-active snapshot authoritative during the next upload.
  if r.last_successful_import_id is null then
    update decisioning.site_access_snapshot_regions
       set status='loading',updated_at=now()
     where region_slug=r.region_slug;
  end if;

  return jsonb_build_object(
    'ok',true,'import_id',v_id,'region_slug',r.region_slug,
    'source_timestamp',p_source_timestamp,'upstream_url',r.upstream_pbf_url,
    'previous_active_import_id',r.last_successful_import_id
  );
end
$function$;

create or replace function public.internal_ingest_site_access_snapshot_batch(
  p_import_id uuid,
  p_features jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  im decisioning.site_access_snapshot_imports%rowtype;
  rg decisioning.site_access_snapshot_regions%rowtype;
  v_source_id uuid;
  f jsonb; t jsonb; c jsonb;
  v_geom extensions.geometry; v_feature_id uuid;
  v_native text; v_type text; v_id text; v_geomtype text;
  v_accepted integer:=0; v_skipped integer:=0;
  v_invalid_identity integer:=0; v_invalid_geometry integer:=0;
  v_outside_region integer:=0; v_classifier_rejected integer:=0;
begin
  if p_features is null or jsonb_typeof(p_features)<>'array'
     or jsonb_array_length(p_features)>1000 then
    raise exception 'features must be a JSON array of at most 1000 items';
  end if;

  select * into im
  from decisioning.site_access_snapshot_imports
  where id=p_import_id and status='loading'
  for update;
  if not found then raise exception 'loading snapshot import not found'; end if;

  select * into rg
  from decisioning.site_access_snapshot_regions
  where region_slug=im.region_slug and enabled;
  if not found or rg.coverage_geometry is null then
    raise exception 'snapshot region unavailable';
  end if;

  select id into v_source_id from ingest.sources
  where slug='openstreetmap-geofabrik-access-snapshot';
  if v_source_id is null then raise exception 'snapshot source missing'; end if;

  for f in select value from jsonb_array_elements(p_features) loop
    t:=coalesce(f->'tags','{}'::jsonb);
    v_type:=lower(coalesce(nullif(f->>'osm_type',''),'unknown'));
    v_id:=coalesce(nullif(f->>'osm_id',''),nullif(f->>'source_native_id',''));
    if v_id is null or v_type not in ('node','way','relation') then
      v_skipped:=v_skipped+1;
      v_invalid_identity:=v_invalid_identity+1;
      continue;
    end if;
    v_native:=left(v_type||'/'||v_id,160);

    begin
      v_geom:=extensions.ST_SetSRID(
        extensions.ST_GeomFromGeoJSON((f->'geometry')::text),4326
      );
      if not extensions.ST_IsValid(v_geom) then
        v_geom:=extensions.ST_MakeValid(v_geom);
      end if;
    exception when others then
      v_geom:=null;
    end;
    if v_geom is null or extensions.ST_IsEmpty(v_geom) then
      v_skipped:=v_skipped+1;
      v_invalid_geometry:=v_invalid_geometry+1;
      continue;
    end if;

    if not extensions.ST_DWithin(
      v_geom::extensions.geography,
      rg.coverage_geometry::extensions.geography,
      2500
    ) then
      v_skipped:=v_skipped+1;
      v_outside_region:=v_outside_region+1;
      continue;
    end if;

    v_geomtype:=replace(upper(extensions.ST_GeometryType(v_geom)),'ST_','');
    c:=decisioning.classify_osm_access_feature(t,v_geomtype);
    if not coalesce((c->>'accepted')::boolean,false) then
      v_skipped:=v_skipped+1;
      v_classifier_rejected:=v_classifier_rejected+1;
      continue;
    end if;

    insert into decisioning.site_access_features(
      source_id,source_native_id,feature_class,feature_subclass,name,
      access_tag,surface_tag,service_tag,drivable,staging_candidate,
      routing_barrier,access_point,source_confidence,geometry,raw_attributes,
      first_observed_at,last_observed_at,updated_at
    ) values (
      v_source_id,v_native,c->>'feature_class',nullif(c->>'feature_subclass',''),
      nullif(t->>'name',''),nullif(c->>'access_tag',''),nullif(c->>'surface_tag',''),
      nullif(c->>'service_tag',''),coalesce((c->>'drivable')::boolean,false),
      coalesce((c->>'staging_candidate')::boolean,false),
      coalesce((c->>'routing_barrier')::boolean,false),
      coalesce((c->>'access_point')::boolean,false),
      coalesce((c->>'source_confidence')::numeric,0.72),v_geom,
      jsonb_build_object(
        'osm_type',v_type,'osm_id',v_id,'tags',t,
        'snapshot_region',im.region_slug,'negative_evidence_allowed',false
      ),
      im.source_timestamp,im.source_timestamp,now()
    ) on conflict(source_id,source_native_id) do update set
      feature_class=excluded.feature_class,
      feature_subclass=excluded.feature_subclass,
      name=excluded.name,access_tag=excluded.access_tag,
      surface_tag=excluded.surface_tag,service_tag=excluded.service_tag,
      drivable=excluded.drivable,staging_candidate=excluded.staging_candidate,
      routing_barrier=excluded.routing_barrier,access_point=excluded.access_point,
      source_confidence=excluded.source_confidence,geometry=excluded.geometry,
      raw_attributes=excluded.raw_attributes,
      last_observed_at=greatest(
        decisioning.site_access_features.last_observed_at,excluded.last_observed_at
      ),updated_at=now()
    returning id into v_feature_id;

    insert into decisioning.site_access_snapshot_feature_regions(
      feature_id,region_slug,last_seen_import_id,last_seen_at
    ) values(v_feature_id,im.region_slug,im.id,now())
    on conflict(feature_id,region_slug) do update
      set last_seen_import_id=excluded.last_seen_import_id,last_seen_at=now();

    insert into decisioning.site_access_snapshot_import_features(
      import_id,region_slug,feature_id,feature_class
    ) values(im.id,im.region_slug,v_feature_id,c->>'feature_class')
    on conflict(import_id,feature_id) do update
      set feature_class=excluded.feature_class;

    v_accepted:=v_accepted+1;
  end loop;

  update decisioning.site_access_snapshot_imports
     set batch_count=batch_count+1,
         submitted_count=coalesce(submitted_count,0)+jsonb_array_length(p_features),
         accepted_count=coalesce(accepted_count,0)+v_accepted,
         skipped_count=coalesce(skipped_count,0)+v_skipped,
         skip_counts=jsonb_build_object(
           'invalid_identity',coalesce((skip_counts->>'invalid_identity')::integer,0)+v_invalid_identity,
           'invalid_geometry',coalesce((skip_counts->>'invalid_geometry')::integer,0)+v_invalid_geometry,
           'outside_region',coalesce((skip_counts->>'outside_region')::integer,0)+v_outside_region,
           'classifier_rejected',coalesce((skip_counts->>'classifier_rejected')::integer,0)+v_classifier_rejected
         )
   where id=im.id;

  return jsonb_build_object(
    'ok',true,'import_id',im.id,'region_slug',im.region_slug,
    'accepted',v_accepted,'skipped',v_skipped,
    'skip_counts',jsonb_build_object(
      'invalid_identity',v_invalid_identity,
      'invalid_geometry',v_invalid_geometry,
      'outside_region',v_outside_region,
      'classifier_rejected',v_classifier_rejected
    ),
    'batch_size',jsonb_array_length(p_features)
  );
end
$function$;

revoke all on function public.internal_start_site_access_snapshot_import(
  text,timestamptz,text,text,text,jsonb
) from public,anon,authenticated;
revoke all on function public.internal_ingest_site_access_snapshot_batch(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function public.internal_start_site_access_snapshot_import(
  text,timestamptz,text,text,text,jsonb
) to postgres,service_role;
grant execute on function public.internal_ingest_site_access_snapshot_batch(uuid,jsonb)
  to postgres,service_role;
