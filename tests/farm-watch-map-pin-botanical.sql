\set ON_ERROR_STOP on
reset role;
do $$ begin
 assert not exists(select 1 from botanical_pins_before b full join farm_watch.property_map_pins_v1 p using(id) where b.original is distinct from to_jsonb(p)), 'migration must preserve all existing pins';
 assert not exists((select * from botanical_grants_before except select * from farm_watch.map_pin_icon_users_v1) union all (select * from farm_watch.map_pin_icon_users_v1 except select * from botanical_grants_before)), 'icon grant membership unchanged';
 assert not exists(select 1 from botanical_rpcs_before b join pg_proc p on p.oid=b.oid where p.proacl is distinct from b.proacl), 'RPC/guard execution ACLs unchanged';
 assert not exists(select 1 from botanical_rpcs_before b where b.oid<>'public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean)'::regprocedure and pg_get_functiondef(b.oid)<>b.definition), 'photo authorization and geometry/privacy guard unchanged';
 assert (select row(relacl,relrowsecurity,relforcerowsecurity) from pg_class where oid='farm_watch.property_map_pins_v1'::regclass) is not distinct from (select row(relacl,relrowsecurity,relforcerowsecurity) from botanical_table_security_before), 'table ACL/RLS unchanged';
 assert not has_function_privilege('anon','public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean)','execute');
 assert not has_table_privilege('authenticated','farm_watch.property_map_pins_v1','insert');
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare icon_name text; saved jsonb; actor text; begin
 foreach icon_name in array array['sprout','sapling','ear_of_corn','wheat','blackberry','acorn'] loop
  saved := public.farm_watch_map_pins_v1('one','create',p_title=>'Botanical '||icon_name,p_longitude=>0,p_latitude=>1,p_icon=>icon_name,p_color=>'#007b0b')->'pin';
  assert saved->>'icon'=icon_name and saved->>'color'='#007b0b' and saved->>'category'='auto';
  assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'id'=saved->>'id' and p->>'icon'=icon_name);
  saved := public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,1,'Manual botanical',null,0,1,p_color=>'#4d7136',p_category=>'hunting')->'pin';
  saved := public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,2,'Legacy botanical',null,0,1)->'pin';
  assert saved->>'icon'=icon_name and saved->>'color'='#4d7136' and saved->>'category'='hunting' and saved->>'revision'='3';
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''Stale'',null,0,1)',saved->>'id'),'PT409');
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''two'',''delete'',%L,3)',saved->>'id'),'42501');
  foreach actor in array array['00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006'] loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'user_metadata',jsonb_build_object('can_use_pin_icons',true))::text,true);
   assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'id'=saved->>'id' and p->>'icon'=icon_name and p->>'can_edit'='false');
   perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Denied'',p_longitude=>0,p_latitude=>1,p_icon=>%L)',icon_name),'42501');
   perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,3)',saved->>'id'),'42501');
  end loop;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","is_anonymous":true}',true);
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Anon'',p_longitude=>0,p_latitude=>1,p_icon=>%L)',icon_name),'42501');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
  perform public.farm_watch_map_pins_v1('one','delete',(saved->>'id')::uuid,3);
 end loop;
 foreach icon_name in array array['ear-of-corn','Sprout','seedling','__proto__','<svg/>'] loop
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Invalid'',p_longitude=>0,p_latitude=>1,p_icon=>%L)',icon_name),'22023');
 end loop;
end $$;
reset role;
select 'PASS: botanical symbols CRUD/reload, saved color/category preservation, stale revisions, property isolation, shared viewing, anonymous and grantless restrictions' as verification;
