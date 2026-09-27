# Scout by Cadastory

Scout by Cadastory is an **evidence-driven data and systems project for opportunity discovery and operational planning**.

The project combines public and geospatial data, relational storage, APIs, evidence/provenance rules, authorization boundaries, and user-facing workflows. The initial operating context is commercial drone and exterior-service work; the repository also contains **Farm Watch**, a property-focused decision-support surface built around explicit scientific evidence and interpretation boundaries.

This is an independent project with **AI-assisted implementation directed and validated by the project owner**. The emphasis is on problem framing, requirements, architecture, source selection, evidence quality, testing, privacy/authorization, and whether the resulting system is operationally useful.

## What this repository demonstrates

- Translating operational questions into product and system requirements
- Designing relational and geospatial data models
- Integrating heterogeneous public-data sources and APIs
- Preserving source provenance, confidence, freshness, and interpretation limits
- Building protected application and model-facing interfaces
- Testing authorization, exposure, and evidence contracts
- Iteratively validating and debugging database, ingestion, backend, and presentation behavior

## Architecture at a glance

The repository includes:

- **PostgreSQL / PostGIS + Supabase** for relational and geospatial persistence
- **TypeScript / Deno Edge Functions** for protected application and tool interfaces
- **Python ingestion and processing scripts** for external datasets
- **GitHub Actions / CI** for repeatable validation and controlled data workflows
- **MCP-oriented tool and presentation contracts** for model-facing access
- Durable documentation and evidence ledgers for scientific and architectural decisions

The design deliberately separates **what the data supports** from stronger conclusions the system is not justified in making. Missing evidence is not treated as proof, and domain-specific interpretations are gated by documented evidence and transferability constraints.

## Repository structure

- `database/` — database-side implementation and supporting assets
- `docs/` — architecture, evidence, science, and implementation documentation
- `scripts/` — ingestion, processing, and operational utilities
- `supabase/` — Edge Functions and protected application/tool surfaces
- `.github/` — CI and controlled workflow definitions

## Farm Watch

Farm Watch extends the same evidence-first architecture into property and land-context analysis. Current work includes terrain, LiDAR-derived structure, environmental context, hydrology, managed features, and a registry-driven deer-science evaluator.

Its evidence ledgers are intentionally conservative: neutral physical measurements do not silently become claims about habitat quality, animal behavior, causation, or land-use outcomes. Biological relationships retain their population, season, movement-state, and transferability constraints.

## Included utility: OSM access snapshot loader

The repository includes a **one-shot / on-demand** loader for Scout's OpenStreetMap access snapshot. It is not scheduled by default.

It downloads the current Geofabrik state PBFs for the regions Scout has enabled, clips them to the server-supplied Louisville 100-mile pilot bounding box, filters access-relevant OSM objects with `osmium-tool`, and sends bounded JSON batches to Scout's service-role-only import RPCs.

### GitHub Actions

The relevant files are:

- `scripts/scout_osm_snapshot_loader.py`
- `.github/workflows/scout-osm-snapshot.yml`

The workflow expects two repository secrets:

- `SCOUT_SUPABASE_URL` — the Supabase project URL
- `SCOUT_SUPABASE_SERVICE_ROLE_KEY` — the project's service-role key

Then manually run **Scout OSM access snapshot** from the Actions tab.

Do not place the service-role key in source code, workflow YAML, logs, issues, or chat messages.

### Local run

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

The database intentionally refuses to perform the global target-link refresh until every enabled snapshot region is ready. Missing OSM features are never treated as proof that a physical access feature does not exist or that access is permitted.
