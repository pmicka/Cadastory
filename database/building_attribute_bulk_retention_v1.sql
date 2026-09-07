-- Scout bulk building-enrichment retention guard v1
--
-- Overture and OSM regional snapshots are reproducible external bulk sources.
-- Scout should durably retain only observations that successfully attach to a
-- canonical building. Unmatched external footprints are discarded at commit
-- after the matcher has had a chance to create a durable evidence link.
--
-- This prevents annual building enrichment from accumulating millions of
-- unused geometries in Postgres while preserving all evidence Scout can use.

create or replace function decisioning.prune_unmatched_bulk_building_attribute_observation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, decisioning, ingest
as $$
declare
  v_slug text;
begin
  select s.slug into v_slug
  from ingest.sources s
  where s.id = new.source_id;

  if v_slug in ('overture-buildings','openstreetmap-geofabrik-building-attributes')
     and not exists (
       select 1
       from decisioning.building_attribute_matches m
       where m.observation_id = new.id
     ) then
    delete from decisioning.building_attribute_observations o
    where o.id = new.id;
  end if;

  return null;
end;
$$;

revoke all on function decisioning.prune_unmatched_bulk_building_attribute_observation_v1()
  from public, anon, authenticated;
grant execute on function decisioning.prune_unmatched_bulk_building_attribute_observation_v1()
  to service_role;

drop trigger if exists prune_unmatched_bulk_building_attribute_observation_v1
  on decisioning.building_attribute_observations;

create constraint trigger prune_unmatched_bulk_building_attribute_observation_v1
after insert or update on decisioning.building_attribute_observations
deferrable initially deferred
for each row
execute function decisioning.prune_unmatched_bulk_building_attribute_observation_v1();

comment on function decisioning.prune_unmatched_bulk_building_attribute_observation_v1() is
  'Storage guard for bulk-reproducible Overture/OSM building enrichment. Unmatched source observations are discarded at transaction end after the canonical building matcher has had a chance to create evidence links; matched observations remain durable.';
