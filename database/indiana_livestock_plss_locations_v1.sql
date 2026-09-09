insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,homepage_url,commercial_use_status,notes
) values (
  'indiana-gis-plss-sections',
  'Indiana GIS PLSS Section Boundaries',
  'State of Indiana',
  'cadastral_reference',
  'Indiana',
  'ArcGIS FeatureServer PLSS section boundary lookup',
  'annual',
  'state_authoritative',
  'active',
  'https://gisdata.in.gov/server/rest/services/Hosted/PLSS_1/FeatureServer/3',
  'public_record',
  'Used with IDEM CFO/CAFO Section/Township/Range identifiers. Derived point is section-level approximate location, not a farmstead, parcel centroid, or mission coordinate.'
)
on conflict(slug) do update set
  name=excluded.name,
  authority=excluded.authority,
  source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,
  acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,
  authority_level=excluded.authority_level,
  status=excluded.status,
  homepage_url=excluded.homepage_url,
  commercial_use_status=excluded.commercial_use_status,
  notes=excluded.notes,
  updated_at=now();

create table if not exists agriculture.farm_location_evidence (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references agriculture.farm_entity_candidates(id) on delete cascade,
  identity_source_id uuid not null references ingest.sources(id),
  geometry_source_id uuid not null references ingest.sources(id),
  location extensions.geography(Point,4326) not null,
  state_code text not null,
  county_name text,
  location_basis text not null,
  accuracy_class text not null,
  confidence numeric not null check (confidence between 0 and 1),
  source_record_key text,
  source_url text,
  observed_at timestamptz not null default now(),
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(candidate_id, location_basis)
);

create index if not exists farm_location_evidence_location_gix
  on agriculture.farm_location_evidence using gist(location);
create index if not exists farm_location_evidence_candidate_idx
  on agriculture.farm_location_evidence(candidate_id);

alter table agriculture.farm_location_evidence enable row level security;
revoke all on agriculture.farm_location_evidence from anon, authenticated;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname='farm_location_evidence_basis_check'
      and conrelid='agriculture.farm_location_evidence'::regclass
  ) then
    alter table agriculture.farm_location_evidence
      add constraint farm_location_evidence_basis_check
      check (location_basis in ('idem_plss_section'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='farm_location_evidence_accuracy_check'
      and conrelid='agriculture.farm_location_evidence'::regclass
  ) then
    alter table agriculture.farm_location_evidence
      add constraint farm_location_evidence_accuracy_check
      check (accuracy_class in ('section_approximate'));
  end if;
end $$;

create or replace function public.internal_get_indiana_livestock_plss_queue(p_limit integer default 250)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
with q as (
  select
    c.id as candidate_id,
    c.display_name,
    c.attributes->>'farm_id' as farm_id,
    c.attributes->>'tempo_id' as tempo_id,
    c.attributes->>'county' as county_name,
    c.attributes->>'date_issued' as date_issued,
    c.attributes->>'project_type' as project_type
  from agriculture.farm_entity_candidates c
  where c.attributes->>'source_slug'='indiana-idem-issued-cfo-cafo'
    and c.attributes->>'permit_lifecycle_status'='current_record'
    and exists (
      select 1 from agriculture.farm_livestock_observations_v1 o
      where o.candidate_id=c.id and o.state_code='IN' and o.is_current
    )
    and not exists (
      select 1 from agriculture.farm_location_evidence l
      where l.candidate_id=c.id and l.location_basis='idem_plss_section'
    )
  order by c.display_name,c.id
  limit greatest(1,least(coalesce(p_limit,250),500))
)
select coalesce(jsonb_agg(jsonb_build_object(
  'candidate_id',candidate_id,
  'display_name',display_name,
  'farm_id',farm_id,
  'tempo_id',tempo_id,
  'county_name',county_name,
  'date_issued',date_issued,
  'project_type',project_type
) order by display_name,candidate_id),'[]'::jsonb)
from q;
$function$;

revoke all on function public.internal_get_indiana_livestock_plss_queue(integer) from public;
grant execute on function public.internal_get_indiana_livestock_plss_queue(integer) to service_role;

create or replace function public.internal_upsert_indiana_livestock_plss_location(
  p_candidate_id uuid,
  p_farm_id text,
  p_tempo_id text,
  p_section integer,
  p_township integer,
  p_township_direction text,
  p_range integer,
  p_range_direction text,
  p_meridian text,
  p_plss_objectid bigint,
  p_lon double precision,
  p_lat double precision,
  p_source_record_key text default null,
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','agriculture','ingest'
as $function$
declare
  v_candidate agriculture.farm_entity_candidates%rowtype;
  v_identity_source uuid;
  v_geometry_source uuid;
  v_location extensions.geography(Point,4326);
  v_actual_county text;
  v_expected_county text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select * into v_candidate
  from agriculture.farm_entity_candidates
  where id=p_candidate_id;
  if not found then raise exception 'candidate not found'; end if;

  if v_candidate.attributes->>'source_slug' <> 'indiana-idem-issued-cfo-cafo'
     or v_candidate.attributes->>'permit_lifecycle_status' <> 'current_record'
     or coalesce(v_candidate.attributes->>'farm_id','') <> coalesce(p_farm_id,'')
     or coalesce(v_candidate.attributes->>'tempo_id','') <> coalesce(p_tempo_id,'') then
    raise exception 'candidate/source identity mismatch';
  end if;

  if not exists (
    select 1 from agriculture.farm_livestock_observations_v1 o
    where o.candidate_id=p_candidate_id and o.state_code='IN' and o.is_current
  ) then raise exception 'candidate lacks current Indiana livestock evidence'; end if;

  if p_section < 1 or p_section > 36
     or p_township < 1 or p_township > 60
     or upper(p_township_direction) not in ('N','S')
     or p_range < 1 or p_range > 30
     or upper(p_range_direction) not in ('E','W') then
    raise exception 'invalid PLSS key';
  end if;

  if p_lon is null or p_lat is null
     or p_lon < -88.2 or p_lon > -84.6
     or p_lat < 37.7 or p_lat > 41.9 then
    return jsonb_build_object('accepted',false,'reason','outside_indiana_bounds');
  end if;

  v_location:=extensions.st_setsrid(extensions.st_makepoint(p_lon,p_lat),4326)::extensions.geography;
  v_expected_county:=nullif(btrim(v_candidate.attributes->>'county'),'');

  select r.raw_payload->'properties'->>'NAME'
    into v_actual_county
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='census-tigerweb-counties-2026'
    and r.geometry is not null
    and r.raw_payload->'properties'->>'STATE'='18'
    and extensions.st_covers(r.geometry::extensions.geometry,v_location::extensions.geometry)
  order by r.retrieved_at desc
  limit 1;

  if v_actual_county is null then
    return jsonb_build_object('accepted',false,'reason','county_not_resolved');
  end if;

  if v_expected_county is not null
     and lower(regexp_replace(v_actual_county,'\s+county$','','i'))
       <> lower(regexp_replace(v_expected_county,'\s+county$','','i')) then
    return jsonb_build_object(
      'accepted',false,'reason','county_mismatch',
      'expected_county',v_expected_county,'actual_county',v_actual_county
    );
  end if;

  select id into v_identity_source from ingest.sources where slug='indiana-idem-issued-cfo-cafo';
  select id into v_geometry_source from ingest.sources where slug='indiana-gis-plss-sections';
  if v_identity_source is null or v_geometry_source is null then raise exception 'location sources missing'; end if;

  insert into agriculture.farm_location_evidence(
    candidate_id,identity_source_id,geometry_source_id,location,state_code,county_name,
    location_basis,accuracy_class,confidence,source_record_key,source_url,observed_at,attributes
  ) values (
    p_candidate_id,v_identity_source,v_geometry_source,v_location,'IN',v_actual_county,
    'idem_plss_section','section_approximate',0.88,p_source_record_key,
    'https://gisdata.in.gov/server/rest/services/Hosted/PLSS_1/FeatureServer/3',
    coalesce(p_observed_at,now()),
    jsonb_build_object(
      'farm_id',p_farm_id,'tempo_id',p_tempo_id,
      'section',p_section,'township',p_township,'township_direction',upper(p_township_direction),
      'range',p_range,'range_direction',upper(p_range_direction),
      'meridian',p_meridian,'plss_objectid',p_plss_objectid,
      'location_semantics','representative point for authoritative PLSS section containing the permitted operation; refine to parcel/farmstead before operational use'
    )
  )
  on conflict(candidate_id,location_basis) do update set
    identity_source_id=excluded.identity_source_id,
    geometry_source_id=excluded.geometry_source_id,
    location=excluded.location,
    state_code=excluded.state_code,
    county_name=excluded.county_name,
    accuracy_class=excluded.accuracy_class,
    confidence=excluded.confidence,
    source_record_key=excluded.source_record_key,
    source_url=excluded.source_url,
    observed_at=excluded.observed_at,
    attributes=excluded.attributes,
    updated_at=now();

  return jsonb_build_object(
    'accepted',true,'candidate_id',p_candidate_id,'county_name',v_actual_county,
    'location_basis','idem_plss_section','accuracy_class','section_approximate'
  );
end;
$function$;

revoke all on function public.internal_upsert_indiana_livestock_plss_location(uuid,text,text,integer,integer,text,integer,text,text,bigint,double precision,double precision,text,timestamptz) from public;
grant execute on function public.internal_upsert_indiana_livestock_plss_location(uuid,text,text,integer,integer,text,integer,text,text,bigint,double precision,double precision,text,timestamptz) to service_role;
