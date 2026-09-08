-- Scout USAspending authoritative parent-IDV spine v1
-- Stores verified master-contract identity separately from child task-order evidence.

create table if not exists procurement.federal_parent_idvs (
  id uuid primary key default gen_random_uuid(),
  source_record_id uuid not null references ingest.raw_records(id) on delete restrict,
  source_slug text not null default 'usaspending' references ingest.sources(slug) on update cascade on delete restrict,
  generated_award_id text not null,
  piid text not null,
  award_type text,
  description text,
  recipient_name text,
  recipient_uei text,
  ultimate_parent_recipient_name text,
  ultimate_parent_recipient_uei text,
  total_obligation numeric,
  base_exercised_options numeric,
  base_and_all_options numeric,
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
  naics_code text,
  naics_description text,
  psc_code text,
  psc_description text,
  attributes jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_slug,generated_award_id),
  unique(source_slug,piid)
);
create index if not exists federal_parent_idvs_recipient_uei_idx on procurement.federal_parent_idvs(recipient_uei);
comment on table procurement.federal_parent_idvs is 'Internal authoritative USAspending parent IDV evidence for Scout-qualified physical-FM vehicles. Master award identity is stored separately from child task orders and does not authorize facility propagation.';

create or replace function public.internal_ingest_usaspending_parent_idv_batch(p_records jsonb,p_observed_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_source_id uuid; v_raw_inserted integer:=0; v_upserted integer:=0;
begin
  select id into v_source_id from ingest.sources where slug='usaspending';
  if v_source_id is null then raise exception 'Registered source slug usaspending is missing'; end if;
  if p_records is null or jsonb_typeof(p_records)<>'array' then raise exception 'p_records must be a JSON array'; end if;
  with incoming as (select * from jsonb_to_recordset(p_records) as x(source_native_id text,source_url text,content_hash text,normalized jsonb,source_payload jsonb))
  insert into ingest.raw_records(source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,parser_version,parse_status,provisional_entity_type,within_pilot_radius,raw_payload)
  select v_source_id,i.source_native_id,i.source_url,now(),p_observed_at,i.content_hash,'usaspending-physical-fm-parent-idv-v1','normalized','federal_parent_idv',null,jsonb_build_object('normalized',coalesce(i.normalized,'{}'::jsonb),'source',coalesce(i.source_payload,'{}'::jsonb))
  from incoming i where nullif(btrim(i.source_native_id),'') is not null and nullif(btrim(i.content_hash),'') is not null and nullif(btrim(i.normalized->>'piid'),'') is not null and nullif(btrim(i.normalized->>'generated_award_id'),'') is not null
  on conflict(source_id,source_native_id,content_hash) do nothing; get diagnostics v_raw_inserted=row_count;
  with incoming as (select * from jsonb_to_recordset(p_records) as x(source_native_id text,source_url text,content_hash text,normalized jsonb,source_payload jsonb)), resolved as (
    select distinct on(i.source_native_id) i.*,r.id raw_id from incoming i join ingest.raw_records r on r.source_id=v_source_id and r.source_native_id=i.source_native_id and r.content_hash=i.content_hash order by i.source_native_id,r.retrieved_at desc,r.created_at desc
  )
  insert into procurement.federal_parent_idvs(source_record_id,source_slug,generated_award_id,piid,award_type,description,recipient_name,recipient_uei,ultimate_parent_recipient_name,ultimate_parent_recipient_uei,total_obligation,base_exercised_options,base_and_all_options,date_signed,pop_start_date,pop_end_date,pop_potential_end_date,awarding_agency_name,awarding_subtier_name,awarding_office_name,funding_agency_name,funding_subtier_name,funding_office_name,naics_code,naics_description,psc_code,psc_description,attributes,first_observed_at,last_observed_at,updated_at)
  select r.raw_id,'usaspending',r.normalized->>'generated_award_id',r.normalized->>'piid',nullif(r.normalized->>'award_type',''),nullif(r.normalized->>'description',''),nullif(r.normalized->>'recipient_name',''),nullif(r.normalized->>'recipient_uei',''),nullif(r.normalized->>'ultimate_parent_recipient_name',''),nullif(r.normalized->>'ultimate_parent_recipient_uei',''),nullif(r.normalized->>'total_obligation','')::numeric,nullif(r.normalized->>'base_exercised_options','')::numeric,nullif(r.normalized->>'base_and_all_options','')::numeric,nullif(r.normalized->>'date_signed','')::date,nullif(r.normalized->>'pop_start_date','')::date,nullif(r.normalized->>'pop_end_date','')::date,nullif(r.normalized->>'pop_potential_end_date','')::date,nullif(r.normalized->>'awarding_agency_name',''),nullif(r.normalized->>'awarding_subtier_name',''),nullif(r.normalized->>'awarding_office_name',''),nullif(r.normalized->>'funding_agency_name',''),nullif(r.normalized->>'funding_subtier_name',''),nullif(r.normalized->>'funding_office_name',''),nullif(r.normalized->>'naics_code',''),nullif(r.normalized->>'naics_description',''),nullif(r.normalized->>'psc_code',''),nullif(r.normalized->>'psc_description',''),coalesce(r.normalized->'attributes','{}'::jsonb),p_observed_at,p_observed_at,now()
  from resolved r
  on conflict(source_slug,generated_award_id) do update set source_record_id=excluded.source_record_id,piid=excluded.piid,award_type=excluded.award_type,description=excluded.description,recipient_name=excluded.recipient_name,recipient_uei=excluded.recipient_uei,ultimate_parent_recipient_name=excluded.ultimate_parent_recipient_name,ultimate_parent_recipient_uei=excluded.ultimate_parent_recipient_uei,total_obligation=excluded.total_obligation,base_exercised_options=excluded.base_exercised_options,base_and_all_options=excluded.base_and_all_options,date_signed=excluded.date_signed,pop_start_date=excluded.pop_start_date,pop_end_date=excluded.pop_end_date,pop_potential_end_date=excluded.pop_potential_end_date,awarding_agency_name=excluded.awarding_agency_name,awarding_subtier_name=excluded.awarding_subtier_name,awarding_office_name=excluded.awarding_office_name,funding_agency_name=excluded.funding_agency_name,funding_subtier_name=excluded.funding_subtier_name,funding_office_name=excluded.funding_office_name,naics_code=excluded.naics_code,naics_description=excluded.naics_description,psc_code=excluded.psc_code,psc_description=excluded.psc_description,attributes=excluded.attributes,last_observed_at=excluded.last_observed_at,updated_at=now(); get diagnostics v_upserted=row_count;
  return jsonb_build_object('received',jsonb_array_length(p_records),'raw_inserted',v_raw_inserted,'parent_idvs_upserted',v_upserted);
end; $$;
revoke all on function public.internal_ingest_usaspending_parent_idv_batch(jsonb,timestamptz) from public,anon,authenticated; grant execute on function public.internal_ingest_usaspending_parent_idv_batch(jsonb,timestamptz) to service_role;

create or replace view research.v_physical_fm_parent_idv_identity as
select t.program_key,t.program_title,t.program_scope_class,t.site_scope_status,p.generated_award_id,p.piid,p.recipient_name,p.recipient_uei,p.ultimate_parent_recipient_name,p.ultimate_parent_recipient_uei,p.total_obligation,p.base_and_all_options,p.date_signed,p.pop_start_date,p.pop_end_date,p.awarding_agency_name,p.awarding_subtier_name,p.awarding_office_name,p.naics_code,p.psc_code,false as facility_relationship_authorized
from procurement.federal_parent_idvs p join research.usaspending_physical_fm_parent_idv_targets t on t.parent_piid=p.piid;
comment on view research.v_physical_fm_parent_idv_identity is 'Research-only authoritative parent-IDV identity for qualified physical-FM vehicles. Recipient UEI is suitable as an identity key, not as permission to infer facility coverage.';
revoke all on procurement.federal_parent_idvs from anon,authenticated; revoke all on research.v_physical_fm_parent_idv_identity from anon,authenticated; grant select,insert,update on procurement.federal_parent_idvs to service_role; grant select on research.v_physical_fm_parent_idv_identity to service_role;
