#!/usr/bin/env python3
"""
Load Overture building height, floor-count and facade-material evidence into Scout.

Requirements:
  - duckdb CLI >= 1.1 on PATH
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE_KEY

Optional:
  - SCOUT_OVERTURE_RELEASE=2026-08-19.0
  - SCOUT_OVERTURE_REGIONS=kentucky,indiana,ohio
  - SCOUT_OVERTURE_BATCH_SIZE=500

The loader queries Overture cloud GeoParquet only within Scout's current
canonical-building coverage extents and transfers buildings/building parts with
useful vertical or facade attributes. States without a canonical building
substrate are skipped automatically. Identical AOIs are queried only once. It
does not overwrite canonical building records; the service-role RPC stores
provenance-aware observations and conservative spatial matches instead.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
RELEASE = os.getenv("SCOUT_OVERTURE_RELEASE", "2026-08-19.0").strip()
REGION_FILTER = {
    value.strip().lower()
    for value in os.getenv("SCOUT_OVERTURE_REGIONS", "").split(",")
    if value.strip()
}
BATCH_SIZE = int(os.getenv("SCOUT_OVERTURE_BATCH_SIZE", "500"))
TIMEOUT = (30, 300)
MAX_RPC_ATTEMPTS = 8
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}

if not 1 <= BATCH_SIZE <= 1000:
    raise SystemExit("SCOUT_OVERTURE_BATCH_SIZE must be between 1 and 1000")

SUPABASE_SESSION = requests.Session()
SUPABASE_SESSION.headers.update(
    {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Scout-Cadastory-Overture-Building-Attributes/1.2",
    }
)


def _retry_delay(attempt: int, response: requests.Response | None = None) -> float:
    if response is not None:
        retry_after = response.headers.get("Retry-After")
        if retry_after:
            try:
                return min(60.0, max(1.0, float(retry_after)))
            except ValueError:
                pass
    return float(min(30, 2 ** attempt))


def rpc(name: str, payload: dict | None = None):
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    last_error: Exception | None = None
    for attempt in range(1, MAX_RPC_ATTEMPTS + 1):
        response = None
        try:
            response = SUPABASE_SESSION.post(
                url,
                json=payload or {},
                timeout=TIMEOUT,
            )
            if response.ok:
                return response.json()
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(
                    f"RPC {name} failed: HTTP {response.status_code}: {response.text[:1200]}"
                )
            last_error = RuntimeError(
                f"RPC {name} transient HTTP {response.status_code}: {response.text[:300]}"
            )
        except requests.RequestException as exc:
            last_error = exc

        if attempt >= MAX_RPC_ATTEMPTS:
            break
        delay = _retry_delay(attempt, response)
        print(
            f"RPC {name} transient failure; retry {attempt}/{MAX_RPC_ATTEMPTS - 1} "
            f"in {delay:.0f}s: {last_error}",
            flush=True,
        )
        time.sleep(delay)

    raise RuntimeError(
        f"RPC {name} failed after {MAX_RPC_ATTEMPTS} attempts: {last_error}"
    ) from last_error


def run(*args: str) -> str:
    process = subprocess.run(args, check=True, text=True, capture_output=True)
    if process.stderr.strip():
        print(process.stderr.strip())
    return process.stdout.strip()


def require_duckdb() -> None:
    try:
        version = run("duckdb", "--version")
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise SystemExit("duckdb CLI is required on PATH") from exc
    print(version, flush=True)


def release_timestamp() -> str:
    release_date = RELEASE.split(".", 1)[0]
    parsed = datetime.strptime(release_date, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    return parsed.isoformat()


def sql_string(value: str) -> str:
    return value.replace("'", "''")


def deduplicated_aois(regions: list[dict]) -> list[dict]:
    grouped: dict[tuple[float, float, float, float], set[str]] = {}
    for region in regions:
        bbox = tuple(float(v) for v in region["bbox"])
        grouped.setdefault(bbox, set()).add(str(region["region_slug"]))
    return [
        {
            "bbox": list(bbox),
            "region_slugs": sorted(slugs),
            "aoi_slug": "+".join(sorted(slugs)),
        }
        for bbox, slugs in grouped.items()
    ]


def export_aoi_kind(aoi: dict, feature_kind: str, destination: Path) -> None:
    minx, miny, maxx, maxy = [float(value) for value in aoi["bbox"]]
    parquet = (
        "s3://overturemaps-us-west-2/release/"
        f"{RELEASE}/theme=buildings/type={feature_kind}/*"
    )

    if feature_kind == "building":
        select_fields = """
          id::varchar AS id,
          height,
          num_floors,
          facade_material::varchar AS facade_material,
          has_parts,
          geometry
        """
        useful_filter = (
            "height IS NOT NULL OR num_floors IS NOT NULL OR "
            "facade_material IS NOT NULL OR has_parts = true"
        )
    else:
        select_fields = """
          id::varchar AS id,
          building_id::varchar AS building_id,
          height,
          num_floors,
          facade_material::varchar AS facade_material,
          false AS has_parts,
          geometry
        """
        useful_filter = (
            "height IS NOT NULL OR num_floors IS NOT NULL OR facade_material IS NOT NULL"
        )

    sql = f"""
INSTALL spatial;
INSTALL httpfs;
LOAD spatial;
LOAD httpfs;
SET s3_region='us-west-2';
SET geometry_always_xy=true;
COPY (
  SELECT {select_fields}
  FROM read_parquet('{sql_string(parquet)}', filename=true, hive_partitioning=1)
  WHERE bbox.xmax >= {minx}
    AND bbox.xmin <= {maxx}
    AND bbox.ymax >= {miny}
    AND bbox.ymin <= {maxy}
    AND ({useful_filter})
) TO '{sql_string(str(destination))}'
WITH (FORMAT GDAL, DRIVER 'GeoJSONSeq', SRS 'EPSG:4326');
"""
    print(
        f"Overture AOI {aoi['aoi_slug']} {feature_kind}: querying release {RELEASE}",
        flush=True,
    )
    subprocess.run(["duckdb", "-c", sql], check=True)


def normalize_material(raw: object) -> str | None:
    if raw is None:
        return None
    value = str(raw).strip().lower()
    allowed = {
        "brick", "cement_block", "clay", "concrete", "glass", "metal",
        "plaster", "plastic", "stone", "timber_framing", "wood",
    }
    return value if value in allowed else None


def iter_payload(path: Path, feature_kind: str, aoi: dict):
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            raw_line = raw_line.strip().lstrip("\x1e")
            if not raw_line:
                continue
            feature = json.loads(raw_line)
            geometry = feature.get("geometry")
            props = feature.get("properties") or {}
            source_native_id = props.get("id")
            if not geometry or source_native_id is None:
                continue

            height = props.get("height")
            stories = props.get("num_floors")
            raw_material = props.get("facade_material")
            material = normalize_material(raw_material)
            has_parts = props.get("has_parts")

            if height is None and stories is None and material is None and not has_parts:
                continue

            yield {
                "source_native_id": str(source_native_id),
                "feature_kind": feature_kind,
                "geometry": geometry,
                "height_m": height,
                "height_status": "source_reported" if height is not None else "unknown",
                "story_count": stories,
                "story_status": "source_reported" if stories is not None else "unknown",
                "facade_material": material,
                "raw_facade_material": str(raw_material) if raw_material is not None else None,
                "facade_material_status": "source_reported" if material else "unknown",
                "glazing_signal": "glass_facade_present" if material == "glass" else None,
                "has_parts": bool(has_parts) if has_parts is not None else None,
                "confidence": 0.90,
                "attributes": {
                    "overture_release": RELEASE,
                    "aoi_slug": aoi["aoi_slug"],
                    "region_slugs": aoi["region_slugs"],
                    "parent_building_id": props.get("building_id"),
                },
            }


def upload_features(features, source_timestamp: str) -> tuple[int, int, int, int]:
    submitted = matched = unmatched = invalid = 0
    batch: list[dict] = []

    def flush(items: list[dict]) -> None:
        nonlocal submitted, matched, unmatched, invalid
        if not items:
            return
        result = rpc(
            "internal_ingest_building_attribute_batch",
            {
                "p_source_slug": "overture-buildings",
                "p_features": items,
                "p_source_timestamp": source_timestamp,
            },
        )
        submitted += len(items)
        matched += int(result.get("matched", 0))
        unmatched += int(result.get("unmatched", 0))
        invalid += int(result.get("invalid", 0))
        print(
            f"submitted={submitted:,} matched={matched:,} "
            f"unmatched={unmatched:,} invalid={invalid:,}",
            flush=True,
        )

    for feature in features:
        batch.append(feature)
        if len(batch) >= BATCH_SIZE:
            flush(batch)
            batch = []
    flush(batch)
    return submitted, matched, unmatched, invalid


def main() -> None:
    require_duckdb()
    config = rpc("internal_get_building_attribute_loader_config")
    regions = config["regions"]
    if REGION_FILTER:
        regions = [r for r in regions if r["region_slug"] in REGION_FILTER]
    if not regions:
        raise SystemExit("No canonical Scout building regions matched SCOUT_OVERTURE_REGIONS")

    aois = deduplicated_aois(regions)
    print(
        f"Scout configured {len(regions)} canonical region rows -> {len(aois)} unique Overture AOI(s)",
        flush=True,
    )
    source_ts = release_timestamp()
    totals = [0, 0, 0, 0]

    with tempfile.TemporaryDirectory(prefix="scout-overture-buildings-") as temp_dir:
        work = Path(temp_dir)
        for aoi_index, aoi in enumerate(aois, start=1):
            for feature_kind in ("building", "building_part"):
                output = work / f"aoi-{aoi_index}-{feature_kind}.geojsonseq"
                export_aoi_kind(aoi, feature_kind, output)
                if not output.exists() or output.stat().st_size == 0:
                    continue
                result = upload_features(
                    iter_payload(output, feature_kind, aoi),
                    source_ts,
                )
                totals = [a + b for a, b in zip(totals, result)]

    print(
        "Overture building enrichment complete: "
        f"submitted={totals[0]:,} matched={totals[1]:,} "
        f"unmatched={totals[2]:,} invalid={totals[3]:,}",
        flush=True,
    )


if __name__ == "__main__":
    main()
