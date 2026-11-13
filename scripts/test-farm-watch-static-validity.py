#!/usr/bin/env python3
"""Run policy/migration tests in an EMPTY scratch Postgres database.

Usage: python scripts/test-farm-watch-static-validity.py psql <connection options>
Or: python scripts/test-farm-watch-static-validity.py docker exec -i <container> psql -U postgres
Refuses an existing farm_watch schema. No production data or provider calls.
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
migrations = root / 'supabase/migrations'


def function(filename, name):
    text = (migrations / filename).read_text()
    match = re.search(r'create or replace function farm_watch\.' + name + r'\(.*?\n\$\$;', text, re.S | re.I)
    if not match:
        raise RuntimeError('function not found: ' + name)
    return match[0]


base = '20260920110740_add_farm_watch_materializations_v1.sql'
property_inputs = '20260930030941_farm_watch_property_input_freshness_v1.sql'
manifest = '20260930002503_farm_watch_materialization_dependency_manifest_v1.sql'
external = '20260930002507_farm_watch_authoritative_external_source_identity_v1.sql'
fail_closed = '20260930025013_farm_watch_fail_closed_reader_semantics_v1.sql'
setup = '''
\\set ON_ERROR_STOP on
set client_min_messages=warning;
-- This MUST fail before anything else if pointed at an existing deployment.
create schema farm_watch;
create schema extensions;
create role anon;
create role authenticated;
create role service_role bypassrls;
create function extensions.gen_random_uuid() returns uuid language sql as
$$ select pg_catalog.gen_random_uuid() $$;
create table farm_watch.properties (
  id uuid primary key, slug text, status text,
  boundary_sha256 text, stated_acres numeric, boundary_srid integer
);
'''
setup += (migrations / base).read_text().split('insert into storage.buckets')[0]
setup += '\n' + function(property_inputs, 'farm_watch_property_input_mismatches_v1')
setup += '\n' + function(external, 'farm_watch_recorded_dependency_value_v1')
setup += '\n' + function(fail_closed, 'farm_watch_compare_materialization_dependency_v1')
setup += '\n' + function(manifest, 'farm_watch_materialization_dependency_mismatches_v1_internal')
setup += '\n' + function(property_inputs, 'farm_watch_get_current_materialization_ref_with_overrides_v1_internal')
# Controlled manifest fixture; all candidate/property/comparison logic above is
# the unchanged production SQL. Live provider resolution has its separate suite.
setup += (root / 'tests/farm-watch-static-validity-fixture.sql').read_text()
policy = (migrations / '20261113222551_farm_watch_static_product_validity_v1.sql').read_text()
assertions = (root / 'tests/farm-watch-static-validity.sql').read_text()
command = sys.argv[1:]
if not command:
    raise SystemExit(__doc__)
subprocess.run(command, input=setup + '\n' + policy + '\n' + assertions, text=True, check=True)
