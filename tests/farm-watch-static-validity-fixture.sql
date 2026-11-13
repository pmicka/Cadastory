-- Controlled provider/manifest fixture for testing the unchanged real reader.
create function farm_watch.farm_watch_materialization_dependency_contract_v1(text)
returns jsonb language sql as $$
  select '{"algorithm_version":"v1","output_schema_version":"v1","dependencies":[{"key":"external:fixture","kind":"external","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"provenance","path":["fixture_source_identity"]},"reason":"source_identity_changed"}]}]}'::jsonb
$$;
create function farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(
  p_property_id uuid, p_product_kind text, p_as_of_date date, p_as_of_at timestamptz,
  p_dependency_overrides jsonb default '{}', p_depth integer default 0
) returns jsonb language sql as $$
  select jsonb_build_object(
    'schema','fixture-manifest', 'property_input_state', to_jsonb(p) || '{"status":"available"}'::jsonb,
    'dependencies', jsonb_build_array(coalesce(p_dependency_overrides->'source',
      '{"key":"external:fixture","status":"available","identity_sha256":"verified-fixture-identity"}'::jsonb))
  ) from farm_watch.properties p where p.id=p_property_id
$$;
insert into farm_watch.properties values (
  '00000000-0000-0000-0000-000000000001','fixture','active',repeat('a',64),40,4326
);
insert into farm_watch.property_materializations_v1 (
 property_id,product_kind,algorithm_version,output_schema_version,
 boundary_sha256,source_signature_sha256,input_signature_sha256,identity_sha256,
 evidence_class,source_provenance,artifact_bucket,artifact_path,artifact_format,
 artifact_mime_type,artifact_size_bytes,artifact_sha256,completed_at,expires_at
)
select '00000000-0000-0000-0000-000000000001',kind,'v1','v1',
 repeat('a',64),repeat('b',64),md5(kind)||md5(kind),md5('identity:'||kind)||md5('identity:'||kind),
 'deterministic_derived','{"fixture_source_identity":"verified-fixture-identity"}',
 'farm-watch-derived',kind||'/fixture.json','json','application/json',10,repeat('d',64),
 now()-interval '1 year',now()-interval '11 months'
from unnest(array[
 'terrain-analysis','lidar-source-coverage','lidar-physical-structure',
 'leaf-off-woody-structure','structure-complementarity','landscape-structure-context',
 'study-aligned-vegetation-height-context','terrain-form-permeability',
 'spatial-edge-patch-context','solar-terrain-context','horizontal-visibility-context',
 'mast-capacity','solar-exposure-context','thermal-exposure-context','unknown-product'
]) kind;
insert into farm_watch.property_materialization_builds_v1 (
 property_id,product_kind,algorithm_version,output_schema_version,boundary_sha256,
 source_signature,source_signature_sha256,deterministic_inputs,input_signature_sha256,
 materialization_id
) select property_id,product_kind,algorithm_version,output_schema_version,boundary_sha256,
 'fixture',source_signature_sha256,'{"stated_acres":40,"boundary_srid":4326}',input_signature_sha256,id
from farm_watch.property_materializations_v1;
create temporary table before_policy as
 select id,to_jsonb(m)-'expires_at' as immutable_content,expires_at
 from farm_watch.property_materializations_v1 m;
do $$ begin
 assert farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(
 '00000000-0000-0000-0000-000000000001','terrain-analysis')->>'status'='stale',
 'baseline must reproduce calendar-only staleness';
end $$;
