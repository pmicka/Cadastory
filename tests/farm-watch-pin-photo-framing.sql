-- Execute after all prior pin, privacy and account migrations. The old photo
-- suite intentionally runs before this migration to guard legacy compatibility.
reset role;
do $$ begin
 assert exists(select 1 from information_schema.columns where table_schema='farm_watch'
  and table_name='map_pin_photos_v1' and column_name='focal_x');
 assert not has_table_privilege('authenticated','farm_watch.map_pin_photos_v1','update');
 assert not has_function_privilege('anon',
  'public.farm_watch_pin_photo_framing_v1(text,uuid,uuid,integer,integer,integer)','execute');
 assert has_function_privilege('authenticated',
  'public.farm_watch_pin_photo_framing_v1(text,uuid,uuid,integer,integer,integer)','execute');
end $$;
begin;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
select set_config('test.framing_pin',(
 public.farm_watch_map_pins_v1('one','create',p_title=>'Framing pin',
  p_longitude=>0,p_latitude=>1)->'pin'->>'id'),true);
reset role;
do $$ declare n int; photo uuid; begin
 for n in 1..4 loop
  photo:=gen_random_uuid();
  perform set_config('test.framing_photo_'||n,photo::text,true);
  perform public.pin_test_seed_photo_v1(current_setting('test.framing_pin')::uuid,photo);
 end loop;
end $$;
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
do $$ declare n int; saved jsonb; pin uuid:=current_setting('test.framing_pin')::uuid;
 photos jsonb; begin
 for n in 1..4 loop
  saved:=public.farm_watch_pin_photos_v1('one',pin,'attach',current_setting('test.framing_photo_'||n)::uuid,n);
  assert (saved->>'revision')::int=n+1,'attachment revision';
  assert saved->'photo'->>'focal_x'='50' and saved->'photo'->>'focal_y'='50','legacy/default centering';
 end loop;
 photos:=public.farm_watch_pin_photos_v1('one',pin,'list')->'photos';
 assert jsonb_array_length(photos)=4,'four photos remain supported';
 assert not exists(select 1 from jsonb_array_elements(photos) p
  where p->>'focal_x'<>'50' or p->>'focal_y'<>'50'),'all existing photos centered';
 for n in 1..4 loop
  saved:=public.farm_watch_pin_photo_framing_v1('one',pin,
   current_setting('test.framing_photo_'||n)::uuid,4+n,10*n,100-10*n);
  assert (saved->>'revision')::int=5+n,'framing increments revision';
  assert (saved->'photo'->>'focal_x')::int=10*n,'independent X';
  assert (saved->'photo'->>'focal_y')::int=100-10*n,'independent Y';
 end loop;
 photos:=public.farm_watch_pin_photos_v1('one',pin,'list')->'photos';
 assert not exists(select 1 from jsonb_array_elements(photos) p
  where (p->>'focal_x')::int not in (10,20,30,40)
    or (p->>'focal_y')::int not in (90,80,70,60));
 saved:=public.farm_watch_pin_photo_framing_v1('one',pin,
   current_setting('test.framing_photo_1')::uuid,9,10,90);
 assert saved->>'revision'='9','no-op framing does not bump revision';
 perform public.pin_test_expect_error(format(
  'select public.farm_watch_pin_photo_framing_v1(''one'',%L,%L,9,-1,50)',
  pin,current_setting('test.framing_photo_1')),'22023');
 perform public.pin_test_expect_error(format(
  'select public.farm_watch_pin_photo_framing_v1(''one'',%L,%L,9,101,50)',
  pin,current_setting('test.framing_photo_1')),'22023');
 perform public.pin_test_expect_error(format(
  'select public.farm_watch_pin_photo_framing_v1(''one'',%L,%L,8,50,50)',
  pin,current_setting('test.framing_photo_1')),'PT409');
 perform public.pin_test_expect_error(format(
  'select public.farm_watch_pin_photo_framing_v1(''one'',%L,%L,9,50,50)',
  pin,gen_random_uuid()),'42501');
 perform public.pin_test_expect_error(format(
  'select public.farm_watch_pin_photo_framing_v1(''two'',%L,%L,9,50,50)',
  pin,current_setting('test.framing_photo_1')),'42501');
end $$;
-- Other authorized property members may see shared framing, but not mutate it.
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare pin uuid:=current_setting('test.framing_pin')::uuid; begin
 assert jsonb_array_length(public.farm_watch_pin_photos_v1('one',pin,'list')->'photos')=4;
 perform public.pin_test_expect_error(format(
  'select public.farm_watch_pin_photo_framing_v1(''one'',%L,%L,9,50,50)',
  pin,current_setting('test.framing_photo_1')),'42501');
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000003"}';
select public.pin_test_expect_error(format(
 'select public.farm_watch_pin_photos_v1(''one'',%L,''list'')',
 current_setting('test.framing_pin')),'42501');
reset role;
-- Security-definer-only path: even an owner cannot change stored bytes or paths.
do $$ begin
 begin
  update farm_watch.map_pin_photos_v1 set bytes=bytes+1
   where id=current_setting('test.framing_photo_1')::uuid;
  raise exception 'photo bytes unexpectedly mutable';
 exception when sqlstate '42501' then null;
 end;
end $$;
rollback;
select 'PASS: pin framing defaults, independent positions, immutable bytes, optimistic revisions, authorized sharing, creator-only updates, isolation and legacy RPC';
