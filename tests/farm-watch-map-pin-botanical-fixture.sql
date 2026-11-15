reset role;
create temp table botanical_pins_before as select id,to_jsonb(p) original from farm_watch.property_map_pins_v1 p;
create temp table botanical_grants_before as select * from farm_watch.map_pin_icon_users_v1;
create temp table botanical_rpcs_before as select oid,pg_get_functiondef(oid) definition,proacl from pg_proc where oid in (
 'public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean)'::regprocedure,
 'public.farm_watch_pin_photos_v1(text,uuid,text,uuid,integer)'::regprocedure,
 'farm_watch.guard_map_pin_v1()'::regprocedure);
create temp table botanical_table_security_before as select relacl,relrowsecurity,relforcerowsecurity from pg_class where oid='farm_watch.property_map_pins_v1'::regclass;
