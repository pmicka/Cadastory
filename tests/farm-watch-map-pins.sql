-- Actual database authorization boundary; no mocked pin/permission implementation.
create function public.pin_test_expect_error(sql text, code text) returns void language plpgsql set search_path = '' as $$
begin
  execute sql;
  raise exception 'Expected error % for %', code, sql;
exception when others then
  if sqlstate <> code then raise; end if;
end $$;
insert into auth.users values
 ('00000000-0000-0000-0000-000000000001','creator@example.invalid',now()),
 ('00000000-0000-0000-0000-000000000002','other@example.invalid',now()),
 ('00000000-0000-0000-0000-000000000003','stranger@example.invalid',now()),
 ('00000000-0000-0000-0000-000000000004','invited@example.invalid',now());
insert into auth.identities values ('00000000-0000-0000-0000-000000000004','google');
insert into farm_watch.authorized_emails(email) values ('invited@example.invalid');
insert into farm_watch.authorized_users(user_id,account_role) values
 ('00000000-0000-0000-0000-000000000001','viewer'),
 ('00000000-0000-0000-0000-000000000002','owner');
insert into farm_watch.properties(id,slug,display_name,boundary) values
 ('10000000-0000-0000-0000-000000000001','one','One',
  extensions.st_multi(extensions.st_geomfromtext('POLYGON((0 0,2 0,2 2,0 2,0 0),(.5 .5,1 .5,1 1,.5 1,.5 .5))',4326))),
 ('10000000-0000-0000-0000-000000000002','two','Two',
  extensions.st_multi(extensions.st_geomfromtext('POLYGON((10 10,12 10,12 12,10 12,10 10))',4326)));
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select public.farm_watch_map_pins_v1('one','create',p_title=>'<img src=x onerror=alert(1)>',p_notes=>'<script>unsafe()</script>',p_longitude=>0,p_latitude=>1)->'pin'->>'id' as id \gset pin_
select public.farm_watch_map_pins_v1('one','create',p_title=>'Hole edge',p_longitude=>.5,p_latitude=>.75);
select public.farm_watch_map_pins_v1('two','create',p_title=>'Other property',p_longitude=>11,p_latitude=>11);
do $$ declare result jsonb; begin
 result := public.farm_watch_map_pins_v1('one','list');
 assert jsonb_array_length(result->'pins')=2,'property isolation';
 assert result->'pins'->0->>'creator_label'='You';
 assert result->'pins'->0->>'can_edit'='true';
 assert not (result->'pins'->0 ? 'created_by'),'no private identifiers';
 assert result->'pins'->0->>'title'='<img src=x onerror=alert(1)>','plain text preserved';
end $$;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'outside',p_longitude=>3,p_latitude=>1)$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'hole',p_longitude=>.75,p_latitude=>.75)$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'',p_longitude=>0,p_latitude=>1)$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>E'\t\n',p_longitude=>0,p_latitude=>1)$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>repeat('a',101),p_longitude=>0,p_latitude=>1)$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'long',p_notes=>repeat('n',2001),p_longitude=>0,p_latitude=>1)$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'NaN',p_longitude=>'NaN',p_latitude=>1)$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'infinite',p_longitude=>0,p_latitude=>'Infinity')$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'invalid',p_longitude=>181,p_latitude=>1)$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'invalid',p_longitude=>0,p_latitude=>91)$q$,'22023');
select public.pin_test_expect_error($q$select * from farm_watch.property_map_pins_v1$q$,'42501');
select public.pin_test_expect_error($q$insert into farm_watch.property_map_pins_v1 default values$q$,'42501');
select public.pin_test_expect_error($q$update farm_watch.property_map_pins_v1 set created_by='00000000-0000-0000-0000-000000000002'$q$,'42501');
select public.pin_test_expect_error($q$update farm_watch.property_map_pins_v1 set property_id='10000000-0000-0000-0000-000000000002'$q$,'42501');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_created_by=>'00000000-0000-0000-0000-000000000002')$q$,'42883');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''two'',''delete'',%L,1)', :'pin_id'),'42501');
-- Technical owner still cannot modify a viewer's annotation, via direct RPC.
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ begin
 assert public.farm_watch_map_pins_v1('one','list')->'pins'->0->>'can_edit'='false';
 assert public.farm_watch_map_pins_v1('one','list')->'pins'->0->>'creator_label'='Property member';
end $$;
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''hijacked'',null,1.5,1.5)', :'pin_id'),'42501');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,1)', :'pin_id'),'42501');
reset role;
update farm_watch.authorized_users set account_role='admin' where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''admin hijack'',null,1.5,1.5)', :'pin_id'),'42501');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,1)', :'pin_id'),'42501');
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000003"}';
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','list')$q$,'42501');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'bad',p_longitude=>0,p_latitude=>1)$q$,'42501');
set request.jwt.claims = '{}';
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','list')$q$,'42501');
set role anon;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','list')$q$,'42501');
reset role;
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000004"}';
select public.farm_watch_map_pins_v1('one','list'); -- existing Google email invitation contract
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","is_anonymous":true}';
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','list')$q$,'42501');
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001"}';
select public.farm_watch_map_pins_v1('one','update', :'pin_id',1,'Edited','Notes',1.5,1.5);
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''stale'',null,1.4,1.4)', :'pin_id'),'PT409');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,1)', :'pin_id'),'PT409');
reset role;
select public.pin_test_expect_error(format('update farm_watch.property_map_pins_v1 set created_by=''00000000-0000-0000-0000-000000000002'' where id=%L', :'pin_id'),'42501');
select public.pin_test_expect_error(format('update farm_watch.property_map_pins_v1 set property_id=''10000000-0000-0000-0000-000000000002'' where id=%L', :'pin_id'),'42501');
select public.pin_test_expect_error(format('update farm_watch.property_map_pins_v1 set geometry=extensions.st_geomfromtext(''LINESTRING(0 0,1 1)'',4326) where id=%L', :'pin_id'),'22023');
do $$ begin
 assert (select revision=2 and updated_at>created_at and title='Edited' and extensions.st_x(geometry)=1.5 from farm_watch.property_map_pins_v1 where title='Edited');
end $$;
set role authenticated;
select public.farm_watch_map_pins_v1('one','delete', :'pin_id',2);
do $$ begin assert jsonb_array_length(public.farm_watch_map_pins_v1('one','list')->'pins')=1; end $$;
reset role;
update farm_watch.authorized_users set status='revoked' where user_id='00000000-0000-0000-0000-000000000001';
set role authenticated;
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','list')$q$,'42501');
reset role;
select 'PASS: actual pin RPC, grants, ownership, geometry, input and revision boundary';
