begin;

create table if not exists farm_watch.property_field_vegetation_collection_runs_v1 (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  as_of_date date not null,
  status text not null check (
    status in (
      'processing',
      'available',
      'partial',
      'no_valid_observation',
      'catalog_incomplete',
      'download_error',
      'processing_error'
    )
  ),
  source_authority text not null default 'NASA LP DAAC',
  distribution_provider text not null default 'Microsoft Planetary Computer',
  source_collections text[] not null default array['hls2-l30','hls2-s30']::text[],
  target_fields integer not null default 0 check (target_fields >= 0),
  discovered_items integer not null default 0 check (discovered_items >= 0),
  complete_asset_items integer not null default 0 check (complete_asset_items >= 0),
  sampled_items integer not null default 0 check (sampled_items >= 0),
  stored_observations integer not null default 0 check (stored_observations >= 0),
  current_quality_fields integer not null default 0 check (current_quality_fields >= 0),
  workflow jsonb not null default '{}'::jsonb,
  details jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists property_field_vegetation_collection_runs_property_date_idx
  on farm_watch.property_field_vegetation_collection_runs_v1(
    property_id,as_of_date desc,started_at desc
  );

alter table farm_watch.property_field_vegetation_collection_runs_v1 enable row level security;
revoke all on farm_watch.property_field_vegetation_collection_runs_v1 from public, anon, authenticated;
grant select,insert,update on farm_watch.property_field_vegetation_collection_runs_v1 to service_role;

insert into ingest.sources (
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,license_notes,commercial_use_status,notes
)
values (
  'microsoft-planetary-computer-hls-v2',
  'Microsoft Planetary Computer — NASA HLS v2.0 distribution',
  'Microsoft Planetary Computer',
  'authoritative_distribution_mirror',
  'Global land',
  'STAC discovery and signed Cloud Optimized GeoTIFF access for NASA HLS L30/S30 v2.0',
  'mirrors source publication',
  'distribution_host',
  'active',
  'https://planetarycomputer.microsoft.com/dataset/group/hls2',
  'Hosted HLS access follows LP DAAC data citation/policy terms and Planetary Computer access terms.',
  'public_cloud_distribution',
  'Operational Batch 4B distribution route. NASA LP DAAC remains the scientific source authority; Microsoft is the host/distribution provider.'
)
on conflict (slug) do update set
  name=excluded.name,
  authority=excluded.authority,
  source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,
  acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,
  authority_level=excluded.authority_level,
  status=excluded.status,
  homepage_url=excluded.homepage_url,
  license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,
  notes=excluded.notes,
  updated_at=now();

create or replace function farm_watch.farm_watch_start_field_vegetation_collection_v1_internal(
  p_slug text,
  p_as_of_date date,
  p_workflow jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_property_id uuid;
  v_run_id uuid;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_as_of_date is null then raise exception 'as-of date is required'; end if;

  select id into v_property_id
  from farm_watch.properties
  where slug=p_slug and status='active'
  limit 1;
  if v_property_id is null then raise exception 'Farm Watch property unavailable'; end if;

  insert into farm_watch.property_field_vegetation_collection_runs_v1(
    property_id,as_of_date,status,workflow,started_at,updated_at
  ) values (
    v_property_id,p_as_of_date,'processing',coalesce(p_workflow,'{}'::jsonb),now(),now()
  )
  returning id into v_run_id;

  return jsonb_build_object(
    'run_id',v_run_id,
    'property_slug',p_slug,
    'property_id',v_property_id,
    'as_of_date',p_as_of_date,
    'status','processing',
    'source_authority','NASA LP DAAC',
    'distribution_provider','Microsoft Planetary Computer',
    'source_collections',jsonb_build_array('hls2-l30','hls2-s30')
  );
end;
$$;

create or replace function farm_watch.farm_watch_finish_field_vegetation_collection_v1_internal(
  p_run_id uuid,
  p_status text,
  p_target_fields integer,
  p_discovered_items integer,
  p_complete_asset_items integer,
  p_sampled_items integer,
  p_stored_observations integer,
  p_current_quality_fields integer,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_row farm_watch.property_field_vegetation_collection_runs_v1%rowtype;
  v_slug text;
begin
  if p_run_id is null then raise exception 'collection run id is required'; end if;
  if p_status not in (
    'available','partial','no_valid_observation',
    'catalog_incomplete','download_error','processing_error'
  ) then
    raise exception 'invalid collection completion status';
  end if;

  select *
  into v_row
  from farm_watch.property_field_vegetation_collection_runs_v1
  where id=p_run_id
  for update;
  if not found then raise exception 'collection run unavailable'; end if;
  if v_row.status <> 'processing' then
    raise exception 'collection run is not processing';
  end if;

  if least(
    coalesce(p_target_fields,-1),
    coalesce(p_discovered_items,-1),
    coalesce(p_complete_asset_items,-1),
    coalesce(p_sampled_items,-1),
    coalesce(p_stored_observations,-1),
    coalesce(p_current_quality_fields,-1)
  ) < 0 then
    raise exception 'collection counters must be nonnegative';
  end if;
  if p_complete_asset_items > p_discovered_items
     or p_sampled_items > p_complete_asset_items
     or p_current_quality_fields > p_target_fields then
    raise exception 'collection counters are inconsistent';
  end if;

  update farm_watch.property_field_vegetation_collection_runs_v1
  set
    status=p_status,
    target_fields=p_target_fields,
    discovered_items=p_discovered_items,
    complete_asset_items=p_complete_asset_items,
    sampled_items=p_sampled_items,
    stored_observations=p_stored_observations,
    current_quality_fields=p_current_quality_fields,
    details=coalesce(p_details,'{}'::jsonb),
    completed_at=now(),
    updated_at=now()
  where id=p_run_id
  returning * into v_row;

  select slug into v_slug from farm_watch.properties where id=v_row.property_id;

  return jsonb_build_object(
    'run_id',v_row.id,
    'property_slug',v_slug,
    'as_of_date',v_row.as_of_date,
    'status',v_row.status,
    'target_fields',v_row.target_fields,
    'discovered_items',v_row.discovered_items,
    'complete_asset_items',v_row.complete_asset_items,
    'sampled_items',v_row.sampled_items,
    'stored_observations',v_row.stored_observations,
    'current_quality_fields',v_row.current_quality_fields,
    'completed_at',v_row.completed_at
  );
end;
$$;

create or replace function farm_watch.farm_watch_get_latest_field_vegetation_collection_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_property_id uuid;
  v_row farm_watch.property_field_vegetation_collection_runs_v1%rowtype;
begin
  select id into v_property_id
  from farm_watch.properties
  where slug=p_slug and status='active'
  limit 1;

  if v_property_id is null then
    return jsonb_build_object(
      'status','missing',
      'property_slug',p_slug,
      'as_of_date',p_as_of_date
    );
  end if;

  select * into v_row
  from farm_watch.property_field_vegetation_collection_runs_v1
  where property_id=v_property_id
    and as_of_date=p_as_of_date
  order by started_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'status','missing',
      'property_slug',p_slug,
      'as_of_date',p_as_of_date
    );
  end if;

  return jsonb_build_object(
    'run_id',v_row.id,
    'property_slug',p_slug,
    'as_of_date',v_row.as_of_date,
    'status',v_row.status,
    'source_authority',v_row.source_authority,
    'distribution_provider',v_row.distribution_provider,
    'source_collections',to_jsonb(v_row.source_collections),
    'target_fields',v_row.target_fields,
    'discovered_items',v_row.discovered_items,
    'complete_asset_items',v_row.complete_asset_items,
    'sampled_items',v_row.sampled_items,
    'stored_observations',v_row.stored_observations,
    'current_quality_fields',v_row.current_quality_fields,
    'workflow',v_row.workflow,
    'details',v_row.details,
    'started_at',v_row.started_at,
    'completed_at',v_row.completed_at
  );
end;
$$;

revoke all on function farm_watch.farm_watch_start_field_vegetation_collection_v1_internal(text,date,jsonb)
from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_finish_field_vegetation_collection_v1_internal(uuid,text,integer,integer,integer,integer,integer,integer,jsonb)
from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_latest_field_vegetation_collection_v1_internal(text,date)
from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_start_field_vegetation_collection_v1_internal(text,date,jsonb)
to service_role;
grant execute on function farm_watch.farm_watch_finish_field_vegetation_collection_v1_internal(uuid,text,integer,integer,integer,integer,integer,integer,jsonb)
to service_role;
grant execute on function farm_watch.farm_watch_get_latest_field_vegetation_collection_v1_internal(text,date)
to service_role;

create or replace function public.farm_watch_start_field_vegetation_collection_v1_internal(
  p_slug text,
  p_as_of_date date,
  p_workflow jsonb default '{}'::jsonb
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_start_field_vegetation_collection_v1_internal(
    p_slug,p_as_of_date,p_workflow
  );
$$;

create or replace function public.farm_watch_finish_field_vegetation_collection_v1_internal(
  p_run_id uuid,
  p_status text,
  p_target_fields integer,
  p_discovered_items integer,
  p_complete_asset_items integer,
  p_sampled_items integer,
  p_stored_observations integer,
  p_current_quality_fields integer,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_finish_field_vegetation_collection_v1_internal(
    p_run_id,p_status,p_target_fields,p_discovered_items,p_complete_asset_items,
    p_sampled_items,p_stored_observations,p_current_quality_fields,p_details
  );
$$;

create or replace function public.farm_watch_get_latest_field_vegetation_collection_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_latest_field_vegetation_collection_v1_internal(
    p_slug,p_as_of_date
  );
$$;

revoke all on function public.farm_watch_start_field_vegetation_collection_v1_internal(text,date,jsonb)
from public,anon,authenticated;
revoke all on function public.farm_watch_finish_field_vegetation_collection_v1_internal(uuid,text,integer,integer,integer,integer,integer,integer,jsonb)
from public,anon,authenticated;
revoke all on function public.farm_watch_get_latest_field_vegetation_collection_v1_internal(text,date)
from public,anon,authenticated;

grant execute on function public.farm_watch_start_field_vegetation_collection_v1_internal(text,date,jsonb)
to service_role;
grant execute on function public.farm_watch_finish_field_vegetation_collection_v1_internal(uuid,text,integer,integer,integer,integer,integer,integer,jsonb)
to service_role;
grant execute on function public.farm_watch_get_latest_field_vegetation_collection_v1_internal(text,date)
to service_role;

comment on table farm_watch.property_field_vegetation_collection_runs_v1 is
'Operational ledger for protected HLS field-observation collection. Source/catalog/download/processing failures remain explicit and separate from field vegetation evidence.';

comment on column farm_watch.field_vegetation_observations_v1.source_sha256 is
'SHA-256 of the stable remote-source identity fingerprint used for the field observation (collection, item, observation time, and unsigned asset identities). It is not asserted to be a full-byte checksum of the remote COG files.';

commit;