-- Run after the Farm Watch authorization fixtures and the gallery migration.
-- All fixture mutations roll back; no public website assets are touched.
reset role;
do $$ begin
  assert not has_table_privilege('authenticated','farm_watch.home_gallery_v1','select,insert,update,delete');
  assert not has_table_privilege('authenticated','farm_watch.home_gallery_photos_v1','select,insert,update,delete');
  assert not has_table_privilege('anon','farm_watch.home_gallery_v1','select');
  assert not has_function_privilege('anon','public.farm_watch_home_gallery_v1(text,text,integer,integer,text,text,integer,integer,boolean,integer[])','execute');
  assert has_function_privilege('authenticated','public.farm_watch_home_gallery_v1(text,text,integer,integer,text,text,integer,integer,boolean,integer[])','execute');
end $$;

begin;
-- Normalize the existing map-pin fixture accounts inside this rollback-only unit.
update farm_watch.authorized_users
set status='active',revoked_at=null,
    account_role=case when user_id='00000000-0000-0000-0000-000000000001' then 'viewer' else 'owner' end
where user_id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
insert into farm_watch.home_gallery_v1(property_id)
select id from farm_watch.properties where slug in ('one','two');
insert into farm_watch.home_gallery_photos_v1(property_id,photo_number,sort_index)
select p.id, n.num, n.ord
from farm_watch.properties p,
unnest(array[6,1,2,3,4,5,7,8,9,10]::smallint[]) with ordinality as n(num,ord)
where p.slug in ('one','two');

set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}'; -- viewer
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v1('one');
  assert result->>'revision'='1' and result->>'can_edit'='false';
  assert jsonb_array_length(result->'photos')=10;
  assert result->'photos'->0->>'photo_number'='6';
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v1('one','update',6,1,p_caption=>'viewer write')
  $q$,'42501');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v1('one','reorder',p_expected_revision=>1,p_order=>array[1,2,3,4,5,6,7,8,9,10])
  $q$,'42501');
end $$;

set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}'; -- owner
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v1('one','update',6,1,
    p_caption=>'<img src=x onerror=alert(1)>',p_alt_text=>'Farm gathering area',
    p_focal_x=>25,p_focal_y=>65,p_is_visible=>false);
  assert result->>'revision'='2';
  result:=public.farm_watch_home_gallery_v1('one','list');
  assert result->>'can_edit'='true' and jsonb_array_length(result->'photos')=10;
  assert result->'photos'->0->>'caption'='<img src=x onerror=alert(1)>';
  assert result->'photos'->0->>'is_visible'='false';
  assert result->'photos'->0->>'focal_x'='25';
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v1('one','update',6,1,p_caption=>'stale')
  $q$,'PT409');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v1('one','update',6,2,p_focal_x=>101)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v1('one','update',6,2,p_caption=>repeat('x',241))
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v1('one','update',6,2)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v1('one','reorder',p_expected_revision=>2,
      p_order=>array[1,1,2,3,4,5,7,8,9,10])
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_home_gallery_v1('no-property')
  $q$,'42501');
  result:=public.farm_watch_home_gallery_v1('one','reorder',
    p_expected_revision=>2,p_order=>array[10,9,8,7,6,5,4,3,2,1]);
  assert result->>'revision'='3';
  result:=public.farm_watch_home_gallery_v1('one','list');
  assert result->'photos'->0->>'photo_number'='10';
  assert result->'photos'->4->>'photo_number'='6';
  assert (public.farm_watch_home_gallery_v1('two','list')->>'revision')::integer=1;
end $$;

set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}'; -- viewer only sees visible
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v1('one','list');
  assert jsonb_array_length(result->'photos')=9;
  assert not exists(select 1 from jsonb_array_elements(result->'photos') p where p->>'photo_number'='6');
  assert not exists(select 1 from jsonb_array_elements(public.farm_watch_home_gallery_v1('two','list')->'photos') p
    where p->>'caption'='<img src=x onerror=alert(1)>');
end $$;

set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000003"}'; -- unauthorized
select public.pin_test_expect_error($q$select public.farm_watch_home_gallery_v1('one')$q$,'42501');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","is_anonymous":true}';
select public.pin_test_expect_error($q$select public.farm_watch_home_gallery_v1('one')$q$,'42501');
set request.jwt.claims='{}';
select public.pin_test_expect_error($q$select public.farm_watch_home_gallery_v1('one')$q$,'42501');
reset role;
set role anon;
select public.pin_test_expect_error($q$select public.farm_watch_home_gallery_v1('one')$q$,'42501');
reset role;

-- Reuse existing role fixtures, exercise current-role revocation and admin role.
update farm_watch.authorized_users set account_role='admin' where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare result jsonb; begin
  result:=public.farm_watch_home_gallery_v1('one','update',6,3,p_alt_text=>'Revised');
  assert result->>'revision'='4';
end $$;
reset role;
update farm_watch.authorized_users set status='revoked',revoked_at=now()
where user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
select public.pin_test_expect_error($q$select public.farm_watch_home_gallery_v1('one')$q$,'42501');
reset role;
rollback;

select 'PASS: gallery owner/admin writes, viewer read-only visibility, protected tables, authorization, revisions, property isolation, bounded text/focal, atomic order and revocation' as verification;
