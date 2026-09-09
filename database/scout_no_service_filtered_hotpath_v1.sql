-- Scout no-service filtered opportunity-search hot path v1
--
-- Purpose:
-- - keep the existing unrestricted fast path;
-- - route no-service filtered searches through a custom-plan helper so PostgreSQL
--   sees the actual state/county/radius/time/contact predicates;
-- - isolate eligible candidate keys before expensive ranking joins;
-- - keep service-specific searches on the existing filtered path;
-- - make exact ranking ties deterministic with candidate_key as the final key.
--
-- Guardrails:
-- - text filters are SQL-quoted via format(... %L ...);
-- - numeric spatial parameters arrive as typed numeric/double values;
-- - helper remains invoker-security and postgres-only;
-- - ranking semantics are unchanged except exact ties are now deterministic.

create or replace function scout.find_opportunities_no_service_filtered_v1(
  p_county_name text default null,
  p_state_code text default null,
  p_center_lat double precision default null,
  p_center_lon double precision default null,
  p_radius_miles numeric default null,
  p_time_sensitive boolean default false,
  p_require_contact boolean default false,
  p_limit integer default 10
)
returns setof scout.v_opportunity_candidates
language plpgsql
stable
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence','cleaning'
as $function$
declare
  v_extra text := '';
  v_limit integer := greatest(1,least(coalesce(p_limit,10),100));
  v_county text;
  v_sql text;
begin
  if p_state_code is not null then
    v_extra := v_extra || format(' and s.state_code=%L', upper(p_state_code));
  end if;
  if p_county_name is not null then
    v_county := regexp_replace(p_county_name,'\s+County$','','i');
    v_extra := v_extra || format(' and lower(s.county_name)=lower(%L)', v_county);
  end if;
  if p_center_lat is not null and p_center_lon is not null and p_radius_miles is not null then
    v_extra := v_extra || format(
      ' and s.location is not null and extensions.ST_DWithin(s.location,extensions.ST_SetSRID(extensions.ST_MakePoint(%s,%s),4326)::extensions.geography,%s)',
      p_center_lon,p_center_lat,p_radius_miles*1609.344
    );
  end if;
  if p_time_sensitive then v_extra := v_extra || ' and s.time_sensitive'; end if;
  if p_require_contact then v_extra := v_extra || ' and s.effective_contact_available'; end if;

  v_sql := format($sql$
with eligible as materialized (
  select s.candidate_key
  from scout.opportunity_search_spine s
  where s.pushable
    and (s.expires_at is null or s.expires_at>=now())
    and not s.global_suppressed
    %s
), filtered as (
  select s.*,
    case when s.source_kind='event_detailing' and coalesce(s.evidence_summary->>'event_paper_trail_status','paper_trail_not_resolved')='paper_trail_not_resolved' then 1 else 0 end as unresolved_event_amplifier,
    exists (
      select 1 from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id and p.name is not null and p.website_url is not null and p.building_match_distance_m is not null and p.building_match_distance_m<=25
    ) as has_public_facility_route,
    exists (
      select 1 from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id and p.name is not null and p.building_match_distance_m is not null and p.building_match_distance_m<=25
    ) as has_resolved_presentation_name,
    coalesce(ba.account_unlock_rank_hint,0) as account_unlock_rank_hint,
    coalesce(mr.rank_adjustment_hint,0) as mining_recurrence_rank_hint,
    coalesce(mad.rank_adjustment_hint,0) as manual_access_rank_hint,
    coalesce(fan.rank_adjustment_hint,0) as ag_acute_need_rank_hint
  from eligible e
  join scout.opportunity_search_spine s using(candidate_key)
  left join lateral (
    select case
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=5 and coalesce(max(st.service_slug_count),0)>=2 then 2
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=2 then 1
      when greatest(coalesce(max(st.buyer_asset_count),0)-1,0)>=5 then 1
      else 0 end as account_unlock_rank_hint
    from scout.buyer_account_unlock_stats_v1 st
    where st.buyer_organization_id=s.buyer_organization_id
  ) ba on true
  left join scout.v_mining_stockpile_recurrence_context_v1 mr on mr.candidate_key=s.candidate_key
  left join scout.manual_access_displacement_stats_v1 mad on mad.candidate_key=s.candidate_key
  left join scout.farm_acute_need_stats_v1 fan on fan.candidate_key=s.candidate_key
), deduped as (
  select distinct on (display_dedupe_key,array_to_string(service_slugs,',')) *
  from filtered
  order by display_dedupe_key,array_to_string(service_slugs,','),
    unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,ag_acute_need_rank_hint desc,effective_contact_available desc,
    strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,account_unlock_rank_hint desc,mining_recurrence_rank_hint desc,manual_access_rank_hint desc,
    confidence desc nulls last,observed_at desc nulls last,candidate_key asc
), ranked as materialized (
  select * from deduped
  order by unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,ag_acute_need_rank_hint desc,effective_contact_available desc,
    strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,account_unlock_rank_hint desc,mining_recurrence_rank_hint desc,manual_access_rank_hint desc,
    confidence desc nulls last,observed_at desc nulls last,candidate_key asc
  limit %s
), expanded_services as (
  select r.candidate_key,u.slug
  from ranked r
  cross join lateral unnest(coalesce(r.service_slugs,'{}'::text[])) u(slug)
  union
  select r.candidate_key,st.slug
  from ranked r
  join scout.opportunity_service_classifications c
    on c.candidate_key=r.candidate_key
   and c.classification_state='supported'
  join commerce.service_types st on st.id=c.service_type_id
), service_agg as (
  select candidate_key,array_agg(slug order by slug) as service_slugs
  from expanded_services
  group by candidate_key
)
select r.candidate_key,r.source_kind,r.source_id,r.subject_type,r.subject_key,r.display_name,r.organization_id,
  coalesce(sa.service_slugs,'{}'::text[]) as service_slugs,
  r.location,r.signal_kind,r.signal_strength,r.confidence,r.observed_at,r.valid_from,r.ideal_until,r.expires_at,r.time_sensitive,r.why_now,r.effective_contact_available as contact_available,r.details
from ranked r
left join service_agg sa on sa.candidate_key=r.candidate_key
order by r.unresolved_event_amplifier asc,r.has_public_facility_route desc,r.has_resolved_presentation_name desc,r.time_sensitive desc,r.ag_acute_need_rank_hint desc,r.effective_contact_available desc,
  r.strength_rank desc,r.premium_priority_rank desc,r.global_counter_penalty asc,r.account_unlock_rank_hint desc,r.mining_recurrence_rank_hint desc,r.manual_access_rank_hint desc,
  r.confidence desc nulls last,r.observed_at desc nulls last,r.candidate_key asc
$sql$, v_extra, v_limit);
  return query execute v_sql;
end;
$function$;

revoke all on function scout.find_opportunities_no_service_filtered_v1(text,text,double precision,double precision,numeric,boolean,boolean,integer) from public;
revoke all on function scout.find_opportunities_no_service_filtered_v1(text,text,double precision,double precision,numeric,boolean,boolean,integer) from anon;
revoke all on function scout.find_opportunities_no_service_filtered_v1(text,text,double precision,double precision,numeric,boolean,boolean,integer) from authenticated;

-- Make the existing unrestricted fast path deterministic for exact ranking ties.
create or replace function scout.find_opportunities_unrestricted_fast_v1(p_limit integer default 10)
returns setof scout.v_opportunity_candidates
language sql
stable
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence','cleaning'
as $function$
with filtered as (
  select s.*,
    case when s.source_kind='event_detailing' and coalesce(s.evidence_summary->>'event_paper_trail_status','paper_trail_not_resolved')='paper_trail_not_resolved' then 1 else 0 end as unresolved_event_amplifier,
    exists (
      select 1 from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id and p.name is not null and p.website_url is not null and p.building_match_distance_m is not null and p.building_match_distance_m<=25
    ) as has_public_facility_route,
    exists (
      select 1 from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id and p.name is not null and p.building_match_distance_m is not null and p.building_match_distance_m<=25
    ) as has_resolved_presentation_name,
    coalesce(ba.account_unlock_rank_hint,0) as account_unlock_rank_hint,
    coalesce(mr.rank_adjustment_hint,0) as mining_recurrence_rank_hint,
    coalesce(mad.rank_adjustment_hint,0) as manual_access_rank_hint,
    coalesce(fan.rank_adjustment_hint,0) as ag_acute_need_rank_hint
  from scout.opportunity_search_spine s
  left join lateral (
    select case
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=5 and coalesce(max(st.service_slug_count),0)>=2 then 2
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=2 then 1
      when greatest(coalesce(max(st.buyer_asset_count),0)-1,0)>=5 then 1
      else 0 end as account_unlock_rank_hint
    from scout.buyer_account_unlock_stats_v1 st
    where st.buyer_organization_id=s.buyer_organization_id
  ) ba on true
  left join scout.v_mining_stockpile_recurrence_context_v1 mr on mr.candidate_key=s.candidate_key
  left join scout.manual_access_displacement_stats_v1 mad on mad.candidate_key=s.candidate_key
  left join scout.farm_acute_need_stats_v1 fan on fan.candidate_key=s.candidate_key
  where s.pushable
    and (s.expires_at is null or s.expires_at>=now())
    and not s.global_suppressed
), deduped as (
  select distinct on (display_dedupe_key,array_to_string(service_slugs,',')) *
  from filtered
  order by display_dedupe_key,array_to_string(service_slugs,','),
    unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,ag_acute_need_rank_hint desc,effective_contact_available desc,
    strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,account_unlock_rank_hint desc,mining_recurrence_rank_hint desc,manual_access_rank_hint desc,
    confidence desc nulls last,observed_at desc nulls last,candidate_key asc
), ranked as materialized (
  select * from deduped
  order by unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,ag_acute_need_rank_hint desc,effective_contact_available desc,
    strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,account_unlock_rank_hint desc,mining_recurrence_rank_hint desc,manual_access_rank_hint desc,
    confidence desc nulls last,observed_at desc nulls last,candidate_key asc
  limit greatest(1,least(coalesce(p_limit,10),100))
), expanded_services as (
  select r.candidate_key,u.slug
  from ranked r
  cross join lateral unnest(coalesce(r.service_slugs,'{}'::text[])) u(slug)
  union
  select r.candidate_key,st.slug
  from ranked r
  join scout.opportunity_service_classifications c
    on c.candidate_key=r.candidate_key
   and c.classification_state='supported'
  join commerce.service_types st on st.id=c.service_type_id
), service_agg as (
  select candidate_key,array_agg(slug order by slug) as service_slugs
  from expanded_services
  group by candidate_key
)
select r.candidate_key,r.source_kind,r.source_id,r.subject_type,r.subject_key,r.display_name,r.organization_id,
  coalesce(sa.service_slugs,'{}'::text[]) as service_slugs,
  r.location,r.signal_kind,r.signal_strength,r.confidence,r.observed_at,r.valid_from,r.ideal_until,r.expires_at,r.time_sensitive,r.why_now,r.effective_contact_available as contact_available,r.details
from ranked r
left join service_agg sa on sa.candidate_key=r.candidate_key
order by r.unresolved_event_amplifier asc,r.has_public_facility_route desc,r.has_resolved_presentation_name desc,r.time_sensitive desc,r.ag_acute_need_rank_hint desc,r.effective_contact_available desc,
  r.strength_rank desc,r.premium_priority_rank desc,r.global_counter_penalty asc,r.account_unlock_rank_hint desc,r.mining_recurrence_rank_hint desc,r.manual_access_rank_hint desc,
  r.confidence desc nulls last,r.observed_at desc nulls last,r.candidate_key asc;
$function$;

-- Keep the service-specific filtered path semantically unchanged, but also make
-- exact ties deterministic.
create or replace function scout.find_opportunities_filtered_v1(
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
returns setof scout.v_opportunity_candidates
language sql
stable
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence','cleaning'
as $function$
with filtered as (
  select s.*,
    case when s.source_kind='event_detailing' and coalesce(s.evidence_summary->>'event_paper_trail_status','paper_trail_not_resolved')='paper_trail_not_resolved' then 1 else 0 end as unresolved_event_amplifier,
    exists (select 1 from intelligence.premium_exterior_targets p where p.building_source_record_id=s.canonical_asset_id and p.name is not null and p.website_url is not null and p.building_match_distance_m is not null and p.building_match_distance_m<=25) as has_public_facility_route,
    exists (select 1 from intelligence.premium_exterior_targets p where p.building_source_record_id=s.canonical_asset_id and p.name is not null and p.building_match_distance_m is not null and p.building_match_distance_m<=25) as has_resolved_presentation_name,
    coalesce(ba.account_unlock_rank_hint,0) as account_unlock_rank_hint,
    coalesce(mr.rank_adjustment_hint,0) as mining_recurrence_rank_hint,
    coalesce(mad.rank_adjustment_hint,0) as manual_access_rank_hint,
    coalesce(fan.rank_adjustment_hint,0) as ag_acute_need_rank_hint
  from scout.opportunity_search_spine s
  left join lateral (
    select case
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=5 and coalesce(max(st.service_slug_count),0)>=2 then 2
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=2 then 1
      when greatest(coalesce(max(st.buyer_asset_count),0)-1,0)>=5 then 1
      else 0 end as account_unlock_rank_hint
    from scout.buyer_account_unlock_stats_v1 st where st.buyer_organization_id=s.buyer_organization_id
  ) ba on true
  left join scout.v_mining_stockpile_recurrence_context_v1 mr on mr.candidate_key=s.candidate_key
  left join scout.manual_access_displacement_stats_v1 mad on mad.candidate_key=s.candidate_key
  left join scout.farm_acute_need_stats_v1 fan on fan.candidate_key=s.candidate_key
  where (
      (p_service_slug is null and s.pushable)
      or (p_service_slug is not null and s.service_slugs @> array[p_service_slug]::text[])
      or (p_service_slug is not null and exists(
        select 1 from cleaning.v_exterior_opportunity_service_classification c
        where c.candidate_key=s.candidate_key and c.service_slug=p_service_slug and c.classification_state='supported'
      ))
    )
    and (not p_time_sensitive or s.time_sensitive)
    and (not p_require_contact or s.effective_contact_available)
    and (s.expires_at is null or s.expires_at>=now())
    and not s.global_suppressed
    and (p_state_code is null or upper(coalesce(s.state_code,''))=upper(p_state_code))
    and (p_county_name is null or lower(coalesce(s.county_name,''))=lower(regexp_replace(p_county_name,'\s+County$','','i')))
    and (
      p_center_lat is null or p_center_lon is null or p_radius_miles is null
      or (s.location is not null and extensions.ST_DWithin(s.location,extensions.ST_SetSRID(extensions.ST_MakePoint(p_center_lon,p_center_lat),4326)::extensions.geography,p_radius_miles*1609.344))
    )
), deduped as (
  select distinct on (display_dedupe_key,coalesce(p_service_slug,array_to_string(service_slugs,','))) *
  from filtered
  order by display_dedupe_key,coalesce(p_service_slug,array_to_string(service_slugs,',')),
    unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,ag_acute_need_rank_hint desc,effective_contact_available desc,
    strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,account_unlock_rank_hint desc,mining_recurrence_rank_hint desc,manual_access_rank_hint desc,
    confidence desc nulls last,observed_at desc nulls last,candidate_key asc
)
select candidate_key,source_kind,source_id,subject_type,subject_key,display_name,organization_id,
  scout.get_opportunity_supported_service_slugs(candidate_key) as service_slugs,
  location,signal_kind,signal_strength,confidence,observed_at,valid_from,ideal_until,expires_at,time_sensitive,why_now,effective_contact_available as contact_available,details
from deduped
order by unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,ag_acute_need_rank_hint desc,effective_contact_available desc,
  strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,account_unlock_rank_hint desc,mining_recurrence_rank_hint desc,manual_access_rank_hint desc,
  confidence desc nulls last,observed_at desc nulls last,candidate_key asc
limit greatest(1,least(coalesce(p_limit,10),100));
$function$;

create or replace function scout.find_opportunities(
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
returns setof scout.v_opportunity_candidates
language plpgsql
stable
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence','cleaning'
as $function$
begin
  if p_service_slug is null
     and p_county_name is null
     and p_state_code is null
     and p_center_lat is null
     and p_center_lon is null
     and p_radius_miles is null
     and not p_time_sensitive
     and not p_require_contact then
    return query select * from scout.find_opportunities_unrestricted_fast_v1(p_limit);
    return;
  end if;

  if p_service_slug is null then
    return query select * from scout.find_opportunities_no_service_filtered_v1(
      p_county_name,p_state_code,p_center_lat,p_center_lon,p_radius_miles,p_time_sensitive,p_require_contact,p_limit
    );
    return;
  end if;

  return query
  select * from scout.find_opportunities_filtered_v1(
    p_service_slug,p_county_name,p_state_code,p_center_lat,p_center_lon,p_radius_miles,p_time_sensitive,p_require_contact,p_limit
  );
end;
$function$;

drop function if exists scout.find_opportunities_no_service_dynamic_probe_v1(text,text,double precision,double precision,numeric,boolean,boolean,integer);
drop function if exists scout.find_opportunities_no_service_filtered_probe_v1(text,text,double precision,double precision,numeric,boolean,boolean,integer);
