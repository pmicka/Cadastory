-- Scout targeted USAspending physical-FM task-order spine v1
-- Internal evidence infrastructure for child task/delivery orders under already-qualified
-- facilities-management / multi-site physical-trade IDVs. This is not a broad USAspending
-- ingestion and does not authorize contractor -> facility propagation.

create table if not exists procurement.federal_task_orders (
  id uuid primary key default gen_random_uuid(),
  source_record_id uuid not null references ingest.raw_records(id) on delete restrict,
  source_slug text not null default 'usaspending' references ingest.sources(slug) on update cascade on delete restrict,
  parent_generated_award_id text not null,
  parent_piid text not null,
  child_generated_award_id text not null,
  child_piid text,
  award_type text,
  description text,
  recipient_name text,
  recipient_uei text,
  parent_recipient_name text,
  parent_recipient_uei text,
  total_obligation numeric,
  date_signed date,
  pop_start_date date,
  pop_end_date date,
  pop_potential_end_date date,
  awarding_agency_name text,
  awarding_subtier_name text,
  awarding_office_name text,
  funding_agency_name text,
  funding_subtier_name text,
  funding_office_name text,
  place_country_code text,
  place_country_name text,
  place_state_code text,
  place_state_name text,
  place_city_name text,
  place_county_name text,
  place_zip5 text,
  place_address_line1 text,
  naics_code text,
  naics_description text,
  psc_code text,
  psc_description text,
  attributes jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_slug, child_generated_award_id)
);

create index if not exists federal_task_orders_parent_piid_idx
  on procurement.federal_task_orders(parent_piid,last_observed_at desc);
create index if not exists federal_task_orders_place_state_idx
  on procurement.federal_task_orders(place_state_code,last_observed_at desc);
create index if not exists federal_task_orders_recipient_uei_idx
  on procurement.federal_task_orders(recipient_uei);

comment on table procurement.federal_task_orders is
  'Internal normalized USAspending child award evidence for qualified physical-FM parent IDVs. Parent/child award facts are authoritative evidence; they do not by themselves prove that every facility in an owner/operator graph is contract scope.';

create or replace view research.v_usaspending_physical_fm_parent_idv_targets as
with expanded as (
  select
    p.program_key,
    p.program_title,
    p.buyer_name,
    p.buyer_subtier,
    p.buyer_office,
    p.program_scope_class,
    p.site_scope_status,
    p.has_surface_work_scope,
    unnest(p.award_numbers) as parent_piid
  from research.v_physical_fm_program_families p
), coded as (
  select
    e.*,
    case
      when upper(coalesce(e.buyer_subtier,'')) like '%NAVY%' then '1700'
      when upper(coalesce(e.buyer_subtier,'')) like '%ARMY%' then '9700'
      when upper(coalesce(e.buyer_name,'')) like '%DEFENSE%' and e.parent_piid like 'W%' then '9700'
      else null
    end as fpds_agency_code
  from expanded e
)
select
  c.*,
  case when c.fpds_agency_code is not null
    then 'CONT_IDV_' || c.parent_piid || '_' || c.fpds_agency_code
    else null end as parent_generated_award_id,
  case when c.fpds_agency_code is not null then 'deterministic_dod_idv_key' else 'agency_code_resolution_required' end as identifier_resolution,
  false as child_propagation_authorized
from coded c;

comment on view research.v_usaspending_physical_fm_parent_idv_targets is
  'Research-only target list for the USAspending IDV child-awards collector. Contains only parent IDVs already qualified by the physical-FM research classifier.';

create or replace function public.internal_get_usaspending_physical_fm_parent_idvs()
returns jsonb
language sql
security definer
set search_path=''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'program_key',v.program_key,
    'program_title',v.program_title,
    'program_scope_class',v.program_scope_class,
    'site_scope_status',v.site_scope_status,
    'has_surface_work_scope',v.has_surface_work_scope,
    'parent_piid',v.parent_piid,
    'fpds_agency_code',v.fpds_agency_code,
    'parent_generated_award_id',v.parent_generated_award_id,
    'identifier_resolution',v.identifier_resolution
  ) order by v.program_title,v.parent_piid),'[]'::jsonb)
  from research.v_usaspending_physical_fm_parent_idv_targets v;
$$;

revoke all on function public.internal_get_usaspending_physical_fm_parent_idvs() from public,anon,authenticated;
grant execute on function public.internal_get_usaspending_physical_fm_parent_idvs() to service_role;

create or replace function public.internal_ingest_usaspending_task_order_batch(
  p_records jsonb,
  p_observed_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_source_id uuid;
  v_raw_inserted integer := 0;
  v_upserted integer := 0;
begin
  select id into v_source_id from ingest.sources where slug='usaspending';
  if v_source_id is null then
    raise exception 'Registered source slug usaspending is missing';
  end if;
  if p_records is null or jsonb_typeof(p_records)<>'array' then
    raise exception 'p_records must be a JSON array';
  end if;

  with incoming as (
    select * from jsonb_to_recordset(p_records) as x(
      source_native_id text, source_url text, content_hash text,
      normalized jsonb, source_payload jsonb
    )
  )
  insert into ingest.raw_records(
    source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,
    parser_version,parse_status,provisional_entity_type,within_pilot_radius,raw_payload
  )
  select
    v_source_id,i.source_native_id,i.source_url,now(),p_observed_at,i.content_hash,
    'usaspending-physical-fm-task-order-v1','normalized','federal_task_order',
    upper(coalesce(i.normalized->>'place_state_code','')) in ('KY','IN','OH'),
    jsonb_build_object(
      'normalized',coalesce(i.normalized,'{}'::jsonb),
      'source',coalesce(i.source_payload,'{}'::jsonb)
    )
  from incoming i
  where nullif(btrim(i.source_native_id),'') is not null
    and nullif(btrim(i.content_hash),'') is not null
    and nullif(btrim(i.normalized->>'parent_piid'),'') is not null
    and nullif(btrim(i.normalized->>'parent_generated_award_id'),'') is not null
  on conflict(source_id,source_native_id,content_hash) do nothing;
  get diagnostics v_raw_inserted=row_count;

  with incoming as (
    select * from jsonb_to_recordset(p_records) as x(
      source_native_id text, source_url text, content_hash text,
      normalized jsonb, source_payload jsonb
    )
  ), resolved as (
    select distinct on(i.source_native_id) i.*,r.id raw_id
    from incoming i
    join ingest.raw_records r
      on r.source_id=v_source_id
     and r.source_native_id=i.source_native_id
     and r.content_hash=i.content_hash
    order by i.source_native_id,r.retrieved_at desc,r.created_at desc
  )
  insert into procurement.federal_task_orders(
    source_record_id,source_slug,parent_generated_award_id,parent_piid,
    child_generated_award_id,child_piid,award_type,description,
    recipient_name,recipient_uei,parent_recipient_name,parent_recipient_uei,
    total_obligation,date_signed,pop_start_date,pop_end_date,pop_potential_end_date,
    awarding_agency_name,awarding_subtier_name,awarding_office_name,
    funding_agency_name,funding_subtier_name,funding_office_name,
    place_country_code,place_country_name,place_state_code,place_state_name,
    place_city_name,place_county_name,place_zip5,place_address_line1,
    naics_code,naics_description,psc_code,psc_description,attributes,
    first_observed_at,last_observed_at,updated_at
  )
  select
    r.raw_id,'usaspending',
    r.normalized->>'parent_generated_award_id',r.normalized->>'parent_piid',
    r.normalized->>'child_generated_award_id',nullif(r.normalized->>'child_piid',''),
    nullif(r.normalized->>'award_type',''),nullif(r.normalized->>'description',''),
    nullif(r.normalized->>'recipient_name',''),nullif(r.normalized->>'recipient_uei',''),
    nullif(r.normalized->>'parent_recipient_name',''),nullif(r.normalized->>'parent_recipient_uei',''),
    nullif(r.normalized->>'total_obligation','')::numeric,
    nullif(r.normalized->>'date_signed','')::date,
    nullif(r.normalized->>'pop_start_date','')::date,
    nullif(r.normalized->>'pop_end_date','')::date,
    nullif(r.normalized->>'pop_potential_end_date','')::date,
    nullif(r.normalized->>'awarding_agency_name',''),nullif(r.normalized->>'awarding_subtier_name',''),nullif(r.normalized->>'awarding_office_name',''),
    nullif(r.normalized->>'funding_agency_name',''),nullif(r.normalized->>'funding_subtier_name',''),nullif(r.normalized->>'funding_office_name',''),
    nullif(upper(r.normalized->>'place_country_code'),''),nullif(r.normalized->>'place_country_name',''),
    nullif(upper(r.normalized->>'place_state_code'),''),nullif(r.normalized->>'place_state_name',''),
    nullif(r.normalized->>'place_city_name',''),nullif(r.normalized->>'place_county_name',''),
    nullif(r.normalized->>'place_zip5',''),nullif(r.normalized->>'place_address_line1',''),
    nullif(r.normalized->>'naics_code',''),nullif(r.normalized->>'naics_description',''),
    nullif(r.normalized->>'psc_code',''),nullif(r.normalized->>'psc_description',''),
    coalesce(r.normalized->'attributes','{}'::jsonb),
    p_observed_at,p_observed_at,now()
  from resolved r
  on conflict(source_slug,child_generated_award_id) do update set
    source_record_id=excluded.source_record_id,
    parent_generated_award_id=excluded.parent_generated_award_id,
    parent_piid=excluded.parent_piid,
    child_piid=excluded.child_piid,
    award_type=excluded.award_type,
    description=excluded.description,
    recipient_name=excluded.recipient_name,
    recipient_uei=excluded.recipient_uei,
    parent_recipient_name=excluded.parent_recipient_name,
    parent_recipient_uei=excluded.parent_recipient_uei,
    total_obligation=excluded.total_obligation,
    date_signed=excluded.date_signed,
    pop_start_date=excluded.pop_start_date,
    pop_end_date=excluded.pop_end_date,
    pop_potential_end_date=excluded.pop_potential_end_date,
    awarding_agency_name=excluded.awarding_agency_name,
    awarding_subtier_name=excluded.awarding_subtier_name,
    awarding_office_name=excluded.awarding_office_name,
    funding_agency_name=excluded.funding_agency_name,
    funding_subtier_name=excluded.funding_subtier_name,
    funding_office_name=excluded.funding_office_name,
    place_country_code=excluded.place_country_code,
    place_country_name=excluded.place_country_name,
    place_state_code=excluded.place_state_code,
    place_state_name=excluded.place_state_name,
    place_city_name=excluded.place_city_name,
    place_county_name=excluded.place_county_name,
    place_zip5=excluded.place_zip5,
    place_address_line1=excluded.place_address_line1,
    naics_code=excluded.naics_code,
    naics_description=excluded.naics_description,
    psc_code=excluded.psc_code,
    psc_description=excluded.psc_description,
    attributes=excluded.attributes,
    last_observed_at=excluded.last_observed_at,
    updated_at=now();
  get diagnostics v_upserted=row_count;

  return jsonb_build_object(
    'source_slug','usaspending',
    'received',jsonb_array_length(p_records),
    'raw_inserted',v_raw_inserted,
    'task_orders_upserted',v_upserted
  );
end;
$$;

revoke all on function public.internal_ingest_usaspending_task_order_batch(jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.internal_ingest_usaspending_task_order_batch(jsonb,timestamptz) to service_role;

create or replace view research.v_physical_fm_task_order_evidence as
select
  t.program_key,
  t.program_title,
  t.program_scope_class,
  t.site_scope_status as parent_site_scope_status,
  t.has_surface_work_scope as parent_has_surface_work_scope,
  f.parent_piid,
  f.parent_generated_award_id,
  f.child_piid,
  f.child_generated_award_id,
  f.award_type,
  f.description,
  f.recipient_name,
  f.recipient_uei,
  f.total_obligation,
  f.date_signed,
  f.pop_start_date,
  f.pop_end_date,
  f.place_country_code,
  f.place_state_code,
  f.place_state_name,
  f.place_city_name,
  f.place_county_name,
  f.place_zip5,
  f.naics_code,
  f.naics_description,
  f.psc_code,
  f.psc_description,
  lower(coalesce(f.description,'')) ~ '(minimum guarantee|minimum contract guarantee)' as is_administrative_minimum_guarantee,
  upper(coalesce(f.place_state_code,'')) in ('KY','IN','OH') as in_supported_state,
  (nullif(f.place_city_name,'') is not null or nullif(f.place_zip5,'') is not null or nullif(f.place_address_line1,'') is not null) as has_site_resolution_detail,
  case
    when lower(coalesce(f.description,'')) ~ '(minimum guarantee|minimum contract guarantee)' then false
    when upper(coalesce(f.place_state_code,'')) in ('KY','IN','OH')
         and (nullif(f.place_city_name,'') is not null or nullif(f.place_zip5,'') is not null or nullif(f.place_address_line1,'') is not null) then true
    else false
  end as usable_supported_site_evidence,
  case
    when lower(coalesce(f.description,'')) ~ '(minimum guarantee|minimum contract guarantee)' then 'administrative_minimum_guarantee'
    when upper(coalesce(f.place_state_code,'')) in ('KY','IN','OH')
         and (nullif(f.place_city_name,'') is not null or nullif(f.place_zip5,'') is not null or nullif(f.place_address_line1,'') is not null) then 'supported_geography_site_candidate'
    when upper(coalesce(f.place_state_code,'')) in ('KY','IN','OH') then 'supported_geography_state_only'
    when nullif(f.place_country_code,'') is not null or nullif(f.place_state_code,'') is not null then 'outside_supported_geography'
    else 'place_of_performance_unresolved'
  end as site_evidence_status,
  false as contractor_facility_relationship_authorized
from procurement.federal_task_orders f
join research.v_usaspending_physical_fm_parent_idv_targets t
  on t.parent_piid=f.parent_piid;

comment on view research.v_physical_fm_task_order_evidence is
  'Research-only child-award evidence. Minimum-guarantee orders are retained but explicitly excluded from site evidence. Supported-geography task orders are candidates for deterministic facility resolution, not automatic relationship propagation.';

create or replace view research.v_physical_fm_task_order_summary as
select
  program_key,
  max(program_title) as program_title,
  count(*) as child_awards,
  count(*) filter (where is_administrative_minimum_guarantee) as administrative_minimum_guarantees,
  count(*) filter (where not is_administrative_minimum_guarantee) as substantive_child_awards,
  count(*) filter (where in_supported_state and not is_administrative_minimum_guarantee) as supported_state_child_awards,
  count(*) filter (where usable_supported_site_evidence) as supported_site_candidates,
  count(distinct recipient_uei) filter (where recipient_uei is not null) as distinct_recipient_ueis,
  coalesce(sum(total_obligation) filter (where not is_administrative_minimum_guarantee),0) as substantive_total_obligation
from research.v_physical_fm_task_order_evidence
group by program_key;

comment on view research.v_physical_fm_task_order_summary is
  'Research-only program summary of USAspending child awards under qualified physical-FM IDVs.';

update ingest.sources
set acquisition_method='USAspending public API; targeted IDV child-awards + award-detail endpoints',
    notes=concat_ws(' ',nullif(notes,''),'Current collector scope is intentionally limited to child awards under Scout-qualified physical facilities-management and multi-site physical-trade parent IDVs; it is not a comprehensive federal-awards mirror.'),
    updated_at=now()
where slug='usaspending';

insert into ingest.source_quality_gates(source_slug,status,reason,validated_at,validation_version,metadata,updated_at)
values(
  'usaspending','degraded',
  'Targeted physical-FM child-award collector schema is deployed; source remains degraded until a live parent-IDV/child-award validation run completes.',
  null,'usaspending-physical-fm-v1',
  jsonb_build_object('scope','qualified_physical_fm_parent_idvs','relationship_propagation_authorized',false),now()
)
on conflict(source_slug) do update set
  status=excluded.status,
  reason=excluded.reason,
  validation_version=excluded.validation_version,
  metadata=coalesce(ingest.source_quality_gates.metadata,'{}'::jsonb) || excluded.metadata,
  updated_at=now();

revoke all on procurement.federal_task_orders from anon,authenticated;
revoke all on research.v_usaspending_physical_fm_parent_idv_targets from anon,authenticated;
revoke all on research.v_physical_fm_task_order_evidence from anon,authenticated;
revoke all on research.v_physical_fm_task_order_summary from anon,authenticated;
grant select,insert,update on procurement.federal_task_orders to service_role;
grant select on research.v_usaspending_physical_fm_parent_idv_targets to service_role;
grant select on research.v_physical_fm_task_order_evidence to service_role;
grant select on research.v_physical_fm_task_order_summary to service_role;
