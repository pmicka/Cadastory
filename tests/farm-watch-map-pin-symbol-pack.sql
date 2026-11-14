reset role;
do $$ begin
 assert not exists(select 1 from symbol_pack_before b full join farm_watch.property_map_pins_v1 p using(id)
   where b.original is distinct from to_jsonb(p)), 'every existing row/revision/icon is unchanged';
 assert not exists((select * from symbol_pack_grants_before except select * from farm_watch.map_pin_icon_users_v1)
   union all (select * from farm_watch.map_pin_icon_users_v1 except select * from symbol_pack_grants_before)), 'grant membership is unchanged';
 assert (select proacl is not distinct from (select proacl from symbol_pack_acl_before) from pg_proc
   where oid='public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text)'::regprocedure), 'RPC ACL unchanged';
 assert pg_get_functiondef('farm_watch.guard_map_pin_v1()'::regprocedure)=(select definition from symbol_pack_guard_before), 'creator/property/revision/boundary guard is unchanged';
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='farm_watch_map_pins_v1');
 assert not has_table_privilege('authenticated','farm_watch.property_map_pins_v1','insert');
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare symbol text; saved jsonb; begin
 foreach symbol in array array['corn_feeder','salt_mineral_block','tree','pop_up_blind','ladder_stand'] loop
  saved:=public.farm_watch_map_pins_v1('one','create',p_title=>'New pack '||symbol,p_longitude=>0,p_latitude=>1,p_icon=>symbol)->'pin';
  assert saved->>'icon'=symbol;
  assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'id'=saved->>'id' and p->>'icon'=symbol);
  saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,1,'Legacy edit',null,1.5,1.5)->'pin';
  assert saved->>'icon'=symbol and saved->>'revision'='2', 'omitted icon preserves new styles';
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''Stale'',null,1.5,1.5)',saved->>'id'),'PT409');
  perform public.farm_watch_map_pins_v1('one','delete',(saved->>'id')::uuid,2);
 end loop;
end $$;
select public.farm_watch_map_pins_v1('one','create',p_title=>'Shared new tree',p_longitude=>0,p_latitude=>1,p_icon=>'tree')->'pin'->>'id' as id \gset pack_
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","app_metadata":{"can_use_pin_icons":true}}';
do $$ declare symbol text; begin
 assert not (public.farm_watch_map_pins_v1('one','list')->'capabilities'->>'can_use_pin_icons')::boolean;
 assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'title'='Shared new tree' and p->>'icon'='tree' and p->>'can_edit'='false');
 foreach symbol in array array['corn_feeder','salt_mineral_block','tree','pop_up_blind','ladder_stand'] loop
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Denied'',p_longitude=>0,p_latitude=>1,p_icon=>%L)',symbol),'42501');
 end loop;
end $$;
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''Stolen'',null,1.5,1.5,null,''pin'')',:'pack_id'),'42501');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,1)',:'pack_id'),'42501');
set role authenticated;
-- Explicit grants, not future owner/admin status, authorize every new symbol.
do $$ declare actor uuid; symbol text; begin
 foreach actor in array array['00000000-0000-0000-0000-000000000005'::uuid,'00000000-0000-0000-0000-000000000006'::uuid] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
  foreach symbol in array array['corn_feeder','salt_mineral_block','tree','pop_up_blind','ladder_stand'] loop
   perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Denied owner/admin'',p_longitude=>0,p_latitude=>1,p_icon=>%L)',symbol),'42501');
  end loop;
 end loop;
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.farm_watch_map_pins_v1('one','delete',:'pack_id',1);
reset role;
select 'PASS: five added styles, persisted CRUD, legacy preservation, exact data/grant/ACL/guard preservation, noncreator and other-owner/admin denials' as verification;
