-- Feed provenance-aware resolved building attributes into the existing premium
-- exterior ranking derivation without mutating raw target records or adding a
-- parallel Scout ranking surface.

create or replace view intelligence.v_premium_exterior_opportunities as
with enriched as (
  select
    t.*,
    a.resolved_height_m,
    a.resolved_height_status,
    a.resolved_height_source_slug,
    a.resolved_story_count,
    a.resolved_story_status,
    a.resolved_story_source_slug,
    a.resolved_facade_material,
    a.resolved_raw_facade_material,
    a.resolved_facade_material_status,
    a.resolved_facade_material_source_slug,
    a.glazing_signal as resolved_glazing_signal,
    a.glazing_confidence as resolved_glazing_confidence,
    a.vertical_geometry_signal,
    a.resolved_attribute_confidence,
    nullif(
      greatest(
        coalesce(t.stated_height_m,0::numeric)::double precision,
        coalesce(t.mapped_height_m,0::double precision),
        coalesce(a.resolved_height_m,0::numeric)::double precision
      ),
      0::double precision
    ) as effective_height_m_enriched,
    coalesce(t.stated_levels,a.resolved_story_count) as effective_story_count,
    case
      when t.glazing_status is not null and t.glazing_status <> 'unknown'
        then t.glazing_status
      when a.glazing_signal='glass_facade_present'
        then 'high_glazing_likelihood'
      else coalesce(t.glazing_status,'unknown')
    end as effective_glazing_status,
    coalesce(t.evidence,'{}'::jsonb) ||
      case
        when a.building_source_record_id is null then '{}'::jsonb
        else jsonb_build_object(
          'building_attribute_resolution',
          jsonb_strip_nulls(
            jsonb_build_object(
              'height_m',a.resolved_height_m,
              'height_status',a.resolved_height_status,
              'height_source',a.resolved_height_source_slug,
              'story_count',a.resolved_story_count,
              'story_status',a.resolved_story_status,
              'story_source',a.resolved_story_source_slug,
              'facade_material',a.resolved_facade_material,
              'raw_facade_material',a.resolved_raw_facade_material,
              'facade_material_status',a.resolved_facade_material_status,
              'facade_material_source',a.resolved_facade_material_source_slug,
              'glazing_signal',a.glazing_signal,
              'glazing_confidence',a.glazing_confidence,
              'vertical_geometry_signal',a.vertical_geometry_signal,
              'attribute_confidence',a.resolved_attribute_confidence
            )
          )
        )
      end as enriched_evidence
  from intelligence.premium_exterior_targets t
  left join decisioning.v_building_resolved_attributes a
    on a.building_source_record_id=t.building_source_record_id
  where t.source_present
), scored as (
  select
    e.id,
    e.source_id,
    e.source_native_id,
    e.target_class,
    e.target_subclass,
    e.name,
    e.operator_name,
    e.website_url,
    e.address_text,
    e.location,
    e.stated_height_m,
    e.stated_levels,
    e.stated_capacity,
    e.effective_glazing_status as glazing_status,
    e.vertical_feature_status,
    e.public_image_sensitivity,
    e.management_budget_proxy,
    e.buyer_resolvability,
    e.confidence,
    e.source_present,
    e.enriched_evidence as evidence,
    e.first_observed_at,
    e.last_observed_at,
    e.updated_at,
    e.building_source_record_id,
    e.building_source_slug,
    e.footprint_sqft,
    e.mapped_height_m,
    e.property_address,
    e.property_city,
    e.state_code,
    e.postal_code,
    e.building_match_distance_m,
    e.effective_height_m_enriched as effective_height_m,
    e.effective_story_count,
    e.resolved_height_m,
    e.resolved_height_status,
    e.resolved_height_source_slug,
    e.resolved_story_count,
    e.resolved_story_status,
    e.resolved_story_source_slug,
    e.resolved_facade_material,
    e.resolved_raw_facade_material,
    e.resolved_facade_material_status,
    e.resolved_facade_material_source_slug,
    e.resolved_glazing_signal,
    e.resolved_glazing_confidence,
    e.vertical_geometry_signal,
    e.resolved_attribute_confidence,
    case e.target_class
      when 'convention_event_center' then 28
      when 'airport_terminal' then 28
      when 'casino_resort' then 27
      when 'sports_venue' then 25
      when 'amusement_park' then 25
      when 'hospital' then 25
      when 'hotel' then 24
      when 'museum_performing_arts' then 24
      when 'corporate_office' then 22
      when 'university' then 21
      when 'dealership_showroom' then 16
      when 'religious_facility' then 15
      else 10
    end
    + case
        when coalesce(e.footprint_sqft,0)>=150000 then 20
        when coalesce(e.footprint_sqft,0)>=75000 then 15
        when coalesce(e.footprint_sqft,0)>=30000 then 10
        when coalesce(e.footprint_sqft,0)>=10000 then 5
        else 0
      end
    + case
        when coalesce(e.effective_height_m_enriched,0)>=30
          or coalesce(e.effective_story_count,0)>=10 then 18
        when coalesce(e.effective_height_m_enriched,0)>=20
          or coalesce(e.effective_story_count,0)>=7 then 14
        when coalesce(e.effective_height_m_enriched,0)>=12
          or coalesce(e.effective_story_count,0)>=4 then 8
        when coalesce(e.effective_height_m_enriched,0)>=8
          or coalesce(e.effective_story_count,0)>=3 then 4
        else 0
      end
    + case e.effective_glazing_status
        when 'confirmed_glazed' then 20
        when 'high_glazing_likelihood' then 10
        else 0
      end
    + case e.public_image_sensitivity
        when 'high' then 8
        when 'medium' then 4
        else 0
      end
    + case e.management_budget_proxy
        when 'strong_professional_management_proxy' then 8
        when 'institutional_management_proxy' then 5
        else 0
      end
    + case e.buyer_resolvability
        when 'public_operator_or_site_route' then 5
        else 0
      end
    + case e.vertical_feature_status
        when 'confirmed_tower' then 15
        when 'tall_religious_structure' then 10
        else 0
      end as raw_score,
    case
      when e.target_class='religious_facility' then
        e.target_subclass=any(array['megachurch_capacity_candidate','bell_tower'])
        or e.vertical_feature_status<>'unknown'
        or coalesce(e.footprint_sqft,0)>=20000
        or coalesce(e.effective_height_m_enriched,0)>=12
        or coalesce(e.effective_story_count,0)>=4
      when e.target_class='sports_venue' then
        e.target_subclass=any(array['stadium','stadium_building','arena','horse_racing_complex'])
        or coalesce(e.footprint_sqft,0)>=30000
        or coalesce(e.effective_height_m_enriched,0)>=12
        or coalesce(e.effective_story_count,0)>=4
      when e.target_class='corporate_office' then
        coalesce(e.footprint_sqft,0)>=20000
        or coalesce(e.effective_height_m_enriched,0)>=12
        or coalesce(e.effective_story_count,0)>=5
        or e.effective_glazing_status in ('confirmed_glazed','high_glazing_likelihood')
      else true
    end as rankable
  from enriched e
)
select
  id,
  source_id,
  source_native_id,
  target_class,
  target_subclass,
  name,
  operator_name,
  website_url,
  address_text,
  location,
  stated_height_m,
  stated_levels,
  stated_capacity,
  glazing_status,
  vertical_feature_status,
  public_image_sensitivity,
  management_budget_proxy,
  buyer_resolvability,
  confidence,
  source_present,
  evidence,
  first_observed_at,
  last_observed_at,
  updated_at,
  building_source_record_id,
  building_source_slug,
  footprint_sqft,
  mapped_height_m,
  property_address,
  property_city,
  state_code,
  postal_code,
  building_match_distance_m,
  effective_height_m,
  raw_score,
  rankable,
  least(100,raw_score) as facade_opportunity_score,
  case
    when raw_score>=75 then 'very_high'
    when raw_score>=60 then 'high'
    when raw_score>=45 then 'medium'
    else 'context'
  end as opportunity_tier,
  case
    when vertical_feature_status=any(array['confirmed_tower','tall_religious_structure'])
      or coalesce(effective_height_m,0)>=20
      or coalesce(effective_story_count,0)>=7 then 'high'
    when coalesce(effective_height_m,0)>=8
      or coalesce(effective_story_count,0)>=3
      or target_class=any(array['hotel','convention_event_center','sports_venue','amusement_park','airport_terminal'])
      then 'medium'
    else 'unknown'
  end as access_burden,
  false as can_open_window,
  'Facility archetype/geometry is a target qualifier only; verify actual facade material, condition, access, owner requirements and current need before outreach. Resolved building attributes preserve their source and confidence separately from the target record.'::text as guardrail,
  effective_story_count,
  resolved_height_m,
  resolved_height_status,
  resolved_height_source_slug,
  resolved_story_count,
  resolved_story_status,
  resolved_story_source_slug,
  resolved_facade_material,
  resolved_raw_facade_material,
  resolved_facade_material_status,
  resolved_facade_material_source_slug,
  resolved_glazing_signal,
  resolved_glazing_confidence,
  vertical_geometry_signal,
  resolved_attribute_confidence
from scored;
