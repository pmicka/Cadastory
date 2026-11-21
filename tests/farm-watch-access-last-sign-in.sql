-- Extend the owner directory without exposing Auth timestamps to other roles.
begin;
update auth.users
  set last_sign_in_at='2026-11-20T15:22:00Z'::timestamptz
  where id in ('00000000-0000-0000-0000-000000000004',
               '00000000-0000-0000-0000-000000000001');
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare members jsonb; begin
  members:=public.farm_watch_manage_access_v1()->'members';
  assert exists(select 1 from jsonb_array_elements(members) m
    where m->>'email'='invited@example.invalid'
      and m->>'google_linked'='true'
      and m->>'has_signed_in'='true'
      and (m->>'last_sign_in_at')::timestamptz =
        '2026-11-20T15:22:00Z'::timestamptz),
      'confirmed Google user must expose recorded sign-in';
  assert exists(select 1 from jsonb_array_elements(members) m
    where m->>'email'='creator@example.invalid'
      and m->>'google_linked'='false'
      and m->>'last_sign_in_at' is null),
      'never imply Google login from unrelated Auth timestamp';
  assert exists(select 1 from jsonb_array_elements(members) m
    where m->>'email'='other@example.invalid'
      and m->>'role'='owner'
      and m->>'last_sign_in_at' is null),
      'unlinked owner account has no verified timestamp';
end $$;

reset role;
update auth.users set last_sign_in_at=null
  where id='00000000-0000-0000-0000-000000000004';
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ begin
  assert exists(select 1
    from jsonb_array_elements(public.farm_watch_manage_access_v1()->'members') m
    where m->>'email'='invited@example.invalid'
      and m->>'google_linked'='true'
      and m->>'has_signed_in'='false'
      and m->>'last_sign_in_at' is null),
      'Google-linked account without recorded login has no timestamp';
end $$;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
select public.pin_test_expect_error($q$
  select public.farm_watch_manage_access_v1()
$q$,'42501');
reset role;
rollback;
select 'PASS: owner-only last sign-in availability, Google verification, null handling and viewer isolation' as verification;
