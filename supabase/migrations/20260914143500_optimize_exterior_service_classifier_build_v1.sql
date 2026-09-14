-- Batch 3: stop rescanning decisioning.building_candidates once per classifier target.
--
-- The classifier only used the building_candidates join as a canonical/current
-- building validation gate. The view expands ~70k building rows; with ~916 target
-- building ids, the planner chose nested loops that rejected ~64M pairs in each
-- of the facade and glazing CTEs. Validate the same source/pilot constraints once
-- through ingest.raw_records primary keys, then reuse that bounded target set.

create or replace view cleaning.v_exterior_opportunity_service_classification_build as
with target as materialized (
  select s.candidate_key,
         s.canonical_asset_id as building_source_record_id,
         s.source_kind,
         s.signal_kind,
         s.signal_strength,
         s.confidence as base_opportunity_confidence,
         s.why_now,
         s.refreshed_at as opportunity_refreshed_at
  from scout.opportunity_search_spine s
  where s.service_slugs @> array['exterior-cleaning'::text]
    and s.target_class='building'
    and s.canonical_namespace='decisioning.building_candidates'
    and s.canonical_asset_id is not null
), target_ids as materialized (
  select distinct target.building_source_record_id
  from target
), valid_target_ids as materialized (
  select ti.building_source_record_id
  from target_ids ti
  join ingest.raw_records r
    on r.id=ti.building_source_record_id
   and r.within_pilot_radius is true
  join ingest.sources src
    on src.id=r.source_id
   and src.slug=any(array[
     'ky-ornl-building-footprints'::text,
     'in-state-building-footprints'::text,
     'openstreetmap-targeted-building-identity'::text
   ])
), facade as materialized (
  select distinct on (m.building_source_record_id)
    m.building_source_record_id,
    o.facade_material as resolved_facade_material,
    o.raw_facade_material as resolved_raw_facade_material,
    coalesce(o.facade_material_status,'unknown'::text) as resolved_facade_material_status,
    src.slug as resolved_facade_material_source_slug
  from valid_target_ids ti
  join decisioning.building_attribute_matches m
    on m.building_source_record_id=ti.building_source_record_id
  join decisioning.building_attribute_observations o
    on o.id=m.observation_id
  join ingest.sources src
    on src.id=o.source_id
  where o.facade_material is not null
  order by m.building_source_record_id,
    case o.facade_material_status when 'documented' then 4 when 'source_reported' then 3 when 'normalized' then 2 else 1 end desc,
    case o.source_feature_kind when 'building' then 2 else 1 end desc,
    m.confidence desc,o.confidence desc,o.observed_at desc
), glazing as materialized (
  select m.building_source_record_id,
         case when bool_or(
           o.facade_material='glass'::text
           or o.glazing_signal=any(array['glass_facade'::text,'glass_facade_present'::text,'confirmed_glazed'::text])
         ) then 'glass_facade_present'::text else null::text end as glazing_signal,
         max(m.confidence*o.confidence) as glazing_confidence
  from valid_target_ids ti
  join decisioning.building_attribute_matches m
    on m.building_source_record_id=ti.building_source_record_id
  join decisioning.building_attribute_observations o
    on o.id=m.observation_id
  group by m.building_source_record_id
), premium as materialized (
  select px.building_source_record_id,
         bool_or(px.glazing_status='confirmed_glazed'::text) as confirmed_glazed,
         bool_or(px.glazing_status='high_glazing_likelihood'::text) as high_glazing_likelihood,
         max(px.confidence) filter (where px.glazing_status=any(array['confirmed_glazed'::text,'high_glazing_likelihood'::text])) as premium_glazing_confidence
  from intelligence.v_premium_exterior_opportunities px
  join target_ids ti on ti.building_source_record_id=px.building_source_record_id
  group by px.building_source_record_id
), historic as materialized (
  select h.building_source_record_id,
         h.individually_listed_building,
         h.within_listed_district,
         h.national_historic_landmark_context,
         h.historic_match_confidence
  from intelligence.v_building_historic_context h
  join target_ids ti on ti.building_source_record_id=h.building_source_record_id
  where h.individually_listed_building or h.within_listed_district
), base as materialized (
  select t.candidate_key,
         t.building_source_record_id,
         t.source_kind,
         t.signal_kind,
         t.signal_strength,
         t.base_opportunity_confidence,
         t.why_now,
         t.opportunity_refreshed_at,
         g.glazing_signal,
         g.glazing_confidence,
         f.resolved_facade_material,
         f.resolved_raw_facade_material,
         f.resolved_facade_material_status,
         f.resolved_facade_material_source_slug,
         h.individually_listed_building,
         h.within_listed_district,
         h.national_historic_landmark_context,
         h.historic_match_confidence,
         case
           when lower(coalesce(f.resolved_raw_facade_material,''::text)) like '%limestone%' then 'explicit_limestone_signal'::text
           when f.resolved_facade_material='stone'::text then 'stone_material_limestone_unresolved'::text
           else 'no_limestone_specific_evidence'::text
         end as limestone_signal,
         case
           when f.resolved_facade_material=any(array['brick'::text,'stone'::text,'concrete'::text,'cement_block'::text,'plaster'::text]) and h.individually_listed_building then 'high'::text
           when f.resolved_facade_material=any(array['brick'::text,'stone'::text,'concrete'::text,'cement_block'::text,'plaster'::text]) and h.within_listed_district then 'medium'::text
           when h.individually_listed_building or h.within_listed_district then 'surface_material_unresolved'::text
           else 'not_historic_context'::text
         end as masonry_target_status,
         f.resolved_facade_material=any(array['brick'::text,'stone'::text,'concrete'::text,'cement_block'::text,'plaster'::text])
           and (h.individually_listed_building or h.within_listed_district) as rankable_historic_masonry_candidate,
         e.biological_growth_context,
         e.tree_canopy_pct,
         e.humidity_context,
         e.confidence as environment_confidence,
         e.refreshed_at as environment_refreshed_at,
         coalesce(p.confirmed_glazed,false) as premium_confirmed_glazed,
         coalesce(p.high_glazing_likelihood,false) as premium_high_glazing_likelihood,
         p.premium_glazing_confidence
  from target t
  left join facade f on f.building_source_record_id=t.building_source_record_id
  left join glazing g on g.building_source_record_id=t.building_source_record_id
  left join historic h on h.building_source_record_id=t.building_source_record_id
  left join cleaning.exterior_environment_context e on e.building_source_record_id=t.building_source_record_id
  left join premium p on p.building_source_record_id=t.building_source_record_id
)
select b.candidate_key,
       b.building_source_record_id,
       v.service_slug,
       v.classification_state,
       v.classification_confidence,
       v.reason,
       v.evidence,
       v.classifier_version,
       v.evidence_refreshed_at
from base b
cross join lateral (values
  ('building-envelope-cleaning'::text,
   'supported'::text,
   b.base_opportunity_confidence,
   'Existing building-level exterior-cleaning need supports the broad Building Envelope Cleaning specialization; execution workflow remains job/operator dependent.'::text,
   jsonb_strip_nulls(jsonb_build_object(
     'basis','existing_exterior_cleaning_need','source_kind',b.source_kind,'signal_kind',b.signal_kind,'signal_strength',b.signal_strength,
     'base_opportunity_confidence',b.base_opportunity_confidence,'why_now',b.why_now,
     'guardrail','This classification does not prove that pressure washing, soft washing, or any particular chemistry is appropriate for the substrate.'
   )),
   'exterior-service-classifier-v1'::text,
   greatest(coalesce(b.opportunity_refreshed_at,'1970-01-01 00:00:00+00'::timestamptz),coalesce(b.environment_refreshed_at,'1970-01-01 00:00:00+00'::timestamptz))),
  ('pure-water-window-cleaning'::text,
   case
     when b.glazing_signal='glass_facade_present'::text and coalesce(b.glazing_confidence,0::numeric)>=0.70 or b.premium_confirmed_glazed then 'supported'::text
     when b.premium_high_glazing_likelihood or b.glazing_signal is not null and b.glazing_signal<>'glass_facade_present'::text then 'investigate'::text
     else 'insufficient_evidence'::text
   end,
   case when b.glazing_signal is not null then b.glazing_confidence when b.premium_confirmed_glazed or b.premium_high_glazing_likelihood then b.premium_glazing_confidence else null::numeric end,
   case
     when b.glazing_signal='glass_facade_present'::text and coalesce(b.glazing_confidence,0::numeric)>=0.70 or b.premium_confirmed_glazed then 'Direct/resolved glazing evidence supports investigating this existing cleaning opportunity specifically for pure-water exterior glass cleaning.'::text
     when b.premium_high_glazing_likelihood then 'A premium-target archetype suggests high glazing likelihood, but that is not direct facade evidence; verify glass extent before treating this as a pure-water opportunity.'::text
     else 'Scout does not currently have enough glazing evidence to specialize this exterior-cleaning opportunity as pure-water glass work.'::text
   end,
   jsonb_strip_nulls(jsonb_build_object(
     'resolved_glazing_signal',b.glazing_signal,'resolved_glazing_confidence',b.glazing_confidence,
     'premium_confirmed_glazed',b.premium_confirmed_glazed,'premium_high_glazing_likelihood',b.premium_high_glazing_likelihood,
     'premium_glazing_confidence',b.premium_glazing_confidence,
     'guardrail','High-glazing archetype likelihood is an investigation cue, not proof of exterior glass area or cleanability.'
   )),
   'exterior-service-classifier-v1'::text,
   b.opportunity_refreshed_at),
  ('exterior-biocide-treatment'::text,
   case when b.biological_growth_context=any(array['elevated_moisture_retention_verification'::text,'moderate_moisture_retention_verification'::text]) then 'investigate'::text else 'insufficient_evidence'::text end,
   b.environment_confidence,
   case
     when b.biological_growth_context='elevated_moisture_retention_verification'::text then 'Environmental evidence indicates elevated moisture-retention conditions that justify checking for biological growth; it does not itself prove biocide treatment is needed.'::text
     when b.biological_growth_context='moderate_moisture_retention_verification'::text then 'Environmental evidence indicates moderate moisture-retention conditions that justify field verification for biological growth; treatment need remains unproven.'::text
     else 'Scout lacks canonical building-level evidence sufficient even to prioritize biological-growth verification for this opportunity.'::text
   end,
   jsonb_strip_nulls(jsonb_build_object(
     'biological_growth_context',b.biological_growth_context,'tree_canopy_pct',b.tree_canopy_pct,'humidity_context',b.humidity_context,
     'environment_confidence',b.environment_confidence,
     'guardrail','Moisture, shade, canopy, or humidity are biological-growth proxies only. They never prove growth, label applicability, or the need for a biocide.'
   )),
   'exterior-service-classifier-v1'::text,
   greatest(coalesce(b.opportunity_refreshed_at,'1970-01-01 00:00:00+00'::timestamptz),coalesce(b.environment_refreshed_at,'1970-01-01 00:00:00+00'::timestamptz))),
  ('masonry-restoration-cleaning'::text,
   case
     when nullif(btrim(coalesce(b.resolved_facade_material,''::text)),''::text) is not null then
       case when lower(b.resolved_facade_material) ~ '(limestone|stone|brick|masonry)'::text then 'supported'::text else 'insufficient_evidence'::text end
     when nullif(btrim(coalesce(b.resolved_raw_facade_material,''::text)),''::text) is not null then
       case when lower(b.resolved_raw_facade_material) ~ '(limestone|stone|brick|masonry)'::text then 'supported'::text else 'insufficient_evidence'::text end
     when coalesce(b.rankable_historic_masonry_candidate,false) then 'supported'::text
     when coalesce(b.individually_listed_building,false) or coalesce(b.within_listed_district,false) or coalesce(b.national_historic_landmark_context,false) then 'investigate'::text
     else 'insufficient_evidence'::text
   end,
   greatest(coalesce(b.historic_match_confidence,0::numeric),coalesce(b.base_opportunity_confidence,0::numeric)),
   case
     when nullif(btrim(coalesce(b.resolved_facade_material,''::text)),''::text) is not null and lower(b.resolved_facade_material) ~ '(limestone|stone|brick|masonry)'::text then 'Resolved facade/material evidence supports investigating this existing cleaning opportunity for masonry or limestone restoration cleaning.'::text
     when nullif(btrim(coalesce(b.resolved_facade_material,''::text)),''::text) is not null then 'Resolved facade material is non-masonry; historic status alone does not justify a masonry-restoration specialization.'::text
     when nullif(btrim(coalesce(b.resolved_raw_facade_material,''::text)),''::text) is not null and lower(b.resolved_raw_facade_material) ~ '(limestone|stone|brick|masonry)'::text then 'Resolved raw facade/material evidence supports investigating this existing cleaning opportunity for masonry or limestone restoration cleaning.'::text
     when nullif(btrim(coalesce(b.resolved_raw_facade_material,''::text)),''::text) is not null then 'Resolved raw facade material does not indicate masonry; historic status alone does not justify a masonry-restoration specialization.'::text
     when coalesce(b.rankable_historic_masonry_candidate,false) then 'Independent historic-masonry evidence supports investigating this existing cleaning opportunity for masonry or limestone restoration cleaning.'::text
     when coalesce(b.individually_listed_building,false) or coalesce(b.within_listed_district,false) or coalesce(b.national_historic_landmark_context,false) then 'Historic-resource context makes material-sensitive restoration worth verifying, but the facade material is not resolved; do not infer masonry from historic status.'::text
     else 'Scout lacks resolved masonry/stone/brick/limestone evidence for this opportunity.'::text
   end,
   jsonb_strip_nulls(jsonb_build_object(
     'resolved_facade_material',b.resolved_facade_material,'resolved_raw_facade_material',b.resolved_raw_facade_material,
     'resolved_facade_material_status',b.resolved_facade_material_status,'resolved_facade_material_source_slug',b.resolved_facade_material_source_slug,
     'rankable_historic_masonry_candidate',b.rankable_historic_masonry_candidate,'limestone_signal',b.limestone_signal,
     'masonry_target_status',b.masonry_target_status,'individually_listed_building',b.individually_listed_building,
     'within_listed_district',b.within_listed_district,'national_historic_landmark_context',b.national_historic_landmark_context,
     'historic_match_confidence',b.historic_match_confidence,
     'guardrail','Historic designation alone never proves facade material or suitability for a restoration chemical.'
   )),
   'exterior-service-classifier-v1'::text,
   b.opportunity_refreshed_at)
) v(service_slug,classification_state,classification_confidence,reason,evidence,classifier_version,evidence_refreshed_at);

comment on view cleaning.v_exterior_opportunity_service_classification_build is
  'Exterior service classification build surface; canonical building validation uses bounded primary-key source checks rather than repeated expansion of decisioning.building_candidates.';