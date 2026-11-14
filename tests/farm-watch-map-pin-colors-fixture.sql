-- Existing-row upgrade fixture, inserted under the original pre-color schema.
insert into auth.users values ('00000000-0000-0000-0000-000000000099','upgrade@example.invalid',now());
insert into farm_watch.properties(id,slug,display_name,boundary) values
 ('10000000-0000-0000-0000-000000000099','color-upgrade-fixture','Upgrade fixture',
  extensions.st_multi(extensions.st_geomfromtext('POLYGON((0 0,2 0,2 2,0 2,0 0))',4326)));
insert into farm_watch.property_map_pins_v1(id,property_id,created_by,title,notes,geometry) values
 ('20000000-0000-0000-0000-000000000099','10000000-0000-0000-0000-000000000099',
  '00000000-0000-0000-0000-000000000099','Existing pin','Keep all original data',
  extensions.st_setsrid(extensions.st_makepoint(1,1),4326));
create temporary table pin_color_before_upgrade as
 select to_jsonb(p) as original from farm_watch.property_map_pins_v1 p
 where id='20000000-0000-0000-0000-000000000099';
