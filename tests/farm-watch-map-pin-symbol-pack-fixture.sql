-- Real legacy symbols must survive the additive allowlist migration unchanged.
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare symbol text; begin
 foreach symbol in array array['deerstand','water_pump','container','trail_camera','gate','bonfire','crop'] loop
  perform public.farm_watch_map_pins_v1('one','create',p_title=>'Before pack '||symbol,p_longitude=>0,p_latitude=>1,p_icon=>symbol);
 end loop;
end $$;
reset role;
create temporary table symbol_pack_before as select id,to_jsonb(p) original from farm_watch.property_map_pins_v1 p;
create temporary table symbol_pack_grants_before as select * from farm_watch.map_pin_icon_users_v1;
create temporary table symbol_pack_acl_before as select proacl from pg_proc
 where oid='public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text)'::regprocedure;
create temporary table symbol_pack_guard_before as select pg_get_functiondef('farm_watch.guard_map_pin_v1()'::regprocedure) definition;
