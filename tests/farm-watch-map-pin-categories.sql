reset role;
do $$ begin
 assert not exists(select 1 from categories_pins_before b full join farm_watch.property_map_pins_v1 p using(id)
   where b.original is distinct from to_jsonb(p)-'category'), 'existing pin identities, fields and revisions unchanged';
 assert (select bool_and(category='auto') from farm_watch.property_map_pins_v1), 'old pins inherit automatic icon categorization';
 assert not exists((select * from categories_grants_before except select * from farm_watch.map_pin_icon_users_v1)
   union all (select * from farm_watch.map_pin_icon_users_v1 except select * from categories_grants_before)), 'no grants changed';
 assert pg_get_functiondef('farm_watch.guard_map_pin_v1()'::regprocedure)=(select definition from categories_guard_before), 'ownership/property/revision/boundary guard unchanged';
 assert to_regprocedure('public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text)') is null, 'old overload removed';
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='farm_watch_map_pins_v1'), 'one unambiguous RPC';
 assert (select proacl is not distinct from (select proacl from categories_acl_before) from pg_proc
   where oid='public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text)'::regprocedure), 'same RPC role grants';
 assert not has_table_privilege('authenticated','farm_watch.property_map_pins_v1','select,insert,update,delete'), 'no direct table access';
end $$;
-- Roll back test pins; the later independent-session and HTTP tests use the
-- original fixture records and expected revisions.
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare saved jsonb; chosen text; actor uuid; begin
 foreach chosen in array array['auto','general','hunting','farming-orchard'] loop
  saved:=public.farm_watch_map_pins_v1('one','create',p_title=>'Category test',p_longitude=>0,p_latitude=>1,p_icon=>'crop',p_category=>chosen)->'pin';
  assert saved->>'category'=chosen and saved->>'revision'='1';
  assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'id'=saved->>'id' and p->>'category'=chosen), 'category persisted and listed';
  saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,1,'Icon changed',null,1.5,1.5,p_icon=>'deerstand')->'pin';
  assert saved->>'category'=chosen and saved->>'revision'='2', 'omission/older client preserves category even on icon change';
  saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,2,'Manual category',null,1.5,1.5,p_category=>'general')->'pin';
  assert saved->>'category'='general' and saved->>'icon'='deerstand';
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,2,''Stale'',null,1.5,1.5,p_category=>''hunting'')',saved->>'id'),'PT409');
  saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,3,'Automatic again',null,1.5,1.5,p_category=>'auto')->'pin';
  assert saved->>'category'='auto' and saved->>'revision'='4';
  foreach actor in array array['00000000-0000-0000-0000-000000000001'::uuid,'00000000-0000-0000-0000-000000000005'::uuid,'00000000-0000-0000-0000-000000000006'::uuid] loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
   assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'id'=saved->>'id' and p->>'category'='auto' and p->>'can_edit'='false');
   perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,4,''Stolen category/move'',null,1,1,p_category=>''hunting'')',saved->>'id'),'42501');
   perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,4)',saved->>'id'),'42501');
  end loop;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''two'',''update'',%L,4,''Wrong property'',null,11,11,p_category=>''general'')',saved->>'id'),'42501');
  perform public.farm_watch_map_pins_v1('one','delete',(saved->>'id')::uuid,4);
 end loop;
 foreach chosen in array array['','Hunting','water','__proto__','<svg/>',repeat('x',2001)] loop
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Invalid'',p_longitude=>0,p_latitude=>1,p_category=>%L)',chosen),'22023');
 end loop;
end $$;
-- Category selection is available to every authorized creator; it does not
-- unlock the original operator's restricted icon choices.
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
select public.farm_watch_map_pins_v1('one','create',p_title=>'Viewer hunting note',p_longitude=>0,p_latitude=>1,p_category=>'hunting');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Not an icon grant',p_longitude=>0,p_latitude=>1,p_category=>'hunting',p_icon=>'crop')$q$,'42501');
reset role;
rollback;
select 'PASS: category persistence, automatic/manual/legacy semantics, bounded input, unchanged data/grants/guard/ACL, creator-only CRUD, role denials, property scope and stale revisions' as verification;
