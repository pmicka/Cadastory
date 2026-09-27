# Scout by Cadastory

**Evidence-driven geospatial data and systems work for opportunity discovery and operational planning.**

> Active development · independent project · AI-assisted implementation directed and validated by the project owner

Scout combines public and geospatial data, relational storage, APIs, evidence/provenance rules, authorization boundaries, and user-facing workflows. The initial operating context is commercial drone and exterior-service work; the repository also contains **Farm Watch**, a property-focused decision-support surface built around explicit scientific evidence and interpretation boundaries.

The project is less about producing a single model or dashboard than building a system that can answer operational questions without losing track of **where evidence came from, how fresh it is, what it actually supports, and who is allowed to see or act on it**.

## What this repository demonstrates

| Area | Examples |
| --- | --- |
| **Business / systems analysis** | Problem framing, requirements, workflows, acceptance criteria, implementation decisions |
| **Data architecture** | Relational + geospatial modeling, heterogeneous public-data integration, provenance and freshness |
| **Application architecture** | Protected APIs, Edge Functions, model-facing interfaces, authorization boundaries |
| **Quality / controls** | CI, contract checks, evidence ledgers, privacy/exposure rules, regression validation |
| **Product judgment** | Separating usable operational signals from unsupported conclusions; preserving uncertainty |

## Architecture at a glance

- **PostgreSQL / PostGIS + Supabase** — relational and geospatial persistence
- **TypeScript / Deno Edge Functions** — protected application and tool interfaces
- **Python** — ingestion and processing of external datasets
- **GitHub Actions / CI** — repeatable validation and controlled data workflows
- **MCP-oriented contracts** — model-facing tools and presentation surfaces
- **Evidence ledgers + architecture doctrine** — durable constraints around provenance, interpretation, privacy, and system evolution

The design deliberately separates **what the data supports** from stronger conclusions the system is not justified in making. Missing evidence is not treated as proof, and domain-specific interpretations are gated by documented evidence and transferability constraints.

## Repository map

```text
database/   database-side implementation and supporting assets
docs/       architecture, evidence, science, and implementation documentation
scripts/    ingestion, processing, and operational utilities
supabase/   Edge Functions and protected application/tool surfaces
.github/    CI and controlled workflow definitions
```

## Farm Watch

Farm Watch applies the same evidence-first architecture to property and land-context analysis. Current work includes terrain, LiDAR-derived structure, environmental context, hydrology, managed features, and a registry-driven deer-science evaluator.

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
