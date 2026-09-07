-- Scout by Cadastory
-- Evidence-backed exterior-cleaning opportunity specialization.
-- Keeps the canonical opportunity spine unchanged; derives service candidates live.

create or replace view cleaning.v_exterior_opportunity_service_classification as
with base as (
  select
    s.candidate_key,
    s.canonical_asset_id as building_source_record_id,
    s.source_kind,
    s.signal_kind,
    s.signal_strength,
    s.confidence as base_opportunity_confidence,
    s.why_now,
    s.refreshed_at as opportunity_refreshed_at,
    a.glazing_signal,
    a.glazing_confidence,
    a.resolved_facade_material,
    a.resolved_raw_facade_material,
    a.resolved_facade_material_status,
    a.resolved_facade_material_source_slug,
    h.individually_listed_building,
    h.within_listed_district,
    h.national_historic_landmark_context,
    h.historic_match_confidence,
    h.limestone_signal,
    h.masonry_target_status,
    h.rankable_historic_masonry_candidate,
    e.biological_growth_context,
    e.tree_canopy_pct,
    e.humidity_context,
    e.confidence as environment_confidence,
    e.refreshed_at as environment_refreshed_at,
    coalesce(p.confirmed_glazed,false) as premium_confirmed_glazed,
    coalesce(p.high_glazing_likelihood,false) as premium_high_glazing_likelihood,
    p.premium_glazing_confidence
  from scout.opportunity_search_spine s
  left join decisioning.v_building_resolved_attributes a
    on a.building_source_record_id=s.canonical_asset_id
  left join cleaning.v_historic_masonry_targets h
    on h.building_source_record_id=s.canonical_asset_id
  left join cleaning.exterior_environment_context e
    on e.building_source_record_id=s.canonical_asset_id
  left join lateral (
    select
      bool_or(px.glazing_status='confirmed_glazed') as confirmed_glazed,
      bool_or(px.glazing_status='high_glazing_likelihood') as high_glazing_likelihood,
      max(px.confidence) filter(where px.glazing_status in ('confirmed_glazed','high_glazing_likelihood')) as premium_glazing_confidence
    from intelligence.v_premium_exterior_opportunities px
    where px.building_source_record_id=s.canonical_asset_id
      and (px.building_match_distance_m is null or px.building_match_distance_m<=25)
  ) p on true
  where s.service_slugs @> array['exterior-cleaning']::text[]
    and s.target_class='building'
    and s.canonical_namespace='decisioning.building_candidates'
    and s.canonical_asset_id is not null
), classified as (
  select
    b.candidate_key,
    b.building_source_record_id,
    'building-envelope-cleaning'::text as service_slug,
    'supported'::text as classification_state,
    b.base_opportunity_confidence as classification_confidence,
    'Existing building-level exterior-cleaning need supports the broad Building Envelope Cleaning specialization; execution workflow remains job/operator dependent.'::text as reason,
    jsonb_strip_nulls(jsonb_build_object(
      'basis','existing_exterior_cleaning_need',
      'source_kind',b.source_kind,
      'signal_kind',b.signal_kind,
      'signal_strength',b.signal_strength,
      'base_opportunity_confidence',b.base_opportunity_confidence,
      'why_now',b.why_now,
      'guardrail','This classification does not prove that pressure washing, soft washing, or any particular chemistry is appropriate for the substrate.'
    )) as evidence,
    'exterior-service-classifier-v1'::text as classifier_version,
    greatest(coalesce(b.opportunity_refreshed_at,'epoch'::timestamptz),coalesce(b.environment_refreshed_at,'epoch'::timestamptz)) as evidence_refreshed_at
  from base b

  union all

  select
    b.candidate_key,
    b.building_source_record_id,
    'pure-water-window-cleaning',
    case
      when (b.glazing_signal='glass_facade_present' and coalesce(b.glazing_confidence,0)>=0.70)
        or b.premium_confirmed_glazed then 'supported'
      when b.premium_high_glazing_likelihood
        or (b.glazing_signal is not null and b.glazing_signal<>'glass_facade_present') then 'investigate'
      else 'insufficient_evidence'
    end,
    case
      when b.glazing_signal is not null then b.glazing_confidence
      when b.premium_confirmed_glazed or b.premium_high_glazing_likelihood then b.premium_glazing_confidence
      else null
    end,
    case
      when (b.glazing_signal='glass_facade_present' and coalesce(b.glazing_confidence,0)>=0.70)
        or b.premium_confirmed_glazed
        then 'Direct/resolved glazing evidence supports investigating this existing cleaning opportunity specifically for pure-water exterior glass cleaning.'
      when b.premium_high_glazing_likelihood
        then 'A premium-target archetype suggests high glazing likelihood, but that is not direct facade evidence; verify glass extent before treating this as a pure-water opportunity.'
      else 'Scout does not currently have enough glazing evidence to specialize this exterior-cleaning opportunity as pure-water glass work.'
    end,
    jsonb_strip_nulls(jsonb_build_object(
      'resolved_glazing_signal',b.glazing_signal,
      'resolved_glazing_confidence',b.glazing_confidence,
      'premium_confirmed_glazed',b.premium_confirmed_glazed,
      'premium_high_glazing_likelihood',b.premium_high_glazing_likelihood,
      'premium_glazing_confidence',b.premium_glazing_confidence,
      'guardrail','High-glazing archetype likelihood is an investigation cue, not proof of exterior glass area or cleanability.'
    )),
    'exterior-service-classifier-v1',
    b.opportunity_refreshed_at
  from base b

  union all

  select
    b.candidate_key,
    b.building_source_record_id,
    'exterior-biocide-treatment',
    case
      when b.biological_growth_context in ('elevated_moisture_retention_verification','moderate_moisture_retention_verification')
        then 'investigate'
      else 'insufficient_evidence'
    end,
    b.environment_confidence,
    case
      when b.biological_growth_context='elevated_moisture_retention_verification'
        then 'Environmental evidence indicates elevated moisture-retention conditions that justify checking for biological growth; it does not itself prove biocide treatment is needed.'
      when b.biological_growth_context='moderate_moisture_retention_verification'
        then 'Environmental evidence indicates moderate moisture-retention conditions that justify field verification for biological growth; treatment need remains unproven.'
      else 'Scout lacks canonical building-level evidence sufficient even to prioritize biological-growth verification for this opportunity.'
    end,
    jsonb_strip_nulls(jsonb_build_object(
      'biological_growth_context',b.biological_growth_context,
      'tree_canopy_pct',b.tree_canopy_pct,
      'humidity_context',b.humidity_context,
      'environment_confidence',b.environment_confidence,
      'guardrail','Moisture, shade, canopy, or humidity are biological-growth proxies only. They never prove growth, label applicability, or the need for a biocide.'
    )),
    'exterior-service-classifier-v1',
    greatest(coalesce(b.opportunity_refreshed_at,'epoch'::timestamptz),coalesce(b.environment_refreshed_at,'epoch'::timestamptz))
  from base b

  union all

  select
    b.candidate_key,
    b.building_source_record_id,
    'masonry-restoration-cleaning',
    case
      when coalesce(b.rankable_historic_masonry_candidate,false)
        or lower(coalesce(b.resolved_facade_material,'')) ~ '(limestone|stone|brick|masonry)'
        or lower(coalesce(b.resolved_raw_facade_material,'')) ~ '(limestone|stone|brick|masonry)'
        then 'supported'
      when coalesce(b.individually_listed_building,false)
        or coalesce(b.within_listed_district,false)
        or coalesce(b.national_historic_landmark_context,false)
        then 'investigate'
      else 'insufficient_evidence'
    end,
    greatest(coalesce(b.historic_match_confidence,0),coalesce(b.base_opportunity_confidence,0))::numeric,
    case
      when coalesce(b.rankable_historic_masonry_candidate,false)
        or lower(coalesce(b.resolved_facade_material,'')) ~ '(limestone|stone|brick|masonry)'
        or lower(coalesce(b.resolved_raw_facade_material,'')) ~ '(limestone|stone|brick|masonry)'
        then 'Resolved facade/material evidence supports investigating this existing cleaning opportunity for masonry or limestone restoration cleaning.'
      when coalesce(b.individually_listed_building,false)
        or coalesce(b.within_listed_district,false)
        or coalesce(b.national_historic_landmark_context,false)
        then 'Historic-resource context makes material-sensitive restoration worth verifying, but the facade material is not resolved; do not infer masonry from historic status.'
      else 'Scout lacks resolved masonry/stone/brick/limestone evidence for this opportunity.'
    end,
    jsonb_strip_nulls(jsonb_build_object(
      'resolved_facade_material',b.resolved_facade_material,
      'resolved_raw_facade_material',b.resolved_raw_facade_material,
      'resolved_facade_material_status',b.resolved_facade_material_status,
      'resolved_facade_material_source_slug',b.resolved_facade_material_source_slug,
      'rankable_historic_masonry_candidate',b.rankable_historic_masonry_candidate,
      'limestone_signal',b.limestone_signal,
      'masonry_target_status',b.masonry_target_status,
      'individually_listed_building',b.individually_listed_building,
      'within_listed_district',b.within_listed_district,
      'national_historic_landmark_context',b.national_historic_landmark_context,
      'historic_match_confidence',b.historic_match_confidence,
      'guardrail','Historic designation alone never proves facade material or suitability for a restoration chemical.'
    )),
    'exterior-service-classifier-v1',
    b.opportunity_refreshed_at
  from base b
)
select * from classified;

alter view cleaning.v_exterior_opportunity_service_classification set (security_invoker=true);
revoke all on cleaning.v_exterior_opportunity_service_classification from anon, authenticated;
grant select on cleaning.v_exterior_opportunity_service_classification to service_role;

create or replace function scout.get_opportunity_service_candidates(p_candidate_key text)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'service_slug',c.service_slug,
    'classification_state',c.classification_state,
    'confidence',c.classification_confidence,
    'reason',c.reason,
    'evidence',c.evidence,
    'classifier_version',c.classifier_version,
    'evidence_refreshed_at',c.evidence_refreshed_at
  ) order by case c.classification_state when 'supported' then 0 when 'investigate' then 1 else 2 end,c.service_slug),'[]'::jsonb)
  from cleaning.v_exterior_opportunity_service_classification c
  where c.candidate_key=p_candidate_key;
$$;

create or replace function scout.get_opportunity_supported_service_slugs(p_candidate_key text)
returns text[]
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(array_agg(distinct x.slug order by x.slug),'{}'::text[])
  from (
    select unnest(s.service_slugs) slug
    from scout.opportunity_search_spine s where s.candidate_key=p_candidate_key
    union
    select c.service_slug
    from cleaning.v_exterior_opportunity_service_classification c
    where c.candidate_key=p_candidate_key and c.classification_state='supported'
  ) x;
$$;

revoke all on function scout.get_opportunity_service_candidates(text) from public, anon, authenticated;
revoke all on function scout.get_opportunity_supported_service_slugs(text) from public, anon, authenticated;
grant execute on function scout.get_opportunity_service_candidates(text) to service_role;
grant execute on function scout.get_opportunity_supported_service_slugs(text) to service_role;

create or replace function scout.assess_opportunity_service_fit(
  p_organization_id uuid,
  p_candidate_key text,
  p_service_slug text,
  p_jurisdiction_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_class jsonb;
  v_access jsonb;
  v_state text;
  v_fit_status text;
  v_candidate_state text;
begin
  select jsonb_build_object(
    'classification_state',c.classification_state,
    'confidence',c.classification_confidence,
    'reason',c.reason,
    'evidence',c.evidence,
    'classifier_version',c.classifier_version
  ) into v_class
  from cleaning.v_exterior_opportunity_service_classification c
  where c.candidate_key=p_candidate_key and c.service_slug=p_service_slug;

  if v_class is null then
    return scout.assess_service_fit(p_organization_id,p_service_slug,p_jurisdiction_code);
  end if;

  v_candidate_state:=v_class->>'classification_state';
  if v_candidate_state<>'supported' then
    return jsonb_build_object(
      'organization_id',p_organization_id,
      'service_slug',p_service_slug,
      'fit_status','not_supported_by_opportunity_evidence',
      'opportunity_service_classification',v_class,
      'interpretation',jsonb_build_object(
        'rule','Operator capability cannot upgrade an investigate/insufficient opportunity classification into evidence that the service is needed.',
        'classification_state',v_candidate_state
      )
    );
  end if;

  select state_code into v_state from scout.opportunity_search_spine where candidate_key=p_candidate_key;
  v_access:=public.scout_get_service_access(
    p_organization_id,
    p_service_slug,
    null,
    jsonb_strip_nulls(jsonb_build_object('state_code',coalesce(nullif(upper(p_jurisdiction_code),''),v_state)))
  );

  v_fit_status:=case
    when coalesce((v_access->>'visible')::boolean,false) then 'ready'
    when v_access->>'access_state'='blocked_hard' then 'blocked'
    when v_access->>'access_state'='not_configured' then 'insufficient_profile'
    when v_access->>'access_state'='blocked_profile' then 'needs_verification'
    else 'needs_verification'
  end;

  return jsonb_build_object(
    'organization_id',p_organization_id,
    'service_slug',p_service_slug,
    'fit_status',v_fit_status,
    'opportunity_service_classification',v_class,
    'service_access',v_access,
    'interpretation',jsonb_build_object(
      'rule','Opportunity evidence and operator execution fit are separate gates. A supported service candidate still requires a configured operator path.',
      'site_specific_preflight_required',true
    )
  );
end;
$$;

revoke all on function scout.assess_opportunity_service_fit(uuid,text,text,text) from public, anon, authenticated;
grant execute on function scout.assess_opportunity_service_fit(uuid,text,text,text) to service_role;

create or replace function scout.assess_opportunity_fit_search(p_organization_id uuid, p_candidate_key text, p_jurisdiction_code text default null)
returns jsonb
language sql
stable
set search_path to 'pg_catalog','public','extensions','scout'
as $$
with c as (
  select candidate_key,scout.get_opportunity_supported_service_slugs(candidate_key) service_slugs
  from scout.opportunity_search_spine where candidate_key=p_candidate_key
), service_fits as (
  select s.service_slug,scout.assess_opportunity_service_fit(p_organization_id,p_candidate_key,s.service_slug,p_jurisdiction_code) fit
  from c cross join lateral unnest(c.service_slugs) s(service_slug)
), aggregate_fit as (
  select coalesce(jsonb_agg(jsonb_build_object('service_slug',service_slug,'fit',fit) order by service_slug),'[]'::jsonb) items,
    case when count(*)=0 then 'unknown'
      when bool_or(fit->>'fit_status'='ready') then 'ready'
      when bool_or(fit->>'fit_status'='needs_verification') then 'needs_verification'
      when bool_or(fit->>'fit_status'='insufficient_profile') then 'insufficient_profile'
      when bool_or(fit->>'fit_status'='not_fully_modeled') then 'not_fully_modeled'
      when bool_and(fit->>'fit_status'='blocked') then 'blocked' else 'needs_verification' end overall_fit_status
  from service_fits
)
select case when not exists(select 1 from c) then null else jsonb_build_object(
  'candidate_key',p_candidate_key,'overall_fit_status',(select overall_fit_status from aggregate_fit),'service_fits',(select items from aggregate_fit),
  'interpretation',jsonb_build_object(
    'fit_scope','Service fit evaluates the canonical opportunity plus evidence-backed specialty classifications against operator equipment, rigs, workflows, products and prerequisites. It does not replace site-specific operability, airspace, weather, access, customer, product-label, substrate or contract checks.',
    'unknown_rule','Insufficient operator profile or missing service-model evidence remains unknown or needs verification rather than being treated as a negative fit.'
  )) end;
$$;

create or replace function scout.get_opportunity_spine_projection(p_candidate_key text)
returns jsonb
language sql
stable
set search_path to ''
as $$
 select jsonb_strip_nulls(jsonb_build_object(
    'candidate_key',s.candidate_key,'contract_version',s.spine_contract_version,
    'derived_from_candidate_key',s.derived_from_candidate_key,'derivation_kind',s.derivation_kind,
    'display_name',s.display_name,'subject_type',s.subject_type,'subject_key',s.subject_key,
    'services',to_jsonb(scout.get_opportunity_supported_service_slugs(s.candidate_key)),'primary_service_slug',s.primary_service_slug,
    'service_candidates',scout.get_opportunity_service_candidates(s.candidate_key),
    'target',jsonb_strip_nulls(jsonb_build_object('resolution_status',s.target_resolution_status,'class',s.target_class,'name',s.target_name,'canonical_namespace',s.canonical_namespace,'canonical_asset_id',s.canonical_asset_id,'operational_target_key',s.operational_target_key,'operational_target_type',s.operational_target_type)),
    'location',case when s.location is null then null else jsonb_build_object('lat',extensions.ST_Y(extensions.ST_PointOnSurface(s.location::extensions.geometry)),'lon',extensions.ST_X(extensions.ST_PointOnSurface(s.location::extensions.geometry)),'state_code',s.state_code,'county_name',s.county_name) end,
    'signal',jsonb_strip_nulls(jsonb_build_object('kind',s.signal_kind,'strength',s.signal_strength,'confidence',s.confidence,'why_now',s.why_now)),
    'timing',jsonb_strip_nulls(jsonb_build_object('time_sensitive',s.time_sensitive,'window_status',s.window_status,'freshness_status',s.freshness_status,'valid_from',s.valid_from,'ideal_until',s.ideal_until,'expires_at',s.expires_at)),
    'base_pursuit_state',s.base_pursuit_state,'buyer',s.buyer_route_summary,
    'property_management',pm.context,'portfolio_account',pa.context,'water_utility_portfolio',wu.context,'water_tank_geometry',wg.context,'industrial_logistics_portfolio',il.context,
    'commercial_scale',s.commercial_scale_summary,'recurrence',s.recurrence_summary,'site_access',s.access_summary,'event',s.event_context,'evidence',s.evidence_summary,'refreshed_at',s.refreshed_at
  ))
 from scout.opportunity_search_spine s
 left join scout.v_opportunity_property_management_context pm on pm.candidate_key=s.candidate_key
 left join scout.v_opportunity_portfolio_account_context pa on pa.candidate_key=s.candidate_key
 left join scout.v_opportunity_water_utility_context wu on wu.candidate_key=s.candidate_key
 left join scout.v_opportunity_water_tank_geometry_context wg on wg.candidate_key=s.candidate_key
 left join scout.v_opportunity_industrial_logistics_context il on il.candidate_key=s.candidate_key
 where s.candidate_key=p_candidate_key;
$$;

create or replace function scout.find_opportunities(p_service_slug text default null, p_county_name text default null, p_state_code text default null, p_center_lat double precision default null, p_center_lon double precision default null, p_radius_miles numeric default null, p_time_sensitive boolean default false, p_require_contact boolean default false, p_limit integer default 10)
returns setof scout.v_opportunity_candidates
language sql
stable
set search_path to 'pg_catalog','public','extensions','scout','commerce','intelligence','cleaning'
as $$
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
    ) as has_resolved_presentation_name
  from scout.opportunity_search_spine s
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
    unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,effective_contact_available desc,strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,confidence desc nulls last,observed_at desc nulls last
)
select candidate_key,source_kind,source_id,subject_type,subject_key,display_name,organization_id,
  scout.get_opportunity_supported_service_slugs(candidate_key) as service_slugs,
  location,signal_kind,signal_strength,confidence,observed_at,valid_from,ideal_until,expires_at,time_sensitive,why_now,effective_contact_available as contact_available,details
from deduped
order by unresolved_event_amplifier asc,has_public_facility_route desc,has_resolved_presentation_name desc,time_sensitive desc,effective_contact_available desc,strength_rank desc,premium_priority_rank desc,global_counter_penalty asc,confidence desc nulls last,observed_at desc nulls last
limit greatest(1,least(coalesce(p_limit,10),100));
$$;
