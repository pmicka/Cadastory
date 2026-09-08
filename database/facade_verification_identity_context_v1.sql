-- Scout by Cadastory
-- Facade verification identity-audit helper.
-- This is a verification/prioritization aid only; it never auto-promotes material or glazing evidence.

create table if not exists decisioning.facade_verification_identity_context (
  building_source_record_id uuid primary key,
  historic_resource_id uuid,
  resource_name text,
  reference_number text,
  historic_address_text text,
  historic_match_confidence numeric,
  historic_distance_m numeric,
  nearest_canonical_building_id uuid,
  nearest_distance_m numeric,
  second_nearest_canonical_building_id uuid,
  second_nearest_distance_m numeric,
  identity_margin_m numeric,
  identity_status text not null check(identity_status in ('strong_identity','probable_identity','ambiguous_identity','complex_resource','no_individual_resource')),
  evidence jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now()
);

alter table decisioning.facade_verification_identity_context enable row level security;
revoke all on decisioning.facade_verification_identity_context from public,anon,authenticated;
grant select,insert,update,delete on decisioning.facade_verification_identity_context to service_role;

create or replace function decisioning.refresh_facade_verification_identity_context_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_rows int:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  truncate decisioning.facade_verification_identity_context;

  insert into decisioning.facade_verification_identity_context(
    building_source_record_id,historic_resource_id,resource_name,reference_number,historic_address_text,
    historic_match_confidence,historic_distance_m,nearest_canonical_building_id,nearest_distance_m,
    second_nearest_canonical_building_id,second_nearest_distance_m,identity_margin_m,identity_status,evidence,refreshed_at
  )
  with queue as (
    select distinct building_source_record_id
    from decisioning.v_facade_visual_verification_queue_v1
    where verification_priority='high'
  ), best_resource as (
    select distinct on (q.building_source_record_id)
      q.building_source_record_id,h.id historic_resource_id,h.resource_name,h.reference_number,h.address_text,
      m.confidence historic_match_confidence,m.distance_m historic_distance_m,h.geometry
    from queue q
    join intelligence.historic_resource_building_matches m on m.building_source_record_id=q.building_source_record_id
    join intelligence.historic_resources h on h.id=m.historic_resource_id and h.resource_type='building'
    order by q.building_source_record_id,m.confidence desc,m.distance_m asc,h.resource_name
  ), nearest as (
    select br.*,n1.source_record_id nearest_id,n1.distance_m nearest_distance,
           n2.source_record_id second_id,n2.distance_m second_distance
    from best_resource br
    left join lateral (
      select bc.source_record_id,
        extensions.st_distance(extensions.st_pointonsurface(bc.geometry)::extensions.geography,
                               extensions.st_pointonsurface(br.geometry)::extensions.geography) distance_m
      from decisioning.building_candidates bc
      where bc.geometry is not null
        and bc.geometry OPERATOR(extensions.&&) extensions.st_expand(br.geometry,0.004)
      order by distance_m
      limit 1
    ) n1 on true
    left join lateral (
      select bc.source_record_id,
        extensions.st_distance(extensions.st_pointonsurface(bc.geometry)::extensions.geography,
                               extensions.st_pointonsurface(br.geometry)::extensions.geography) distance_m
      from decisioning.building_candidates bc
      where bc.geometry is not null
        and bc.geometry OPERATOR(extensions.&&) extensions.st_expand(br.geometry,0.004)
        and bc.source_record_id<>n1.source_record_id
      order by distance_m
      limit 1
    ) n2 on true
  )
  select n.building_source_record_id,n.historic_resource_id,n.resource_name,n.reference_number,n.address_text,
    n.historic_match_confidence,n.historic_distance_m,n.nearest_id,n.nearest_distance,n.second_id,n.second_distance,
    case when n.nearest_distance is not null and n.second_distance is not null then n.second_distance-n.nearest_distance end,
    case
      when lower(n.resource_name) ~ '(complex|boundary increase|church, rectory|church and rectory|rectory, convent|campus)' then 'complex_resource'
      when n.nearest_id=n.building_source_record_id
       and n.historic_match_confidence>=0.85
       and n.historic_distance_m<=35
       and coalesce(n.second_distance-n.nearest_distance,999)>=40 then 'strong_identity'
      when n.nearest_id=n.building_source_record_id
       and n.historic_match_confidence>=0.80
       and n.historic_distance_m<=50
       and coalesce(n.second_distance-n.nearest_distance,999)>=20 then 'probable_identity'
      else 'ambiguous_identity'
    end,
    jsonb_build_object(
      'purpose','verification_aid_only',
      'guardrail','Identity status prioritizes research and review; it does not auto-promote facade material, glazing, cleaning need, or historic ownership. Complex resources require component-level evidence before promotion.',
      'rule_version','facade-identity-v1.1'
    ),now()
  from nearest n;
  get diagnostics v_rows=row_count;

  return jsonb_build_object(
    'rows',v_rows,
    'strong_identity',(select count(*) from decisioning.facade_verification_identity_context where identity_status='strong_identity'),
    'probable_identity',(select count(*) from decisioning.facade_verification_identity_context where identity_status='probable_identity'),
    'ambiguous_identity',(select count(*) from decisioning.facade_verification_identity_context where identity_status='ambiguous_identity'),
    'complex_resource',(select count(*) from decisioning.facade_verification_identity_context where identity_status='complex_resource'),
    'refreshed_at',now()
  );
end;
$$;

revoke all on function decisioning.refresh_facade_verification_identity_context_v1() from public,anon,authenticated;
grant execute on function decisioning.refresh_facade_verification_identity_context_v1() to service_role;

create or replace view decisioning.v_facade_visual_verification_queue_v2 as
select q.*,
       i.resource_name as identity_historic_resource_name,
       i.reference_number as identity_historic_reference_number,
       i.historic_address_text as identity_historic_address_text,
       i.historic_match_confidence as identity_match_confidence,
       i.historic_distance_m as identity_distance_m,
       i.nearest_canonical_building_id as identity_nearest_canonical_building_id,
       i.nearest_distance_m as identity_nearest_distance_m,
       i.second_nearest_canonical_building_id as identity_second_nearest_canonical_building_id,
       i.second_nearest_distance_m as identity_second_nearest_distance_m,
       i.identity_margin_m,
       coalesce(i.identity_status,'no_individual_resource') as identity_status,
       i.evidence as identity_evidence
from decisioning.v_facade_visual_verification_queue_v1 q
left join decisioning.facade_verification_identity_context i using(building_source_record_id);

revoke all on decisioning.v_facade_visual_verification_queue_v2 from public,anon,authenticated;
grant select on decisioning.v_facade_visual_verification_queue_v2 to service_role;
