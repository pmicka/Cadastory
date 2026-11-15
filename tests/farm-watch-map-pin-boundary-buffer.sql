reset role;
do $$ begin
 assert not exists(select 1 from buffer_pins_before b full join farm_watch.property_map_pins_v1 p using(id) where b.original is distinct from to_jsonb(p)),'all existing pins and revisions preserved';
 assert not exists(select 1 from buffer_properties_before b full join farm_watch.properties p using(id) where b.original is distinct from to_jsonb(p)),'property boundaries unchanged';
 assert not exists((select * from buffer_grants_before except select * from farm_watch.map_pin_icon_users_v1) union all(select * from farm_watch.map_pin_icon_users_v1 except select * from buffer_grants_before)),'icon grants preserved';
 assert not exists(select 1 from buffer_rpcs_before b join pg_proc p on p.oid=b.oid where b.definition<>pg_get_functiondef(p.oid) or b.proacl is distinct from p.proacl),'pin/photo RPCs and execution grants preserved';
 assert (select proacl is not distinct from (select proacl from buffer_guard_acl_before) from pg_proc where oid='farm_watch.guard_map_pin_v1()'::regprocedure),'trigger ACL preserved';
 assert not has_table_privilege('authenticated','farm_watch.property_map_pins_v1','select,insert,update,delete');
end $$;
begin;
-- Fixture-only PostGIS access for probe construction; no private data grants.
grant usage on schema extensions to authenticated;
-- Real Kentucky latitude, interior hole and two disjoint property pieces.
insert into farm_watch.properties(id,slug,display_name,boundary) values
 ('10000000-0000-0000-0000-000000000010','buffer-test','Buffer test',extensions.st_multi(extensions.st_geomfromtext('POLYGON((-84.9 38.3,-84.89 38.3,-84.89 38.31,-84.9 38.31,-84.9 38.3),(-84.897 38.303,-84.893 38.303,-84.893 38.307,-84.897 38.307,-84.897 38.303))',4326))),
 ('10000000-0000-0000-0000-000000000011','buffer-multi','Buffer multipart',extensions.st_geomfromtext('MULTIPOLYGON(((-84.88 38.3,-84.87 38.3,-84.87 38.31,-84.88 38.31,-84.88 38.3)),((-84.86 38.3,-84.85 38.3,-84.85 38.31,-84.86 38.31,-84.86 38.3)))',4326));
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
do $$ declare point extensions.geometry; saved jsonb; pin uuid; feet double precision; actor uuid; denied boolean; begin
 -- Project probes across a meridian boundary, using spheroidal ground metres.
 foreach feet in array array[0.,1.,50.,99.99] loop
  point:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-84.9,38.305),4326)::extensions.geography,feet*.3048,-pi()/2)::extensions.geometry;
  saved:=public.farm_watch_map_pins_v1('buffer-test','create',p_title=>'Near boundary',p_longitude=>extensions.st_x(point),p_latitude=>extensions.st_y(point),p_is_private=>true)->'pin';
  assert (saved->>'longitude')::double precision=extensions.st_x(point),'stored location must not snap to boundary';
  assert (saved->>'latitude')::double precision=extensions.st_y(point);
  pin:=(saved->>'id')::uuid;
  -- The same off-property location supports metadata edits and privacy toggles.
  saved:=public.farm_watch_map_pins_v1('buffer-test','update',pin,1,'Updated outside',null,extensions.st_x(point),extensions.st_y(point),p_is_private=>false)->'pin';
  assert saved->>'revision'='2' and saved->>'is_private'='false';
  foreach actor in array array['00000000-0000-0000-0000-000000000002'::uuid,'00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006'] loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
   perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''buffer-test'',''update'',%L,2,''Take over'',null,%s,%s)',pin,extensions.st_x(point),extensions.st_y(point)),'42501');
  end loop;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''buffer-multi'',''update'',%L,2,''Reassign'',null,%s,%s)',pin,extensions.st_x(point),extensions.st_y(point)),'42501');
  -- Other property geometry cannot qualify this pin's selected property.
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''buffer-multi'',''create'',p_title=>''Wrong footprint'',p_longitude=>%s,p_latitude=>%s)',extensions.st_x(point),extensions.st_y(point)),'22023');
  perform public.farm_watch_map_pins_v1('buffer-test','delete',pin,2);
 end loop;
 foreach feet in array array[100.01,101.,500.] loop
  point:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-84.9,38.305),4326)::extensions.geography,feet*.3048,-pi()/2)::extensions.geometry;
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''buffer-test'',''create'',p_title=>''Too far'',p_longitude=>%s,p_latitude=>%s)',extensions.st_x(point),extensions.st_y(point)),'22023');
 end loop;
 -- Moving an existing pin beyond the allowance fails without changing revision.
 saved:=public.farm_watch_map_pins_v1('buffer-test','create',p_title=>'Move test',p_longitude=>-84.899,p_latitude=>38.305)->'pin';pin:=(saved->>'id')::uuid;
 perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''buffer-test'',''update'',%L,1,''Too far'',null,%s,%s)',pin,extensions.st_x(point),extensions.st_y(point)),'22023');
 assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('buffer-test','list')->'pins') p where p->>'id'=pin::text and p->>'revision'='1' and p->>'title'='Move test');
 point:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-84.9,38.305),4326)::extensions.geography,30.,-pi()/2)::extensions.geometry;
 saved:=public.farm_watch_map_pins_v1('buffer-test','update',pin,1,'Near outside',null,extensions.st_x(point),extensions.st_y(point))->'pin';assert saved->>'revision'='2';
 perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''buffer-test'',''update'',%L,1,''Stale'',null,%s,%s)',pin,extensions.st_x(point),extensions.st_y(point)),'PT409');
 -- Hole edges have the same small allowance; deep hole interiors remain denied.
 point:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-84.897,38.305),4326)::extensions.geography,20.,pi()/2)::extensions.geometry;
 perform public.farm_watch_map_pins_v1('buffer-test','create',p_title=>'Near interior edge',p_longitude=>extensions.st_x(point),p_latitude=>extensions.st_y(point));
 perform public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('buffer-test','create',p_title=>'Deep hole',p_longitude=>-84.895,p_latitude=>38.305)$q$,'22023');
 -- Every piece of a multipart property uses ground distance, not a bbox.
 point:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-84.85,38.305),4326)::extensions.geography,20.,pi()/2)::extensions.geometry;
 perform public.farm_watch_map_pins_v1('buffer-multi','create',p_title=>'Near second island',p_longitude=>extensions.st_x(point),p_latitude=>extensions.st_y(point));
 perform public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('buffer-multi','create',p_title=>'Between islands',p_longitude=>-84.865,p_latitude=>38.305)$q$,'22023');
end $$;
reset role;
-- Missing, invalid, empty and inactive property geometry still fails closed.
update farm_watch.properties set boundary=null where slug='buffer-test';
set role authenticated;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('buffer-test','create',p_title=>'No geometry',p_longitude=>-84.9,p_latitude=>38.305)$q$,'22023');
reset role;
update farm_watch.properties set boundary=extensions.st_multi(extensions.st_geomfromtext('POLYGON((-84.9 38.3,-84.89 38.31,-84.89 38.3,-84.9 38.31,-84.9 38.3))',4326)) where slug='buffer-test';
set role authenticated;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('buffer-test','create',p_title=>'Invalid geometry',p_longitude=>-84.9,p_latitude=>38.305)$q$,'22023');
reset role;
update farm_watch.properties set boundary=extensions.st_geomfromtext('MULTIPOLYGON EMPTY',4326) where slug='buffer-test';
set role authenticated;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('buffer-test','create',p_title=>'Empty geometry',p_longitude=>-84.9,p_latitude=>38.305)$q$,'22023');
reset role;
update farm_watch.properties set status='archived' where slug='buffer-test';
set role authenticated;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('buffer-test','create',p_title=>'Archived',p_longitude=>-84.9,p_latitude=>38.305)$q$,'42501');
reset role;
rollback;
select 'PASS: bounded off-property create/move/metadata/privacy, metres at Kentucky latitude, holes/islands, preservation, selected-property and creator guards, denied far moves and stale revisions' as verification;
