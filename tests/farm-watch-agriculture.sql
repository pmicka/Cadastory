begin;
do $$ begin
  assert not has_function_privilege('anon','public.farm_watch_saved_areas_v3(text,text,uuid,integer,text,jsonb,text,text,boolean,text,jsonb,text[],jsonb)','execute');
  assert not has_function_privilege('anon','public.farm_watch_map_pins_v2(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean,text[],jsonb,uuid,boolean)','execute');
end $$;
set local role authenticated;
set local request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';

do $$
declare
  food uuid := gen_random_uuid();
  orchard uuid := gen_random_uuid();
  exclusion uuid := gen_random_uuid();
  private_group uuid := gen_random_uuid();
  orchard_two uuid := gen_random_uuid();
  other_owner_group uuid := gen_random_uuid();
  ring jsonb := '[[0,1],[0.001,1],[0.001,1.001],[0,1.001]]';
  other_ring jsonb := '[[0.0005,1],[0.0015,1],[0.0015,1.001],[0.0005,1.001]]';
  area jsonb;
  pin jsonb;
  listing jsonb;
  ident uuid;
  photo_id uuid := gen_random_uuid();
  baseline_acres numeric;
  union_acres numeric;
begin
  area := public.farm_watch_saved_areas_v2('one','create',food,null,'Cover crop fixture',ring,'#729033','hunting',false,'Check seeds')->'area';
  assert area->'specialized_views'='null'::jsonb and area->'agriculture'='null'::jsonb;
  area := public.farm_watch_saved_areas_v3('one','update',food,1,'Cover crop fixture',ring,'#729033','hunting',false,
    p_specialized_views=>array['hunting','farming-orchard'],p_agriculture=>'{"type":"food_plot","season":"2027","status":"planned"}')->'area';
  assert area @> jsonb_build_object('id',food,'outline',ring,'title','Cover crop fixture','notes','Check seeds','revision',2,
    'category','hunting','color','#729033','is_private',false,'specialized_views',array['hunting','farming-orchard']);
  baseline_acres := (public.farm_watch_saved_areas_v3('one','list')->'managed_acreage'->>'unique_acres')::numeric;
  assert baseline_acres > 0;
  area := public.farm_watch_saved_areas_v3('one','create',orchard,null,'Orchard',other_ring,'#729033','general',false,
    p_agriculture=>'{"type":"orchard"}')->'area';
  assert public.farm_watch_saved_areas_v3('one','create',orchard,null,'Orchard',other_ring,'#729033','general',false,
    p_agriculture=>'{"type":"orchard"}')->'area'=area;
  perform public.pin_test_expect_error(format(
    'select public.farm_watch_saved_areas_v3(''one'',''create'',%L,null,''Orchard'',%L,''#729033'',''general'',false,p_agriculture=>''{"type":"garden"}'')',
    orchard,other_ring),'PT409');
  perform public.farm_watch_saved_areas_v3('one','create',exclusion,null,'Exclusion',other_ring,'#729033','general',false,
    p_agriculture=>'{"type":"turkey_exclusion"}');
  perform public.farm_watch_saved_areas_v3('one','create',private_group,null,'Private orchard',ring,'#729033','general',true,
    p_agriculture=>'{"type":"orchard","status":"inactive"}');
  perform public.farm_watch_saved_areas_v3('two','create',orchard_two,null,'Other property orchard',ring,'#729033','general',false,
    p_agriculture=>'{"type":"orchard"}');
  listing := public.farm_watch_saved_areas_v3('one','list')->'managed_acreage';
  union_acres := (listing->>'unique_acres')::numeric;
  assert union_acres > baseline_acres*1.49 and union_acres < baseline_acres*1.51;
  assert (listing->'by_type'->>'orchard')::numeric > baseline_acres*.99;
  assert not (listing->'by_type' ? 'turkey_exclusion');

  perform public.pin_test_expect_error(format(
    'select public.farm_watch_map_pins_v2(''one'',''create'',p_title=>''Cross-property'',p_longitude=>0,p_latitude=>1,
      p_agriculture=>''{"type":"fruit_tree"}'',p_group_id=>%L,p_set_group=>true)',orchard_two),'22023');
  perform public.pin_test_expect_error(format(
    'select public.farm_watch_map_pins_v2(''one'',''create'',p_title=>''Exclusion group'',p_longitude=>0,p_latitude=>1,
      p_agriculture=>''{"type":"fruit_tree"}'',p_group_id=>%L,p_set_group=>true)',exclusion),'22023');
  perform public.pin_test_expect_error($sql$select public.farm_watch_map_pins_v2('one','create',p_title=>'Invalid date',
    p_longitude=>0,p_latitude=>1,p_agriculture=>'{"type":"fruit_tree","planted_date":"2027-02-29"}')$sql$,'23514');
  perform public.pin_test_expect_error($sql$select public.farm_watch_map_pins_v2('one','create',p_title=>'Invalid status',
    p_longitude=>0,p_latitude=>1,p_agriculture=>'{"type":"fruit_tree","status":"healthy"}')$sql$,'23514');

  pin := public.farm_watch_map_pins_v2('one','create',p_title=>'Apple',p_notes=>'Original notes',p_longitude=>0,p_latitude=>1,
    p_specialized_views=>array['farming-orchard'],p_agriculture=>'{"type":"fruit_tree","status":"planned","species":"Apple","cultivar":"Liberty","condition":"Unchecked"}',
    p_group_id=>private_group,p_set_group=>true)->'pin';
  ident := (pin->>'id')::uuid;
  assert pin->>'planting_group_id'=private_group::text;
  execute 'reset role';
  perform public.pin_test_seed_photo_v1(ident,photo_id);
  execute 'set local role authenticated';
  perform public.farm_watch_pin_photos_v1('one',ident,'attach',photo_id,1,22,66);
  pin := public.farm_watch_map_pins_v2('one','update',ident,2,'Apple','Original notes',0,1,
    p_agriculture=>jsonb_set(pin->'agriculture','{status}','"established"'))->'pin';
  assert pin @> jsonb_build_object('id',ident,'revision',3,'notes','Original notes','planting_group_id',private_group,
    'longitude',0,'latitude',1,'agriculture','{"status":"established","cultivar":"Liberty","condition":"Unchecked"}'::jsonb);
  assert public.farm_watch_pin_photos_v1('one',ident,'list')->'photos'->0
    @> jsonb_build_object('id',photo_id,'focal_x',22,'focal_y',66);
  -- Associating a point outside its group's outline is intentional.
  perform public.farm_watch_saved_areas_v1('one','update',private_group,1,'Private orchard',other_ring,'#729033','general',true);
  assert exists (select 1 from jsonb_array_elements(public.farm_watch_map_pins_v2('one','list')->'pins') p
    where p->>'id'=ident::text and p->>'planting_group_id'=private_group::text);

  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001"}',true);
  assert not exists (select 1 from jsonb_array_elements(public.farm_watch_saved_areas_v3('one','list')->'areas') a
    where a->>'id'=private_group::text);
  assert exists (select 1 from jsonb_array_elements(public.farm_watch_map_pins_v2('one','list')->'pins') p
    where p->>'id'=ident::text and p->>'planting_group_id' is null and not (p->>'can_edit')::boolean);
  perform public.pin_test_expect_error($sql$select public.farm_watch_map_pins_v2('one','create',p_title=>'Viewer',
    p_longitude=>0,p_latitude=>1,p_agriculture=>'{"type":"fruit_tree"}')$sql$,'42501');
  perform public.pin_test_expect_error(format(
    'select public.farm_watch_saved_areas_v3(''one'',''create'',%L,null,''Viewer'',%L,''#729033'',''general'',false,p_specialized_views=>array[''hunting''])',
    gen_random_uuid(),ring),'42501');

  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
  perform public.farm_watch_saved_areas_v3('one','delete',private_group,2);
  assert exists (select 1 from jsonb_array_elements(public.farm_watch_map_pins_v2('one','list')->'pins') p
    where p->>'id'=ident::text and p->>'planting_group_id' is null and p->>'revision'='4' and p->'agriculture'->>'status'='established');
  perform public.farm_watch_map_pins_v2('one','update',ident,4,'Apple','Original notes',0,1,p_group_id=>orchard,p_set_group=>true);
  perform public.farm_watch_saved_areas_v3('one','update',orchard,1,'Orchard',other_ring,'#729033','general',false,p_agriculture=>'{}');
  assert exists (select 1 from jsonb_array_elements(public.farm_watch_map_pins_v2('one','list')->'pins') p
    where p->>'id'=ident::text and p->>'planting_group_id' is null and p->>'revision'='6');
  -- The group's authorized creator need not own the pin or hold its icon grant.
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000005"}',true);
  perform public.farm_watch_saved_areas_v3('one','create',other_owner_group,null,'Shared orchard',ring,'#729033','general',false,
    p_agriculture=>'{"type":"orchard"}');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
  pin := public.farm_watch_map_pins_v2('one','create',p_icon=>'tree',p_title=>'Shared group tree',p_longitude=>0,p_latitude=>1,
    p_agriculture=>'{"type":"fruit_tree"}',p_group_id=>other_owner_group,p_set_group=>true)->'pin';
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000005"}',true);
  perform public.farm_watch_saved_areas_v3('one','delete',other_owner_group,1);
  assert exists (select 1 from jsonb_array_elements(public.farm_watch_map_pins_v2('one','list')->'pins') p
    where p->>'id'=pin->>'id' and p->>'planting_group_id' is null and p->>'revision'='2' and p->>'icon'='tree');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002"}',true);
  perform set_config('test.demoted_agriculture_pin',ident::text,true);
  perform set_config('test.demoted_agriculture_area',food::text,true);
end $$;
reset role;
update farm_watch.authorized_users set account_role='viewer' where user_id='00000000-0000-0000-0000-000000000002';
set local role authenticated;
do $$ declare ident uuid := current_setting('test.demoted_agriculture_pin')::uuid;
  area_id uuid := current_setting('test.demoted_agriculture_area')::uuid;
begin
  assert exists (select 1 from jsonb_array_elements(public.farm_watch_saved_areas_v3('one','list')->'areas') a
    where a->>'id'=area_id::text and not (a->>'can_edit')::boolean);
  perform public.pin_test_expect_error(format('select public.farm_watch_map_pins_v1(''one'',''delete'',%L,6)',ident),'42501');
  perform public.pin_test_expect_error(format(
    'select public.farm_watch_pin_photos_v1(''one'',%L,''prepare'',%L,6)',ident,gen_random_uuid()),'42501');
  perform public.pin_test_expect_error(format('select public.farm_watch_saved_areas_v1(''one'',''delete'',%L,2)',area_id),'42501');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000003"}',true);
  perform public.pin_test_expect_error('select public.farm_watch_map_pins_v2(''one'',''list'')','42501');
  perform public.pin_test_expect_error('select public.farm_watch_saved_areas_v3(''one'',''list'')','42501');
end $$;
rollback;
\echo PASS: agricultural metadata, legacy reclassification, acreage union, isolation, role changes and groups
