-- Batch 4: make construction/SWPPP snapshot ingest resumable within edge RPC limits.
--
-- The ECHO snapshot currently contains ~15.9k rows. The legacy RPC first marked
-- every row absent and then rewrote the entire snapshot in one PostgREST call,
-- which repeatedly exceeded the statement timeout. These chunk RPCs keep one
-- run-level seen timestamp across bounded writes and reconcile source presence
-- only after every chunk has succeeded.

create or replace function public.internal_ingest_construction_stormwater_evidence_chunk(
  p_rows jsonb,
  p_seen_at timestamptz
)
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  n integer:=0;
  v_source uuid;
begin
  if p_seen_at is null then
    raise exception 'p_seen_at is required';
  end if;

  select id into v_source from ingest.sources where slug='epa-echo-cwa-facilities';
  if v_source is null then raise exception 'Missing source epa-echo-cwa-facilities'; end if;

  insert into compliance.construction_stormwater_evidence(
    source_native_id,source_id,state_code,master_permit_number,facility_name,registry_id,permit_status_code,permit_status_desc,
    permit_type_code,permit_type_desc,issue_date,effective_date,expiration_date,termination_date,storm_water_area_acres,storm_water_area_raw,
    swppp_url,permit_components,permitting_agency,location,evidence_strength,source_present,attributes,first_seen_at,last_seen_at,updated_at
  )
  select r.source_native_id,v_source,r.state_code,r.master_permit_number,r.facility_name,r.registry_id,r.permit_status_code,r.permit_status_desc,
    r.permit_type_code,r.permit_type_desc,r.issue_date,r.effective_date,r.expiration_date,r.termination_date,r.storm_water_area_acres,r.storm_water_area_raw,
    r.swppp_url,r.permit_components,r.permitting_agency,
    case when r.longitude is not null and r.latitude is not null then extensions.st_setsrid(extensions.st_makepoint(r.longitude,r.latitude),4326)::extensions.geography else null end,
    'documented_permit',true,coalesce(r.attributes,'{}'::jsonb),p_seen_at,p_seen_at,now()
  from jsonb_to_recordset(coalesce(p_rows,'[]'::jsonb)) as r(
    source_native_id text,state_code text,master_permit_number text,facility_name text,registry_id text,permit_status_code text,permit_status_desc text,
    permit_type_code text,permit_type_desc text,issue_date date,effective_date date,expiration_date date,termination_date date,
    storm_water_area_acres numeric,storm_water_area_raw text,swppp_url text,permit_components text,permitting_agency text,
    longitude double precision,latitude double precision,attributes jsonb
  )
  where nullif(btrim(r.source_native_id),'') is not null
  on conflict(source_native_id) do update set
    source_id=excluded.source_id,state_code=excluded.state_code,master_permit_number=excluded.master_permit_number,facility_name=excluded.facility_name,
    registry_id=excluded.registry_id,permit_status_code=excluded.permit_status_code,permit_status_desc=excluded.permit_status_desc,
    permit_type_code=excluded.permit_type_code,permit_type_desc=excluded.permit_type_desc,issue_date=excluded.issue_date,effective_date=excluded.effective_date,
    expiration_date=excluded.expiration_date,termination_date=excluded.termination_date,storm_water_area_acres=excluded.storm_water_area_acres,
    storm_water_area_raw=excluded.storm_water_area_raw,swppp_url=excluded.swppp_url,permit_components=excluded.permit_components,
    permitting_agency=excluded.permitting_agency,location=excluded.location,evidence_strength=excluded.evidence_strength,source_present=true,
    attributes=excluded.attributes,last_seen_at=p_seen_at,updated_at=now();

  get diagnostics n=row_count;
  return n;
end
$function$;

create or replace function public.internal_ingest_ohio_construction_stormwater_chunk(
  p_rows jsonb,
  p_seen_at timestamptz
)
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  n integer:=0;
  v_source uuid;
begin
  if p_seen_at is null then
    raise exception 'p_seen_at is required';
  end if;

  select id into v_source from ingest.sources where slug='ohio-epa-npdes-construction';
  if v_source is null then raise exception 'Missing Ohio EPA construction source'; end if;

  insert into compliance.construction_stormwater_evidence(
    source_native_id,source_id,state_code,master_permit_number,facility_name,registry_id,permit_status_code,permit_status_desc,
    permit_type_code,permit_type_desc,issue_date,effective_date,expiration_date,termination_date,storm_water_area_acres,storm_water_area_raw,
    swppp_url,permit_components,permitting_agency,location,evidence_strength,source_present,attributes,first_seen_at,last_seen_at,updated_at
  )
  select 'ohio-epa:'||r.ohio_epa_no,v_source,'OH','OHC000006',r.facility_name,r.us_epa_no,null,r.permit_status,null,r.permit_type,
    r.issue_date,r.effective_date,r.expiration_date,null,r.total_acres,case when r.total_acres is null then null else r.total_acres::text end,
    null,r.permitdetail,'Ohio EPA',
    case when r.longitude is not null and r.latitude is not null then extensions.st_setsrid(extensions.st_makepoint(r.longitude,r.latitude),4326)::extensions.geography else null end,
    'documented_state_construction_permit',true,
    jsonb_build_object('ohio_epa_no',r.ohio_epa_no,'permit_category',r.permit_category,'county',r.county_name,'documented_total_acres',r.total_acres,
      'disturbance_semantics','Ohio EPA total_acres is stored as documented state permit acreage; do not substitute building square footage or infer disturbed acreage.'),
    p_seen_at,p_seen_at,now()
  from jsonb_to_recordset(coalesce(p_rows,'[]'::jsonb)) r(
    ohio_epa_no text,facility_name text,us_epa_no text,permit_status text,permit_type text,permit_category text,permitdetail text,
    issue_date date,effective_date date,expiration_date date,total_acres numeric,county_name text,longitude double precision,latitude double precision
  )
  where nullif(btrim(r.ohio_epa_no),'') is not null
  on conflict(source_native_id) do update set
    source_id=excluded.source_id,state_code='OH',master_permit_number='OHC000006',facility_name=excluded.facility_name,registry_id=excluded.registry_id,
    permit_status_desc=excluded.permit_status_desc,permit_type_desc=excluded.permit_type_desc,issue_date=excluded.issue_date,effective_date=excluded.effective_date,
    expiration_date=excluded.expiration_date,storm_water_area_acres=excluded.storm_water_area_acres,storm_water_area_raw=excluded.storm_water_area_raw,
    permitting_agency='Ohio EPA',location=excluded.location,evidence_strength=excluded.evidence_strength,source_present=true,attributes=excluded.attributes,
    last_seen_at=p_seen_at,updated_at=now();

  get diagnostics n=row_count;
  return n;
end
$function$;

create or replace function public.internal_finalize_construction_stormwater_snapshot(
  p_source_slug text,
  p_seen_at timestamptz
)
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  n integer:=0;
  v_source uuid;
begin
  if p_source_slug not in ('epa-echo-cwa-facilities','ohio-epa-npdes-construction') then
    raise exception 'Unsupported construction stormwater source';
  end if;
  if p_seen_at is null then
    raise exception 'p_seen_at is required';
  end if;

  select id into v_source from ingest.sources where slug=p_source_slug;
  if v_source is null then raise exception 'Missing construction stormwater source %',p_source_slug; end if;

  update compliance.construction_stormwater_evidence
     set source_present=false,
         updated_at=now()
   where source_id=v_source
     and source_present=true
     and (last_seen_at is null or last_seen_at < p_seen_at);
  get diagnostics n=row_count;
  return n;
end
$function$;

revoke all on function public.internal_ingest_construction_stormwater_evidence_chunk(jsonb,timestamptz) from public,anon,authenticated;
revoke all on function public.internal_ingest_ohio_construction_stormwater_chunk(jsonb,timestamptz) from public,anon,authenticated;
revoke all on function public.internal_finalize_construction_stormwater_snapshot(text,timestamptz) from public,anon,authenticated;
grant execute on function public.internal_ingest_construction_stormwater_evidence_chunk(jsonb,timestamptz) to service_role;
grant execute on function public.internal_ingest_ohio_construction_stormwater_chunk(jsonb,timestamptz) to service_role;
grant execute on function public.internal_finalize_construction_stormwater_snapshot(text,timestamptz) to service_role;

comment on function public.internal_finalize_construction_stormwater_snapshot(text,timestamptz) is
  'Finalizes a fully successful bounded construction-stormwater snapshot by marking only rows not seen in that run absent.';