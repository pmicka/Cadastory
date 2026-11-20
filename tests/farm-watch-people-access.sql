-- Single-property WMW Farm access management must never bypass current roles.
reset role;
do $$ begin
  assert has_function_privilege('authenticated',
    'public.farm_watch_manage_access_v1(text,text,text,integer)','execute');
  assert not has_function_privilege('anon',
    'public.farm_watch_manage_access_v1(text,text,text,integer)','execute');
  assert not has_table_privilege('anon','farm_watch.access_audit_v1','select');
  assert not has_table_privilege('authenticated',
    'farm_watch.authorized_users','select,insert,update,delete');
  assert not has_table_privilege('authenticated',
    'farm_watch.authorized_emails','select,insert,update,delete');
  assert not has_table_privilege('authenticated',
    'farm_watch.access_audit_v1','select,insert,update,delete');
  assert (select relrowsecurity and relforcerowsecurity from pg_class
    where oid='farm_watch.access_audit_v1'::regclass);
end $$;

begin;
update farm_watch.authorized_users set account_role='owner',
 status='active',revoked_at=null where user_id='00000000-0000-0000-0000-000000000002';
update farm_watch.authorized_users set account_role='viewer',
 status='active',revoked_at=null where user_id='00000000-0000-0000-0000-000000000001';
update farm_watch.authorized_emails set status='active',account_role='viewer',revoked_at=null
 where email='invited@example.invalid';

set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
do $$ declare result jsonb;begin
  result:=public.farm_watch_manage_access_v1('list');
  assert result->>'source'='farm-access-v1';
  assert result->>'can_manage'='true';
  assert result->>'revision'='1';
  assert jsonb_array_length(result->'members')>=2;
  assert exists(select 1 from jsonb_array_elements(result->'members') m
    where m->>'source'='direct' and m->>'role'='owner'
      and m->>'managed'='false');
  assert exists(select 1 from jsonb_array_elements(result->'members') m
    where m->>'email'='invited@example.invalid' and m->>'role'='viewer'
      and m->>'google_linked'='true');
  assert exists(select 1 from jsonb_array_elements(result->'members') m
    where m->>'email'='creator@example.invalid' and m->>'source'='direct'
      and m->>'managed'='true'); -- identifiable direct nonowner can be managed
  assert not exists(select 1 from jsonb_array_elements(result->'members') m
    where m ? 'password' or m ? 'access_token');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1('set','other@example.invalid','owner',1)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1('set','other@example.invalid',null,1)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1(null)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1('set','a@example.invalid','viewer',0)
  $q$,'PT409');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1('set','../../evil','viewer',1)
  $q$,'22023');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1('set','other@example.invalid','viewer',1)
  $q$,'42501'); -- owner cannot edit their own access
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1('revoke','other@example.invalid',null,1)
  $q$,'42501'); -- final owner is immutable
end $$;

-- Create a grant for someone who has never signed in. Never impersonate/create
-- an Auth user: an approved email is a pending Google sign-in.
do $$ declare result jsonb;begin
  result:=public.farm_watch_manage_access_v1('set',' NEWperson@Example.invalid ','viewer',1);
  assert result->>'revision'='2' and result->>'action'='grant';
  result:=public.farm_watch_manage_access_v1();
  assert exists(select 1 from jsonb_array_elements(result->'members') m
    where m->>'email'='newperson@example.invalid'
      and m->>'status'='active' and m->>'role'='viewer'
      and m->>'google_linked'='false' and m->>'has_signed_in'='false'
      and m->>'effective_role' is null);
  assert jsonb_array_length(result->'activity')=1;
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1('set','newperson@example.invalid','viewer',1)
  $q$,'PT409');
end $$;

-- Existing direct non-owner grants are synchronized on role changes/revocation.
reset role;
insert into farm_watch.authorized_users(user_id,account_role)
 values('00000000-0000-0000-0000-000000000004','admin');
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000004"}';
select public.pin_test_expect_error($q$
  select public.farm_watch_manage_access_v1()
$q$,'42501'); -- existing admin may not see directory or promote self
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
-- These white-box assertions inspect private tables as the test harness
-- superuser. The RPC itself still verifies JWT and current owner role.
reset role;
do $ declare result jsonb;begin
  result:=public.farm_watch_manage_access_v1('set','invited@example.invalid','viewer',2);
  assert result->>'revision'='3';
  assert (select account_role from farm_watch.authorized_users
    where user_id='00000000-0000-0000-0000-000000000004')='viewer';
  assert public.farm_watch_get_account_role_v1_internal(
    '00000000-0000-0000-0000-000000000004')='viewer';
  result:=public.farm_watch_manage_access_v1('set','invited@example.invalid','admin',3);
  assert result->>'revision'='4';
  assert (select account_role from farm_watch.authorized_users
    where user_id='00000000-0000-0000-0000-000000000004')='admin';
  result:=public.farm_watch_manage_access_v1('revoke','invited@example.invalid',null,4);
  assert result->>'revision'='5' and result->>'action'='revoke';
  assert (select status from farm_watch.authorized_users
    where user_id='00000000-0000-0000-0000-000000000004')='revoked';
  assert (select status from farm_watch.authorized_emails
    where email='invited@example.invalid')='revoked';
  assert not public.farm_watch_authorize_user_v1_internal(
    '00000000-0000-0000-0000-000000000004');
  assert public.farm_watch_get_account_role_v1_internal(
    '00000000-0000-0000-0000-000000000004') is null;
  assert (select count(*) from farm_watch.access_audit_v1)=4;
  assert exists(select 1 from farm_watch.access_audit_v1
    where action='revoke' and target_email='invited@example.invalid'
      and actor_user_id='00000000-0000-0000-0000-000000000002');
  perform public.pin_test_expect_error($q$
    select public.farm_watch_manage_access_v1('revoke','invited@example.invalid',null,5)
  $q$,'PT409');
end $$;

-- A pending email's grant may be changed or revoked; its allowed status is
-- independent of whether Google sign-in has occurred.
do $$ declare result jsonb;begin
  result:=public.farm_watch_manage_access_v1('set','newperson@example.invalid','admin',5);
  assert result->>'action'='change';
  result:=public.farm_watch_manage_access_v1('revoke','newperson@example.invalid',null,6);
  assert result->>'revision'='7';
  assert (select status from farm_watch.authorized_emails
    where email='newperson@example.invalid')='revoked';
  assert jsonb_array_length(public.farm_watch_manage_access_v1()->'activity')=6;
end $$;

-- The target can log back in after revocation; fresh role checks must deny it.
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000004"}';
select public.pin_test_expect_error($q$
 select public.farm_watch_manage_access_v1('set','newperson@example.invalid','owner',7)
$q$,'42501');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}'; -- viewer
select public.pin_test_expect_error($q$
 select public.farm_watch_manage_access_v1()
$q$,'42501');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002","is_anonymous":true}';
select public.pin_test_expect_error($q$
 select public.farm_watch_manage_access_v1()
$q$,'42501');
set request.jwt.claims='{}';
select public.pin_test_expect_error($q$
 select public.farm_watch_manage_access_v1()
$q$,'42501');
reset role;
set role anon;
select public.pin_test_expect_error($q$
 select public.farm_watch_manage_access_v1()
$q$,'42501');
reset role;

-- The audit/state tables remain private under direct SQL access, including a
-- fabricated browser JWT; owner may use only the audited RPC.
set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
select public.pin_test_expect_error($q$
 select * from farm_watch.access_audit_v1
$q$,'42501');
select public.pin_test_expect_error($q$
 update farm_watch.authorized_emails set account_role='owner'
$q$,'42501');
reset role;
rollback;
select 'PASS: WMW access owner-only grants, pending email, direct override reconciliation, revoked login, audit, self/owner protection, revision and RLS' as verification;
