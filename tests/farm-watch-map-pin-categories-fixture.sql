reset role;
create temp table categories_pins_before as select id,to_jsonb(p) original from farm_watch.property_map_pins_v1 p;
create temp table categories_grants_before as select * from farm_watch.map_pin_icon_users_v1;
create temp table categories_guard_before as select pg_get_functiondef('farm_watch.guard_map_pin_v1()'::regprocedure) definition;
create temp table categories_acl_before as select proacl from pg_proc where oid='public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text)'::regprocedure;
