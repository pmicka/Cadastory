reset role;
do $$ begin
 assert not exists(select 1 from camera_pins_before b full join farm_watch.property_map_pins_v1 p using(id)
   where b.original is distinct from to_jsonb(p)-array['camera_bearing_deg','camera_range_m','camera_fov_deg']), 'all legacy data/revisions/timestamps unchanged';
 assert (select bool_and(camera_bearing_deg is null and camera_range_m is null and camera_fov_deg is null) from farm_watch.property_map_pins_v1), 'no invented legacy headings';
 assert not exists((select * from camera_grants_before except select * from farm_watch.map_pin_icon_users_v1)
   union all (select * from farm_watch.map_pin_icon_users_v1 except select * from camera_grants_before)), 'icon grants unchanged';
 assert pg_get_functiondef('farm_watch.guard_map_pin_v1()'::regprocedure)=(select definition from camera_guard_before), 'ownership/property/boundary/revision guard unchanged';
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='farm_watch_map_pins_v1'), 'one unambiguous RPC';
 assert (select proacl is not distinct from (select proacl from camera_acl_before) from pg_proc
   where oid='public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer)'::regprocedure), 'same RPC role grants';
 assert not has_table_privilege('authenticated','farm_watch.property_map_pins_v1','select,insert,update,delete'), 'private table stays private';
end $$;
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare saved jsonb; actor uuid; item jsonb; key text; value text; begin
 saved:=public.farm_watch_map_pins_v1('one','create',p_title=>'Legacy camera',p_longitude=>0,p_latitude=>1,p_icon=>'trail_camera')->'pin';
 assert saved->>'camera_bearing_deg' is null and saved->>'camera_range_m'='24.384' and saved->>'camera_fov_deg'='40', 'legacy camera has proposed defaults but no heading';
 saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,1,'Legacy notes',null,0,1)->'pin';
 assert saved->>'camera_bearing_deg' is null, 'older clients must not invent headings';
 perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,2,''No direction'',null,0,1,p_camera_range_m=>30)',saved->>'id'),'22023');
 saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,2,'Aimed camera',null,0,1,p_camera_bearing_deg=>90)->'pin';
 assert saved->>'camera_bearing_deg'='90' and saved->>'camera_range_m'='24.384' and saved->>'camera_fov_deg'='40';
 foreach actor in array array['00000000-0000-0000-0000-000000000001'::uuid,'00000000-0000-0000-0000-000000000005'::uuid,'00000000-0000-0000-0000-000000000006'::uuid] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
  select p into item from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'id'=saved->>'id';
  assert item->>'camera_bearing_deg'='90' and item->>'can_edit'='false', 'authorized users share camera view';
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,3,''Stolen direction/move'',null,1.5,1.5,p_camera_bearing_deg=>180)',saved->>'id'),'42501');
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,3)',saved->>'id'),'42501');
 end loop;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
 perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''two'',''update'',%L,3,''Reassigned'',null,11,11,p_camera_bearing_deg=>180)',saved->>'id'),'42501');
 saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,3,'Custom view',null,1.5,1.5,p_camera_bearing_deg=>359,p_camera_range_m=>91.44,p_camera_fov_deg=>120)->'pin';
 assert saved->>'camera_bearing_deg'='359' and saved->>'camera_range_m'='91.44' and saved->>'camera_fov_deg'='120';
 assert saved->>'latitude'='1.5';
 perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,3,''Stale'',null,1.5,1.5,p_camera_bearing_deg=>0)',saved->>'id'),'PT409');
 saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,4,'Old client',null,1.5,1.5)->'pin';
 assert saved->>'camera_bearing_deg'='359' and saved->>'camera_range_m'='91.44' and saved->>'camera_fov_deg'='120', 'omitted fields preserve camera configuration';
 saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,5,'Other icon',null,1.5,1.5,p_icon=>'container')->'pin';
 assert saved->>'camera_bearing_deg' is null and saved->>'camera_range_m' is null and saved->>'camera_fov_deg' is null, 'non-camera clears all settings';
 perform public.farm_watch_map_pins_v1('one','delete',(saved->>'id')::uuid,6);
 for key,value in select * from (values ('camera_bearing_deg','-1'),('camera_bearing_deg','360'),('camera_range_m','1.523'),('camera_range_m','91.441'),('camera_range_m','''NaN'''),('camera_range_m','''Infinity'''),('camera_range_m','''-Infinity'''),('camera_fov_deg','9'),('camera_fov_deg','121')) v(k,v) loop
  perform public.pin_test_expect_error('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Invalid'',p_longitude=>0,p_latitude=>1,p_icon=>''trail_camera'',p_'||key||'=>'||value||')','22023');
 end loop;
 perform public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Not camera',p_longitude=>0,p_latitude=>1,p_camera_bearing_deg=>90)$q$,'22023');
 perform public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Missing direction',p_longitude=>0,p_latitude=>1,p_icon=>'trail_camera',p_camera_fov_deg=>40)$q$,'22023');
 saved:=public.farm_watch_map_pins_v1('one','create',p_title=>'Minimum',p_longitude=>0,p_latitude=>1,p_icon=>'trail_camera',p_camera_bearing_deg=>0,p_camera_range_m=>1.524,p_camera_fov_deg=>10)->'pin';
 assert saved->>'camera_range_m'='1.524' and saved->>'camera_fov_deg'='10';
 -- Revoking the restricted icon grant retains the existing fail-closed guard
 -- even if an old client omits the unchanged icon.
 perform set_config('test.camera_id',saved->>'id',true);
end $$;
reset role;
delete from farm_watch.map_pin_icon_users_v1 where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','update',current_setting('test.camera_id')::uuid,1,'Existing camera',null,0,1,p_camera_bearing_deg=>45)$q$,'42501');
reset role;
insert into farm_watch.map_pin_icon_users_v1 select * from camera_grants_before;
-- Storage constraint is also authoritative for malformed or inappropriate data.
select public.pin_test_expect_error($q$update farm_watch.property_map_pins_v1 set camera_range_m='NaN' where id=current_setting('test.camera_id')::uuid$q$,'23514');
select public.pin_test_expect_error($q$update farm_watch.property_map_pins_v1 set icon='container' where id=current_setting('test.camera_id')::uuid$q$,'23514');
rollback;
select 'PASS: camera settings, real creator authorization, shared reads, bounds, legacy compatibility, unchanged records/ACL/grants/guard, storage constraints and revision conflict';
