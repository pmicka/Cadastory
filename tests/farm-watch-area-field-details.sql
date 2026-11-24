begin;
do $$ begin
  assert not has_function_privilege('anon','public.farm_watch_saved_areas_v2(text,text,uuid,integer,text,jsonb,text,text,boolean,text,jsonb)','execute');
  assert not has_table_privilege('authenticated','farm_watch.saved_map_area_photos_v1','select');
  assert (select relrowsecurity from pg_class where oid='farm_watch.saved_map_area_photos_v1'::regclass);
end $$;
set local role authenticated;
set local request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
do $$
declare
  area_id uuid := gen_random_uuid();
  outline jsonb := '[[0,1],[0.1,1],[0.1,1.1]]';
  photos jsonb := '["/9j/AA=="]';
  item jsonb;
begin
  item := public.farm_watch_saved_areas_v2('one','create',area_id,null,'Field notes',outline,'#abc123','general',true,'Private note',photos)->'area';
  assert item->>'notes'='Private note' and not item ? 'photos';
  assert public.farm_watch_saved_areas_v2('one','create',area_id,null,'Field notes',outline,'#abc123','general',true,'Private note',photos)->'area'=item;
  perform public.pin_test_expect_error(format(
    'select public.farm_watch_saved_areas_v2(''one'',''create'',%L,null,''Field notes'',%L,''#abc123'',''general'',true,''Other'',%L)',
    area_id,outline,photos),'PT409');
  assert public.farm_watch_saved_areas_v2('one','photos',area_id)->'photos'=photos;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
  assert public.farm_watch_saved_areas_v2('one','list')->'areas'='[]'::jsonb;
  perform public.pin_test_expect_error(format('select public.farm_watch_saved_areas_v2(''one'',''photos'',%L)',area_id),'42501');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
  perform public.pin_test_expect_error(format('select public.farm_watch_saved_areas_v2(''two'',''photos'',%L)',area_id),'42501');
  perform public.pin_test_expect_error(format(
    'select public.farm_watch_saved_areas_v2(''one'',''update'',%L,1,''Field notes'',%L,''#abc123'',''general'',false,''No write'',''["invalid"]'')',
    area_id,outline),'22023');
  item := public.farm_watch_saved_areas_v2('one','update',area_id,1,'Field notes',outline,'#abc123','general',false,'Shared note')->'area';
  assert item->>'revision'='2' and item->>'notes'='Shared note';
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
  assert public.farm_watch_saved_areas_v2('one','photos',area_id)->'photos'=photos;
  perform public.pin_test_expect_error(format(
    'select public.farm_watch_saved_areas_v2(''one'',''update'',%L,2,''Field notes'',%L,''#abc123'',''general'',false,''No write'',''[]'')',
    area_id,outline),'42501');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
  perform public.farm_watch_saved_areas_v2('one','update',area_id,2,'Field notes',outline,'#abc123','general',true,'Private again','[]');
  assert public.farm_watch_saved_areas_v2('one','photos',area_id)->'photos'='[]'::jsonb;
  perform public.farm_watch_saved_areas_v2('one','delete',area_id,3);
  perform public.pin_test_expect_error(format('select public.farm_watch_saved_areas_v2(''one'',''photos'',%L)',area_id),'42501');
end $$;
rollback;
\echo PASS: area notes, attachments, visibility, ownership, omission and validation
