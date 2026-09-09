-- Scout agriculture buyer/contact bridge v1.
--
-- Connects phone-bearing farm/operator directory candidates to field-linked landholder
-- candidates only where the fully normalized mailing address matches exactly.
-- The bridge is candidate evidence, not proof of current field operation, customer
-- identity, or purchasing authority. Agricultural opportunities are then fed into the
-- existing buyer-resolution queue for unattended enrichment.

create table if not exists agriculture.farm_operator_field_bridge_candidates (
  field_id uuid not null references agriculture.field_boundaries(id) on delete cascade,
  operator_candidate_id uuid not null references agriculture.farm_entity_candidates(id) on delete cascade,
  match_basis text not null,
  match_confidence numeric not null check(match_confidence between 0 and 1),
  bridge_state text not null default 'candidate' check(bridge_state in ('candidate','corroborated','rejected')),
  supporting_landholder_candidate_ids uuid[] not null default '{}'::uuid[],
  source_evidence_ids uuid[] not null default '{}'::uuid[],
  evidence_summary jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  primary key(field_id,operator_candidate_id)
);

create index if not exists farm_operator_field_bridge_operator_idx
  on agriculture.farm_operator_field_bridge_candidates(operator_candidate_id,bridge_state);
create index if not exists farm_operator_field_bridge_state_idx
  on agriculture.farm_operator_field_bridge_candidates(bridge_state,match_confidence desc);

alter table agriculture.farm_operator_field_bridge_candidates enable row level security;
revoke all on table agriculture.farm_operator_field_bridge_candidates from public,anon,authenticated;
grant select on table agriculture.farm_operator_field_bridge_candidates to service_role;

comment on table agriculture.farm_operator_field_bridge_candidates is
  'Internal candidate bridge from phone-bearing farm/operator directory identities to fields. Exact address evidence is a research lead only and does not prove current field operation, customer identity, or purchasing authority.';

create or replace function agriculture.refresh_farm_operator_field_bridge_candidates_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_upserted integer:=0;
  v_active integer:=0;
  v_operator_count integer:=0;
  v_field_count integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  with phone_ops as (
    select c.id operator_candidate_id,
           array_agg(distinct e.id order by e.id) filter(where nullif(e.observed_phone,'') is not null) source_evidence_ids
    from agriculture.farm_entity_candidates c
    join agriculture.farm_entity_evidence e on e.candidate_id=c.id
    where c.resolution_status in ('operator_candidate','operator_confirmed')
      and nullif(e.observed_phone,'') is not null
      and c.mailing_address_normalized is not null
      and c.mailing_city_state_zip_normalized is not null
      and c.mailing_address_normalized<>''
      and c.mailing_city_state_zip_normalized<>''
    group by c.id
  ), exact_matches as (
    select f.field_id,
           p.operator_candidate_id,
           array_agg(distinct l.id order by l.id) supporting_landholder_candidate_ids,
           p.source_evidence_ids,
           array_agg(distinct l.display_name order by l.display_name) supporting_landholder_names,
           array_agg(distinct f.relationship_type order by f.relationship_type) relationship_types
    from phone_ops p
    join agriculture.farm_entity_candidates op on op.id=p.operator_candidate_id
    join agriculture.farm_entity_candidates l
      on l.id<>op.id
     and l.mailing_address_normalized=op.mailing_address_normalized
     and l.mailing_city_state_zip_normalized=op.mailing_city_state_zip_normalized
    join agriculture.field_entity_candidates f
      on f.candidate_id=l.id and f.relationship_status<>'rejected'
    group by f.field_id,p.operator_candidate_id,p.source_evidence_ids
  )
  insert into agriculture.farm_operator_field_bridge_candidates(
    field_id,operator_candidate_id,match_basis,match_confidence,bridge_state,
    supporting_landholder_candidate_ids,source_evidence_ids,evidence_summary,last_observed_at
  )
  select m.field_id,m.operator_candidate_id,'exact_normalized_mailing_address_v1',0.80,'candidate',
         m.supporting_landholder_candidate_ids,coalesce(m.source_evidence_ids,'{}'::uuid[]),
         jsonb_build_object(
           'supporting_landholder_names',to_jsonb(m.supporting_landholder_names),
           'supporting_relationship_types',to_jsonb(m.relationship_types),
           'evidence_class','candidate_operator_field_bridge',
           'match_reason','Phone-bearing operator candidate and one or more field-linked landholder candidates share the same fully normalized mailing address.',
           'guardrail','Shared mailing address is corroborating identity/context only. It does not prove that the phone-bearing party currently operates this field, is the customer, or has purchasing authority.'
         ),now()
  from exact_matches m
  on conflict(field_id,operator_candidate_id) do update set
    match_basis=excluded.match_basis,
    match_confidence=excluded.match_confidence,
    supporting_landholder_candidate_ids=excluded.supporting_landholder_candidate_ids,
    source_evidence_ids=excluded.source_evidence_ids,
    evidence_summary=excluded.evidence_summary,
    last_observed_at=now(),
    bridge_state=case
      when agriculture.farm_operator_field_bridge_candidates.bridge_state='rejected' then 'rejected'
      else agriculture.farm_operator_field_bridge_candidates.bridge_state
    end;
  get diagnostics v_upserted=row_count;

  select count(*),count(distinct operator_candidate_id),count(distinct field_id)
    into v_active,v_operator_count,v_field_count
  from agriculture.farm_operator_field_bridge_candidates
  where bridge_state in ('candidate','corroborated');

  return jsonb_build_object(
    'bridge_rows_upserted',v_upserted,
    'active_bridge_rows',v_active,
    'distinct_phone_operators',v_operator_count,
    'distinct_fields',v_field_count,
    'match_basis','exact_normalized_mailing_address_v1'
  );
end;
$function$;

revoke all on function agriculture.refresh_farm_operator_field_bridge_candidates_v1() from public,anon,authenticated;
grant execute on function agriculture.refresh_farm_operator_field_bridge_candidates_v1() to service_role;

create or replace function public.internal_seed_agricultural_buyer_enrichment(
  p_limit integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_bridge jsonb;
  v_queue_upserted integer:=0;
  v_ag_queue integer:=0;
  v_bridge_opportunities integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_limit<1 or p_limit>5000 then
    raise exception 'p_limit must be between 1 and 5000';
  end if;

  v_bridge:=agriculture.refresh_farm_operator_field_bridge_candidates_v1();

  with eligible as (
    select s.candidate_key,s.source_kind,s.source_id,s.primary_service_slug,s.time_sensitive,
           s.buyer_organization_id,s.buyer_name,s.buyer_role_code,s.buyer_contact_status,
           f.display_name farm_display_name,f.mailing_address,f.mailing_city_state_zip,
           exists(
             select 1
             from agriculture.field_entity_candidates sf
             join agriculture.farm_operator_field_bridge_candidates b on b.field_id=sf.field_id
             where sf.candidate_id=f.id and sf.relationship_status<>'rejected'
               and b.bridge_state in ('candidate','corroborated')
           ) has_operator_bridge,
           case s.primary_service_slug
             when 'agricultural-aerial-application' then 195
             when 'agricultural-crop-scouting' then 185
             when 'agricultural-multispectral-imaging' then 175
             when 'agricultural-drainage-mapping' then 165
             when 'agricultural-imaging' then 155
             else 150
           end
           +case when coalesce(s.time_sensitive,false) then 20 else 0 end
           +case when exists(
             select 1
             from agriculture.field_entity_candidates sf
             join agriculture.farm_operator_field_bridge_candidates b on b.field_id=sf.field_id
             where sf.candidate_id=f.id and sf.relationship_status<>'rejected'
               and b.bridge_state in ('candidate','corroborated')
           ) then 25 else 0 end as queue_priority
    from scout.opportunity_search_spine s
    join agriculture.farm_entity_candidates f on f.id=s.source_id
    where s.primary_service_slug like 'agricultural-%'
      and coalesce(s.global_suppressed,false)=false
      and coalesce(s.buyer_contact_status,'unresolved')='unresolved'
    order by coalesce(s.time_sensitive,false) desc,s.candidate_key
    limit p_limit
  )
  insert into scout.buyer_resolution_queue(
    candidate_key,source_kind,priority,state,missing_steps,buyer_hint,address_hint,role_code,
    attempt_count,next_attempt_at,last_error,updated_at
  )
  select e.candidate_key,e.source_kind,e.queue_priority,'pending',
         case when e.buyer_organization_id is null
              then array['organization','contact']::text[]
              else array['contact']::text[] end
         || case when e.has_operator_bridge then array['operator_bridge_verification']::text[] else '{}'::text[] end,
         coalesce(e.buyer_name,e.farm_display_name),
         nullif(concat_ws(', ',nullif(e.mailing_address,''),nullif(e.mailing_city_state_zip,'')),''),
         coalesce(e.buyer_role_code,'farm_operator_or_owner'),0,now(),null,now()
  from eligible e
  on conflict(candidate_key) do update set
    source_kind=excluded.source_kind,
    priority=greatest(scout.buyer_resolution_queue.priority,excluded.priority),
    missing_steps=excluded.missing_steps,
    buyer_hint=coalesce(excluded.buyer_hint,scout.buyer_resolution_queue.buyer_hint),
    address_hint=coalesce(excluded.address_hint,scout.buyer_resolution_queue.address_hint),
    role_code=coalesce(excluded.role_code,scout.buyer_resolution_queue.role_code),
    state=case when scout.buyer_resolution_queue.state='resolved' then 'pending'
               else scout.buyer_resolution_queue.state end,
    next_attempt_at=case when scout.buyer_resolution_queue.state='resolved' then now()
                         else scout.buyer_resolution_queue.next_attempt_at end,
    last_error=case when scout.buyer_resolution_queue.state='resolved' then null
                    else scout.buyer_resolution_queue.last_error end,
    updated_at=now();
  get diagnostics v_queue_upserted=row_count;

  select count(*) into v_ag_queue
  from scout.buyer_resolution_queue q
  where q.source_kind='farm_seasonal' and q.state in ('pending','researching','failed');

  select count(distinct s.candidate_key) into v_bridge_opportunities
  from scout.opportunity_search_spine s
  join agriculture.farm_entity_candidates f on f.id=s.source_id
  join agriculture.field_entity_candidates sf on sf.candidate_id=f.id and sf.relationship_status<>'rejected'
  join agriculture.farm_operator_field_bridge_candidates b on b.field_id=sf.field_id
    and b.bridge_state in ('candidate','corroborated')
  where s.primary_service_slug like 'agricultural-%'
    and coalesce(s.global_suppressed,false)=false;

  return jsonb_build_object(
    'bridge_refresh',v_bridge,
    'queue_rows_upserted',v_queue_upserted,
    'active_agricultural_buyer_queue',v_ag_queue,
    'agricultural_opportunities_with_phone_operator_bridge',v_bridge_opportunities,
    'guardrail','Phone-bearing operator-field bridges remain candidate evidence until independently corroborated; no operator identity or contact route is auto-promoted by this function.'
  );
end;
$function$;

revoke all on function public.internal_seed_agricultural_buyer_enrichment(integer) from public,anon,authenticated;
grant execute on function public.internal_seed_agricultural_buyer_enrichment(integer) to service_role;

comment on function public.internal_seed_agricultural_buyer_enrichment(integer) is
  'Seeds unresolved agricultural opportunity buyers into the existing buyer enrichment queue and refreshes conservative phone-bearing operator-to-field candidate bridges. Does not auto-promote operator identity or contact routes.';
