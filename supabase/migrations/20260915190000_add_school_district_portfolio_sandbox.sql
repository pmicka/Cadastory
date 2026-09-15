create or replace function public.scout_get_component_sandbox_school_district_portfolio_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
with facilities as (
  select distinct on (r.raw_payload->>'nces_school_id')
    r.raw_payload->>'nces_school_id' as nces_school_id,
    r.raw_payload->>'school_name' as school_name,
    r.raw_payload->>'address_1' as address_1,
    r.raw_payload->>'city' as city,
    trim(r.raw_payload->>'state') as state_code,
    r.raw_payload->>'zip' as zip,
    (r.raw_payload->>'longitude')::double precision as lon,
    (r.raw_payload->>'latitude')::double precision as lat,
    r.raw_payload->>'school_year' as school_year,
    r.retrieved_at
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='nces-edge-public-schools-2425'
    and r.provisional_entity_type='public_school_facility'
    and r.raw_payload->>'state_district_id'='IN-7255'
    and nullif(r.raw_payload->>'nces_school_id','') is not null
    and nullif(r.raw_payload->>'longitude','') is not null
    and nullif(r.raw_payload->>'latitude','') is not null
  order by r.raw_payload->>'nces_school_id',r.retrieved_at desc,r.id
), roof as (
  select
    r.raw_payload->>'project_title' as project_title,
    (r.raw_payload->>'estimated_cost')::numeric as estimated_cost,
    r.raw_payload->>'start_date_text' as start_date_text,
    r.raw_payload->>'end_date_text' as end_date_text,
    (r.raw_payload->>'plan_year')::integer as plan_year,
    r.raw_payload->>'plan_id' as plan_id,
    r.raw_payload->>'extraction_confidence' as extraction_confidence,
    to_char(to_timestamp(r.raw_payload->>'date_submitted','MM/DD/YYYY HH12:MI:SS AM') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') as plan_submitted_at,
    r.retrieved_at
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='indiana-dlgf-school-capital-projects'
    and r.provisional_entity_type='indiana_school_capital_project_candidate'
    and r.raw_payload->>'unit_code'='7255'
    and r.raw_payload->>'candidate_kind'='capital_project'
    and lower(trim(r.raw_payload->>'project_title'))='roof project'
  order by r.retrieved_at desc,r.id
  limit 1
)
select jsonb_build_object(
  'contract_version','school_district_portfolio_map_v1',
  'account_name','Scott County School District 2',
  'district_key','IN-7255',
  'nces_district_id','1810020',
  'dlgf_unit_id','1288',
  'dlgf_unit_code','7255',
  'scope','documented_public_school_roster',
  'facility_source_slug','nces-edge-public-schools-2425',
  'signal_source_slug','indiana-dlgf-school-capital-projects',
  'relationship','district_membership',
  'generated_at',statement_timestamp(),
  'facility_observed_at',max(f.retrieved_at),
  'capital_plan_observed_at',(select retrieved_at from roof),
  'members',jsonb_agg(jsonb_build_object('id',f.nces_school_id,'name',f.school_name,'address',f.address_1,'city',f.city,'state_code',f.state_code,'zip',f.zip,'point',jsonb_build_object('type','Point','coordinates',jsonb_build_array(f.lon,f.lat)),'school_year',f.school_year,'observed_at',f.retrieved_at) order by f.school_name,f.nces_school_id),
  'capital_signals',(select jsonb_build_array(jsonb_build_object('id','dlgf:10695:roof-project','kind','district_roof_capital_project','project_title',roof.project_title,'estimated_cost',roof.estimated_cost,'start_date_text',roof.start_date_text,'end_date_text',roof.end_date_text,'plan_year',roof.plan_year,'plan_id',roof.plan_id,'plan_submitted_at',roof.plan_submitted_at,'extraction_confidence',roof.extraction_confidence,'site_attribution','district_only_unresolved','observed_at',roof.retrieved_at)) from roof)
)
from facilities f
having count(*) between 1 and 100 and (select count(*) from roof)=1;
$function$;
revoke all on function public.scout_get_component_sandbox_school_district_portfolio_v1_internal() from public,anon,authenticated;
grant execute on function public.scout_get_component_sandbox_school_district_portfolio_v1_internal() to service_role;
