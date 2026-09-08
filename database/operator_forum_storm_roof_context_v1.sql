-- Scout operator-forum storm-roof context v1
-- Converts recent severe-weather building exposure into conservative roof-inspection prospecting context.
-- Critical semantic guardrail: hazard-footprint overlap does NOT establish roof damage.
-- Production integration also includes this view as a UNION ALL branch of scout.v_opportunity_candidates.

insert into research.operator_field_hypotheses(
  hypothesis_slug,claim,evidence_basis,confidence_status,testability_status,
  applicable_services,source_urls,attributes
)
values (
  'storm_roof_inspection_demand',
  'Recent severe-weather exposure increases near-term roof-inspection relevance, especially for larger commercial roofs; hazard-footprint exposure does not prove roof damage.',
  'Repeated anecdotal reports from professional drone-operator communities, combined with Scout hazard-footprint and commercial-building evidence; not yet validated against provider conversion outcomes.',
  'repeated_anecdotal',
  'proxy_testable',
  array['roof-inspection'],
  jsonb_build_array('https://commercialdronepilots.com/threads/roof-inspection-courses.3095/'),
  jsonb_build_object(
    'origin','professional_operator_forum_research',
    'first_test','recent hazard exposure + severity + recency + building scale, with roof-lifecycle corroboration when independently available',
    'interpretation','Exposure can open an inspection prospecting window; never represent exposure as confirmed damage without separate evidence.',
    'formula_version','storm_roof_context_v1',
    'ideal_window_days',14,
    'expiry_window_days',45
  )
)
on conflict (hypothesis_slug) do update
set claim=excluded.claim,
    evidence_basis=excluded.evidence_basis,
    confidence_status=excluded.confidence_status,
    testability_status=excluded.testability_status,
    applicable_services=excluded.applicable_services,
    source_urls=excluded.source_urls,
    attributes=research.operator_field_hypotheses.attributes||excluded.attributes,
    updated_at=now();

create or replace view scout.v_storm_roof_opportunity_candidates_v1 as
with canonical_sources as (
  select id,slug
  from ingest.sources
  where slug in ('ky-ornl-building-footprints','in-state-building-footprints')
),
exposure_raw as (
  select e.source_record_id as exposure_source_record_id,
         er.source_native_id,
         es.slug as exposure_source_slug,
         e.event_id,
         e.confidence as exposure_confidence,
         e.damage_confirmed,
         e.status as exposure_status,
         e.exposure_basis,
         e.rationale,
         w.hazard_family,
         w.event_type,
         w.magnitude,
         w.magnitude_unit,
         w.damage_scale,
         coalesce(w.onset_at,w.effective_at,w.sent_at,w.first_observed_at,w.created_at) as event_at,
         case when es.slug in ('ky-ornl-building-footprints','in-state-building-footprints') then er.id else cm.id end as canonical_building_source_record_id
  from intelligence.weather_asset_exposures e
  join intelligence.weather_events w on w.id=e.event_id
  join ingest.raw_records er on er.id=e.source_record_id
  join ingest.sources es on es.id=er.source_id
  left join lateral (
    select cr.id
    from canonical_sources cs
    join ingest.raw_records cr on cr.source_id=cs.id
    where es.slug not in ('ky-ornl-building-footprints','in-state-building-footprints')
      and cr.source_native_id=er.source_native_id
      and cr.within_pilot_radius is true
    order by case cs.slug when 'ky-ornl-building-footprints' then 1 when 'in-state-building-footprints' then 2 else 9 end,
             cr.retrieved_at desc,cr.id
    limit 1
  ) cm on true
  where e.status='confirmed_hazard_exposure'
    and w.hazard_family in ('hail','tornado','wind','severe_thunderstorm')
    and coalesce(w.onset_at,w.effective_at,w.sent_at,w.first_observed_at,w.created_at)>=now()-interval '45 days'
),
exposure_dedup as (
  select distinct on (canonical_building_source_record_id,event_id) *
  from exposure_raw
  where canonical_building_source_record_id is not null
  order by canonical_building_source_record_id,event_id,exposure_confidence desc,
           case when exposure_source_slug in ('ky-ornl-building-footprints','in-state-building-footprints') then 0 else 1 end,
           exposure_source_record_id
),
recent as (
  select d.*,
         rr.source_native_id as canonical_source_native_id,
         rr.location,
         scout.try_numeric(rr.raw_payload#>>'{properties,SQFEET}') as footprint_sqft,
         scout.try_numeric(rr.raw_payload#>>'{properties,HEIGHT}') as height_m,
         nullif(btrim(rr.raw_payload#>>'{properties,PROP_ADDR}'),'') as raw_address,
         nullif(btrim(rr.raw_payload#>>'{properties,PROP_CITY}'),'') as raw_city,
         nullif(btrim(rr.raw_payload#>>'{properties,PROP_CNTY}'),'') as raw_county,
         nullif(btrim(rr.raw_payload#>>'{properties,PRIM_OCC}'),'') as primary_occupancy,
         nullif(btrim(rr.raw_payload#>>'{properties,OCC_CLS}'),'') as occupancy_class,
         case when d.hazard_family='hail' and coalesce(d.magnitude,0)>=1.5 then 2
              when d.hazard_family='hail' and coalesce(d.magnitude,0)>=1.0 then 1
              when d.hazard_family='tornado' then 2
              when d.hazard_family in ('wind','severe_thunderstorm') then 1 else 0 end as hazard_points,
         case when d.event_at>=now()-interval '7 days' then 2
              when d.event_at>=now()-interval '21 days' then 1 else 0 end as recency_points,
         case when scout.try_numeric(rr.raw_payload#>>'{properties,SQFEET}')>=25000 then 2
              when scout.try_numeric(rr.raw_payload#>>'{properties,SQFEET}')>=10000 then 1 else 0 end as scale_points
  from exposure_dedup d
  join ingest.raw_records rr on rr.id=d.canonical_building_source_record_id
),
ranked as (
  select r.*,
         row_number() over(partition by canonical_building_source_record_id order by hazard_points desc,recency_points desc,coalesce(magnitude,0) desc,event_at desc,event_id) as rn,
         count(*) over(partition by canonical_building_source_record_id)::integer as exposure_event_count_45d,
         max(magnitude) filter(where hazard_family='hail') over(partition by canonical_building_source_record_id) as max_hail_magnitude_45d
  from recent r
),
best as (
  select r.*,
         cl.county_name as resolved_county_name,
         cl.state_code as resolved_state_code,
         lf.lifecycle_anchor_id,
         lf.lifecycle_band,
         lf.signal_strength as lifecycle_signal_strength,
         lf.age_years_estimate,
         lf.confidence as lifecycle_confidence,
         lf.lifecycle_match_m,
         case when lf.lifecycle_anchor_id is null then 0
              when lower(coalesce(lf.signal_strength,'')) in ('very_high','high','strong') then 2 else 1 end as lifecycle_points,
         org.organization_id
  from ranked r
  left join lateral (
    select l.lifecycle_anchor_id,l.lifecycle_band,l.signal_strength,l.age_years_estimate,l.confidence,
           st_distance(r.location::geography,l.location::geography) as lifecycle_match_m
    from intelligence.v_roof_lifecycle_pressure l
    where r.location is not null and l.location is not null
      and st_dwithin(r.location::geography,l.location::geography,75)
    order by r.location<->l.location,l.confidence desc,l.lifecycle_anchor_id
    limit 1
  ) lf on true
  left join lateral (
    select c.county_name,c.state_code
    from scout.county_lookup c
    where r.location is not null and st_intersects(c.geometry,r.location::geometry)
    order by st_area(c.geometry)
    limit 1
  ) cl on true
  left join lateral (
    select f.organization_id
    from core.organization_facilities f
    where f.source_record_id=r.canonical_building_source_record_id and f.organization_id is not null
    order by f.organization_id
    limit 1
  ) org on true
  where r.rn=1
),
scored as (
  select b.*,hazard_points+recency_points+scale_points+lifecycle_points as priority_points
  from best b
)
select 'storm_roof:'||canonical_building_source_record_id::text as candidate_key,
       'storm_roof'::text as source_kind,
       canonical_building_source_record_id as source_id,
       'building'::text as subject_type,
       canonical_building_source_record_id::text as subject_key,
       coalesce(nullif(raw_address,''),concat_ws(' · ',coalesce(nullif(primary_occupancy,''),nullif(occupancy_class,''),'Commercial building'),
         case when nullif(coalesce(raw_county,resolved_county_name),'') is not null then coalesce(raw_county,resolved_county_name)||' County' end,
         case when footprint_sqft is not null then to_char(round(footprint_sqft),'FM999,999,999')||' sq ft' end)) as display_name,
       organization_id,
       array['roof-inspection']::text[] as service_slugs,
       location::geography as location,
       'recent_severe_weather_exposure'::text as signal_kind,
       case when priority_points>=7 then 'very_high' when priority_points>=5 then 'high' when priority_points>=3 then 'moderate' else 'context' end as signal_strength,
       least(greatest(coalesce(exposure_confidence,0.5),0),0.90) as confidence,
       event_at as observed_at,
       event_at as valid_from,
       event_at+interval '14 days' as ideal_until,
       event_at+interval '45 days' as expires_at,
       true as time_sensitive,
       concat('Recent ',hazard_family,' footprint overlap',case when magnitude is not null then ' ('||magnitude::text||coalesce(' '||magnitude_unit,'')||')' else '' end,
              ' creates a time-sensitive roof-inspection prospecting window for this ',coalesce(round(footprint_sqft)::text||' sq ft ','commercial '),
              'building. Hazard exposure is confirmed; roof damage is not.') as why_now,
       exists(select 1 from core.v_durable_facility_contacts dc where dc.organization_id=scored.organization_id and dc.verification_due is false) as contact_available,
       jsonb_strip_nulls(jsonb_build_object(
         'building_source_record_id',canonical_building_source_record_id,'building_source_native_id',canonical_source_native_id,
         'weather_exposure_source_record_id',exposure_source_record_id,'weather_exposure_source_slug',exposure_source_slug,
         'weather_event_id',event_id,'weather_event_at',event_at,'hazard_family',hazard_family,'event_type',event_type,
         'magnitude',magnitude,'magnitude_unit',magnitude_unit,'damage_scale',damage_scale,
         'hazard_exposure_status',exposure_status,'hazard_exposure_basis',exposure_basis,'damage_confirmed',damage_confirmed,
         'exposure_confidence',exposure_confidence,'exposure_event_count_45d',exposure_event_count_45d,
         'max_hail_magnitude_45d',max_hail_magnitude_45d,'footprint_sqft',footprint_sqft,'height_m',height_m,
         'property_address',raw_address,'city',raw_city,'county',coalesce(raw_county,resolved_county_name),'state_code',resolved_state_code,
         'primary_occupancy',primary_occupancy,'occupancy_class',occupancy_class,'roof_lifecycle_anchor_id',lifecycle_anchor_id,
         'roof_lifecycle_band',lifecycle_band,'roof_lifecycle_signal_strength',lifecycle_signal_strength,
         'roof_age_years_estimate',age_years_estimate,'roof_lifecycle_confidence',lifecycle_confidence,
         'roof_lifecycle_match_m',case when lifecycle_match_m is null then null else round(lifecycle_match_m::numeric,1) end,
         'forum_hypothesis_slug','storm_roof_inspection_demand','priority_points',priority_points,
         'priority_formula','hazard severity + recency + commercial footprint scale + independent roof-lifecycle corroboration when available',
         'formula_version','storm_roof_context_v1',
         'claim_limit','A hazard footprint overlapped this building. This does not establish roof damage, customer demand, insurance eligibility, or a required inspection.'
       )) as details
from scored;

insert into scout.opportunity_decision_profiles(
  source_kind,evidence_posture,need_semantics,timing_semantics,recurrence_mode,buyer_role_hint,
  default_unknowns,default_frictions,default_next_move,commercial_scale_note,active,notes
)
values (
  'storm_roof','event_exposure_proxy',
  'A documented severe-weather footprint overlaps a building and supports investigating roof condition; exposure alone does not prove damage.',
  'The strongest prospecting window is shortly after the documented event; urgency decays with time and expires without newer evidence.',
  'event_driven','building_owner_or_facilities',
  array['Verify actual roof condition and whether any inspection, claim, repair, or replacement is already underway.'],
  array['Roof material, airspace, access, occupied-site constraints, weather, insurance workflow, and customer authorization remain job-specific.'],
  'Resolve the responsible owner/facilities route and offer condition documentation without representing hazard exposure as confirmed damage.',
  'Building footprint is a commercial-scale proxy; it is not roof area, inspection price, or repair value.',
  true,
  'Forum-derived hypothesis; keep exposure and damage semantics separate until provider outcomes validate the business effect.'
)
on conflict (source_kind) do update set
  evidence_posture=excluded.evidence_posture,need_semantics=excluded.need_semantics,timing_semantics=excluded.timing_semantics,
  recurrence_mode=excluded.recurrence_mode,buyer_role_hint=excluded.buyer_role_hint,default_unknowns=excluded.default_unknowns,
  default_frictions=excluded.default_frictions,default_next_move=excluded.default_next_move,
  commercial_scale_note=excluded.commercial_scale_note,active=excluded.active,notes=excluded.notes,updated_at=now();

insert into scout.opportunity_target_rules(
  source_kind,subject_type,target_class,resolution_mode,canonical_namespace,identity_confidence,access_applicability,active,notes
)
values ('storm_roof','building','building','building_source_record','decisioning.building_candidates',0.99,'physical_site',true,
        'source_id is the hazard-exposed normalized building source_record_id; hazard exposure does not imply damage.')
on conflict (source_kind,subject_type) do update set
  target_class=excluded.target_class,resolution_mode=excluded.resolution_mode,canonical_namespace=excluded.canonical_namespace,
  identity_confidence=excluded.identity_confidence,access_applicability=excluded.access_applicability,active=excluded.active,notes=excluded.notes;

insert into scout.opportunity_scale_rules(
  source_kind,metric_key,metric_role,source_path,numeric_multiplier,unit,meaning,confidence,active
)
values ('storm_roof','building_area','asset_scale',array['footprint_sqft'],1,'sq_ft',
        'Documented hazard-exposed building footprint area; useful for commercial scale, not a roof-repair cost estimate.',0.9,true)
on conflict (source_kind,metric_key) do update set
  metric_role=excluded.metric_role,source_path=excluded.source_path,numeric_multiplier=excluded.numeric_multiplier,
  unit=excluded.unit,meaning=excluded.meaning,confidence=excluded.confidence,active=excluded.active;

-- Integration invariant: production scout.v_opportunity_candidates has a UNION ALL branch selecting
-- the 20 candidate columns from scout.v_storm_roof_opportunity_candidates_v1.

create or replace view scout.v_storm_roof_spine_projection_v1 as
with c as (select * from scout.v_storm_roof_opportunity_candidates_v1),
scale_agg as (
  select m.candidate_key,count(*)::integer metric_count,
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object('metric_key',m.metric_key,'role',m.metric_role,'value',m.value_numeric,'unit',m.unit,'meaning',m.meaning,'confidence',m.confidence,'observed_at',m.observed_at))
                   order by case m.metric_role when 'asset_scale' then 1 when 'project_scale' then 2 when 'operational_complexity' then 3 when 'budget_context' then 4 when 'impact_context' then 5 else 9 end,m.metric_key) measures
  from scout.opportunity_scale_metrics m join c on c.candidate_key=m.candidate_key group by m.candidate_key
),
recurrence_agg as (
  select r.candidate_key,
         coalesce((array_agg(r.recurrence_status order by case r.recurrence_status when 'documented_cadence' then 1 when 'partial_cadence' then 2 when 'cycle_context' then 3 when 'event_driven' then 4 when 'seasonal' then 5 when 'project_stage' then 6 when 'lifecycle_context' then 7 else 8 end))[1],'contextual') recurrence_status,
         min(r.next_due_at) filter(where r.next_due_at is not null) next_due_at,max(r.last_normalized_at) last_normalized_at,
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object('service_slug',st.slug,'mode',r.recurrence_mode,'status',r.recurrence_status,'interval_days',r.interval_days,'tolerance_days',r.tolerance_days,'last_completed_at',r.last_completed_at,'next_due_at',r.next_due_at,'cadence_source',r.cadence_source,'confidence',r.confidence)) order by st.slug) services
  from scout.opportunity_recurrence r join c on c.candidate_key=r.candidate_key join commerce.service_types st on st.id=r.service_type_id group by r.candidate_key
),
access_agg as (
  select a.candidate_key,count(*)::integer service_count,
         count(*) filter(where a.access_applicability='physical_site')::integer physical_rows,
         count(*) filter(where a.access_applicability='physical_site' and a.site_enrichment_status='unscanned')::integer pending_rows,
         count(*) filter(where a.access_applicability='physical_site' and a.site_enrichment_status='scan_failed')::integer failed_rows,
         count(*) filter(where a.access_applicability='physical_site' and coalesce(a.linked_feature_count,0)>0)::integer mapped_rows,
         max(a.last_access_scan_at) last_access_scan_at,
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object('service_slug',st.slug,'access_applicability',a.access_applicability,'site_enrichment_status',a.site_enrichment_status,'service_geometry_status',a.service_geometry_status,'decision_state',a.access_decision_state,'setup_class',a.setup_class,'mobility_pattern',a.mobility_pattern,'parking_need',a.parking_need,'authorization_status',a.authorization_status,'access_permission_required',a.access_permission_required,'live_job_validation_required',a.live_job_validation_required,'linked_feature_count',a.linked_feature_count,'road_count',a.road_count,'driveway_count',a.driveway_count,'parking_area_count',a.parking_area_count,'barrier_count',a.barrier_count,'gate_count',a.gate_count,'nearest_road_m',a.nearest_road_m,'nearest_driveway_m',a.nearest_driveway_m,'nearest_staging_m',a.nearest_staging_m,'unknowns',to_jsonb(a.access_unknowns),'last_access_scan_at',a.last_access_scan_at)) order by st.slug) services
  from scout.opportunity_service_access a join c on c.candidate_key=a.candidate_key join commerce.service_types st on st.id=a.service_type_id group by a.candidate_key
),
counter_agg as (
  select e.candidate_key,
         count(*) filter(where e.active and e.effective_from<=now() and (e.expires_at is null or e.expires_at>now()))::integer active_count,
         count(*) filter(where e.active and e.effective_from<=now() and (e.expires_at is null or e.expires_at>now()) and e.effect='downgrade')::integer downgrade_count,
         count(*) filter(where e.active and e.effective_from<=now() and (e.expires_at is null or e.expires_at>now()) and e.effect in ('suppress','cooldown'))::integer suppress_count,
         bool_or(e.active and e.effective_from<=now() and (e.expires_at is null or e.expires_at>now()) and e.effect in ('suppress','cooldown')) suppressed
  from scout.opportunity_counter_evidence e join c on c.candidate_key=e.candidate_key where e.provider_organization_id is null group by e.candidate_key
)
select c.candidate_key,c.source_kind,c.source_id,c.subject_type,c.subject_key,c.display_name,
       lower(coalesce(nullif(btrim(c.display_name),''),c.subject_type||':'||c.subject_key)) display_dedupe_key,
       c.organization_id,c.service_slugs,
       exists(select 1 from unnest(c.service_slugs) ss(slug) join commerce.service_types st on st.slug=ss.slug left join intelligence.service_indicator_profiles sp on sp.service_type_id=st.id and sp.active where coalesce(sp.push_strategy,'direct') not in ('on_demand','derived_child')) pushable,
       c.location,upper(nullif(c.details->>'state_code','')) state_code,regexp_replace(coalesce(nullif(c.details->>'county',''),''),'\s+County$','','i') county_name,
       c.signal_kind,c.signal_strength,
       case lower(coalesce(c.signal_strength,'')) when 'critical' then 6 when 'very_high' then 5 when 'high' then 4 when 'strong' then 4 when 'medium' then 3 when 'moderate' then 3 when 'low' then 2 when 'context' then 1 else 0 end strength_rank,
       c.confidence,c.observed_at,c.valid_from,c.ideal_until,c.expires_at,c.time_sensitive,c.why_now,
       c.contact_available source_contact_available,(c.contact_available or br.contact_point_id is not null) effective_contact_available,
       coalesce(c.details,'{}'::jsonb) details,0::integer premium_priority_rank,
       case when coalesce(ca.downgrade_count,0)>0 then 1 else 0 end global_counter_penalty,coalesce(ca.suppressed,false) global_suppressed,
       coalesce(br.resolution_status,bi.resolution_status,'unresolved') buyer_resolution_status,coalesce(br.organization_id,bi.organization_id) buyer_organization_id,
       case when br.contact_point_id is not null then 'durable_route_available' when c.contact_available then 'route_available' else 'unresolved' end buyer_contact_status,
       coalesce(br.procurement_status,'unresolved') procurement_status,
       case when aa.physical_rows is null then null when aa.pending_rows>0 then 'access_enrichment_pending' when aa.failed_rows>0 then 'access_scan_failed' when aa.mapped_rows>0 then 'mapped_context_available' else 'access_context_unresolved' end site_access_status,
       aa.last_access_scan_at,clock_timestamp() refreshed_at,'2.0'::text spine_contract_version,
       case when cardinality(coalesce(c.service_slugs,'{}'::text[]))=1 then c.service_slugs[1] end primary_service_slug,
       coalesce(t.resolution_status,'unresolved') target_resolution_status,t.target_class,t.target_name,t.canonical_namespace,t.canonical_asset_id,t.operational_target_key,t.operational_target_type,
       coalesce(br.organization_name,bi.buyer_name) buyer_name,coalesce(br.organization_type,bi.organization_type) buyer_organization_type,
       coalesce(br.role_code,bi.role_code) buyer_role_code,coalesce(br.resolution_confidence,bi.confidence) buyer_confidence,
       jsonb_strip_nulls(jsonb_build_object('resolution_status',coalesce(br.resolution_status,bi.resolution_status,'unresolved'),'organization_id',coalesce(br.organization_id,bi.organization_id),'organization_name',coalesce(br.organization_name,bi.buyer_name),'organization_type',coalesce(br.organization_type,bi.organization_type),'role_code',coalesce(br.role_code,bi.role_code),'confidence',coalesce(br.resolution_confidence,bi.confidence),'contact_status',case when br.contact_point_id is not null then 'durable_route_available' when c.contact_available then 'route_available' else 'unresolved' end,'contact_scope',br.contact_scope,'contact_channel_type',br.contact_channel_type,'contact_department_name',br.contact_department_name,'contact_stability_class',br.contact_stability_class,'contact_confidence',br.contact_confidence,'contact_verify_after',br.contact_verify_after,'procurement_status',coalesce(br.procurement_status,'unresolved'),'procurement_scope',br.procurement_scope,'procurement_channel_type',br.procurement_channel_type,'procurement_contract_count',br.procurement_contract_count,'latest_procurement_type',br.latest_procurement_type,'latest_contract_begin_date',br.latest_contract_begin_date)) buyer_route_summary,
       case when sa.candidate_key is not null then 'documented' else 'unknown' end commercial_scale_status,coalesce(sa.metric_count,0) scale_metric_count,
       jsonb_build_object('status',case when sa.candidate_key is not null then 'documented' else 'unknown' end,'metric_count',coalesce(sa.metric_count,0),'measures',coalesce(sa.measures,'[]'::jsonb),'normalized',true) commercial_scale_summary,
       coalesce(ra.recurrence_status,'contextual') recurrence_status,ra.next_due_at,
       jsonb_build_object('status',coalesce(ra.recurrence_status,'contextual'),'next_due_at',ra.next_due_at,'services',coalesce(ra.services,'[]'::jsonb),'normalized',true,'last_normalized_at',ra.last_normalized_at) recurrence_summary,
       jsonb_build_object('status',case when aa.physical_rows is null then 'not_modeled' when aa.pending_rows>0 then 'access_enrichment_pending' when aa.failed_rows>0 then 'access_scan_failed' when aa.mapped_rows>0 then 'mapped_context_available' else 'access_context_unresolved' end,'service_count',coalesce(aa.service_count,0),'services',coalesce(aa.services,'[]'::jsonb),'normalized',true,'guardrail','Mapped access context is planning evidence, not permission or dispatch clearance.') access_summary,
       null::uuid event_id,null::text event_title,null::date event_start,null::text event_tier,null::numeric event_impact_score,null::jsonb event_context,
       case when c.expires_at is not null and c.expires_at<now() then 'expired' when c.valid_from is not null and c.valid_from>now() then 'not_yet_open' when c.time_sensitive and c.ideal_until is not null and c.ideal_until>=now() then 'active_ideal_window' when c.time_sensitive and (c.expires_at is null or c.expires_at>=now()) then 'active_time_window' when c.ideal_until is not null and c.ideal_until>=now() then 'upcoming_or_contextual_window' else 'ongoing_context' end window_status,
       case when c.expires_at is not null and c.expires_at<now() then 'expired_by_explicit_window' when c.valid_from is not null and c.valid_from>now() then 'future_window' when c.time_sensitive and (c.expires_at is null or c.expires_at>=now()) then 'current_by_explicit_window' when c.observed_at is not null then 'source_timestamp_present' else 'undated' end freshness_status,
       case when coalesce(ca.suppressed,false) then 'suppressed' when c.expires_at is not null and c.expires_at<now() then 'expired' when c.valid_from is not null and c.valid_from>now() then 'not_yet_open' when c.time_sensitive or (c.ideal_until is not null and c.ideal_until>=now()) then 'active_signal' when coalesce(br.resolution_status,bi.resolution_status,'unresolved')='organization_resolved' and (c.contact_available or br.contact_point_id is not null) then 'route_ready_context' when coalesce(br.resolution_status,bi.resolution_status,'unresolved') in ('unresolved','role_only','possible_route') then 'buyer_resolution_needed' else 'investigate' end base_pursuit_state,
       jsonb_strip_nulls(jsonb_build_object('positive_signal',jsonb_build_object('kind',c.signal_kind,'strength',c.signal_strength,'confidence',c.confidence),'source_kind',c.source_kind,'observed_at',c.observed_at,'claim_limit',c.details->>'claim_limit','counter_evidence',jsonb_build_object('active_count',coalesce(ca.active_count,0),'downgrade_count',coalesce(ca.downgrade_count,0),'suppress_or_cooldown_count',coalesce(ca.suppress_count,0)),'guardrail','This summary supports investigation and presentation. It does not expose proprietary ranking formulas or prove customer demand beyond the underlying evidence.')) evidence_summary,
       null::text derived_from_candidate_key,null::text derivation_kind
from c
left join scout.opportunity_buyer_identities bi on bi.candidate_key=c.candidate_key
left join scout.opportunity_buyer_routes br on br.candidate_key=c.candidate_key
left join scout.opportunity_target_identities t on t.candidate_key=c.candidate_key
left join scale_agg sa on sa.candidate_key=c.candidate_key
left join recurrence_agg ra on ra.candidate_key=c.candidate_key
left join access_agg aa on aa.candidate_key=c.candidate_key
left join counter_agg ca on ca.candidate_key=c.candidate_key;

create or replace function scout.refresh_storm_roof_search_spine_v1()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_deleted integer:=0; v_inserted integer:=0; v_now timestamptz:=clock_timestamp();
begin
  if not pg_try_advisory_xact_lock(hashtextextended('scout.refresh_storm_roof_search_spine_v1',0)) then
    return jsonb_build_object('skipped',true,'reason','refresh_already_running');
  end if;
  delete from scout.opportunity_search_spine where source_kind='storm_roof';
  get diagnostics v_deleted=row_count;
  insert into scout.opportunity_search_spine select * from scout.v_storm_roof_spine_projection_v1;
  get diagnostics v_inserted=row_count;
  return jsonb_build_object('refreshed_at',v_now,'source_kind','storm_roof','deleted_rows',v_deleted,'inserted_rows',v_inserted,'contract_version','2.0','mode','direct_incremental_source_refresh');
end $$;

comment on function scout.refresh_storm_roof_search_spine_v1() is
'Refreshes only the storm_roof slice of opportunity_search_spine from the storm-specific projection. Normalized buyer/target/scale/recurrence/access facts should be refreshed upstream before this function when new storm candidates are introduced.';

create or replace function scout.storm_roof_provider_priority_v1(p_provider_organization_id uuid)
returns table(
  candidate_key text,display_name text,county_name text,state_code text,storm_signal_strength text,storm_confidence numeric,
  storm_priority_points integer,mobilization_rank_hint integer,combined_priority_points integer,provider_priority_tier text,
  base_distance_miles numeric,nearby_same_service_count integer,nearby_same_buyer_count integer,rank_hint_reason text,claim_limit text,formula_version text
)
language sql stable
set search_path to pg_catalog,public,extensions,scout,commerce,research
as $$
select s.candidate_key,s.display_name,s.county_name,s.state_code,s.signal_strength,s.confidence,
       coalesce((s.details->>'priority_points')::integer,0),m.rank_adjustment_hint,
       coalesce((s.details->>'priority_points')::integer,0)+m.rank_adjustment_hint,
       case when coalesce((s.details->>'priority_points')::integer,0)+m.rank_adjustment_hint>=7 then 'high_with_mobilization_leverage'
            when coalesce((s.details->>'priority_points')::integer,0)+m.rank_adjustment_hint>=5 then 'high'
            when coalesce((s.details->>'priority_points')::integer,0)+m.rank_adjustment_hint>=4 then 'moderate' else 'review' end,
       m.base_distance_miles,m.nearby_same_service_count,m.nearby_same_buyer_count,m.rank_hint_reason,s.details->>'claim_limit','storm_roof_provider_priority_v1'
from scout.opportunity_search_spine s
cross join lateral scout.opportunity_mobilization_rank_hint_v1(p_provider_organization_id,s.candidate_key) m
where s.source_kind='storm_roof';
$$;

comment on function scout.storm_roof_provider_priority_v1(uuid) is
'Internal provider-specific storm-roof prioritization. Combines storm context with the bounded mobilization hint while preserving exposure-not-damage semantics.';

revoke all on function scout.refresh_storm_roof_search_spine_v1() from public;
revoke all on function scout.refresh_storm_roof_search_spine_v1() from anon;
revoke all on function scout.refresh_storm_roof_search_spine_v1() from authenticated;
grant execute on function scout.refresh_storm_roof_search_spine_v1() to service_role;

revoke all on function scout.storm_roof_provider_priority_v1(uuid) from public;
revoke all on function scout.storm_roof_provider_priority_v1(uuid) from anon;
revoke all on function scout.storm_roof_provider_priority_v1(uuid) from authenticated;
grant execute on function scout.storm_roof_provider_priority_v1(uuid) to service_role;
