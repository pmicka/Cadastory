reset role;
insert into farm_watch.properties(id,slug,display_name,boundary) values
 ('10000000-0000-0000-0000-000000000003','validation-property-01','Migration fixture',
  extensions.st_multi(extensions.st_geomfromtext('POLYGON((0 0,2 0,2 2,0 2,0 0))',4326)));
insert into farm_watch.property_operator_observations_v1(property_id,observation_key,observation_kind,observation_state,geometry_basis,geometry,notes)
values
 ('10000000-0000-0000-0000-000000000003','flat-creek-deer-feeder-01','deer_feeder_location','observed_present','operator_identified',extensions.st_setsrid(extensions.st_makepoint(.2,.4),4326),'Historical feeder provenance'),
 ('10000000-0000-0000-0000-000000000003','flat-creek-salt-block-01','mineral_attractant_location','observed_present','operator_identified',extensions.st_setsrid(extensions.st_makepoint(.7,.8),4326),'Historical mineral provenance'),
 ('10000000-0000-0000-0000-000000000001','flat-creek-deer-feeder-01','deer_feeder_location','observed_present','operator_identified',extensions.st_setsrid(extensions.st_makepoint(0,1),4326),'Different property');
create temporary table fixture_evidence_before as select id,to_jsonb(o) original from farm_watch.property_operator_observations_v1 o;
create temporary table fixture_pins_before as select id,to_jsonb(p) original from farm_watch.property_map_pins_v1 p;
create temporary table fixture_acl_before as select proacl,pg_get_functiondef(oid) definition from pg_proc
 where oid='public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text)'::regprocedure;
create temporary table fixture_claims_before as select current_setting('request.jwt.claims',true) claims;
create temporary table fixture_grants_before as select * from farm_watch.map_pin_icon_users_v1;
