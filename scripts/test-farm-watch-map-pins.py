#!/usr/bin/env python3
"""Test the real pin migration + existing allowlist/role SQL in an EMPTY PostGIS DB.

Usage: python scripts/test-farm-watch-map-pins.py docker exec -i <container> psql -U postgres
Refuses an existing farm_watch schema. JWT claims are supplied as PostgREST does;
only the auth schema bootstrap is synthetic. Never run against a deployment.
"""
from pathlib import Path
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

root = Path(__file__).resolve().parents[1]
migrations = root / 'supabase/migrations'
setup = r'''
\set ON_ERROR_STOP on
set client_min_messages=warning;
create schema farm_watch; -- fail first on a nonempty deployment
create schema extensions;
create extension if not exists postgis with schema extensions;
create schema auth;
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls; end if;
end $$;
create function extensions.gen_random_uuid() returns uuid language sql as $$select gen_random_uuid()$$;
create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz);
create table auth.identities(user_id uuid references auth.users, provider text);
create function auth.uid() returns uuid language sql stable as
$$select nullif(current_setting('request.jwt.claims',true)::jsonb->>'sub','')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as
$$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
grant usage on schema auth to authenticated;
'''
for filename in ['20260917053544_add_private_farm_watch_v0.sql',
                 '20260920163700_add_farm_watch_authorized_email_viewers_v1.sql',
                 '20260924003000_add_farm_watch_admin_presentation_role_v1.sql']:
    setup += '\n' + (migrations / filename).read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_property_map_pins_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-colors-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_map_pin_colors_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pins.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-colors.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-icons-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_map_pin_icons_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-icons.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-symbol-pack-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_map_pin_symbol_pack_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-symbol-pack.sql').read_text()
setup += '\n' + (migrations / '20260920234800_add_farm_watch_operator_field_observations_v1.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-fixtures-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_fixture_map_pins_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-fixtures.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_fixture_map_pins_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-fixtures-replay.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-categories-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_map_pin_categories_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-categories.sql').read_text()
if not sys.argv[1:]:
    raise SystemExit(__doc__)
subprocess.run(sys.argv[1:], input=setup, text=True, check=True)
# Two independent sessions race the same revision against the actual row lock.
command = sys.argv[1:]
def query(sql):
    return subprocess.run(command + ['-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-c', sql],
                          text=True, capture_output=True)
# Exercise the actual migration body under failed preconditions; each scratch
# transaction rolls back, preserving the successfully migrated test records.
migration = next(migrations.glob('*_farm_watch_fixture_map_pins_v1.sql')).read_text()
backfill = migration[migration.index('do $$'):migration.index('\ncommit;')]
for label, preparation, code in [
    ('missing original icon account', 'delete from farm_watch.map_pin_icon_users_v1;', 'P0001'),
    ('ambiguous icon accounts', "insert into farm_watch.map_pin_icon_users_v1 values('00000000-0000-0000-0000-000000000005');", 'P0001'),
    ('unexpected source type', "update farm_watch.property_operator_observations_v1 set observation_kind='other' where observation_key='flat-creek-deer-feeder-01';", 'P0001'),
    ('outside boundary', "update farm_watch.property_operator_observations_v1 set geometry=extensions.st_setsrid(extensions.st_makepoint(5,5),4326) where property_id='10000000-0000-0000-0000-000000000003' and observation_key='flat-creek-deer-feeder-01';", '22023'),
]:
    checked = query('begin; delete from farm_watch.property_map_pin_fixture_links_v1; ' + preparation +
                    " select public.pin_test_expect_error($migration$" + backfill + "$migration$,'" + code + "'); rollback;")
    assert checked.returncode == 0, (label, checked.stderr)
print('PASS: migration fails closed for missing/ambiguous creator binding, unexpected source kinds and out-of-boundary geometry')
restored = query("update farm_watch.authorized_users set status='active'; select id from farm_watch.property_map_pins_v1 where title='Hole edge'")
if restored.returncode:
    raise RuntimeError(restored.stderr)
pin_id = restored.stdout.strip().splitlines()[-1]
def race(index):
    return query("""begin; set role authenticated;
      set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
      select public.farm_watch_map_pins_v1('one','update','%s',1,'Concurrent %s',null,1.5,1.5,p_category=>'%s');
      select pg_sleep(.3); commit;""" % (pin_id, index, "general" if index==1 else "hunting"))
with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(race, [1,2]))
assert sorted(result.returncode for result in results) == [0,1], [(r.returncode,r.stderr) for r in results]
assert any('pin changed; reload' in r.stderr for r in results)
assert query("select category = case title when 'Concurrent 1' then 'general' when 'Concurrent 2' then 'hunting' end from farm_watch.property_map_pins_v1 where id='"+pin_id+"'").stdout.strip()=='t'
print('PASS: concurrent independent sessions, exactly one winning revision/category')
filled = query("""insert into farm_watch.property_map_pins_v1(property_id,created_by,title,geometry)
  select '10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','Cap fixture',
    extensions.st_setsrid(extensions.st_makepoint(11,11),4326)
  from generate_series(1,499-(select count(*)::int from farm_watch.property_map_pins_v1
    where property_id='10000000-0000-0000-0000-000000000002'));""")
assert filled.returncode == 0, filled.stderr
def race_create(index):
    return query("""begin; set role authenticated;
      set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
      select public.farm_watch_map_pins_v1('two','create',p_title=>'Final cap %s',p_longitude=>11,p_latitude=>11);
      select pg_sleep(.3); commit;""" % index)
with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(race_create,[1,2]))
assert sorted(r.returncode for r in results)==[0,1], [(r.returncode,r.stderr) for r in results]
assert any('property pin limit reached' in r.stderr for r in results)
assert query("select count(*) from farm_watch.property_map_pins_v1 where property_id='10000000-0000-0000-0000-000000000002'").stdout.strip()=='500'
print('PASS: property cap remains 500 under concurrent creates')
