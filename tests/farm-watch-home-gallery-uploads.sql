-- WMW homepage upload staging: real Postgres auth/RLS regression.
-- Run after the gallery catalog and upload-staging migrations in the
-- disposable PostGIS harness; all fixture mutations are rolled back.
reset role;
do $$ begin
  assert not has_table_privilege('authenticated',
    'farm_watch.home_gallery_uploads_v1','select,insert,update,delete');
  assert not has_table_privilege('anon',
    'farm_watch.home_gallery_upload_deletions_v1','select');
  assert not has_function_privilege('anon',
    'public.farm_watch_home_gallery_uploads_v1(text,text,uuid,integer)','execute');
  assert has_function_privilege('authenticated',
    'public.farm_watch_home_gallery_uploads_v1(text,text,uuid,integer)','execute');
  assert not has_function_privilege('authenticated',
    'public.farm_watch_home_gallery_upload_cleanup_v1(text[],text)','execute');
  assert has_function_privilege('service_role',
    'public.farm_watch_home_gallery_upload_cleanup_v1(text[],text)','execute');
  assert exists(select 1 from storage.buckets where id='farm-watch-home-gallery-uploads'
    and public=false and file_size_limit=524288
    and allowed_mime_types=array['image/webp']);
end $$;

begin;
update farm_watch.authorized_users set status='active',revoked_at=null,
  account_role=case
    when user_id='00000000-0000-0000-0000-000000000001' then 'viewer'
    else 'owner' end
where user_id in ('00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002');
insert into farm_watch.home_gallery_v1(property_id)
  select id from farm_watch.properties where slug in ('one','two');
insert into farm_watch.home_gallery_photos_v1(property_id,photo_number,sort_index)
select p.id,n.number,n.ord from farm_watch.properties p,
  unnest(array[6,1,2,3,4,5,7,8,9,10]::smallint[])
    with ordinality as n(number,ord)
where p.slug in ('one','two');

set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','list')
$q$,'42501');
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','prepare',
    '33333333-3333-3333-3333-333333333333',1)
$q$,'42501');
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_upload_cleanup_v1()
$q$,'42501');

set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_uploads_v1('one','list');
  assert result->>'revision'='1' and result->>'staged_only'='true'
    and jsonb_array_length(result->'photos')=0;
  result:=public.farm_watch_home_gallery_uploads_v1('one','prepare',
    '33333333-3333-3333-3333-333333333333',1);
  -- Authenticated clients cannot SELECT the private properties table.
  assert split_part(result->>'object_path','/',2) =
    '33333333-3333-3333-3333-333333333333.webp'
    and char_length(split_part(result->>'object_path','/',1))=36;
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('one','attach',
      '33333333-3333-3333-3333-333333333333',1)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('one','prepare',
      '33333333-3333-3333-3333-333333333333',0)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('absent','list')
  $q$,'42501');
end $$;

reset role;
insert into storage.objects(
  bucket_id,name,metadata,user_metadata
) select 'farm-watch-home-gallery-uploads',
  p.id::text||'/33333333-3333-3333-3333-333333333333.webp',
  '{"mimetype":"image/webp","size":123}'::jsonb,
  jsonb_build_object('property_id',p.id::text,
    'photo_id','33333333-3333-3333-3333-333333333333',
    'created_by','00000000-0000-0000-0000-000000000002',
    'width',120,'height',100)
from farm_watch.properties p where p.slug='one';

set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_uploads_v1('one','attach',
    '33333333-3333-3333-3333-333333333333',1);
  assert result->>'revision'='2' and result->>'staged_only'='true';
  assert result->'photo'->>'width'='120';
  result:=public.farm_watch_home_gallery_uploads_v1('one','list');
  assert jsonb_array_length(result->'photos')=1
    and result->'photos'->0->>'id'='33333333-3333-3333-3333-333333333333';
  result:=public.farm_watch_home_gallery_uploads_v1('one','read',
    '33333333-3333-3333-3333-333333333333');
  assert result->>'bytes'='123';
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('one','attach',
      '33333333-3333-3333-3333-333333333333',2)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('one','delete',
      '33333333-3333-3333-3333-333333333333',1)
  $q$,'PT409');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('two','read',
      '33333333-3333-3333-3333-333333333333')
  $q$,'42501');
  assert (public.farm_watch_home_gallery_v1('one','list')->>'revision')::integer=2;
  assert jsonb_array_length(public.farm_watch_home_gallery_v1('one','list')->'photos')=10;
end $$;

-- Even with the deliberately permissive synthetic Storage policy in the pin
-- fixture, the dedicated gallery bucket cannot be listed or written directly.
select count(*)=0 as gallery_storage_is_private from storage.objects
  where bucket_id='farm-watch-home-gallery-uploads';
select public.pin_test_expect_error($q$
  insert into storage.objects(bucket_id,name,metadata,user_metadata)
  values('farm-watch-home-gallery-uploads','forbidden.webp','{}','{}')
$q$,'42501');

select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','delete',null,2)
$q$,'22023');
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_uploads_v1('one','delete',
    '33333333-3333-3333-3333-333333333333',2);
  assert result->>'revision'='3' and result->>'deleted'='true';
  assert jsonb_array_length(public.farm_watch_home_gallery_uploads_v1('one','list')->'photos')=0;
end $$;

reset role;
do $$ begin
  assert exists(select 1 from farm_watch.home_gallery_upload_deletions_v1);
  assert not exists(select 1 from farm_watch.home_gallery_uploads_v1);
end $$;
set role service_role;
set request.jwt.claims='{"role":"service_role"}';
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_upload_cleanup_v1();
  assert jsonb_array_length(result->'paths')=1;
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_upload_cleanup_v1(
      p_queue_path=>'../../evil.webp')
  $q$,'22023');
  result:=public.farm_watch_home_gallery_upload_cleanup_v1(
    p_ack_paths=>array[result->'paths'->>0]);
  assert jsonb_array_length(result->'paths')=0;
end $$;
reset role;
update storage.objects set created_at=now()-interval '2 hours'
  where bucket_id='farm-watch-home-gallery-uploads';
set role service_role;
set request.jwt.claims='{"role":"service_role"}';
do $$ begin
  assert jsonb_array_length(
    public.farm_watch_home_gallery_upload_cleanup_v1()->'paths')=1;
end $$;

-- Service-role cleanup never grants an authenticated client path deletion.
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_upload_cleanup_v1(
    p_queue_path=>'11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.webp')
$q$,'42501');
reset role;
update farm_watch.authorized_users set account_role='admin'
where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ begin
  assert public.farm_watch_home_gallery_uploads_v1('one','list')->>'revision'='3';
end $$;
reset role;
update farm_watch.authorized_users set status='revoked',revoked_at=now()
where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','list')
$q$,'42501');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","is_anonymous":true}';
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','list')
$q$,'42501');
reset role;
set role anon;
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','list')
$q$,'42501');
reset role;
rollback;

select 'PASS: private staged gallery storage, owner/admin-only reads and edits, metadata verification, revision lock, isolation, queued cleanup, role revocation and unchanged legacy photos' as verification;
;
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('one','attach',
      '33333333-3333-3333-3333-333333333333',1)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('one','prepare',
      '33333333-3333-3333-3333-333333333333',0)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('absent','list')
  $q$,'42501');
end $$;

reset role;
insert into storage.objects(
  bucket_id,name,metadata,user_metadata
) select 'farm-watch-home-gallery-uploads',
  p.id::text||'/33333333-3333-3333-3333-333333333333.webp',
  '{"mimetype":"image/webp","size":123}'::jsonb,
  jsonb_build_object('property_id',p.id::text,
    'photo_id','33333333-3333-3333-3333-333333333333',
    'created_by','00000000-0000-0000-0000-000000000002',
    'width',120,'height',100)
from farm_watch.properties p where p.slug='one';

set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_uploads_v1('one','attach',
    '33333333-3333-3333-3333-333333333333',1);
  assert result->>'revision'='2' and result->>'staged_only'='true';
  assert result->'photo'->>'width'='120';
  result:=public.farm_watch_home_gallery_uploads_v1('one','list');
  assert jsonb_array_length(result->'photos')=1
    and result->'photos'->0->>'id'='33333333-3333-3333-3333-333333333333';
  result:=public.farm_watch_home_gallery_uploads_v1('one','read',
    '33333333-3333-3333-3333-333333333333');
  assert result->>'bytes'='123';
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('one','attach',
      '33333333-3333-3333-3333-333333333333',2)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('one','delete',
      '33333333-3333-3333-3333-333333333333',1)
  $q$,'PT409');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_uploads_v1('two','read',
      '33333333-3333-3333-3333-333333333333')
  $q$,'42501');
  assert (public.farm_watch_home_gallery_v1('one','list')->>'revision')::integer=2;
  assert jsonb_array_length(public.farm_watch_home_gallery_v1('one','list')->'photos')=10;
end $$;

-- Even with the deliberately permissive synthetic Storage policy in the pin
-- fixture, the dedicated gallery bucket cannot be listed or written directly.
select count(*)=0 as gallery_storage_is_private from storage.objects
  where bucket_id='farm-watch-home-gallery-uploads';
select public.pin_test_expect_error($q$
  insert into storage.objects(bucket_id,name,metadata,user_metadata)
  values('farm-watch-home-gallery-uploads','forbidden.webp','{}','{}')
$q$,'42501');

select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','delete',null,2)
$q$,'22023');
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_uploads_v1('one','delete',
    '33333333-3333-3333-3333-333333333333',2);
  assert result->>'revision'='3' and result->>'deleted'='true';
  assert jsonb_array_length(public.farm_watch_home_gallery_uploads_v1('one','list')->'photos')=0;
end $$;

reset role;
do $$ begin
  assert exists(select 1 from farm_watch.home_gallery_upload_deletions_v1);
  assert not exists(select 1 from farm_watch.home_gallery_uploads_v1);
end $$;
set role service_role;
set request.jwt.claims='{"role":"service_role"}';
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_upload_cleanup_v1();
  assert jsonb_array_length(result->'paths')=1;
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_upload_cleanup_v1(
      p_queue_path=>'../../evil.webp')
  $q$,'22023');
  result:=public.farm_watch_home_gallery_upload_cleanup_v1(
    p_ack_paths=>array(select object_path
      from farm_watch.home_gallery_upload_deletions_v1));
  assert jsonb_array_length(result->'paths')=0;
end $$;
reset role;
update storage.objects set created_at=now()-interval '2 hours'
  where bucket_id='farm-watch-home-gallery-uploads';
set role service_role;
set request.jwt.claims='{"role":"service_role"}';
do $$ begin
  assert jsonb_array_length(
    public.farm_watch_home_gallery_upload_cleanup_v1()->'paths')=1;
end $$;

-- Service-role cleanup never grants an authenticated client path deletion.
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_upload_cleanup_v1(
    p_queue_path=>'11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.webp')
$q$,'42501');
reset role;
update farm_watch.authorized_users set account_role='admin'
where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ begin
  assert public.farm_watch_home_gallery_uploads_v1('one','list')->>'revision'='3';
end $$;
reset role;
update farm_watch.authorized_users set status='revoked',revoked_at=now()
where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','list')
$q$,'42501');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","is_anonymous":true}';
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','list')
$q$,'42501');
reset role;
set role anon;
select public.pin_test_expect_error($q$
  select public.farm_watch_home_gallery_uploads_v1('one','list')
$q$,'42501');
reset role;
rollback;

select 'PASS: private staged gallery storage, owner/admin-only reads and edits, metadata verification, revision lock, isolation, queued cleanup, role revocation and unchanged legacy photos' as verification;
