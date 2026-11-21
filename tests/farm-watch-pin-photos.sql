reset role;
do $$ begin
 assert not exists(select 1 from photos_pins_before b full join farm_watch.property_map_pins_v1 p using(id) where b.original is distinct from to_jsonb(p)), 'legacy pins unchanged';
 assert pg_get_functiondef('farm_watch.guard_map_pin_v1()'::regprocedure)=(select definition from photos_guard_before),'guard unchanged';
 assert not exists((select * from photos_grants_before except select * from farm_watch.map_pin_icon_users_v1) union all(select * from farm_watch.map_pin_icon_users_v1 except select * from photos_grants_before)),'grants unchanged';
 assert not has_table_privilege('authenticated','farm_watch.map_pin_photos_v1','select,insert,update,delete');
 assert not has_table_privilege('service_role','farm_watch.map_pin_photos_v1','select,insert,update,delete');
 assert not has_function_privilege('authenticated','public.farm_watch_pin_photo_cleanup_v1(text[],text)','execute');
 assert not has_function_privilege('anon','public.farm_watch_pin_photos_v1(text,uuid,text,uuid,integer)','execute');
 assert exists(select 1 from storage.buckets where id='farm-watch-pin-photos' and not public and file_size_limit=524288);
end $$;
-- Test helper models the private service's Storage write; never shipped/deployed.
create function public.pin_test_seed_photo_v1(p_pin_id uuid,p_photo_id uuid,p_width integer default 1600,p_bytes integer default 100000)
returns text language plpgsql security definer set search_path='' as $$
declare path text; begin
 select property_id::text||'/'||id::text||'/'||p_photo_id::text||'.webp' into path from farm_watch.property_map_pins_v1 where id=p_pin_id;
 insert into storage.objects(bucket_id,name,metadata,user_metadata) values('farm-watch-pin-photos',path,jsonb_build_object('size',p_bytes,'mimetype','image/webp'),jsonb_build_object('pin_id',p_pin_id,'photo_id',p_photo_id,'width',p_width,'height',1000));return path;
end $$;
revoke all on function public.pin_test_seed_photo_v1(uuid,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.pin_test_seed_photo_v1(uuid,uuid,integer,integer) to service_role;
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
select set_config('test.photo_pin',(public.farm_watch_map_pins_v1('one','create',p_title=>'Photo pin',p_longitude=>0,p_latitude=>1)->'pin'->>'id'),true);
reset role;
do $$ declare id uuid; n integer; begin
 for n in 1..5 loop
  id:=gen_random_uuid();perform set_config('test.photo_'||n,id::text,true);
  perform public.pin_test_seed_photo_v1(current_setting('test.photo_pin')::uuid,id);
 end loop;
 id:=gen_random_uuid();perform set_config('test.photo_wide',id::text,true);perform public.pin_test_seed_photo_v1(current_setting('test.photo_pin')::uuid,id,1601);
 id:=gen_random_uuid();perform set_config('test.photo_large',id::text,true);perform public.pin_test_seed_photo_v1(current_setting('test.photo_pin')::uuid,id,1600,524289);
 id:=gen_random_uuid();perform set_config('test.photo_old',id::text,true);perform public.pin_test_seed_photo_v1(current_setting('test.photo_pin')::uuid,id);
 update storage.objects set created_at=now()-interval '2 hours' where name like '%'||current_setting('test.photo_old')||'.webp';
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
do $$ declare saved jsonb; n integer; actor uuid; id uuid:=current_setting('test.photo_pin')::uuid; begin
 assert public.farm_watch_pin_photos_v1('one',id,'list')->'photos'='[]'::jsonb;
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''two'',%L,''list'')',id),'42501');
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''attach'',%L,1)',id,gen_random_uuid()),'22023');
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''attach'',%L,1)',id,current_setting('test.photo_wide')),'23514');
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''attach'',%L,1)',id,current_setting('test.photo_large')),'23514');
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''attach'',%L,1)',id,current_setting('test.photo_old')),'22023');
 for n in 1..4 loop
  saved:=public.farm_watch_pin_photos_v1('one',id,'attach',current_setting('test.photo_'||n)::uuid,n);
  assert (saved->>'revision')::integer=n+1;
 end loop;
 assert jsonb_array_length(public.farm_watch_pin_photos_v1('one',id,'list')->'photos')=4;
 assert exists(select 1 from jsonb_array_elements(public.farm_watch_map_pins_v1('one','list')->'pins') p where p->>'id'=id::text and p->>'photo_count'='4');
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''attach'',%L,5)',id,current_setting('test.photo_5')),'PT409');
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''delete'',%L,1)',id,current_setting('test.photo_1')),'PT409');
 foreach actor in array array['00000000-0000-0000-0000-000000000002'::uuid,'00000000-0000-0000-0000-000000000005'::uuid,'00000000-0000-0000-0000-000000000006'::uuid] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
  assert jsonb_array_length(public.farm_watch_pin_photos_v1('one',id,'list')->'photos')=4;
  assert public.farm_watch_pin_photos_v1('one',id,'read',current_setting('test.photo_1')::uuid)->>'object_path' is not null;
  perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''prepare'',%L,5)',id,current_setting('test.photo_5')),'42501');
  perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''delete'',%L,5)',id,current_setting('test.photo_1')),'42501');
 end loop;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000003"}',true);
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''list'')',id),'42501');
 perform set_config('request.jwt.claims','{}',true);
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''list'')',id),'42501');
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
 saved:=public.farm_watch_pin_photos_v1('one',id,'delete',current_setting('test.photo_1')::uuid,5);assert saved->>'revision'='6';
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''read'',%L)',id,current_setting('test.photo_1')),'42501');
 perform public.pin_test_expect_error(format('select public.farm_watch_pin_photos_v1(''one'',%L,''attach'',%L,6)',id,current_setting('test.photo_1')),'22023');
 perform public.farm_watch_map_pins_v1('one','delete',id,6);
end $$;
-- Even a broad permissive Storage policy cannot let a user read/write photos.
do $$ begin
 assert not exists(select 1 from storage.objects where bucket_id='farm-watch-pin-photos');
 perform public.pin_test_expect_error($q$insert into storage.objects(bucket_id,name) values('farm-watch-pin-photos','spoof.webp')$q$,'42501');
end $$;
reset role;
do $$ begin
 assert not exists(select 1 from farm_watch.map_pin_photos_v1 where pin_id=current_setting('test.photo_pin')::uuid);
 assert (select count(*)=4 from farm_watch.map_pin_photo_deletions_v1),'pin delete cascades metadata and queues all four objects';
end $$;
set role anon;
select public.pin_test_expect_error($q$select public.farm_watch_pin_photos_v1('one',current_setting('test.photo_pin')::uuid,'list')$q$,'42501');
reset role;
set role service_role;
set request.jwt.claims='{"role":"service_role"}';
select public.farm_watch_pin_photo_cleanup_v1();
reset role;
rollback;
select 'PASS: real photo RPC/RLS ownership, sharing, cap, revisions, property isolation, invalid storage references, restricted direct Storage, deletion queue and legacy preservation';
