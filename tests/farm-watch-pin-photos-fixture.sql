reset role;
-- Minimal Storage catalog only; the SQL/RLS and pin authorization are real.
-- Object bytes and actual WASM conversion are tested separately by Edge tests.
create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,metadata jsonb,user_metadata jsonb,created_at timestamptz default now(),unique(bucket_id,name));
alter table storage.objects enable row level security;
alter table storage.objects force row level security;
grant usage on schema storage to anon,authenticated,service_role;
grant all on storage.objects to anon,authenticated,service_role;
-- Prove a future permissive policy cannot expose the dedicated private bucket.
create policy broad_test_policy on storage.objects for all to anon,authenticated using(true) with check(true);
create temp table photos_pins_before as select id,to_jsonb(p) original from farm_watch.property_map_pins_v1 p;
create temp table photos_guard_before as select pg_get_functiondef('farm_watch.guard_map_pin_v1()'::regprocedure) definition;
create temp table photos_grants_before as select * from farm_watch.map_pin_icon_users_v1;
