reset role;
do $$ begin
 assert (select count(*)=2 from farm_watch.property_map_pin_fixture_links_v1);
 assert current_setting('request.jwt.claims',true) is not distinct from (select claims from fixture_claims_before), 'migration restores the prior claims';
 assert not exists((select * from fixture_grants_before except select * from farm_watch.map_pin_icon_users_v1)
   union all (select * from farm_watch.map_pin_icon_users_v1 except select * from fixture_grants_before)), 'account grants are unchanged';
 assert not exists(select 1 from fixture_evidence_before b full join farm_watch.property_operator_observations_v1 o using(id) where b.original is distinct from to_jsonb(o)), 'original evidence is unchanged';
 assert not exists(select 1 from fixture_pins_before b left join farm_watch.property_map_pins_v1 p using(id) where b.original is distinct from to_jsonb(p)), 'existing pins are unchanged';
 assert (select pg_get_functiondef(oid)=(select definition from fixture_acl_before) and proacl is not distinct from (select proacl from fixture_acl_before) from pg_proc where oid='public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text)'::regprocedure), 'RPC/ACL unchanged';
 assert (select relrowsecurity and relforcerowsecurity from pg_class where oid='farm_watch.property_map_pin_fixture_links_v1'::regclass);
 assert not has_table_privilege('authenticated','farm_watch.property_map_pin_fixture_links_v1','select');
 assert not has_table_privilege('anon','farm_watch.property_map_pin_fixture_links_v1','insert');
 assert not has_table_privilege('service_role','farm_watch.property_map_pin_fixture_links_v1','update');
 assert not exists(select 1 from farm_watch.property_map_pin_fixture_links_v1 l join farm_watch.property_map_pins_v1 p on p.id=l.pin_id join farm_watch.property_operator_observations_v1 o on o.id=l.source_observation_id where p.created_by<>'00000000-0000-0000-0000-000000000002'::uuid or p.property_id<>o.property_id or not extensions.st_equals(p.geometry,o.geometry) or p.notes is not null or p.revision<>1), 'correct creator/property/location, concise notes';
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.farm_watch_map_pins_v1('validation-property-01','list')->'pins'->0->>'id' as id \gset migrated_
do $$ declare result jsonb; begin
 result:=public.farm_watch_map_pins_v1('validation-property-01','list');
 assert jsonb_array_length(result->'pins')=2;
 assert result->'pins'->0->>'icon'='corn_feeder' and result->'pins'->1->>'icon'='salt_mineral_block';
 assert result->'pins'->0->>'can_edit'='true';
 assert not exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'title' in ('Corn feeder','Salt block')), 'property isolation';
end $$;
select public.farm_watch_map_pins_v1('validation-property-01','update',:'migrated_id',1,'Migrated feeder edited','Field notes',1.1,1.2);
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''validation-property-01'',''update'',%L,1,''Stale'',null,1.1,1.2)',:'migrated_id'),'PT409');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
do $$ begin
 assert (public.farm_watch_map_pins_v1('validation-property-01','list')->'pins'->0->>'can_edit')::boolean=false;
end $$;
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''validation-property-01'',''delete'',%L,2)',:'migrated_id'),'42501');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''validation-property-01'',''update'',%L,2,''Stolen'',null,1,1)',:'migrated_id'),'42501');
select public.pin_test_expect_error('select * from farm_watch.property_map_pin_fixture_links_v1','42501');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.farm_watch_map_pins_v1('validation-property-01','delete',(public.farm_watch_map_pins_v1('validation-property-01','list')->'pins'->1->>'id')::uuid,1);
reset role;
