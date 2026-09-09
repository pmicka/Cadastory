-- Search/projection/refresh wiring for manual-access displacement and agricultural acute-need v1.
--
-- This sequential migration supersedes earlier definitions of these functions while
-- preserving their public signatures. Numeric ranking hints stay internal; normal
-- lead projection exposes only qualitative evidence context and guardrails.

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
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence','cleaning'
as $function$
with filtered as (
  select s.*,
    case when s.source_kind='event_detailing'
              and coalesce(s.evidence_summary->>'event_paper_trail_status','paper_trail_not_resolved')='paper_trail_not_resolved'
         then 1 else 0 end as unresolved_event_amplifier,
    exists (
      select 1 from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id
        and p.name is not null and p.website_url is not null
        and p.building_match_distance_m is not null and p.building_match_distance_m<=25
    ) as has_public_facility_route,
    exists (
      select 1 from intelligence.premium_exterior_targets p
      where p.building_source_record_id=s.canonical_asset_id
        and p.name is not null
        and p.building_match_distance_m is not null and p.building_match_distance_m<=25
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
      else 0 end as account_unlock_rank_hint
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
        select 1 from cleaning.v_exterior_opportunity_service_classification c
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
      or (s.location is not null and extensions.ST_DWithin(
        s.location,
        extensions.ST_SetSRID(extensions.ST_MakePoint(p_center_lon,p_center_lat),4326)::extensions.geography,
        p_radius_miles*1609.344
      ))
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
select candidate_key,source_kind,source_id,subject_type,subject_key,display_name,organization_id,
  scout.get_opportunity_supported_service_slugs(candidate_key) as service_slugs,
  location,signal_kind,signal_strength,confidence,observed_at,valid_from,ideal_until,expires_at,
  time_sensitive,why_now,effective_contact_available as contact_available,details
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
    p_service_slug,p_county_name,p_state_code,p_center_lat,p_center_lon,p_radius_miles,
    p_time_sensitive,p_require_contact,least(greatest(coalesce(p_limit,10)*3,12),60)
  )
), fitted as (
  select c.*,sp.premium_priority_rank,sp.global_counter_penalty,
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
    case when exists(
      select 1 from scout.opportunity_counter_evidence e
      where e.candidate_key=c.candidate_key
        and e.provider_organization_id=p_organization_id
        and e.active and e.effective_from<=now()
        and (e.expires_at is null or e.expires_at>now())
        and e.effect='downgrade'
        and (e.service_slug is null or p_service_slug is null or e.service_slug=p_service_slug)
    ) then 1 else sp.global_counter_penalty end counter_penalty
  from candidates c
  join scout.opportunity_search_spine sp on sp.candidate_key=c.candidate_key
  left join scout.v_opportunity_property_management_context pm on pm.candidate_key=c.candidate_key
  left join lateral (
    select case
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(sp.service_slugs)),0)-1,0)>=5
           and coalesce(max(st.service_slug_count),0)>=2 then 2
      when greatest(coalesce(max(st.service_asset_count) filter(where st.service_slug=any(sp.service_slugs)),0)-1,0)>=2 then 1
      when greatest(coalesce(max(st.buyer_asset_count),0)-1,0)>=5 then 1
      else 0 end as account_unlock_rank_hint
    from scout.buyer_account_unlock_stats_v1 st
    where st.buyer_organization_id=sp.buyer_organization_id
  ) ba on true
  left join scout.v_mining_stockpile_recurrence_context_v1 mr on mr.candidate_key=c.candidate_key
  left join scout.manual_access_displacement_stats_v1 mad on mad.candidate_key=c.candidate_key
  left join scout.farm_acute_need_stats_v1 fan on fan.candidate_key=c.candidate_key
  cross join lateral (
    select scout.assess_opportunity_fit_search(p_organization_id,c.candidate_key,p_jurisdiction_code) fit_json
  ) f
  where not exists(
      select 1 from scout.opportunity_counter_evidence e
      where e.candidate_key=c.candidate_key
        and e.provider_organization_id=p_organization_id
        and e.active and e.effective_from<=now()
        and (e.expires_at is null or e.expires_at>now())
        and e.effect in ('suppress','cooldown')
        and (e.service_slug is null or p_service_slug is null or e.service_slug=p_service_slug)
    )
    and not exists(
      select 1 from commerce.provider_entry_item_state s
      where s.organization_id=p_organization_id
        and s.item_key in (c.candidate_key,'opportunity:'||c.candidate_key)
        and ((s.snoozed_until is not null and s.snoozed_until>now()) or s.dismissed_at is not null or s.completed_at is not null)
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
  select * from fitted
  where p_fit_filter is null
     or lower(overall_fit_status)=lower(p_fit_filter)
     or (lower(p_fit_filter)='pursuable' and overall_fit_status in ('ready','needs_verification','insufficient_profile'))
)
select f.candidate_key,
  coalesce(nullif(f.presentation_name,''),f.display_name),
  f.subject_type,f.service_slugs,f.why_now,f.signal_strength,f.confidence,f.time_sensitive,f.contact_available,
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
           else 5 end,
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

create or replace function scout.get_opportunity_spine_projection(p_candidate_key text)
returns jsonb
language sql
stable
set search_path to ''
as $function$
select jsonb_strip_nulls(jsonb_build_object(
  'candidate_key',s.candidate_key,
  'contract_version',s.spine_contract_version,
  'derived_from_candidate_key',s.derived_from_candidate_key,
  'derivation_kind',s.derivation_kind,
  'display_name',s.display_name,
  'subject_type',s.subject_type,
  'subject_key',s.subject_key,
  'services',to_jsonb(scout.get_opportunity_supported_service_slugs(s.candidate_key)),
  'primary_service_slug',s.primary_service_slug,
  'service_candidates',scout.get_opportunity_service_candidates(s.candidate_key),
  'target',jsonb_strip_nulls(jsonb_build_object(
    'resolution_status',s.target_resolution_status,
    'class',s.target_class,
    'name',s.target_name,
    'canonical_namespace',s.canonical_namespace,
    'canonical_asset_id',s.canonical_asset_id,
    'operational_target_key',s.operational_target_key,
    'operational_target_type',s.operational_target_type
  )),
  'location',case when s.location is null then null else jsonb_build_object(
    'lat',extensions.ST_Y(extensions.ST_PointOnSurface(s.location::extensions.geometry)),
    'lon',extensions.ST_X(extensions.ST_PointOnSurface(s.location::extensions.geometry)),
    'state_code',s.state_code,
    'county_name',s.county_name
  ) end,
  'signal',jsonb_strip_nulls(jsonb_build_object(
    'kind',s.signal_kind,'strength',s.signal_strength,'confidence',s.confidence,'why_now',s.why_now
  )),
  'timing',jsonb_strip_nulls(jsonb_build_object(
    'time_sensitive',s.time_sensitive,'window_status',s.window_status,'freshness_status',s.freshness_status,
    'valid_from',s.valid_from,'ideal_until',s.ideal_until,'expires_at',s.expires_at
  )),
  'base_pursuit_state',s.base_pursuit_state,
  'buyer',s.buyer_route_summary,
  'property_management',pm.context,
  'portfolio_account',pa.context,
  'account_unlock',au.context,
  'water_utility_portfolio',wu.context,
  'water_tank_geometry',wg.context,
  'industrial_logistics_portfolio',il.context,
  'mining_recurrence',mr.context,
  'manual_access_displacement',case when mad.candidate_key is null then null else
    mad.context || jsonb_build_object(
      'signal',mad.burden_signal,
      'substitution_scope',mad.substitution_scope,
      'refreshed_at',mad.refreshed_at
    ) end,
  'agricultural_acute_need',case when fan.candidate_key is null then null else
    fan.context || jsonb_build_object(
      'signal',fan.acute_signal,
      'extension_signal_count',fan.extension_signal_count,
      'moisture_field_count',fan.moisture_field_count,
      'refreshed_at',fan.refreshed_at
    ) end,
  'commercial_scale',s.commercial_scale_summary,
  'recurrence',s.recurrence_summary,
  'site_access',s.access_summary,
  'event',s.event_context,
  'evidence',s.evidence_summary,
  'refreshed_at',s.refreshed_at
))
from scout.opportunity_search_spine s
left join scout.v_opportunity_property_management_context pm on pm.candidate_key=s.candidate_key
left join scout.v_opportunity_portfolio_account_context pa on pa.candidate_key=s.candidate_key
left join lateral (
  select jsonb_strip_nulls(jsonb_build_object(
    'signal',a.account_unlock_signal,
    'other_pushable_asset_count',a.other_pushable_asset_count,
    'other_same_service_asset_count',a.other_same_service_asset_count,
    'service_breadth',a.other_service_slug_count,
    'documented_portfolio_account',a.documented_portfolio_account,
    'documented_portfolio_leverage',a.documented_portfolio_leverage,
    'evidence_state',a.evidence_state,
    'stats_refreshed_at',a.stats_refreshed_at,
    'guardrail','Account scale is a bounded prioritization context; it does not establish conversion probability, revenue, or permission to expose sibling sites.'
  )) as context
  from scout.opportunity_account_unlock_context_v1(s.candidate_key) a
) au on true
left join scout.v_opportunity_water_utility_context wu on wu.candidate_key=s.candidate_key
left join scout.v_opportunity_water_tank_geometry_context wg on wg.candidate_key=s.candidate_key
left join scout.v_opportunity_industrial_logistics_context il on il.candidate_key=s.candidate_key
left join lateral (
  select jsonb_strip_nulls(jsonb_build_object(
    'recurrence_evidence_state',m.recurrence_evidence_state,
    'recurrence_signal',m.recurrence_signal,
    'operator_site_count',m.operator_site_count,
    'controller_site_count',m.controller_site_count,
    'portfolio_site_count',m.portfolio_site_count,
    'bulk_inventory_workfit',m.bulk_inventory_workfit,
    'documented_interval_days',m.documented_interval_days,
    'documented_next_due_at',m.documented_next_due_at,
    'documented_cadence_confidence',m.documented_cadence_confidence,
    'cadence_interpretation',m.cadence_interpretation,
    'guardrail','Monthly/quarterly is market-pattern evidence only unless a site-specific cadence profile is documented.'
  )) as context
  from scout.v_mining_stockpile_recurrence_context_v1 m
  where m.candidate_key=s.candidate_key
) mr on true
left join scout.manual_access_displacement_stats_v1 mad on mad.candidate_key=s.candidate_key
left join scout.farm_acute_need_stats_v1 fan on fan.candidate_key=s.candidate_key
where s.candidate_key=p_candidate_key;
$function$;

create or replace function scout.refresh_opportunity_search_spine()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_stage integer:=0;
  v_now timestamptz:=clock_timestamp();
  v_classifier jsonb;
  v_account_unlock jsonb;
  v_manual_access jsonb;
  v_farm_acute jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_opportunity_search_spine',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;
  truncate scout.opportunity_search_spine_stage;
  insert into scout.opportunity_search_spine_stage
  select * from scout.v_opportunity_spine_build;
  get diagnostics v_stage=row_count;

  update scout.opportunity_search_spine_stage e
  set derived_from_candidate_key=b.candidate_key,
      derivation_kind='timing_amplifier',
      organization_id=coalesce(e.organization_id,b.organization_id),
      effective_contact_available=(e.effective_contact_available or b.effective_contact_available),
      premium_priority_rank=greatest(e.premium_priority_rank,b.premium_priority_rank),
      global_counter_penalty=greatest(e.global_counter_penalty,b.global_counter_penalty),
      global_suppressed=(e.global_suppressed or b.global_suppressed),
      buyer_resolution_status=case when e.buyer_resolution_status='unresolved' then b.buyer_resolution_status else e.buyer_resolution_status end,
      buyer_organization_id=coalesce(e.buyer_organization_id,b.buyer_organization_id),
      buyer_contact_status=case when e.buyer_contact_status='unresolved' then b.buyer_contact_status else e.buyer_contact_status end,
      procurement_status=case when e.procurement_status='unresolved' then b.procurement_status else e.procurement_status end,
      site_access_status=coalesce(e.site_access_status,b.site_access_status),
      last_access_scan_at=coalesce(e.last_access_scan_at,b.last_access_scan_at),
      target_resolution_status=case when e.target_resolution_status='unresolved' then b.target_resolution_status else e.target_resolution_status end,
      target_class=coalesce(e.target_class,b.target_class),
      target_name=coalesce(e.target_name,b.target_name),
      canonical_namespace=coalesce(e.canonical_namespace,b.canonical_namespace),
      canonical_asset_id=coalesce(e.canonical_asset_id,b.canonical_asset_id),
      operational_target_key=coalesce(e.operational_target_key,b.operational_target_key),
      operational_target_type=coalesce(e.operational_target_type,b.operational_target_type),
      buyer_name=coalesce(e.buyer_name,b.buyer_name),
      buyer_organization_type=coalesce(e.buyer_organization_type,b.buyer_organization_type),
      buyer_role_code=coalesce(e.buyer_role_code,b.buyer_role_code),
      buyer_confidence=coalesce(e.buyer_confidence,b.buyer_confidence),
      buyer_route_summary=case when coalesce(e.buyer_route_summary->>'resolution_status','unresolved')='unresolved' then b.buyer_route_summary else e.buyer_route_summary end,
      commercial_scale_status=case when e.commercial_scale_status='unknown' then b.commercial_scale_status else e.commercial_scale_status end,
      scale_metric_count=greatest(coalesce(e.scale_metric_count,0),coalesce(b.scale_metric_count,0)),
      commercial_scale_summary=case when e.commercial_scale_status='unknown' then b.commercial_scale_summary else e.commercial_scale_summary end,
      recurrence_status=case when e.recurrence_status='contextual' then b.recurrence_status else e.recurrence_status end,
      next_due_at=coalesce(e.next_due_at,b.next_due_at),
      recurrence_summary=case when e.recurrence_status='contextual' then b.recurrence_summary else e.recurrence_summary end,
      access_summary=case when coalesce(e.access_summary->>'status','not_modeled')='not_modeled' then b.access_summary else e.access_summary end,
      base_pursuit_state=case
        when (e.global_suppressed or b.global_suppressed) then 'suppressed'
        when e.expires_at is not null and e.expires_at<now() then 'expired'
        when e.valid_from is not null and e.valid_from>now() then 'not_yet_open'
        when e.time_sensitive or (e.ideal_until is not null and e.ideal_until>=now()) then 'active_signal'
        when coalesce(nullif(e.buyer_resolution_status,'unresolved'),b.buyer_resolution_status)='organization_resolved'
             and (e.effective_contact_available or b.effective_contact_available) then 'route_ready_context'
        else 'investigate' end,
      evidence_summary=jsonb_set(
        coalesce(e.evidence_summary,'{}'::jsonb),
        '{derived_from}',
        jsonb_build_object(
          'candidate_key',b.candidate_key,
          'derivation_kind','timing_amplifier',
          'inheritance','target_buyer_scale_recurrence_access_counter_evidence'
        ),
        true
      ),
      display_name=case
        when e.display_name ~ '^\{?[0-9a-fA-F-]{36}\}?$'
        then coalesce(nullif(b.target_name,''),nullif(b.display_name,''),e.display_name)
        else e.display_name end
  from scout.opportunity_search_spine_stage b
  where e.source_kind='event_detailing'
    and b.source_kind='exterior_cleaning'
    and b.subject_key=e.subject_key;

  truncate scout.opportunity_search_spine;
  insert into scout.opportunity_search_spine
  select * from scout.opportunity_search_spine_stage;

  v_classifier:=scout.refresh_exterior_opportunity_service_classifications();
  v_account_unlock:=scout.refresh_buyer_account_unlock_stats_v1();
  v_manual_access:=scout.refresh_manual_access_displacement_stats_v1();
  v_farm_acute:=scout.refresh_farm_acute_need_stats_v1();

  return jsonb_build_object(
    'refreshed_at',v_now,
    'rows',v_stage,
    'contract_version','2.0',
    'derived_event_rows',(select count(*) from scout.opportunity_search_spine_stage where source_kind='event_detailing' and derived_from_candidate_key is not null),
    'service_classifier',v_classifier,
    'account_unlock_stats',v_account_unlock,
    'manual_access_stats',v_manual_access,
    'farm_acute_need_stats',v_farm_acute
  );
end;
$function$;

create or replace function scout.refresh_storm_roof_search_spine_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_deleted integer:=0;
  v_inserted integer:=0;
  v_now timestamptz:=clock_timestamp();
  v_account_unlock jsonb;
  v_manual_access jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_storm_roof_search_spine_v1',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;

  delete from scout.opportunity_search_spine where source_kind='storm_roof';
  get diagnostics v_deleted=row_count;

  insert into scout.opportunity_search_spine
  select * from scout.v_storm_roof_spine_projection_v1;
  get diagnostics v_inserted=row_count;

  v_account_unlock:=scout.refresh_buyer_account_unlock_stats_v1();
  v_manual_access:=scout.refresh_manual_access_displacement_source_v1('storm_roof');

  return jsonb_build_object(
    'refreshed_at',v_now,
    'source_kind','storm_roof',
    'deleted_rows',v_deleted,
    'inserted_rows',v_inserted,
    'contract_version','2.0',
    'mode','direct_incremental_source_refresh',
    'account_unlock_stats',v_account_unlock,
    'manual_access_stats',v_manual_access
  );
end;
$function$;
