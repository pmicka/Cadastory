-- Keep the cleanup job's region foreign key indexed.  The initial state index
-- was unused by the implemented control path, which addresses jobs by import.

drop index if exists decisioning.site_access_snapshot_cleanup_jobs_state_idx;

create index if not exists site_access_snapshot_cleanup_jobs_region_idx
  on decisioning.site_access_snapshot_cleanup_jobs(region_slug);
