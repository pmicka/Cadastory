-- Scout opportunity-search hot path v2
--
-- Goals:
-- 1) keep the exact unrestricted Find Work path out of the generic optional-filter
--    planner shape;
-- 2) expand supported service slugs set-wise after rank/limit rather than invoking
--    a per-result helper on the unrestricted hot path;
-- 3) keep service-specific/classifier semantics unchanged via the legacy-compatible
--    filtered helper;
-- 4) remove the expensive property-management portfolio view from operator search
--    by caching only the two ranking counts it needs;
-- 5) ignore that cache when any of its canonical source families are newer than the
--    cache refresh, so stale optimization data can only fall back to neutral ranking.
--
-- The evidence-rich property-management views remain canonical for projections and
-- detail. The cache below is ranking-only and does not become a new evidence source.

create table if not exists scout.opportunity_property_management_rank_stats_v1(
  candidate_key text primary key,
  max_operating_managed_property_count integer not null default 0,
  max_active_exterior_opportunity_count integer not null default 0,
  refreshed_at timestamptz not null default now()
);

create index if not exists opportunity_property_management_rank_stats_v1_rank_idx
  on scout.opportunity_property_management_rank_stats_v1(
    max_active_exterior_opportunity_count desc,
    max_operating_managed_property_count desc,
    candidate_key
  );

revoke all on scout.opportunity_property_management_rank_stats_v1 from public,anon,authenticated;
grant select on scout.opportunity_property_management_rank_stats_v1 to service_role;

create or replace function scout.refresh_opportunity_property_management_rank_stats_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_rows integer:=0;
  v_now timestamptz:=clock_timestamp();
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_opportunity_property_management_rank_stats_v1',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;

  truncate scout.opportunity_property_management_rank_stats_v1;

  insert into scout.opportunity_property_management_rank_stats_v1(
    candidate_key,
    max_operating_managed_property_count,
    max_active_exterior_opportunity_count,
    refreshed_at
  )
  select candidate_key,
         coalesce(max_operating_managed_property_count,0),
         coalesce(max_active_exterior_opportunity_count,0),
         v_now
  from scout.v_opportunity_property_management_context;

  get diagnostics v_rows=row_count;

  return jsonb_build_object(
    'rows',v_rows,
    'refreshed_at',v_now,
    'formula_version','property_management_rank_stats_v1'
  );
end;
$function$;

comment on table scout.opportunity_property_management_rank_stats_v1 is
'Ranking-only cache of two property-management portfolio counts used by operator opportunity search. Canonical property-management evidence remains in the existing portfolio/context views.';

comment on function scout.refresh_opportunity_property_management_rank_stats_v1() is
'Rebuilds the small property-management rank cache from canonical Scout property-management context. Search ignores cache rows older than the current spine/property/crosswalk/facility/exterior-need freshness watermark.';

revoke all on function scout.refresh_opportunity_property_management_rank_stats_v1() from public,anon,authenticated;
grant execute on function scout.refresh_opportunity_property_management_rank_stats_v1() to service_role;

create or replace function scout.find_opportunities_unrestricted_fast_v1(p_limit integer default 10)
returns setof scout.v_opportunity_candidates
language sql
stable
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence','cleaning'
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
    ) as has_resolved_presentation_name,
    coalesce(ba.account_unlock_rank_hint,0) as account_unlock_rank_hint,
    coalesce(mr.rank_adjustment_hint,0) as mining_recurrence_rank_hint,
    coalesce(mad.rank_adjustment_hint,0) as manual_access_rank_hint,
    coalesce(fan.rank_adjustment_hint,0) as ag_acute_need_rank_hint
  from scout.opportunity_search_spine s
  left join lateral (
    select case
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=5
       and coalesce(max(st.service_slug_count),0)>=2 then 2
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=2 then 1
      when greatest(coalesce(max(st.buyer_asset_count),0)-1,0)>=5 then 1
      else 0
    end as account_unlock_rank_hint
    from scout.buyer_account_unlock_stats_v1 st
    where st.buyer_organization_id=s.buyer_organization_id
  ) ba on true
  left join scout.v_mining_stockpile_recurrence_context_v1 mr
    on mr.candidate_key=s.candidate_key
  left join scout.manual_access_displacement_stats_v1 mad
    on mad.candidate_key=s.candidate_key
  left join scout.farm_acute_need_stats_v1 fan
    on fan.candidate_key=s.candidate_key
  where s.pushable
    and (s.expires_at is null or s.expires_at>=now())
    and not s.global_suppressed
), deduped as (
  select distinct on (display_dedupe_key,array_to_string(service_slugs,',')) *
  from filtered
  order by display_dedupe_key,array_to_string(service_slugs,','),
    unresolved_event_amplifier asc,
    has_public_facility_route desc,
    has_resolved_presentation_name desc,
    time_sensitive desc,
    ag_acute_need_rank_hint desc,
    effective_contact_available desc,
    strength_rank desc,
    premium_priority_rank desc,
    global_counter_penalty asc,
    account_unlock_rank_hint desc,
    mining_recurrence_rank_hint desc,
    manual_access_rank_hint desc,
    confidence desc nulls last,
    observed_at desc nulls last
), ranked as materialized (
  select *
  from deduped
  order by unresolved_event_amplifier asc,
    has_public_facility_route desc,
    has_resolved_presentation_name desc,
    time_sensitive desc,
    ag_acute_need_rank_hint desc,
    effective_contact_available desc,
    strength_rank desc,
    premium_priority_rank desc,
    global_counter_penalty asc,
    account_unlock_rank_hint desc,
    mining_recurrence_rank_hint desc,
    manual_access_rank_hint desc,
    confidence desc nulls last,
    observed_at desc nulls last
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
select r.candidate_key,
       r.source_kind,
       r.source_id,
       r.subject_type,
       r.subject_key,
       r.display_name,
       r.organization_id,
       coalesce(sa.service_slugs,'{}'::text[]) as service_slugs,
       r.location,
       r.signal_kind,
       r.signal_strength,
       r.confidence,
       r.observed_at,
       r.valid_from,
       r.ideal_until,
       r.expires_at,
       r.time_sensitive,
       r.why_now,
       r.effective_contact_available as contact_available,
       r.details
from ranked r
left join service_agg sa on sa.candidate_key=r.candidate_key
order by r.unresolved_event_amplifier asc,
  r.has_public_facility_route desc,
  r.has_resolved_presentation_name desc,
  r.time_sensitive desc,
  r.ag_acute_need_rank_hint desc,
  r.effective_contact_available desc,
  r.strength_rank desc,
  r.premium_priority_rank desc,
  r.global_counter_penalty asc,
  r.account_unlock_rank_hint desc,
  r.mining_recurrence_rank_hint desc,
  r.manual_access_rank_hint desc,
  r.confidence desc nulls last,
  r.observed_at desc nulls last;
$function$;

revoke all on function scout.find_opportunities_unrestricted_fast_v1(integer) from public,anon,authenticated;

create or replace function scout.find_opportunities_filtered_v1(
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
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence','cleaning'
as $function$
with filtered as (
  select s.*,
    case when s.source_kind='event_detailing' and coalesce(s.evidence_summary->>'event_paper_trail_status','paper_trail_not_resolved')='paper_trail_not_resolved' then 1 else 0 end as unresolved_event_amplifier,
    exists (
      select 1 from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id
        and p.name is not null
        and p.website_url is not null
        and p.building_match_distance_m is not null
        and p.building_match_distance_m<=25
    ) as has_public_facility_route,
    exists (
      select 1 from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id
        and p.name is not null
        and p.building_match_distance_m is not null
        and p.building_match_distance_m<=25
    ) as has_resolved_presentation_name,
    coalesce(ba.account_unlock_rank_hint,0) as account_unlock_rank_hint,
    coalesce(mr.rank_adjustment_hint,0) as mining_recurrence_rank_hint,
    coalesce(mad.rank_adjustment_hint,0) as manual_access_rank_hint,
    coalesce(fan.rank_adjustment_hint,0) as ag_acute_need_rank_hint
  from scout.opportunity_search_spine s
  left join lateral (
    select case
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=5
       and coalesce(max(st.service_slug_count),0)>=2 then 2
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(s.service_slugs)),0)-1,0)>=2 then 1
      when greatest(coalesce(max(st.buyer_asset_count),0)-1,0)>=5 then 1
      else 0
    end as account_unlock_rank_hint
    from scout.buyer_account_unlock_stats_v1 st
    where st.buyer_organization_id=s.buyer_organization_id
  ) ba on true
  left join scout.v_mining_stockpile_recurrence_context_v1 mr on mr.candidate_key=s.candidate_key
  left join scout.manual_access_displacement_stats_v1 mad on mad.candidate_key=s.candidate_key
  left join scout.farm_acute_need_stats_v1 fan on fan.candidate_key=s.candidate_key
  where (
      (p_service_slug is null and s.pushable)
      or (p_service_slug is not null and s.service_slugs @> array[p_service_slug]::text[])
      or (p_service_slug is not null and exists(
        select 1
        from cleaning.v_exterior_opportunity_service_classification c
        where c.candidate_key=s.candidate_key
          and c.service_slug=p_service_slug
          and c.classification_state='supported'
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
    unresolved_event_amplifier asc,
    has_public_facility_route desc,
    has_resolved_presentation_name desc,
    time_sensitive desc,
    ag_acute_need_rank_hint desc,
    effective_contact_available desc,
    strength_rank desc,
    premium_priority_rank desc,
    global_counter_penalty asc,
    account_unlock_rank_hint desc,
    mining_recurrence_rank_hint desc,
    manual_access_rank_hint desc,
    confidence desc nulls last,
    observed_at desc nulls last
)
select candidate_key,
       source_kind,
       source_id,
       subject_type,
       subject_key,
       display_name,
       organization_id,
       scout.get_opportunity_supported_service_slugs(candidate_key) as service_slugs,
       location,
       signal_kind,
       signal_strength,
       confidence,
       observed_at,
       valid_from,
       ideal_until,
       expires_at,
       time_sensitive,
       why_now,
       effective_contact_available as contact_available,
       details
from deduped
order by unresolved_event_amplifier asc,
  has_public_facility_route desc,
  has_resolved_presentation_name desc,
  time_sensitive desc,
  ag_acute_need_rank_hint desc,
  effective_contact_available desc,
  strength_rank desc,
  premium_priority_rank desc,
  global_counter_penalty asc,
  account_unlock_rank_hint desc,
  mining_recurrence_rank_hint desc,
  manual_access_rank_hint desc,
  confidence desc nulls last,
  observed_at desc nulls last
limit greatest(1,least(coalesce(p_limit,10),100));
$function$;

revoke all on function scout.find_opportunities_filtered_v1(text,text,text,double precision,double precision,numeric,boolean,boolean,integer) from public,anon,authenticated;

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
    return query
      select * from scout.find_opportunities_unrestricted_fast_v1(p_limit);
    return;
  end if;

  return query
    select *
    from scout.find_opportunities_filtered_v1(
      p_service_slug,
      p_county_name,
      p_state_code,
      p_center_lat,
      p_center_lon,
      p_radius_miles,
      p_time_sensitive,
      p_require_contact,
      p_limit
    );
end;
$function$;

create or replace function scout.find_opportunities_for_operator(
  p_organization_id uuid,
  p_service_slug text default null::text,
  p_county_name text default null::text,
  p_state_code text default null::text,
  p_center_lat double precision default null::double precision,
  p_center_lon double precision default null::double precision,
  p_radius_miles numeric default null::numeric,
  p_jurisdiction_code text default null::text,
  p_time_sensitive boolean default false,
  p_require_contact boolean default false,
  p_fit_filter text default null::text,
  p_limit integer default 10
)
returns table(
  candidate_key text,
  display_name text,
  subject_type text,
  service_slugs text[],
  why_now text,
  signal_strength text,
  confidence numeric,
  time_sensitive boolean,
  contact_available boolean,
  location jsonb,
  overall_fit_status text,
  service_fits jsonb,
  fit_limits jsonb
)
language sql
stable
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence'
as $function$
with candidates as (
  select *
  from scout.find_opportunities(
    p_service_slug,
    p_county_name,
    p_state_code,
    p_center_lat,
    p_center_lon,
    p_radius_miles,
    p_time_sensitive,
    p_require_contact,
    least(greatest(coalesce(p_limit,10)*3,12),60)
  )
), fitted as (
  select c.*,
    sp.premium_priority_rank,
    sp.global_counter_penalty,
    coalesce(pm.max_operating_managed_property_count,0) as portfolio_scope_count,
    coalesce(pm.max_active_exterior_opportunity_count,0) as portfolio_active_opportunity_count,
    coalesce(ba.account_unlock_rank_hint,0) as account_unlock_rank_hint,
    coalesce(mr.rank_adjustment_hint,0) as mining_recurrence_rank_hint,
    coalesce(mad.rank_adjustment_hint,0) as manual_access_rank_hint,
    coalesce(fan.rank_adjustment_hint,0) as ag_acute_need_rank_hint,
    scout.get_opportunity_presentation_name(c.candidate_key) as presentation_name,
    (scout.get_opportunity_public_facility_route(c.candidate_key) is not null) as has_public_facility_route,
    f.fit_json,
    f.fit_json->>'overall_fit_status' overall_fit_status,
    case
      when exists(
        select 1
        from scout.opportunity_counter_evidence e
        where e.candidate_key=c.candidate_key
          and e.provider_organization_id=p_organization_id
          and e.active
          and e.effective_from<=now()
          and (e.expires_at is null or e.expires_at>now())
          and e.effect='downgrade'
          and (e.service_slug is null or p_service_slug is null or e.service_slug=p_service_slug)
      ) then 1
      else sp.global_counter_penalty
    end counter_penalty
  from candidates c
  join scout.opportunity_search_spine sp on sp.candidate_key=c.candidate_key
  left join scout.opportunity_property_management_rank_stats_v1 pm
    on pm.candidate_key=c.candidate_key
   and pm.refreshed_at >= greatest(
      coalesce((select max(x.refreshed_at) from scout.opportunity_search_spine x),'-infinity'::timestamptz),
      coalesce((select max(x.last_observed_at) from scout.property_building_links x),'-infinity'::timestamptz),
      coalesce((select max(x.last_observed_at) from scout.raw_building_canonical_crosswalks x),'-infinity'::timestamptz),
      coalesce((select max(x.last_observed_at) from core.organization_facilities x),'-infinity'::timestamptz),
      coalesce((select max(x.refreshed_at) from cleaning.exterior_need_candidates x),'-infinity'::timestamptz)
   )
  left join lateral (
    select case
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(sp.service_slugs)),0)-1,0)>=5
       and coalesce(max(st.service_slug_count),0)>=2 then 2
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(sp.service_slugs)),0)-1,0)>=2 then 1
      when greatest(coalesce(max(st.buyer_asset_count),0)-1,0)>=5 then 1
      else 0
    end as account_unlock_rank_hint
    from scout.buyer_account_unlock_stats_v1 st
    where st.buyer_organization_id=sp.buyer_organization_id
  ) ba on true
  left join scout.v_mining_stockpile_recurrence_context_v1 mr on mr.candidate_key=c.candidate_key
  left join scout.manual_access_displacement_stats_v1 mad on mad.candidate_key=c.candidate_key
  left join scout.farm_acute_need_stats_v1 fan on fan.candidate_key=c.candidate_key
  cross join lateral (
    select scout.assess_opportunity_fit_search(
      p_organization_id,
      c.candidate_key,
      p_jurisdiction_code
    ) fit_json
  ) f
  where not exists(
      select 1
      from scout.opportunity_counter_evidence e
      where e.candidate_key=c.candidate_key
        and e.provider_organization_id=p_organization_id
        and e.active
        and e.effective_from<=now()
        and (e.expires_at is null or e.expires_at>now())
        and e.effect in ('suppress','cooldown')
        and (e.service_slug is null or p_service_slug is null or e.service_slug=p_service_slug)
    )
    and not exists(
      select 1
      from commerce.provider_entry_item_state s
      where s.organization_id=p_organization_id
        and s.item_key in (c.candidate_key,'opportunity:'||c.candidate_key)
        and (
          (s.snoozed_until is not null and s.snoozed_until>now())
          or s.dismissed_at is not null
          or s.completed_at is not null
        )
    )
    and not exists(
      select 1
      from intelligence.measurement_cadence_profiles mp
      join commerce.service_types st on st.id=mp.service_type_id
      where p_service_slug is not null
        and mp.active
        and mp.subject_type=c.subject_type
        and mp.subject_key=c.subject_key
        and st.slug=p_service_slug
        and mp.next_due_at is not null
        and (mp.next_due_at-make_interval(days=>coalesce(mp.tolerance_days,0)))>now()
    )
), filtered as (
  select *
  from fitted
  where p_fit_filter is null
     or lower(overall_fit_status)=lower(p_fit_filter)
     or (
       lower(p_fit_filter)='pursuable'
       and overall_fit_status in ('ready','needs_verification','insufficient_profile')
     )
)
select f.candidate_key,
       coalesce(nullif(f.presentation_name,''),f.display_name),
       f.subject_type,
       f.service_slugs,
       f.why_now,
       f.signal_strength,
       f.confidence,
       f.time_sensitive,
       f.contact_available,
       case when f.location is null then null else jsonb_build_object(
         'lat',extensions.ST_Y(extensions.ST_PointOnSurface(f.location::extensions.geometry)),
         'lon',extensions.ST_X(extensions.ST_PointOnSurface(f.location::extensions.geometry))
       ) end,
       f.overall_fit_status,
       coalesce(f.fit_json->'service_fits','[]'::jsonb),
       coalesce(f.fit_json->'interpretation','{}'::jsonb)
from filtered f
order by case f.overall_fit_status
           when 'ready' then 0
           when 'needs_verification' then 1
           when 'insufficient_profile' then 2
           when 'not_fully_modeled' then 3
           when 'blocked' then 4
           else 5
         end,
  f.has_public_facility_route desc,
  f.time_sensitive desc,
  f.ag_acute_need_rank_hint desc,
  (f.presentation_name is not null) desc,
  f.contact_available desc,
  f.portfolio_active_opportunity_count desc,
  f.portfolio_scope_count desc,
  f.account_unlock_rank_hint desc,
  f.mining_recurrence_rank_hint desc,
  f.manual_access_rank_hint desc,
  f.counter_penalty asc,
  f.premium_priority_rank desc,
  f.confidence desc nulls last,
  f.observed_at desc nulls last
limit greatest(1,least(coalesce(p_limit,10),50));
$function$;

-- Seed/update the ranking cache from the current canonical property-management view.
select scout.refresh_opportunity_property_management_rank_stats_v1();
