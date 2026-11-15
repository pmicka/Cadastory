reset role;
create temp table privacy_pins_before as select id,to_jsonb(p) original from farm_watch.property_map_pins_v1 p;
create temp table privacy_guard_before as select pg_get_functiondef('farm_watch.guard_map_pin_v1()'::regprocedure) definition;
create temp table privacy_grants_before as select * from farm_watch.map_pin_icon_users_v1;

create temp table privacy_photo_rpc_before as select pg_get_functiondef('public.farm_watch_pin_photos_v1(text,uuid,text,uuid,integer)'::regprocedure) definition;
