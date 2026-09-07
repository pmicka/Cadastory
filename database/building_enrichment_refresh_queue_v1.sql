-- Scout building enrichment refresh queue v1
--
-- Operational initial/annual physical-enrichment queue only. No commercial
-- valuation, lead scoring, or outreach prioritization is included.

create or replace view decisioning.v_building_enrichment_refresh_queue_v1
with (security_invoker=true) as
select
  e.building_source_record_id,
  e.source_slug,
  e.source_native_id,
  e.footprint_sqft,
  e.last_attribute_enriched_at,
  e.latest_source_timestamp,
  e.nominal_refresh_due_at,
  e.refresh_status,
  e.physical_enrichment_status,
  array_remove(array[
    case when e.needs_height then 'height' end,
    case when e.needs_stories then 'stories' end,
    case when e.needs_facade_material then 'facade_material' end,
    case when e.glazing_unresolved then 'glazing' end
  ],null)::text[] as unresolved_dimensions,
  case
    when e.refresh_status='never_enriched' then 'initial_enrichment'
    when e.refresh_status='refresh_due' then 'annual_refresh'
    when e.needs_height or e.needs_stories or e.needs_facade_material or e.glazing_unresolved then 'gap_fill_on_next_refresh'
    else 'no_action'
  end as refresh_reason
from decisioning.v_building_enrichment_status_v1 e
where e.refresh_status in ('never_enriched','refresh_due')
   or e.needs_height
   or e.needs_stories
   or e.needs_facade_material
   or e.glazing_unresolved;

revoke all on decisioning.v_building_enrichment_refresh_queue_v1 from public,anon,authenticated;
grant select on decisioning.v_building_enrichment_refresh_queue_v1 to service_role;

comment on view decisioning.v_building_enrichment_refresh_queue_v1 is
  'Operational queue for initial/annual physical building enrichment. Lists unresolved dimensions and nominal annual freshness only; contains no commercial value or lead prioritization.';
