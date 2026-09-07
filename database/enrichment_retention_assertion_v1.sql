-- Scout enrichment retention regression guard v1

create or replace function decisioning.assert_enrichment_retention_v1()
returns void
language plpgsql
security definer
set search_path = pg_catalog, decisioning, ingest
as $$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from decisioning.building_attribute_observations o
  join ingest.sources s on s.id=o.source_id
  where s.slug in ('overture-buildings','openstreetmap-geofabrik-building-attributes')
    and not exists (
      select 1 from decisioning.building_attribute_matches m
      where m.observation_id=o.id
    );

  if v_count <> 0 then
    raise exception 'bulk building enrichment retention violation: % unmatched observations retained', v_count;
  end if;

  select count(*) into v_count
  from decisioning.site_access_snapshot_import_features f
  join decisioning.site_access_snapshot_imports i on i.id=f.import_id
  where i.status='complete' and i.finalization_phase='complete';

  if v_count <> 0 then
    raise exception 'site-access staging retention violation: % rows retained for completed imports', v_count;
  end if;
end;
$$;

revoke all on function decisioning.assert_enrichment_retention_v1()
  from public,anon,authenticated;
grant execute on function decisioning.assert_enrichment_retention_v1()
  to service_role;

comment on function decisioning.assert_enrichment_retention_v1() is
  'Regression guard: reproducible unmatched Overture/OSM building observations and completed site-access import staging rows must not remain durable.';
