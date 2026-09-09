-- Scout generalized operator decision-support tranche v1
-- Mirrors production migrations:
--   20260909003204 operator_contact_travel_fact_cards_v1
--   20260909003331 operator_fact_cards_contact_unresolved_fix_v1
--
-- Purpose:
--   1) derive source-backed contact trust tiers;
--   2) support operator-configurable one-way travel economics without universal defaults;
--   3) project fact-based provider lead cards without exposing composite scores.
--
-- No pilot thresholds are seeded here.

create table if not exists commerce.provider_decision_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references core.organizations(id) on delete cascade,
  service_type_id uuid references commerce.service_types(id) on delete cascade,
  travel_policy_enabled boolean not null default true,
  min_revenue_per_one_way_travel_hour numeric,
  max_one_way_travel_hours numeric,
  currency_code text not null default 'USD',
  source_kind text not null default 'operator_configured',
  confidence numeric not null default 1.0,
  notes text,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_decision_policies_min_revenue_check
    check (min_revenue_per_one_way_travel_hour is null or min_revenue_per_one_way_travel_hour >= 0),
  constraint provider_decision_policies_max_travel_check
    check (max_one_way_travel_hours is null or max_one_way_travel_hours >= 0),
  constraint provider_decision_policies_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint provider_decision_policies_source_kind_check
    check (source_kind in ('operator_configured','organization_default','imported')),
  constraint provider_decision_policies_confidence_check
    check (confidence >= 0 and confidence <= 1)
);

create unique index if not exists provider_decision_policies_org_default_uidx
  on commerce.provider_decision_policies(organization_id)
  where service_type_id is null;
create unique index if not exists provider_decision_policies_org_service_uidx
  on commerce.provider_decision_policies(organization_id,service_type_id)
  where service_type_id is not null;
create index if not exists provider_decision_policies_service_idx
  on commerce.provider_decision_policies(service_type_id,organization_id);

alter table commerce.provider_decision_policies enable row level security;
revoke all on table commerce.provider_decision_policies from public, anon, authenticated;
grant select,insert,update,delete on table commerce.provider_decision_policies to service_role;

comment on table commerce.provider_decision_policies is
'Operator-configurable decision policies. Travel thresholds express minimum acceptable gross opportunity value for travel burden; they are not travel-cost estimates and are never universal Scout defaults.';

create or replace function commerce.upsert_provider_decision_policy_v1(
  p_organization_id uuid,
  p_service_slug text default null,
  p_travel_policy_enabled boolean default true,
  p_min_revenue_per_one_way_travel_hour numeric default null,
  p_max_one_way_travel_hours numeric default null,
  p_currency_code text default 'USD',
  p_notes text default null,
  p_attributes jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_service_type_id uuid;
  v_id uuid;
begin
  if p_organization_id is null or not exists(select 1 from core.organizations o where o.id=p_organization_id) then
    raise exception 'unknown organization';
  end if;
  if p_min_revenue_per_one_way_travel_hour is not null and p_min_revenue_per_one_way_travel_hour < 0 then
    raise exception 'min revenue per travel hour must be nonnegative';
  end if;
  if p_max_one_way_travel_hours is not null and p_max_one_way_travel_hours < 0 then
    raise exception 'max one-way travel hours must be nonnegative';
  end if;
  if p_currency_code is null or upper(p_currency_code) !~ '^[A-Z]{3}$' then
    raise exception 'currency code must be a 3-letter code';
  end if;
  if p_attributes is null or jsonb_typeof(p_attributes) <> 'object' then
    raise exception 'attributes must be a JSON object';
  end if;

  if p_service_slug is not null then
    select st.id into v_service_type_id
    from commerce.service_types st
    where st.slug=p_service_slug and st.active
    limit 1;
    if v_service_type_id is null then raise exception 'unknown active service slug: %',p_service_slug; end if;
  end if;

  if v_service_type_id is null then
    update commerce.provider_decision_policies
       set travel_policy_enabled=coalesce(p_travel_policy_enabled,true),
           min_revenue_per_one_way_travel_hour=p_min_revenue_per_one_way_travel_hour,
           max_one_way_travel_hours=p_max_one_way_travel_hours,
           currency_code=upper(p_currency_code),
           source_kind='operator_configured',confidence=1.0,
           notes=p_notes,attributes=p_attributes,updated_at=now()
     where organization_id=p_organization_id and service_type_id is null
     returning id into v_id;
    if v_id is null then
      insert into commerce.provider_decision_policies(
        organization_id,service_type_id,travel_policy_enabled,
        min_revenue_per_one_way_travel_hour,max_one_way_travel_hours,
        currency_code,source_kind,confidence,notes,attributes
      ) values (
        p_organization_id,null,coalesce(p_travel_policy_enabled,true),
        p_min_revenue_per_one_way_travel_hour,p_max_one_way_travel_hours,
        upper(p_currency_code),'operator_configured',1.0,p_notes,p_attributes
      ) returning id into v_id;
    end if;
  else
    insert into commerce.provider_decision_policies(
      organization_id,service_type_id,travel_policy_enabled,
      min_revenue_per_one_way_travel_hour,max_one_way_travel_hours,
      currency_code,source_kind,confidence,notes,attributes
    ) values (
      p_organization_id,v_service_type_id,coalesce(p_travel_policy_enabled,true),
      p_min_revenue_per_one_way_travel_hour,p_max_one_way_travel_hours,
      upper(p_currency_code),'operator_configured',1.0,p_notes,p_attributes
    )
    on conflict (organization_id,service_type_id) where service_type_id is not null
    do update set
      travel_policy_enabled=excluded.travel_policy_enabled,
      min_revenue_per_one_way_travel_hour=excluded.min_revenue_per_one_way_travel_hour,
      max_one_way_travel_hours=excluded.max_one_way_travel_hours,
      currency_code=excluded.currency_code,
      source_kind='operator_configured',confidence=1.0,
      notes=excluded.notes,attributes=excluded.attributes,updated_at=now()
    returning id into v_id;
  end if;

  return v_id;
end;
$$;
revoke all on function commerce.upsert_provider_decision_policy_v1(uuid,text,boolean,numeric,numeric,text,text,jsonb) from public, anon, authenticated;
grant execute on function commerce.upsert_provider_decision_policy_v1(uuid,text,boolean,numeric,numeric,text,text,jsonb) to service_role;

create or replace view scout.v_opportunity_contact_trust_v1
with (security_invoker=true)
as
select
  r.candidate_key,
  r.organization_id as buyer_organization_id,
  r.organization_name as buyer_name,
  r.resolution_status as buyer_resolution_status,
  r.contact_point_id,
  r.contact_scope,
  r.contact_channel_type,
  r.contact_stability_class,
  r.contact_confidence,
  cp.source_authority as contact_source_authority,
  cp.source_url as contact_source_url,
  cp.observed_on as contact_observed_on,
  coalesce(r.contact_verify_after,cp.verify_after) as contact_verify_after,
  case
    when r.contact_point_id is not null
      and nullif(r.contact_value,'') is not null
      and r.contact_channel_type in ('email','phone')
      and coalesce(r.contact_stability_class,cp.stability_class)='role_holder'
      and coalesce(r.contact_scope,cp.contact_scope) not in ('general_switchboard','supplier_registration')
      and coalesce(r.contact_confidence,cp.confidence,0) >= 0.90
      and nullif(cp.source_authority,'') is not null
      and nullif(cp.source_url,'') is not null
      and (coalesce(r.contact_verify_after,cp.verify_after) is null or coalesce(r.contact_verify_after,cp.verify_after) >= current_date)
      then 'VERIFIED DIRECT'
    when r.contact_point_id is not null
      or nullif(r.contact_value,'') is not null
      or r.procurement_contact_point_id is not null
      or nullif(r.procurement_contact_value,'') is not null
      or r.resolution_status in ('organization_resolved','named_responsibility','possible_route','role_only')
      then 'PUBLIC / UNVERIFIED'
    else 'UNRESOLVED'
  end as contact_trust_badge,
  case
    when r.contact_point_id is not null
      and nullif(r.contact_value,'') is not null
      and r.contact_channel_type in ('email','phone')
      and coalesce(r.contact_stability_class,cp.stability_class)='role_holder'
      and coalesce(r.contact_scope,cp.contact_scope) not in ('general_switchboard','supplier_registration')
      and coalesce(r.contact_confidence,cp.confidence,0) >= 0.90
      and nullif(cp.source_authority,'') is not null
      and nullif(cp.source_url,'') is not null
      and (coalesce(r.contact_verify_after,cp.verify_after) is null or coalesce(r.contact_verify_after,cp.verify_after) >= current_date)
      then 'current source-backed role-holder email/phone with >=0.90 contact confidence'
    when r.contact_point_id is not null or nullif(r.contact_value,'') is not null or r.procurement_contact_point_id is not null or nullif(r.procurement_contact_value,'') is not null
      then 'public contact or procurement route exists but does not satisfy direct-contact verification criteria'
    when r.resolution_status in ('organization_resolved','named_responsibility','possible_route','role_only')
      then 'buyer responsibility is partially resolved but no qualifying direct contact is established'
    else 'no usable buyer contact route is established'
  end as contact_trust_basis,
  case when coalesce(r.contact_verify_after,cp.verify_after) is not null and coalesce(r.contact_verify_after,cp.verify_after) < current_date then true else false end as contact_verification_stale,
  r.procurement_status,
  r.refreshed_at
from scout.opportunity_buyer_routes r
left join core.organization_contact_points cp on cp.id=r.contact_point_id;

create or replace function decisioning.evaluate_provider_travel_economics_v1(
  p_organization_id uuid,
  p_service_type_id uuid,
  p_one_way_travel_hours numeric,
  p_estimated_revenue numeric
) returns table(
  policy_id uuid, policy_scope text, currency_code text,
  min_revenue_per_one_way_travel_hour numeric, max_one_way_travel_hours numeric,
  one_way_travel_hours numeric, estimated_revenue numeric,
  required_revenue_for_travel numeric, revenue_above_travel_threshold numeric,
  travel_gate_state text, travel_gate_pass boolean, interpretation text
)
language sql stable security invoker set search_path=''
as $$
with policy as (
  select p.*,case when p.service_type_id is not null then 'service_specific' else 'organization_default' end as scope_label
  from commerce.provider_decision_policies p
  where p.organization_id=p_organization_id
    and (p.service_type_id=p_service_type_id or p.service_type_id is null)
  order by (p.service_type_id is not null) desc
  limit 1
)
select p.id,p.scope_label,p.currency_code,p.min_revenue_per_one_way_travel_hour,p.max_one_way_travel_hours,
       p_one_way_travel_hours,p_estimated_revenue,
       case when p.min_revenue_per_one_way_travel_hour is not null and p_one_way_travel_hours is not null then p.min_revenue_per_one_way_travel_hour*p_one_way_travel_hours end,
       case when p.min_revenue_per_one_way_travel_hour is not null and p_one_way_travel_hours is not null and p_estimated_revenue is not null then p_estimated_revenue-(p.min_revenue_per_one_way_travel_hour*p_one_way_travel_hours) end,
       case
         when p.id is null then 'policy_not_configured'
         when not p.travel_policy_enabled then 'policy_disabled'
         when p_one_way_travel_hours is null then 'travel_time_unknown'
         when p_estimated_revenue is null then 'estimated_revenue_unknown'
         when p.max_one_way_travel_hours is not null and p_one_way_travel_hours>p.max_one_way_travel_hours then 'max_travel_exceeded'
         when p.min_revenue_per_one_way_travel_hour is null then 'threshold_not_configured'
         when p_estimated_revenue>=p.min_revenue_per_one_way_travel_hour*p_one_way_travel_hours then 'pass'
         else 'fail' end,
       case
         when p.id is null or not p.travel_policy_enabled or p_one_way_travel_hours is null or p_estimated_revenue is null or p.min_revenue_per_one_way_travel_hour is null then null
         when p.max_one_way_travel_hours is not null and p_one_way_travel_hours>p.max_one_way_travel_hours then false
         else p_estimated_revenue>=p.min_revenue_per_one_way_travel_hour*p_one_way_travel_hours end,
       'The revenue-per-travel-hour threshold is an operator-configured minimum acceptable gross opportunity value for one-way travel burden. It is not a calculated travel expense or universal Scout rule.'::text
from policy p
union all
select null,null,null,null,null,p_one_way_travel_hours,p_estimated_revenue,null,null,'policy_not_configured',null,
       'No operator travel-economics policy is configured; Scout must not infer one from distance or another operator.'::text
where not exists(select 1 from policy);
$$;
revoke all on function decisioning.evaluate_provider_travel_economics_v1(uuid,uuid,numeric,numeric) from public, anon, authenticated;
grant execute on function decisioning.evaluate_provider_travel_economics_v1(uuid,uuid,numeric,numeric) to service_role;

create or replace function scout.get_provider_fact_lead_cards_v1(
  p_organization_id uuid,
  p_candidate_keys text[]
) returns table(
  candidate_key text, display_name text, target_name text, target_class text, service_slugs text[],
  state_code text, county_name text,
  estimated_revenue_usd numeric, one_way_travel_hours numeric, travel_distance_miles numeric, execution_method text,
  travel_required_revenue_usd numeric, travel_revenue_surplus_usd numeric, travel_gate_state text, travel_gate_pass boolean,
  contact_trust_badge text, contact_trust_basis text, contact_confidence numeric, contact_source_authority text,
  contact_observed_on date, contact_verify_after date,
  buyer_name text, buyer_resolution_status text, procurement_status text,
  signal_kind text, signal_strength text, signal_confidence numeric, why_now text, time_sensitive boolean, window_status text,
  recurrence_status text, next_due_at timestamptz, site_access_status text, event_title text, event_start date,
  evidence_summary jsonb, fact_card jsonb
)
language sql stable security invoker set search_path=''
as $$
select
  c.candidate_key,c.display_name,c.target_name,c.target_class,c.service_slugs,c.state_code,c.county_name,
  ef.estimated_revenue_usd,ef.one_way_travel_hours,ef.travel_distance_miles,ef.execution_method,
  te.required_revenue_for_travel,te.revenue_above_travel_threshold,te.travel_gate_state,te.travel_gate_pass,
  coalesce(ct.contact_trust_badge,'UNRESOLVED'),
  coalesce(ct.contact_trust_basis,'no buyer-route record is established for this candidate'),
  ct.contact_confidence,ct.contact_source_authority,ct.contact_observed_on,ct.contact_verify_after,
  c.buyer_name,c.buyer_resolution_status,c.procurement_status,
  c.signal_kind,c.signal_strength,c.confidence,c.why_now,c.time_sensitive,c.window_status,c.recurrence_status,c.next_due_at,
  c.site_access_status,c.event_title,c.event_start,c.evidence_summary,
  jsonb_build_object(
    'economics',jsonb_build_object(
      'estimated_revenue_usd',ef.estimated_revenue_usd,
      'one_way_travel_hours',ef.one_way_travel_hours,
      'travel_distance_miles',ef.travel_distance_miles,
      'required_revenue_for_travel_usd',te.required_revenue_for_travel,
      'revenue_above_travel_threshold_usd',te.revenue_above_travel_threshold,
      'travel_gate_state',te.travel_gate_state,
      'travel_gate_pass',te.travel_gate_pass,
      'guardrail','Travel economics use explicit provider policy plus explicit revenue/travel facts; unknown inputs stay unknown.'
    ),
    'execution',jsonb_build_object('execution_method',ef.execution_method,'site_access_status',c.site_access_status,'access_summary',c.access_summary),
    'need_and_timing',jsonb_build_object(
      'signal_kind',c.signal_kind,'signal_strength',c.signal_strength,'signal_confidence',c.confidence,
      'why_now',c.why_now,'time_sensitive',c.time_sensitive,'window_status',c.window_status,
      'recurrence_status',c.recurrence_status,'next_due_at',c.next_due_at,'event_title',c.event_title,'event_start',c.event_start
    ),
    'buyer',jsonb_build_object(
      'buyer_name',c.buyer_name,'buyer_resolution_status',c.buyer_resolution_status,
      'contact_trust_badge',coalesce(ct.contact_trust_badge,'UNRESOLVED'),
      'contact_trust_basis',coalesce(ct.contact_trust_basis,'no buyer-route record is established for this candidate'),
      'contact_confidence',ct.contact_confidence,'contact_source_authority',ct.contact_source_authority,
      'contact_observed_on',ct.contact_observed_on,'contact_verify_after',ct.contact_verify_after,
      'procurement_status',c.procurement_status
    ),
    'evidence',c.evidence_summary,
    'presentation_contract',jsonb_build_object(
      'composite_score_exposed',false,
      'unknown_facts_remain_null',true,
      'internal_ranking_is_not_presented_as_operator_fact',true
    )
  )
from scout.v_opportunity_spine_cards c
join scout.opportunity_search_spine s on s.candidate_key=c.candidate_key
left join scout.v_opportunity_contact_trust_v1 ct on ct.candidate_key=c.candidate_key
left join lateral (
  select
    max(x.value_numeric) filter(where x.facet_key='estimated_revenue_usd') as estimated_revenue_usd,
    max(x.value_numeric) filter(where x.facet_key='one_way_travel_hours') as one_way_travel_hours,
    max(x.value_numeric) filter(where x.facet_key='travel_distance_miles') as travel_distance_miles,
    max(x.value_text) filter(where x.facet_key='execution_method') as execution_method
  from (
    select distinct on (f.facet_key) f.facet_key,f.value_numeric,f.value_text
    from scout.opportunity_facets f
    where f.candidate_key=c.candidate_key and f.active
      and f.facet_key in ('estimated_revenue_usd','one_way_travel_hours','travel_distance_miles','execution_method')
      and (f.provider_organization_id=p_organization_id or f.provider_organization_id is null)
      and (f.expires_at is null or f.expires_at>now())
    order by f.facet_key,(f.provider_organization_id=p_organization_id) desc,f.confidence desc nulls last,f.observed_at desc nulls last,f.updated_at desc
  ) x
) ef on true
left join commerce.service_types st on st.slug=s.primary_service_slug
left join lateral decisioning.evaluate_provider_travel_economics_v1(p_organization_id,st.id,ef.one_way_travel_hours,ef.estimated_revenue_usd) te on true
where p_candidate_keys is not null and c.candidate_key=any(p_candidate_keys)
order by array_position(p_candidate_keys,c.candidate_key);
$$;
revoke all on function scout.get_provider_fact_lead_cards_v1(uuid,text[]) from public, anon, authenticated;
grant execute on function scout.get_provider_fact_lead_cards_v1(uuid,text[]) to service_role;

comment on function scout.get_provider_fact_lead_cards_v1(uuid,text[]) is
'Provider-aware factual lead-card projection. Revenue and travel remain null unless explicitly evidenced in opportunity facets. No operator-facing composite score is returned.';
