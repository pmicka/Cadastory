-- Scout external-agent Find Work performance repair.
-- Preserve public ranking semantics while avoiding two nested per-candidate
-- opportunity_search_spine lookups before dedupe/limit.

create or replace function scout.find_opportunities(
  p_service_slug text default null::text,
  p_county_name text default null::text,
  p_state_code text default null::text,
  p_center_lat double precision default null::double precision,
  p_center_lon double precision default null::double precision,
  p_radius_miles numeric default null::numeric,
  p_time_sensitive boolean default false,
  p_require_contact boolean default false,
  p_limit integer default 10
)
returns setof scout.v_opportunity_candidates
language sql
stable
set search_path to 'pg_catalog', 'public', 'extensions', 'scout', 'commerce', 'intelligence'
as $function$
with filtered as (
  select s.*,
    case
      when s.source_kind='event_detailing'
       and coalesce(s.evidence_summary->>'event_paper_trail_status','paper_trail_not_resolved')='paper_trail_not_resolved'
      then 1 else 0
    end as unresolved_event_amplifier,
    exists (
      select 1
      from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id
        and p.name is not null
        and p.website_url is not null
        and p.building_match_distance_m is not null
        and p.building_match_distance_m<=25
    ) as has_public_facility_route,
    exists (
      select 1
      from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id
        and p.name is not null
        and p.building_match_distance_m is not null
        and p.building_match_distance_m<=25
    ) as has_resolved_presentation_name
  from scout.opportunity_search_spine s
  where (p_service_slug is null and s.pushable or p_service_slug is not null and s.service_slugs @> array[p_service_slug]::text[])
    and (not p_time_sensitive or s.time_sensitive)
    and (not p_require_contact or s.effective_contact_available)
    and (s.expires_at is null or s.expires_at>=now())
    and not s.global_suppressed
    and (p_state_code is null or upper(coalesce(s.state_code,''))=upper(p_state_code))
    and (p_county_name is null or lower(coalesce(s.county_name,''))=lower(regexp_replace(p_county_name,'\s+County$','','i')))
    and (
      p_center_lat is null or p_center_lon is null or p_radius_miles is null
      or (
        s.location is not null
        and extensions.ST_DWithin(
          s.location,
          extensions.ST_SetSRID(extensions.ST_MakePoint(p_center_lon,p_center_lat),4326)::extensions.geography,
          p_radius_miles*1609.344
        )
      )
    )
), deduped as (
  select distinct on (display_dedupe_key,coalesce(p_service_slug,array_to_string(service_slugs,','))) *
  from filtered
  order by display_dedupe_key,coalesce(p_service_slug,array_to_string(service_slugs,',')),
    unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,effective_contact_available desc,strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,confidence desc nulls last,observed_at desc nulls last
)
select candidate_key,source_kind,source_id,subject_type,subject_key,display_name,organization_id,service_slugs,location,signal_kind,signal_strength,confidence,observed_at,valid_from,ideal_until,expires_at,time_sensitive,why_now,effective_contact_available as contact_available,details
from deduped
order by unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,effective_contact_available desc,strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,confidence desc nulls last,observed_at desc nulls last
limit greatest(1,least(coalesce(p_limit,10),100));
$function$;
