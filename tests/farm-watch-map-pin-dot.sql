\set ON_ERROR_STOP on
reset role;
do $$ begin
 assert not exists(select 1 from dot_pins_before b full join farm_watch.property_map_pins_v1 p using(id) where b.original is distinct from to_jsonb(p)), 'migration must preserve all existing pins';
 assert not exists((select * from dot_grants_before except select * from farm_watch.map_pin_icon_users_v1) union all (select * from farm_watch.map_pin_icon_users_v1 except select * from dot_grants_before)), 'icon grant membership unchanged';
 assert not exists(select 1 from dot_rpcs_before b join pg_proc p on p.oid=b.oid where p.proacl is distinct from b.proacl), 'RPC/guard execution ACLs unchanged';
 assert not exists(select 1 from dot_rpcs_before b where b.oid<>'public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean)'::regprocedure and pg_get_functiondef(b.oid)<>b.definition), 'photo authorization and geometry/privacy guard unchanged';
 assert (select row(relacl,relrowsecurity,relforcerowsecurity) from pg_class where oid='farm_watch.property_map_pins_v1'::regclass) is not distinct from (select row(relacl,relrowsecurity,relforcerowsecurity) from dot_table_security_before), 'table ACL/RLS unchanged';
 assert not has_function_privilege('anon','public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean)','execute');
 assert not has_table_privilege('authenticated','farm_watch.property_map_pins_v1','insert');
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.farm_watch_map_pins_v1('one','create',p_title=>'Small dot',p_notes=>'Reference point',p_longitude=>0,p_latitude=>1,p_color=>'#008F95',p_icon=>'dot')->'pin'->>'id' as id \gset dot_
do $$ declare result jsonb; begin
 select p into result from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'title'='Small dot';
 assert result->>'icon'='dot' and result->>'color'='#008f95' and result->>'category'='auto';
 assert result->>'notes'='Reference point' and result->>'can_edit'='true' and result->>'is_private'='false' and result->>'photo_count'='0';
 assert result->'camera_bearing_deg'='null'::jsonb and result->'camera_range_m'='null'::jsonb;
end $$;
-- Legacy omission preserves the dot, color and automatic category.
select public.farm_watch_map_pins_v1('one','update',:'dot_id',1,'Small dot edited','Reference point',0,1);
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,1,''Stale'',null,0,1,p_icon=>''dot'')',:'dot_id'),'PT409');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","app_metadata":{"can_use_pin_icons":true}}';
do $$ declare result jsonb; begin
 select p into result from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'title'='Small dot edited';
 assert result->>'icon'='dot' and result->>'can_edit'='false' and result->>'color'='#008f95';
 assert not (public.farm_watch_map_pins_v1('one','list')->'capabilities'->>'can_use_pin_icons')::boolean;
end $$;
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''update'',%L,2,''Stolen'',null,0,1,p_icon=>''dot'')',:'dot_id'),'42501');
select public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,2)',:'dot_id'),'42501');
-- Other owners/admins/viewers cannot acquire dot capability via role or claims.
do $$ declare actor uuid; begin
 foreach actor in array array['00000000-0000-0000-0000-000000000001'::uuid,'00000000-0000-0000-0000-000000000005'::uuid,'00000000-0000-0000-0000-000000000006'::uuid] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'user_metadata',jsonb_build_object('can_use_pin_icons',true))::text,true);
  perform public.pin_test_expect_error('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Denied dot'',p_longitude=>0,p_latitude=>1,p_icon=>''dot'')','42501');
 end loop;
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.farm_watch_map_pins_v1('one','update',:'dot_id',2,'Small dot private',null,0,1,p_icon=>'dot',p_category=>'hunting',p_is_private=>true);
select public.pin_test_expect_error('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Invalid dot'',p_longitude=>0,p_latitude=>1,p_icon=>''dot-small'')','22023');
select public.pin_test_expect_error('select public.farm_watch_map_pins_v1(''one'',''create'',p_title=>''Camera data on dot'',p_longitude=>0,p_latitude=>1,p_icon=>''dot'',p_camera_bearing_deg=>90)','22023');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
do $$ begin assert not exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'title'='Small dot private'); end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
-- Icon conversions keep identity/notes/category/privacy; camera data is cleared.
select public.farm_watch_map_pins_v1('one','update',:'dot_id',3,'Small dot private',null,0,1,p_icon=>'trail_camera',p_camera_bearing_deg=>90);
select public.farm_watch_map_pins_v1('one','update',:'dot_id',4,'Small dot private',null,0,1,p_icon=>'dot');
do $$ declare result jsonb; begin
 select p into result from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'title'='Small dot private';
 assert result->>'icon'='dot' and result->>'category'='hunting' and result->>'is_private'='true' and result->>'revision'='5';
 assert result->'camera_bearing_deg'='null'::jsonb and result->'camera_range_m'='null'::jsonb and result->'camera_fov_deg'='null'::jsonb;
end $$;
select public.farm_watch_map_pins_v1('one','delete',:'dot_id',5);
reset role;
select 'PASS: small dot CRUD, legacy preservation, camera transitions, shared/private visibility, grants, ACL/RLS and stale/noncreator guards' as verification;
