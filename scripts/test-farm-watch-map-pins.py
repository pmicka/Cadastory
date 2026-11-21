#!/usr/bin/env python3
"""Test the real pin migration + existing allowlist/role SQL in an EMPTY PostGIS DB.

Usage: python scripts/test-farm-watch-map-pins.py docker exec -i <container> psql -U postgres
Refuses an existing farm_watch schema. JWT claims are supplied as PostgREST does;
only the Auth/Storage catalog bootstraps are synthetic. Never run against a deployment.
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
setup += '\n' + (root / 'tests/farm-watch-map-pin-camera-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_map_pin_camera_view_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-camera.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-pin-photos-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_pin_photos_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-pin-photos.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-private-pins-fixture.sql').read_text()
# Exercise rollback after the map RPC/column changes but before photo privacy.
# With an accidental intermediate COMMIT, these assertions fail on the leaked DDL.
privacy_migration = next(migrations.glob('*_farm_watch_private_map_pins_v1.sql')).read_text()
fault = privacy_migration.replace('create or replace function public.farm_watch_pin_photos_v1',
    "do $$ begin raise exception 'injected photo RPC deployment failure'; end $$;\n"
    'create or replace function public.farm_watch_pin_photos_v1', 1)
assert fault != privacy_migration
setup += '\n\\set ON_ERROR_STOP off\n' + fault + r'''
\set ON_ERROR_STOP on
do $$ begin
 assert not exists(select 1 from information_schema.columns where table_schema='farm_watch' and table_name='property_map_pins_v1' and column_name='is_private'),'failed migration must roll back privacy column';
 assert to_regprocedure('public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer)') is not null,'old map RPC survives failed migration';
 assert to_regprocedure('public.farm_watch_map_pins_v1(text,text,uuid,integer,text,text,double precision,double precision,text,text,text,integer,double precision,integer,boolean)') is null,'new map RPC must roll back';
 assert pg_get_functiondef('public.farm_watch_pin_photos_v1(text,uuid,text,uuid,integer)'::regprocedure)=(select definition from privacy_photo_rpc_before),'photo RPC survives failed migration';
 assert not exists(select 1 from privacy_pins_before b full join farm_watch.property_map_pins_v1 p using(id) where b.original is distinct from to_jsonb(p)),'failed migration leaves all pins unchanged';
end $$;
\echo PASS: injected photo RPC failure rolls back the entire privacy migration
'''
setup += '\n' + privacy_migration
setup += '\n' + (root / 'tests/farm-watch-private-pins.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-boundary-buffer-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_map_pin_boundary_buffer_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-boundary-buffer.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-dot-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_map_pin_dot_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-dot.sql').read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-botanical-fixture.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_map_pin_botanical_symbols_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-map-pin-botanical.sql').read_text()
# WMW homepage gallery catalog is isolated from map pins and uses the same
# real authorization/RLS test fixture. No website assets or hosted DB are used.
setup += '\n' + next(migrations.glob('*_farm_watch_home_gallery_catalog_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-home-gallery.sql').read_text()
# Unpublished managed gallery uploads use the existing real auth and Storage fixtures.
setup += '\n' + next(migrations.glob('*_farm_watch_home_gallery_uploads_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-home-gallery-uploads.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_home_gallery_direct_publish_v2.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-home-gallery-direct-publish.sql').read_text()
# Owner-only WMW user management uses real Auth catalog timestamps in Postgres.
setup += r'''
alter table auth.users add column created_at timestamptz not null default now();
alter table auth.users add column last_sign_in_at timestamptz;
insert into farm_watch.properties(slug,display_name) values ('validation-property-01','WMW Farm') on conflict (slug) do nothing;
'''
setup += '\n' + next(migrations.glob('*_farm_watch_people_access_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-people-access.sql').read_text()
setup += '\n' + next(migrations.glob('*_farm_watch_access_last_sign_in_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-access-last-sign-in.sql').read_text()
# Apply the framing migration after the privacy-aware pin-photo RPC migration.
# Preserve the legacy photo tests at their original migration boundary.
setup += '\n' + next(migrations.glob('*_farm_watch_pin_photo_framing_v1.sql')).read_text()
setup += '\n' + (root / 'tests/farm-watch-pin-photo-framing.sql').read_text()
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
# Camera geometry settings must win atomically with the same optimistic revision.
created_camera = query("""set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
 select public.farm_watch_map_pins_v1('one','create',p_title=>'Camera race',p_longitude=>0,p_latitude=>1,p_icon=>'trail_camera',p_camera_bearing_deg=>0)->'pin'->>'id';""")
assert created_camera.returncode == 0, created_camera.stderr
camera_id = created_camera.stdout.strip().splitlines()[-1]
def race_camera(index):
    return query("""begin; set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000002"}';
      select public.farm_watch_map_pins_v1('one','update','%s',1,'Camera race %s',null,0,1,p_camera_bearing_deg=>%s,p_camera_range_m=>%s,p_camera_fov_deg=>%s);
      select pg_sleep(.3); commit;""" % (camera_id,index,index*90,index*10,index*20))
with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(race_camera,[1,2]))
assert sorted(r.returncode for r in results)==[0,1], [(r.returncode,r.stderr) for r in results]
assert any('pin changed; reload' in r.stderr for r in results)
assert query("select revision=2 and ((camera_bearing_deg,camera_range_m,camera_fov_deg)=(90,10,20) or (camera_bearing_deg,camera_range_m,camera_fov_deg)=(180,20,40)) from farm_watch.property_map_pins_v1 where id='"+camera_id+"'").stdout.strip()=='t'
print('PASS: concurrent camera bearing/range/FOV writes have exactly one atomic winning revision')
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

# Independently raced uploads must not exceed four or lose an edit revision.
created_photo_pin=query("""set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
 select public.farm_watch_map_pins_v1('one','create',p_title=>'Photo race',p_longitude=>0,p_latitude=>1)->'pin'->>'id';""")
assert created_photo_pin.returncode==0,created_photo_pin.stderr
photo_pin_id=created_photo_pin.stdout.strip().splitlines()[-1]
import uuid
photo_ids=[str(uuid.uuid4()) for _ in range(5)]
for index,photo in enumerate(photo_ids):
 seeded=query("select public.pin_test_seed_photo_v1('"+photo_pin_id+"','"+photo+"')")
 assert seeded.returncode==0,seeded.stderr
 if index<3:
  attached=query("""set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
   select public.farm_watch_pin_photos_v1('one','%s','attach','%s',%s);"""%(photo_pin_id,photo,index+1))
  assert attached.returncode==0,attached.stderr
def race_photo(photo):
 return query("""begin;set role authenticated;set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
 select public.farm_watch_pin_photos_v1('one','%s','attach','%s',4); select pg_sleep(.3);commit;"""%(photo_pin_id,photo))
with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(race_photo,photo_ids[3:]))
assert sorted(r.returncode for r in results)==[0,1],[(r.returncode,r.stderr) for r in results]
assert query("select count(*) from farm_watch.map_pin_photos_v1 where pin_id='"+photo_pin_id+"'").stdout.strip()=='4'
assert query("select revision from farm_watch.property_map_pins_v1 where id='"+photo_pin_id+"'").stdout.strip()=='5'
print('PASS: concurrent photo attaches serialize at four photos with one winning revision')

# Privacy and a legacy edit contend for the same revision: no silent overwrite.
private_created=query("""set role authenticated;set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
 select public.farm_watch_map_pins_v1('one','create',p_title=>'Privacy race',p_longitude=>0,p_latitude=>1)->'pin'->>'id';""")
assert private_created.returncode==0,private_created.stderr
private_id=private_created.stdout.strip().splitlines()[-1]
def race_privacy(index):
 return query("""begin;set role authenticated;set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001"}';
 select public.farm_watch_map_pins_v1('one','update','%s',1,'Privacy race %s',null,0,1%s);select pg_sleep(.3);commit;"""%(private_id,index,',p_is_private=>true' if index==1 else ''))
with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(race_privacy,[1,2]))
assert sorted(r.returncode for r in results)==[0,1],[(r.returncode,r.stderr) for r in results]
assert any('pin changed; reload' in r.stderr for r in results)
assert query("select revision=2 and ((title='Privacy race 1' and is_private) or (title='Privacy race 2' and not is_private)) from farm_watch.property_map_pins_v1 where id='"+private_id+"'").stdout.strip()=='t'
print('PASS: concurrent privacy and legacy edits share one atomic revision winner')
