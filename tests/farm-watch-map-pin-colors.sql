reset role;
do $$ begin
 assert (select color='#ffd27e' and to_jsonb(p)-'color'=(select original from pin_color_before_upgrade)
  from farm_watch.property_map_pins_v1 p where id='20000000-0000-0000-0000-000000000099'),
  'existing pins gain gold without changing identity, content, position, timestamps or revision';
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='farm_watch_map_pins_v1'), 'one unambiguous RPC signature';
 assert not has_function_privilege('anon',
  'public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text)','execute');
end $$;
delete from farm_watch.properties where slug='color-upgrade-fixture';
delete from auth.users where id='00000000-0000-0000-0000-000000000099';
update farm_watch.authorized_users set status='active';
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
select public.farm_watch_map_pins_v1('one','create',p_title=>'Color fixture',p_longitude=>0,p_latitude=>1,p_color=>'#2463EB')->'pin'->>'id' as id \gset color_
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Invalid color',p_longitude=>0,p_latitude=>1,p_color=>'#fff')$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'Trailing newline',p_longitude=>0,p_latitude=>1,p_color=>E'#2463eb\n')$q$,'22023');
select public.pin_test_expect_error($q$select public.farm_watch_map_pins_v1('one','create',p_title=>'CSS injection',p_longitude=>0,p_latitude=>1,p_color=>'red;fill:url(x)')$q$,'22023');
do $$ begin
 assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p
  where p->>'title'='Color fixture' and p->>'color'='#2463eb'), 'normalized color persists and lists';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''Stolen color'',null,0,1,''#ff0000'')', :'color_id'),'42501');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
-- An old client does not know the new color field; its update must preserve it.
select public.farm_watch_map_pins_v1('one','update', :'color_id',1,'Color fixture','Legacy edit',0,1);
do $$ begin
 assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p
  where p->>'title'='Color fixture' and p->>'color'='#2463eb' and p->>'revision'='2');
end $$;
select public.farm_watch_map_pins_v1('one','update', :'color_id',2,'Color fixture',null,0,1,'#FF0000');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,2,''Stale color'',null,0,1,''#00ff00'')', :'color_id'),'PT409');
select public.farm_watch_map_pins_v1('one','delete', :'color_id',3);
reset role;
select 'PASS: existing-pin upgrade, persisted colors, creator-only recolor, safe color bounds, stale-color conflict and old-client preservation' as verification;
