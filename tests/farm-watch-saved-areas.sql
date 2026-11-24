begin;
do $$ begin
  assert not has_function_privilege('anon','public.farm_watch_saved_areas_v1(text,text,uuid,integer,text,jsonb,text,text,boolean)','execute');
  assert not has_table_privilege('authenticated','farm_watch.saved_map_areas_v1','select,insert,update,delete');
  assert (select relrowsecurity from pg_class where oid='farm_watch.saved_map_areas_v1'::regclass);
end $$;
set local role authenticated;
set local request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
do $$
declare
  shared uuid := gen_random_uuid();
  private uuid := gen_random_uuid();
  outline jsonb := '[[0,1],[0.1,1],[0.1,1.1]]';
  item jsonb;
  command text;
begin
  item := public.farm_watch_saved_areas_v1('one','create', shared,null,'Shared trail',outline,'#AbC123','hunting',false)->'area';
  assert item->>'color' = '#abc123' and item->>'category'='hunting' and item->'outline'=outline;
  assert item->>'revision'='1' and item->>'can_edit'='true' and not item ? 'created_by';
  assert (public.farm_watch_saved_areas_v1('one','create', shared,null,'Shared trail',outline,'#AbC123','hunting',false)->'area') = item;
  perform public.farm_watch_saved_areas_v1('one','create',private,null,'Private garden',outline,'#123abc','farming-orchard',true);
  assert jsonb_array_length(public.farm_watch_saved_areas_v1('one','list')->'areas')=2;
  assert jsonb_array_length(public.farm_watch_saved_areas_v1('two','list')->'areas')=0;
  perform public.pin_test_expect_error(format(
    'select public.farm_watch_saved_areas_v1(''one'',''update'',%L,1,''Invalid'',%L,''#abc123'',''general'',false)',
      shared,'[[0,0],[1,1],[0,1],[1,0]]'),'22023');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
  item := public.farm_watch_saved_areas_v1('one','list')->'areas';
  assert jsonb_array_length(item)=1 and item->0->>'id'=shared::text and item->0->>'can_edit'='false';
  foreach command in array array[
    format('select public.farm_watch_saved_areas_v1(''one'',''delete'',%L,1)',shared),
    format('select public.farm_watch_saved_areas_v1(''one'',''delete'',%L,1)',private)
  ] loop
    perform public.pin_test_expect_error(command,'42501');
  end loop;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","is_anonymous":true}',true);
  perform public.pin_test_expect_error('select public.farm_watch_saved_areas_v1(''one'',''list'')','42501');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
  item := public.farm_watch_saved_areas_v1('one','update',shared,1,'Private trail',outline,'#abcdef','general',true)->'area';
  assert item->>'is_private'='true' and item->>'revision'='2';
  perform public.pin_test_expect_error(format('select public.farm_watch_saved_areas_v1(''one'',''delete'',%L,1)',shared),'PT409');
  assert (public.farm_watch_saved_areas_v1('one','delete',shared,2)->>'deleted')::boolean;
end $$;
rollback;
\echo PASS: saved area persistence, property isolation, visibility, ownership, validation, and revisions
