reset role;
do $$ begin
 assert (select count(*)=2 from farm_watch.property_map_pin_fixture_links_v1), 'replay adds no migration links';
 assert (select count(*)=1 from farm_watch.property_map_pin_fixture_links_v1 where pin_id is null), 'deleted pin stays deleted';
 assert (select count(*)=1 from farm_watch.property_map_pins_v1 where property_id='10000000-0000-0000-0000-000000000003'), 'no resurrection/duplicates';
 assert exists(select 1 from farm_watch.property_map_pins_v1 where title='Migrated feeder edited' and notes='Field notes' and revision=2 and extensions.st_x(geometry)=1.1 and extensions.st_y(geometry)=1.2), 'replay preserves edits/location/revision';
 assert not exists(select 1 from fixture_evidence_before b full join farm_watch.property_operator_observations_v1 o using(id) where b.original is distinct from to_jsonb(o)), 'editing and deleting annotations never rewrite source evidence';
end $$;
select 'PASS: legacy fixture migration, existing data/ACL preservation, creator-only editing, property isolation, revision conflicts, evidence separation and deletion tombstones/replay' as verification;
