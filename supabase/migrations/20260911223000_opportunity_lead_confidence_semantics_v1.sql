-- Separate evidence confidence from categorical lead confidence.
-- Existing confidence remains an additive compatibility alias; new consumers should use
-- evidence_confidence plus lead_confidence_label, actionability, and buyer_readiness.

create or replace view scout.v_opportunity_lead_semantics_v1
with (security_invoker = true)
as
with base as (
  select
    s.candidate_key,
    s.confidence as evidence_confidence,
    s.signal_strength,
    s.buyer_resolution_status,
    s.buyer_contact_status,
    s.procurement_status,
    s.details,
    a.action_window_open,
    a.actionability_state,
    a.actionability_reason,
    case
      when s.buyer_resolution_status = 'organization_resolved'
        and s.buyer_contact_status in ('contact_available','route_available','durable_route_available')
        then 'buyer_ready'
      when s.buyer_resolution_status in ('organization_resolved','named_responsibility')
        then 'organization_identified'
      when s.buyer_resolution_status in ('possible_route','role_only')
        then 'route_or_role_only'
      else 'buyer_unresolved'
    end as buyer_readiness
  from scout.opportunity_search_spine s
  join scout.v_opportunity_actionability_v1 a using (candidate_key)
), labeled as (
  select
    b.*,
    case
      when b.action_window_open
        and b.procurement_status in ('open_solicitation','open_bid','rfq_open','direct_purchase_open')
        and b.details ->> 'opportunity_confirmation' = 'documented_open_purchase'
        then 'confirmed_opportunity'
      when b.action_window_open
        and b.buyer_readiness = 'buyer_ready'
        and lower(coalesce(b.signal_strength,'')) in ('high','strong','serious')
        then 'strong_lead'
      when b.action_window_open and b.buyer_readiness = 'buyer_ready'
        then 'qualified_prospect'
      when b.action_window_open
        then 'investigate'
      else 'market_context_only'
    end as lead_confidence_label
  from base b
)
select
  l.candidate_key,
  l.evidence_confidence,
  l.lead_confidence_label,
  case l.lead_confidence_label
    when 'confirmed_opportunity' then 4
    when 'strong_lead' then 3
    when 'qualified_prospect' then 2
    when 'investigate' then 1
    else 0
  end as lead_confidence_rank,
  case l.lead_confidence_label
    when 'confirmed_opportunity'
      then 'A documented open purchasing event, an open action window, and an explicit opportunity confirmation are present.'
    when 'strong_lead'
      then 'An evidence-backed action window, a reachable buyer, and a strong need signal are present; purchase intent is not confirmed.'
    when 'qualified_prospect'
      then 'An evidence-backed action window and reachable buyer are present; service need and purchase intent still require qualification.'
    when 'investigate'
      then 'An evidence-backed action window is present, but the buyer or purchasing route is not ready.'
    else 'The evidence is useful for market or account research but does not establish an immediate purchasable job.'
  end as lead_confidence_reason,
  l.action_window_open,
  l.actionability_state,
  l.actionability_reason,
  l.buyer_readiness,
  case l.buyer_readiness
    when 'buyer_ready' then 'A resolved organization and a usable contact or durable route are available.'
    when 'organization_identified' then 'A responsible organization is identified, but no usable contact or purchasing route is resolved.'
    when 'route_or_role_only' then 'Scout has only a possible route or role hypothesis, not a resolved buyer.'
    else 'No defensible buyer identity or route is resolved.'
  end as buyer_readiness_reason,
  'lead_semantics_v1'::text as semantics_contract_version
from labeled l;

comment on view scout.v_opportunity_lead_semantics_v1 is
  'Versioned semantic separation of evidence reliability, categorical lead confidence, actionability, and buyer readiness. Lead confidence is intentionally categorical until outcome data supports calibration.';
comment on column scout.v_opportunity_lead_semantics_v1.evidence_confidence is
  'Reliability of the underlying evidence or derived fact; not the probability that work is available or will convert.';
comment on column scout.v_opportunity_lead_semantics_v1.lead_confidence_label is
  'Conservative categorical assessment of whether combined evidence supports a purchasable service opportunity. Not a numeric probability.';

revoke all on scout.v_opportunity_lead_semantics_v1 from public, anon, authenticated;
grant select on scout.v_opportunity_lead_semantics_v1 to service_role;

create or replace view scout.v_opportunity_candidates_v2
with (security_invoker = true)
as
select
  c.*,
  l.evidence_confidence,
  l.lead_confidence_label,
  l.lead_confidence_rank,
  l.lead_confidence_reason,
  l.action_window_open,
  l.actionability_state,
  l.actionability_reason,
  l.buyer_readiness,
  l.buyer_readiness_reason,
  l.semantics_contract_version
from scout.v_opportunity_candidates c
join scout.v_opportunity_lead_semantics_v1 l using (candidate_key);

comment on view scout.v_opportunity_candidates_v2 is
  'Additive opportunity contract with separated evidence confidence, categorical lead confidence, actionability, and buyer readiness. The legacy confidence field is retained unchanged for compatibility and equals evidence_confidence.';
comment on column scout.v_opportunity_candidates_v2.confidence is
  'Legacy compatibility field. This is evidence confidence, not lead confidence; prefer evidence_confidence in new consumers.';

revoke all on scout.v_opportunity_candidates_v2 from public, anon, authenticated;
grant select on scout.v_opportunity_candidates_v2 to service_role;

create or replace function scout.find_opportunities_v2(
  p_service_slug text default null,
  p_county_name text default null,
  p_state_code text default null,
  p_center_lat double precision default null,
  p_center_lon double precision default null,
  p_radius_miles numeric default null,
  p_time_sensitive boolean default false,
  p_require_contact boolean default false,
  p_limit integer default 10
)
returns setof scout.v_opportunity_candidates_v2
language sql
stable
set search_path = pg_catalog, public, extensions, scout
as $function$
  select c.*
  from scout.v_opportunity_candidates_v2 c
  join scout.opportunity_search_spine s using (candidate_key)
  where (p_service_slug is null or c.service_slugs @> array[p_service_slug])
    and (p_state_code is null or s.state_code = upper(p_state_code))
    and (
      p_county_name is null
      or lower(s.county_name) = lower(regexp_replace(p_county_name, '\s+County$', '', 'i'))
    )
    and (
      p_center_lat is null or p_center_lon is null or p_radius_miles is null
      or (
        c.location is not null
        and extensions.st_dwithin(
          c.location,
          extensions.st_setsrid(extensions.st_makepoint(p_center_lon, p_center_lat), 4326)::extensions.geography,
          (p_radius_miles * 1609.344)::double precision
        )
      )
    )
    and (not p_time_sensitive or c.action_window_open)
    and (not p_require_contact or c.buyer_readiness = 'buyer_ready' or c.contact_available)
  order by
    c.lead_confidence_rank desc,
    c.action_window_open desc,
    case c.buyer_readiness
      when 'buyer_ready' then 3
      when 'organization_identified' then 2
      when 'route_or_role_only' then 1
      else 0
    end desc,
    s.strength_rank desc nulls last,
    c.evidence_confidence desc nulls last,
    c.observed_at desc nulls last,
    c.candidate_key
  limit greatest(1, least(coalesce(p_limit, 10), 100));
$function$;

revoke all on function scout.find_opportunities_v2(text,text,text,double precision,double precision,numeric,boolean,boolean,integer) from public, anon, authenticated;
grant execute on function scout.find_opportunities_v2(text,text,text,double precision,double precision,numeric,boolean,boolean,integer) to service_role;

create or replace function scout.find_time_sensitive_opportunities_v2(
  p_service_slug text default null,
  p_county_name text default null,
  p_state_code text default null,
  p_center_lat double precision default null,
  p_center_lon double precision default null,
  p_radius_miles numeric default null,
  p_require_contact boolean default false,
  p_limit integer default 10
)
returns setof scout.v_opportunity_candidates_v2
language sql
stable
set search_path = pg_catalog, public, extensions, scout
as $function$
  select *
  from scout.find_opportunities_v2(
    p_service_slug,p_county_name,p_state_code,p_center_lat,p_center_lon,p_radius_miles,
    true,p_require_contact,p_limit
  );
$function$;

revoke all on function scout.find_time_sensitive_opportunities_v2(text,text,text,double precision,double precision,numeric,boolean,integer) from public, anon, authenticated;
grant execute on function scout.find_time_sensitive_opportunities_v2(text,text,text,double precision,double precision,numeric,boolean,integer) to service_role;

-- Improve the existing time-sensitive search ranking while preserving its v1 result shape.
create or replace function scout.find_time_sensitive_opportunities(
  p_service_slug text default null,
  p_county_name text default null,
  p_state_code text default null,
  p_center_lat double precision default null,
  p_center_lon double precision default null,
  p_radius_miles numeric default null,
  p_require_contact boolean default false,
  p_limit integer default 10
)
returns setof scout.v_opportunity_candidates
language sql
stable
set search_path = pg_catalog, public, extensions, scout
as $function$
  select c.*
  from scout.v_opportunity_candidates c
  join scout.opportunity_search_spine s using (candidate_key)
  join scout.v_opportunity_lead_semantics_v1 l using (candidate_key)
  where l.action_window_open
    and (p_service_slug is null or c.service_slugs @> array[p_service_slug])
    and (p_state_code is null or s.state_code = upper(p_state_code))
    and (
      p_county_name is null
      or lower(s.county_name) = lower(regexp_replace(p_county_name, '\s+County$', '', 'i'))
    )
    and (
      p_center_lat is null or p_center_lon is null or p_radius_miles is null
      or (
        c.location is not null
        and extensions.st_dwithin(
          c.location,
          extensions.st_setsrid(extensions.st_makepoint(p_center_lon, p_center_lat), 4326)::extensions.geography,
          (p_radius_miles * 1609.344)::double precision
        )
      )
    )
    and (
      not p_require_contact
      or l.buyer_readiness = 'buyer_ready'
      or c.contact_available
    )
  order by
    l.lead_confidence_rank desc,
    case l.buyer_readiness
      when 'buyer_ready' then 3
      when 'organization_identified' then 2
      when 'route_or_role_only' then 1
      else 0
    end desc,
    coalesce(c.expires_at, c.ideal_until) asc nulls last,
    s.strength_rank desc nulls last,
    l.evidence_confidence desc nulls last,
    c.candidate_key
  limit greatest(1, least(coalesce(p_limit, 10), 100));
$function$;

comment on function scout.find_opportunities_v2(text,text,text,double precision,double precision,numeric,boolean,boolean,integer) is
  'Versioned opportunity search ranked by categorical lead confidence, actionability, and buyer readiness before evidence confidence.';
comment on function scout.find_time_sensitive_opportunities_v2(text,text,text,double precision,double precision,numeric,boolean,integer) is
  'Versioned immediate-action search returning the lead-semantics v2 candidate contract.';
