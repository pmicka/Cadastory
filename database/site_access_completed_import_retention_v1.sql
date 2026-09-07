-- Scout site-access completed-import retention v1
--
-- Per-import feature memberships are needed while an import is being
-- normalized/validated, but become redundant once the import reaches
-- status=complete and finalization_phase=complete. Durable canonical feature
-- rows, region membership, import counts and provenance remain elsewhere.

create or replace function decisioning.prune_completed_site_access_import_features_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, decisioning
as $$
begin
  if new.status='complete'
     and new.finalization_phase='complete'
     and (old.status is distinct from new.status or old.finalization_phase is distinct from new.finalization_phase) then
    delete from decisioning.site_access_snapshot_import_features f
    where f.import_id=new.id;
  end if;
  return null;
end;
$$;

revoke all on function decisioning.prune_completed_site_access_import_features_v1()
  from public,anon,authenticated;
grant execute on function decisioning.prune_completed_site_access_import_features_v1()
  to service_role;

drop trigger if exists prune_completed_site_access_import_features_v1
  on decisioning.site_access_snapshot_imports;

create constraint trigger prune_completed_site_access_import_features_v1
after update on decisioning.site_access_snapshot_imports
deferrable initially deferred
for each row
execute function decisioning.prune_completed_site_access_import_features_v1();

comment on function decisioning.prune_completed_site_access_import_features_v1() is
  'Purges per-import site-access staging memberships after an import is fully finalized. Canonical site_access_features and site_access_snapshot_feature_regions remain durable; import-level counts and provenance remain on site_access_snapshot_imports.';
