do $$
declare
 v_id uuid := '00000000-0000-0000-0000-000000000001';
 v_ref jsonb;
 v_kind text;
 v_column text;
 v_row farm_watch.property_materializations_v1%rowtype;
begin
 assert (select count(*)=12 from farm_watch.property_materializations_v1 where expires_at is null),
 'exactly the twelve stable kinds must lose calendar expiry';
 assert not exists (
  select 1 from farm_watch.property_materializations_v1 m join before_policy b using(id)
  where to_jsonb(m)-'expires_at' is distinct from b.immutable_content
 ), 'backfill changed scientific data, identities, provenance, or completion dates';
 assert not exists (
  select 1 from farm_watch.property_materializations_v1 m join before_policy b using(id)
  where not farm_watch.farm_watch_materialization_is_stable_v1(m.product_kind)
  and m.expires_at is distinct from b.expires_at
 ), 'temporal or unknown product expiry changed';

 for v_kind in select product_kind from farm_watch.property_materializations_v1 where expires_at is null loop
  v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(v_id,v_kind);
  assert v_ref->>'status'='available', 'unchanged stable product still stale: '||v_kind;
 end loop;
 for v_kind in select product_kind from farm_watch.property_materializations_v1 where expires_at is not null loop
  v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(v_id,v_kind);
  assert v_ref->>'status'='stale' and v_ref->'reason_codes' ? 'expired',
   'temporal/unknown expired product became current';
 end loop;

 -- Both update and insert by an older worker obey central policy.
 update farm_watch.property_materializations_v1 set expires_at=now()+interval '30 days'
 where product_kind='terrain-analysis';
 assert (select expires_at is null from farm_watch.property_materializations_v1 where product_kind='terrain-analysis'),
 'older worker update reintroduced expiry';
 select * into v_row from farm_watch.property_materializations_v1 where product_kind='terrain-analysis';
 v_row.id := gen_random_uuid();
 v_row.input_signature_sha256 := repeat('e',64);
 v_row.identity_sha256 := repeat('e',64);
 v_row.artifact_path := 'insert-test/fixture.json';
 v_row.expires_at := now()+interval '30 days';
 insert into farm_watch.property_materializations_v1 select (v_row).*;
 assert (select expires_at is null from farm_watch.property_materializations_v1 where id=v_row.id),
 'older worker insert reintroduced expiry';
 delete from farm_watch.property_materializations_v1 where id=v_row.id;

 -- Real production comparison and candidate code must continue rejecting drift/outages.
 v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(
  v_id,'terrain-analysis',current_date,now(),
  '{"source":{"key":"external:fixture","status":"available","identity_sha256":"corrected-source"}}'
 );
 assert v_ref->>'status'='stale' and v_ref->'reason_codes' ? 'source_identity_changed', 'source drift accepted';
 v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(
  v_id,'terrain-analysis',current_date,now(),
  '{"source":{"key":"external:fixture","status":"unavailable","reason":"provider_observation_failed"}}'
 );
 assert v_ref->>'status'='stale' and v_ref->'reason_codes' ? 'provider_observation_failed', 'outage accepted';
 update farm_watch.properties set boundary_sha256=repeat('f',64);
 v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(v_id,'terrain-analysis');
 assert v_ref->>'status'='stale' and v_ref->'reason_codes' ? 'property_boundary_changed', 'boundary drift accepted';
 update farm_watch.properties set boundary_sha256=repeat('a',64),stated_acres=41;
 v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(v_id,'terrain-analysis');
 assert v_ref->>'status'='stale' and v_ref->'reason_codes' ? 'property_stated_acres_changed', 'acreage drift accepted';
 update farm_watch.properties set stated_acres=40,boundary_srid=3857;
 v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(v_id,'terrain-analysis');
 assert v_ref->>'status'='stale' and v_ref->'reason_codes' ? 'property_boundary_srid_changed', 'SRID drift accepted';
 update farm_watch.properties set boundary_srid=4326;
 update farm_watch.property_materializations_v1 set algorithm_version='old' where product_kind='terrain-analysis';
 v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(v_id,'terrain-analysis');
 assert v_ref->>'status'='stale' and v_ref->'reason_codes' ? 'contract_version_mismatch', 'model drift accepted';
 update farm_watch.property_materializations_v1 set algorithm_version='v1',output_schema_version='old' where product_kind='terrain-analysis';
 v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(v_id,'terrain-analysis');
 assert v_ref->>'status'='stale' and v_ref->'reason_codes' ? 'contract_version_mismatch', 'schema drift accepted';
 update farm_watch.properties set status='inactive';
 v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(v_id,'terrain-analysis');
 assert v_ref->>'status'='unavailable', 'inactive property accepted';
 assert not farm_watch.farm_watch_materialization_is_stable_v1(null), 'null product accepted';
 assert not has_function_privilege('anon','farm_watch.farm_watch_materialization_is_stable_v1(text)','execute'),
 'new helper exposed to anon';
 assert not has_function_privilege('authenticated','farm_watch.farm_watch_normalize_materialization_expiry_v1()','execute'),
 'new trigger exposed to authenticated';
 assert not has_table_privilege('authenticated','farm_watch.property_materializations_v1','select'),
 'private materializations exposed';
end $$;

-- Match the deployed schema usage grant and exercise the invoker trigger under
-- the actual writer role, including its nested policy-helper permissions.
grant usage on schema farm_watch to service_role;
set role service_role;
do $$
declare v_updated integer;
begin
 update farm_watch.property_materializations_v1 set expires_at=now()+interval '30 days'
 where product_kind='lidar-source-coverage';
 get diagnostics v_updated = row_count;
 assert v_updated=1, 'service-role test did not exercise a real worker write';
end $$;
reset role;
do $$ begin
 assert (select expires_at is null from farm_watch.property_materializations_v1 where product_kind='lidar-source-coverage'),
 'service-role worker reintroduced expiry';
end $$;
select 'Farm Watch static validity migration and canonical reader checks passed' as result;
