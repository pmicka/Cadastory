-- Unified Farm Watch homepage gallery v2: no separate publishing step.
-- Run after v1 gallery + upload fixture tests; rollback all writes.
reset role;
do $$ begin
  assert has_function_privilege('authenticated',
    'public.farm_watch_home_gallery_v2(text,text,text,integer,text,text,integer,integer,boolean,text[])','execute');
  assert not has_function_privilege('anon',
    'public.farm_watch_home_gallery_v2(text,text,text,integer,text,text,integer,integer,boolean,text[])','execute');
  assert not has_function_privilege('anon',
    'public.farm_watch_home_gallery_image_v1(text,uuid)','execute');
  assert has_function_privilege('authenticated',
    'public.farm_watch_home_gallery_image_v1(text,uuid)','execute');
end $$;

begin;
update farm_watch.authorized_users
  set status='active',revoked_at=null,
  account_role=case when user_id='00000000-0000-0000-0000-000000000001'
    then 'viewer' else 'owner' end
where user_id in ('00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002');
insert into farm_watch.home_gallery_v1(property_id)
  select id from farm_watch.properties where slug in ('one','two');
insert into farm_watch.home_gallery_photos_v1(property_id,photo_number,sort_index)
select p.id,n.number,n.ord from farm_watch.properties p,
 unnest(array[6,1,2,3,4,5,7,8,9,10]::smallint[])
 with ordinality as n(number,ord) where p.slug in ('one','two');

reset role;
insert into storage.objects(bucket_id,name,metadata,user_metadata)
select 'farm-watch-home-gallery-uploads',
 p.id::text||'/33333333-3333-3333-3333-333333333333.webp',
 '{"mimetype":"image/webp","size":124}'::jsonb,
 jsonb_build_object('property_id',p.id::text,
  'photo_id','33333333-3333-3333-3333-333333333333',
  'created_by','00000000-0000-0000-0000-000000000002',
  'width',960,'height',1280)
from farm_watch.properties p where p.slug='one';

set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}'; -- owner
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v2('one','list');
  assert result->>'source'='mixed-gallery-v2';
  assert jsonb_array_length(result->'photos')=10;
  assert result->'photos'->0->>'photo_id'='legacy:6';
  result:=public.farm_watch_home_gallery_uploads_v1('one','attach',
    '33333333-3333-3333-3333-333333333333',1);
  assert result->>'revision'='2';
  result:=public.farm_watch_home_gallery_v2('one');
  assert jsonb_array_length(result->'photos')=11;
  assert result->'photos'->10->>'photo_id'='upload:33333333-3333-3333-3333-333333333333';
  assert result->'photos'->10->>'is_visible'='true';
  assert result->'photos'->10->>'sort_index'='11';
  assert not exists(select 1 from jsonb_array_elements(result->'photos') a
    where a ? 'object_path');
  assert jsonb_array_length(public.farm_watch_home_gallery_v2('two')->'photos')=10;
  assert (public.farm_watch_home_gallery_image_v1('one',
    '33333333-3333-3333-3333-333333333333')->>'bytes')::integer=124;
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v2('one','update','upload:33333333-3333-3333-3333-333333333333',
      1,p_caption=>'stale')
  $q$,'PT409');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v2('one','update','upload:../other',
      2,p_caption=>'unsafe')
  $q$,'22023');
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}'; -- viewer
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v2('one');
  assert result->>'can_edit'='false';
  assert jsonb_array_length(result->'photos')=11;
  assert result->'photos'->10->>'kind'='upload';
  assert (public.farm_watch_home_gallery_image_v1('one',
    '33333333-3333-3333-3333-333333333333')->>'bytes')::integer=124;
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v2('one','update','legacy:6',
      2,p_caption=>'viewer-write')
  $q$,'42501');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_image_v1('two',
      '33333333-3333-3333-3333-333333333333')
  $q$,'42501');
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}'; -- owner
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v2('one','update',
    'upload:33333333-3333-3333-3333-333333333333',2,
    p_caption=>'New orchard photograph',p_alt_text=>'A pear tree',
    p_focal_x=>31,p_focal_y=>63,p_is_visible=>false);
  assert result->>'revision'='3';
  result:=public.farm_watch_home_gallery_v2('one','list');
  assert result->'photos'->10->>'caption'='New orchard photograph';
  assert result->'photos'->10->>'focal_x'='31';
  assert result->'photos'->10->>'is_visible'='false';
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v2('one','reorder',
      p_expected_revision=>3,p_order=>array['legacy:6','legacy:6'])
  $q$,'22023');
  result:=public.farm_watch_home_gallery_v2('one','reorder',
    p_expected_revision=>3,p_order=>array[
      'upload:33333333-3333-3333-3333-333333333333',
      'legacy:6','legacy:1','legacy:2','legacy:3','legacy:4',
      'legacy:5','legacy:7','legacy:8','legacy:9','legacy:10']);
  assert result->>'revision'='4';
  result:=public.farm_watch_home_gallery_v2('one');
  assert result->'photos'->0->>'photo_id'='upload:33333333-3333-3333-3333-333333333333';
  assert result->'photos'->1->>'photo_id'='legacy:6';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}'; -- viewer
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v2('one');
  assert jsonb_array_length(result->'photos')=10;
  assert not exists(select 1 from jsonb_array_elements(result->'photos') p
    where p->>'kind'='upload');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_image_v1('one',
      '33333333-3333-3333-3333-333333333333')
  $q$,'42501');
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v2('one','update',
    'upload:33333333-3333-3333-3333-333333333333',4,p_is_visible=>true);
  assert result->>'revision'='5';
  result:=public.farm_watch_home_gallery_uploads_v1('one','delete',
    '33333333-3333-3333-3333-333333333333',5);
  assert result->>'revision'='6';
  assert jsonb_array_length(public.farm_watch_home_gallery_v2('one')->'photos')=10;
  assert jsonb_array_length(public.farm_watch_home_gallery_v1('one')->'photos')=10;
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_image_v1('one',
      '33333333-3333-3333-3333-333333333333')
  $q$,'42501');
end $$;
reset role;
do $$ begin
  assert (select count(*) from farm_watch.home_gallery_upload_deletions_v1)>0;
end $$;
rollback;
select 'PASS: direct upload auto-publishes in mixed gallery, viewer-safe private image reads, metadata, reordering, hiding, revocation and removal' as verification;
