reset role;
do $$ begin
 assert not exists(select 1 from pin_icons_before_upgrade b
  join farm_watch.property_map_pins_v1 p using(id)
  where p.icon<>'pin' or to_jsonb(p)-'icon'<>b.original), 'upgrade preserves all previous pin data';
 assert (select count(*)=1 from farm_watch.map_pin_icon_users_v1), 'one explicit bootstrap grant';
 assert (select user_id='00000000-0000-0000-0000-000000000002' from farm_watch.map_pin_icon_users_v1);
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='farm_watch_map_pins_v1'), 'no bypass through an old RPC overload';
 assert (select relrowsecurity and relforcerowsecurity from pg_class
  where oid='farm_watch.map_pin_icon_users_v1'::regclass);
 assert not has_table_privilege('authenticated','farm_watch.map_pin_icon_users_v1','insert');
 assert not has_table_privilege('authenticated','farm_watch.property_map_pins_v1','update');
 assert not has_function_privilege('anon',
  'public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text)','execute');
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare symbol text; saved jsonb; begin
 assert (public.farm_watch_map_pins_v1('one','list')->'capabilities'->>'can_use_pin_icons')::boolean;
 foreach symbol in array array['deerstand','water_pump','container','trail_camera','gate','bonfire','crop'] loop
  saved:=public.farm_watch_map_pins_v1('one','create',p_title=>'Icon '||symbol,p_longitude=>1.5,p_latitude=>1.5,p_icon=>symbol)->'pin';
  assert saved->>'icon'=symbol, 'each allowed symbol persists';
  assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p
    where p->>'id'=saved->>'id' and p->>'icon'=symbol), 'persisted symbol survives retrieval';
  -- Old clients preserve icons as they edit text/color/coordinates.
  saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,1,'Legacy edit',null,0,1)->'pin';
  assert saved->>'icon'=symbol and saved->>'revision'='2';
  saved:=public.farm_watch_map_pins_v1('one','update',(saved->>'id')::uuid,2,'Changed icon',null,1.5,1.5,'#2463eb','gate')->'pin';
  assert saved->>'icon'='gate' and saved->>'revision'='3';
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,2,''Stale'',null,1.5,1.5,null,''crop'')',saved->>'id'),'PT409');
  perform public.farm_watch_map_pins_v1('one','delete',(saved->>'id')::uuid,3);
 end loop;
end $$;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Bad',p_longitude=>0,p_latitude=>1,p_icon=>'<svg onload=alert(1)>')$q$,'22023');
select public.farm_watch_map_pins_v1('one','create',p_title=>'Shared symbol',p_longitude=>0,p_latitude=>1,p_icon=>'trail_camera')->'pin'->>'id' as id \gset icon_
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","app_metadata":{"can_use_pin_icons":true}}';
do $$ begin
 assert not (public.farm_watch_map_pins_v1('one','list')->'capabilities'->>'can_use_pin_icons')::boolean;
 assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p
  where p->>'title'='Shared symbol' and p->>'icon'='trail_camera' and p->>'can_edit'='false'), 'viewers see icons without editing permission';
end $$;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Bypass',p_longitude=>0,p_latitude=>1,p_icon=>'gate')$q$,'42501');
select public.pin_test_expect_error($q$insert into farm_watch.map_pin_icon_users_v1 values(auth.uid())$q$,'42501');
select public.pin_test_expect_error($q$select farm_watch.can_use_map_pin_icons_v1(auth.uid())$q$,'42501');
select public.farm_watch_map_pins_v1('one','create',p_title=>'Ordinary pin',p_longitude=>0,p_latitude=>1)->'pin'->>'id' as id \gset ordinary_
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''No icon grant'',null,0,1,null,''crop'')',:'ordinary_id'),'42501');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''Stolen'',null,0,1,null,''pin'')',:'icon_id'),'42501');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,1)',:'icon_id'),'42501');
select public.farm_watch_map_pins_v1('one','delete',:'ordinary_id',1);
reset role;
-- Later role assignments never confer the one-account feature grant.
insert into farm_watch.authorized_users(user_id,account_role) values('00000000-0000-0000-0000-000000000003','owner');
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000003"}';
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Other owner',p_longitude=>0,p_latitude=>1,p_icon=>'gate')$q$,'42501');
reset role;
update farm_watch.authorized_users set account_role='admin' where user_id='00000000-0000-0000-0000-000000000003';
set role authenticated;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Admin',p_longitude=>0,p_latitude=>1,p_icon=>'bonfire')$q$,'42501');
reset role;
delete from farm_watch.authorized_users where user_id='00000000-0000-0000-0000-000000000003';
-- Revocation takes effect at the database even for an already-issued session.
delete from farm_watch.map_pin_icon_users_v1 where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''Revoked'',null,0,1)',:'icon_id'),'42501');
select public.farm_watch_map_pins_v1('one','delete',:'icon_id',1);
reset role;
insert into farm_watch.map_pin_icon_users_v1 values('00000000-0000-0000-0000-000000000002');
-- Keep distinct authorized owner/admin HTTP fixtures without expanding the grant.
insert into auth.users values
 ('00000000-0000-0000-0000-000000000005','future-owner@example.invalid',now()),
 ('00000000-0000-0000-0000-000000000006','admin@example.invalid',now());
insert into farm_watch.authorized_users(user_id,account_role) values
 ('00000000-0000-0000-0000-000000000005','owner'),
 ('00000000-0000-0000-0000-000000000006','admin');
select 'PASS: account-scoped icons, all seven symbols, shared views, upgrade and legacy preservation, direct-RPC bypass denial, owner/admin denial, revocation and icon conflicts' as verification;
