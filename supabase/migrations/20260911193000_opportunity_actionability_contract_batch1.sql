-- Batch 1: establish a strict, bounded "act now" contract without deleting
-- useful contextual opportunities from the Scout spine.

create or replace view scout.v_opportunity_actionability_v1
with (security_invoker = true)
as
select
  s.candidate_key,
  s.source_kind,
  s.time_sensitive as has_timing_context,
  case
    when not coalesce(s.time_sensitive, false) then false

    -- An event may open a window only for its primary venue when Scout has
    -- documented an asset-specific pre-event service pattern.
    when s.source_kind = 'event_detailing' then
      coalesce(s.event_context ->> 'relationship_type', '') = 'primary_venue'
      and coalesce(s.event_context ->> 'action_basis', '') = 'documented_pre_event_service_pattern'
      and coalesce(s.valid_from, s.observed_at, now()) <= now()
      and coalesce(s.expires_at, s.ideal_until) >= now()

    -- A nominal bridge inspection is actionable only before the projected
    -- inspection date, never indefinitely after an overdue estimate.
    when s.source_kind = 'bridge' then
      s.ideal_until >= now()
      and s.ideal_until <= now() + interval '90 days'

    -- Other generators need a bounded window that is open now. A recorded
    -- ideal date without an expiry is accepted only within a conservative
    -- 120-day horizon.
    else
      coalesce(s.valid_from, s.observed_at, now()) <= now()
      and (
        s.expires_at >= now()
        or (
          s.expires_at is null
          and s.ideal_until >= now()
          and s.ideal_until <= now() + interval '120 days'
        )
      )
  end as action_window_open,
  case
    when not coalesce(s.time_sensitive, false) then 'ongoing_context'
    when s.source_kind = 'event_detailing'
      and not (
        coalesce(s.event_context ->> 'relationship_type', '') = 'primary_venue'
        and coalesce(s.event_context ->> 'action_basis', '') = 'documented_pre_event_service_pattern'
      )
      then 'event_context_only'
    when s.source_kind = 'bridge' and s.ideal_until < now()
      then 'projected_date_passed'
    when coalesce(s.valid_from, s.observed_at, now()) > now()
      then 'not_yet_open'
    when s.expires_at is null and s.ideal_until is null
      then 'unbounded_context_only'
    when coalesce(s.expires_at, s.ideal_until) < now()
      then 'window_closed'
    when s.expires_at is null and s.ideal_until > now() + interval '120 days'
      then 'long_horizon_context'
    else 'action_window_open'
  end as actionability_state,
  case
    when s.source_kind = 'event_detailing'
      and not (
        coalesce(s.event_context ->> 'relationship_type', '') = 'primary_venue'
        and coalesce(s.event_context ->> 'action_basis', '') = 'documented_pre_event_service_pattern'
      )
      then 'Event proximity is context only; no asset-specific pre-event service pattern is documented.'
    when s.source_kind = 'bridge' and s.ideal_until < now()
      then 'The nominal inspection date has passed and does not prove an open procurement or unmet service need.'
    when s.expires_at is null and s.ideal_until is null
      then 'The evidence has no bounded buying or service window.'
    when coalesce(s.valid_from, s.observed_at, now()) > now()
      then 'The bounded window has not opened.'
    when coalesce(s.expires_at, s.ideal_until) < now()
      then 'The bounded window has closed.'
    when s.expires_at is null and s.ideal_until > now() + interval '120 days'
      then 'The timing horizon is too broad to imply immediate action.'
    else 'A bounded evidence-backed window is currently open.'
  end as actionability_reason,
  s.valid_from,
  s.ideal_until,
  s.expires_at,
  s.refreshed_at
from scout.opportunity_search_spine s;

comment on view scout.v_opportunity_actionability_v1 is
  'Canonical Batch 1 actionability overlay. Separates timing context from a bounded currently-open action window; routine nearby events and overdue nominal bridge dates remain context only.';

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
  join scout.v_opportunity_actionability_v1 a using (candidate_key)
  where a.action_window_open
    and (p_service_slug is null or c.service_slugs @> array[p_service_slug])
    and (p_state_code is null or s.state_code = upper(p_state_code))
    and (
      p_county_name is null
      or lower(s.county_name) = lower(regexp_replace(p_county_name, '\\s+County$', '', 'i'))
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
      or s.buyer_contact_status <> 'unresolved'
      or c.contact_available
    )
  order by
    coalesce(c.expires_at, c.ideal_until) asc nulls last,
    s.strength_rank desc nulls last,
    c.confidence desc nulls last,
    c.candidate_key
  limit greatest(1, least(coalesce(p_limit, 10), 100));
$function$;

comment on function scout.find_time_sensitive_opportunities(text,text,text,double precision,double precision,numeric,boolean,integer) is
  'Returns only opportunities with a bounded currently-open action window under scout.v_opportunity_actionability_v1. Timing context alone is insufficient.';

revoke all on scout.v_opportunity_actionability_v1 from public, anon, authenticated;
grant select on scout.v_opportunity_actionability_v1 to service_role;
