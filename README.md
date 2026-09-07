# Scout OSM access snapshot loader

This is a **one-shot / on-demand** loader for Scout by Cadastory. It is not
scheduled by default.

It downloads the current Geofabrik state PBFs for the regions Scout has
enabled, clips them to the server-supplied Louisville 100-mile pilot bounding
box, filters access-relevant OSM objects with `osmium-tool`, and sends bounded
JSON batches to Scout's service-role-only import RPCs.

## GitHub Actions

Copy:

- `scripts/scout_osm_snapshot_loader.py`
- `.github/workflows/scout-osm-snapshot.yml`

into a repository.

Add two GitHub Actions repository secrets:

- `SCOUT_SUPABASE_URL` — the Supabase project URL.
- `SCOUT_SUPABASE_SERVICE_ROLE_KEY` — the project's service-role key.

Then manually run **Scout OSM access snapshot** from the Actions tab.

Do not place the service-role key in source code, workflow YAML, logs, issues,
or chat messages.

## Local run

Install `osmium-tool` and `requests`, then export:

```bash
export SUPABASE_URL="https://<project-ref>.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<secret>"
python scripts/scout_osm_snapshot_loader.py
```

Optional subset:

```bash
SCOUT_OSM_REGIONS=kentucky python scripts/scout_osm_snapshot_loader.py
```

The database intentionally refuses to perform the global target-link refresh
until every enabled snapshot region is ready. Missing OSM features are never
treated as proof that a physical access feature does not exist or that access
is permitted.
