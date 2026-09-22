#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import math
import os
import sys
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import numpy as np
import planetary_computer
import rasterio
import requests
from pystac import Item
from pystac_client import Client
from rasterio.features import geometry_mask
from rasterio.mask import geometry_window
from rasterio.warp import transform_geom
from rasterio.errors import WindowError

EDGE_URL = (
    "https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/"
    "farm-watch-field-phenology-worker"
)
OIDC_AUDIENCE = (
    "https://ufpkjaadmmpmeogzhrcq.supabase.co/farm-watch-materialization-worker"
)
STAC_URL = "https://planetarycomputer.microsoft.com/api/stac/v1/"
COLLECTIONS = {
    "hls2-l30": {
        "source_product": "HLSL30.v2.0",
        "blue": "B02",
        "red": "B04",
        "nir": "B05",
        "qa": "Fmask",
        "doi": "10.5067/HLS/HLSL30.002",
    },
    "hls2-s30": {
        "source_product": "HLSS30.v2.0",
        "blue": "B02",
        "red": "B04",
        "nir": "B8A",
        "qa": "Fmask",
        "doi": "10.5067/HLS/HLSS30.002",
    },
}

# HLS v2 QA bits 1-5: cloud, adjacent cloud/shadow, shadow, snow/ice, water.
HLS_EXCLUDED_QA_BITS = sum(1 << bit for bit in (1, 2, 3, 4, 5))
HLS_CLOUDLIKE_QA_BITS = sum(1 << bit for bit in (1, 2, 3))
HLS_HIGH_AEROSOL_CODE = 3

@dataclass
class Counters:
    target_fields: int = 0
    discovered_items: int = 0
    complete_asset_items: int = 0
    sampled_items: int = 0
    current_quality_fields: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--property", default="validation-property-01")
    parser.add_argument("--as-of-date", required=True)
    return parser.parse_args()


def stable_url(url: str) -> str:
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def sha256_json(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def package_versions() -> dict[str, str]:
    out: dict[str, str] = {}
    for name in ("numpy", "rasterio", "pystac-client", "planetary-computer", "requests"):
        try:
            out[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            out[name] = "unknown"
    return out


def github_oidc_token() -> str:
    request_url = os.getenv("ACTIONS_ID_TOKEN_REQUEST_URL", "")
    request_token = os.getenv("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "")
    if not request_url or not request_token:
        raise RuntimeError("GitHub Actions OIDC environment unavailable")
    response = requests.get(
        request_url,
        params={"audience": OIDC_AUDIENCE},
        headers={
            "Authorization": "Bearer " + request_token,
            "Accept": "application/json",
        },
        timeout=20,
    )
    response.raise_for_status()
    payload = response.json()
    token = payload.get("value")
    if not token:
        raise RuntimeError("GitHub OIDC token response was empty")
    return str(token)


def worker_request(body: dict[str, Any]) -> dict[str, Any]:
    response = requests.post(
        EDGE_URL,
        headers={
            "Authorization": "Bearer " + github_oidc_token(),
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        json=body,
        timeout=120,
    )
    payload = response.json() if response.content else {}
    if not response.ok:
        raise RuntimeError(
            str(payload.get("detail") or payload.get("error") or f"worker HTTP {response.status_code}")
        )
    return payload


def positions(value: Any, out: list[tuple[float, float]] | None = None) -> list[tuple[float, float]]:
    if out is None:
        out = []
    if not isinstance(value, list):
        return out
    if (
        len(value) >= 2
        and isinstance(value[0], (int, float))
        and isinstance(value[1], (int, float))
    ):
        out.append((float(value[0]), float(value[1])))
        return out
    for child in value:
        positions(child, out)
    return out


def targets_bbox(targets: list[dict[str, Any]]) -> list[float]:
    points: list[tuple[float, float]] = []
    for target in targets:
        geometry = target.get("field_geometry_geojson")
        points.extend(positions(geometry.get("coordinates") if isinstance(geometry, dict) else None))
    if not points:
        raise RuntimeError("field target geometries are unavailable")
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def item_datetime(item: Item) -> datetime:
    dt = item.datetime
    if dt is None:
        text = item.properties.get("datetime")
        if not text:
            raise RuntimeError(f"STAC item {item.id} has no datetime")
        dt = datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def required_assets(item: Item, spec: dict[str, str]) -> tuple[bool, list[str]]:
    required = [spec["blue"], spec["red"], spec["nir"], spec["qa"]]
    missing = [key for key in required if key not in item.assets or not item.assets[key].href]
    return (not missing, missing)


def scale_offset(dataset: rasterio.io.DatasetReader) -> tuple[float, float]:
    scale = float(dataset.scales[0]) if dataset.scales else 1.0
    offset = float(dataset.offsets[0]) if dataset.offsets else 0.0
    if scale == 1.0:
        tags = dataset.tags(1)
        raw = tags.get("scale_factor") or dataset.tags().get("scale_factor")
        if raw is not None:
            try:
                scale = float(raw)
            except ValueError:
                pass
    if scale == 1.0:
        # HLS v2 surface reflectance is stored as int16 with a 0.0001 scale.
        scale = 0.0001
    return scale, offset


def finite_mean(values: np.ndarray) -> float | None:
    if values.size == 0:
        return None
    value = float(np.mean(values))
    return value if math.isfinite(value) else None


def finite_median(values: np.ndarray) -> float | None:
    if values.size == 0:
        return None
    value = float(np.median(values))
    return value if math.isfinite(value) else None


def sample_field(
    target: dict[str, Any],
    item: Item,
    collection_id: str,
    spec: dict[str, str],
    as_of: date,
) -> dict[str, Any] | None:
    geometry = target.get("field_geometry_geojson")
    if not isinstance(geometry, dict):
        return None

    assets = {
        "blue": item.assets[spec["blue"]].href,
        "red": item.assets[spec["red"]].href,
        "nir": item.assets[spec["nir"]].href,
        "qa": item.assets[spec["qa"]].href,
    }

    with rasterio.Env(
        GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
        GDAL_HTTP_MULTIRANGE="YES",
        GDAL_HTTP_MERGE_CONSECUTIVE_RANGES="YES",
    ):
        with (
            rasterio.open(assets["blue"]) as blue_ds,
            rasterio.open(assets["red"]) as red_ds,
            rasterio.open(assets["nir"]) as nir_ds,
            rasterio.open(assets["qa"]) as qa_ds,
        ):
            if not (
                blue_ds.crs == red_ds.crs == nir_ds.crs == qa_ds.crs
                and blue_ds.transform == red_ds.transform == nir_ds.transform == qa_ds.transform
                and blue_ds.width == red_ds.width == nir_ds.width == qa_ds.width
                and blue_ds.height == red_ds.height == nir_ds.height == qa_ds.height
            ):
                raise RuntimeError(f"HLS assets are not co-registered for {item.id}")

            projected = transform_geom("EPSG:4326", red_ds.crs, geometry, precision=9)
            try:
                window = geometry_window(red_ds, [projected], pad_x=0, pad_y=0)
            except WindowError:
                return None

            blue_raw = blue_ds.read(1, window=window, masked=True)
            red_raw = red_ds.read(1, window=window, masked=True)
            nir_raw = nir_ds.read(1, window=window, masked=True)
            qa_raw = qa_ds.read(1, window=window, masked=True)

            inside = geometry_mask(
                [projected],
                out_shape=(int(window.height), int(window.width)),
                transform=red_ds.window_transform(window),
                invert=True,
                all_touched=False,
            )
            total = int(np.count_nonzero(inside))
            if total <= 0:
                return None

            common_mask = (
                inside
                & ~np.ma.getmaskarray(blue_raw)
                & ~np.ma.getmaskarray(red_raw)
                & ~np.ma.getmaskarray(nir_raw)
                & ~np.ma.getmaskarray(qa_raw)
            )

            qa = np.asarray(qa_raw.data, dtype=np.uint8)
            excluded = (qa & HLS_EXCLUDED_QA_BITS) != 0
            high_aerosol = ((qa >> 6) & 0b11) == HLS_HIGH_AEROSOL_CODE
            valid = common_mask & ~excluded & ~high_aerosol

            blue_scale, blue_offset = scale_offset(blue_ds)
            red_scale, red_offset = scale_offset(red_ds)
            nir_scale, nir_offset = scale_offset(nir_ds)
            blue = np.asarray(blue_raw.data, dtype=np.float64) * blue_scale + blue_offset
            red = np.asarray(red_raw.data, dtype=np.float64) * red_scale + red_offset
            nir = np.asarray(nir_raw.data, dtype=np.float64) * nir_scale + nir_offset

            spectral_finite = np.isfinite(blue) & np.isfinite(red) & np.isfinite(nir)
            valid &= spectral_finite
            valid_count = int(np.count_nonzero(valid))
            valid_fraction = valid_count / total

            ndvi_values = np.empty(0, dtype=np.float64)
            evi_values = np.empty(0, dtype=np.float64)
            nir_values = nir[valid]

            if valid_count:
                ndvi_den = nir + red
                ndvi_mask = valid & (np.abs(ndvi_den) > 1e-8)
                ndvi_values = (nir[ndvi_mask] - red[ndvi_mask]) / ndvi_den[ndvi_mask]

                evi_den = nir + 6.0 * red - 7.5 * blue + 1.0
                evi_mask = valid & (np.abs(evi_den) > 1e-8)
                evi_values = 2.5 * (nir[evi_mask] - red[evi_mask]) / evi_den[evi_mask]

            cloudlike = inside & ((qa & HLS_CLOUDLIKE_QA_BITS) != 0)
            snow = inside & ((qa & (1 << 4)) != 0)
            water = inside & ((qa & (1 << 5)) != 0)
            high_aerosol_inside = inside & high_aerosol
            observed_at = item_datetime(item)
            unsigned_assets = {key: stable_url(value) for key, value in assets.items()}
            source_fingerprint = {
                "distribution_provider": "Microsoft Planetary Computer",
                "source_authority": "NASA LP DAAC",
                "collection": collection_id,
                "source_product": spec["source_product"],
                "source_doi": spec["doi"],
                "item_id": item.id,
                "observed_at": observed_at.isoformat().replace("+00:00", "Z"),
                "assets": unsigned_assets,
            }
            stable_item_url = (
                f"{STAC_URL}collections/{collection_id}/items/{item.id}"
            )

            return {
                "field_id": str(target["field_id"]),
                "source_product": spec["source_product"],
                "source_granule_id": item.id,
                "observed_at": observed_at.isoformat().replace("+00:00", "Z"),
                "ndvi_mean": finite_mean(ndvi_values),
                "ndvi_median": finite_median(ndvi_values),
                "evi_mean": finite_mean(evi_values),
                "evi_median": finite_median(evi_values),
                "nir_mean": finite_mean(nir_values),
                "valid_pixel_count": valid_count,
                "total_pixel_count": total,
                "valid_fraction": valid_fraction,
                "cloud_fraction": float(np.count_nonzero(cloudlike)) / total,
                "qa_context": {
                    "schema": "hls-field-vegetation-observation-v1",
                    "method": "farm-watch-hls-field-sampler-v1",
                    "distribution_provider": "Microsoft Planetary Computer",
                    "source_authority": "NASA LP DAAC",
                    "stac_collection": collection_id,
                    "source_doi": spec["doi"],
                    "asset_keys": {
                        "blue": spec["blue"],
                        "red": spec["red"],
                        "nir": spec["nir"],
                        "qa": spec["qa"],
                    },
                    "geometry_pixel_rule": "pixel_center_inside_field",
                    "qa_filter": {
                        "excluded_bits": [1, 2, 3, 4, 5],
                        "high_aerosol_code_excluded": HLS_HIGH_AEROSOL_CODE,
                    },
                    "qa_counts": {
                        "cloud_or_adjacent_or_shadow": int(np.count_nonzero(cloudlike)),
                        "snow": int(np.count_nonzero(snow)),
                        "water": int(np.count_nonzero(water)),
                        "high_aerosol": int(np.count_nonzero(high_aerosol_inside)),
                    },
                    "reflectance_scale": {
                        "blue": blue_scale,
                        "red": red_scale,
                        "nir": nir_scale,
                    },
                    "index_formulas": {
                        "ndvi": "(nir-red)/(nir+red)",
                        "evi": "2.5*(nir-red)/(nir+6*red-7.5*blue+1)",
                    },
                    "source_identity_kind": "stable_collection_item_asset_fingerprint",
                    "freshness_days": (as_of - observed_at.date()).days,
                    "scoring_performed": False,
                    "behavioral_inference_performed": False,
                },
                "source_url": stable_item_url,
                "source_sha256": sha256_json(source_fingerprint),
                "retrieved_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }


def search_items(
    bbox: list[float],
    start: datetime,
    end: datetime,
) -> tuple[list[tuple[str, Item]], list[dict[str, Any]]]:
    catalog = Client.open(STAC_URL, modifier=planetary_computer.sign_inplace)
    complete: list[tuple[str, Item]] = []
    incomplete: list[dict[str, Any]] = []
    for collection_id, spec in COLLECTIONS.items():
        search = catalog.search(
            collections=[collection_id],
            bbox=bbox,
            datetime=f"{start.isoformat().replace('+00:00','Z')}/{end.isoformat().replace('+00:00','Z')}",
            max_items=100,
        )
        for item in search.items():
            ok, missing = required_assets(item, spec)
            if ok:
                complete.append((collection_id, item))
            else:
                incomplete.append({
                    "collection": collection_id,
                    "item_id": item.id,
                    "missing_assets": missing,
                })
    complete.sort(key=lambda row: (item_datetime(row[1]), row[0], row[1].id))
    return complete, incomplete


def status_for(
    counters: Counters,
    incomplete_count: int,
    download_error_count: int,
) -> str:
    if counters.current_quality_fields == counters.target_fields and counters.target_fields > 0:
        if incomplete_count == 0 and download_error_count == 0:
            return "available"
        return "partial"
    if counters.current_quality_fields > 0:
        return "partial"
    if counters.sampled_items == 0 and download_error_count > 0:
        return "download_error"
    if counters.discovered_items > 0 and counters.complete_asset_items == 0:
        return "catalog_incomplete"
    return "no_valid_observation"


def main() -> int:
    args = parse_args()
    as_of = date.fromisoformat(args.as_of_date)
    property_slug = args.property.strip().lower()
    counters = Counters()
    run_id: str | None = None
    incomplete: list[dict[str, Any]] = []
    download_errors: list[dict[str, Any]] = []
    observations: list[dict[str, Any]] = []

    try:
        claim = worker_request({
            "operation": "claim",
            "property": property_slug,
            "as_of_date": as_of.isoformat(),
        })
        run_id = str(claim["run_id"])
        targets = claim.get("targets") or []
        contract = claim.get("contract") or {}
        if not isinstance(targets, list):
            raise RuntimeError("HLS worker targets contract is invalid")

        counters.target_fields = len(targets)
        lookback_days = int(contract.get("lookback_days", 45))
        freshness_days = int(contract.get("freshness_days", 10))
        minimum_valid_fraction = float(contract.get("minimum_valid_fraction", 0.30))

        if not targets:
            result = worker_request({
                "operation": "complete",
                "property": property_slug,
                "as_of_date": as_of.isoformat(),
                "run_id": run_id,
                "status": "no_valid_observation",
                "target_fields": 0,
                "discovered_items": 0,
                "complete_asset_items": 0,
                "sampled_items": 0,
                "stored_observations": 0,
                "current_quality_fields": 0,
                "observations": [],
                "details": {
                    "reason": "no_field_targets",
                    "package_versions": package_versions(),
                },
                "scoring_performed": False,
                "behavioral_inference_performed": False,
            })
            print(json.dumps({"status": "no_valid_observation", "result": result}, indent=2))
            return 0

        bbox = targets_bbox(targets)
        start = datetime.combine(
            as_of - timedelta(days=lookback_days),
            time.min,
            tzinfo=timezone.utc,
        )
        end = datetime.combine(
            as_of + timedelta(days=1),
            time.min,
            tzinfo=timezone.utc,
        )

        try:
            items, incomplete = search_items(bbox, start, end)
        except Exception as error:
            worker_request({
                "operation": "fail",
                "property": property_slug,
                "as_of_date": as_of.isoformat(),
                "run_id": run_id,
                "status": "catalog_incomplete",
                "target_fields": counters.target_fields,
                "discovered_items": 0,
                "complete_asset_items": 0,
                "sampled_items": 0,
                "details": {
                    "failure_stage": "stac_search",
                    "error_type": type(error).__name__,
                    "package_versions": package_versions(),
                },
                "error": str(error),
            })
            raise

        counters.complete_asset_items = len(items)
        counters.discovered_items = len(items) + len(incomplete)
        quality_fields: set[str] = set()

        for collection_id, item in items:
            spec = COLLECTIONS[collection_id]
            item_rows: list[dict[str, Any]] = []
            try:
                for target in targets:
                    row = sample_field(target, item, collection_id, spec, as_of)
                    if row is None:
                        continue
                    item_rows.append(row)
                    observed_date = datetime.fromisoformat(
                        row["observed_at"].replace("Z", "+00:00")
                    ).date()
                    age_days = (as_of - observed_date).days
                    if (
                        0 <= age_days <= freshness_days
                        and float(row["valid_fraction"]) >= minimum_valid_fraction
                    ):
                        quality_fields.add(str(row["field_id"]))
                observations.extend(item_rows)
                if item_rows:
                    counters.sampled_items += 1
            except Exception as error:
                download_errors.append({
                    "collection": collection_id,
                    "item_id": item.id,
                    "error_type": type(error).__name__,
                    "error": str(error)[:500],
                })

        counters.current_quality_fields = len(quality_fields)
        status = status_for(counters, len(incomplete), len(download_errors))
        result = worker_request({
            "operation": "complete",
            "property": property_slug,
            "as_of_date": as_of.isoformat(),
            "run_id": run_id,
            "status": status,
            "target_fields": counters.target_fields,
            "discovered_items": counters.discovered_items,
            "complete_asset_items": counters.complete_asset_items,
            "sampled_items": counters.sampled_items,
            "stored_observations": len(observations),
            "current_quality_fields": counters.current_quality_fields,
            "observations": observations,
            "details": {
                "lookback_start": start.isoformat().replace("+00:00", "Z"),
                "lookback_end_exclusive": end.isoformat().replace("+00:00", "Z"),
                "bbox_wgs84": bbox,
                "incomplete_catalog_items": incomplete[:25],
                "incomplete_catalog_item_count": len(incomplete),
                "download_errors": download_errors[:25],
                "download_error_count": len(download_errors),
                "quality_field_ids": sorted(quality_fields),
                "package_versions": package_versions(),
                "distribution": {
                    "provider": "Microsoft Planetary Computer",
                    "stac_endpoint": STAC_URL,
                    "collections": sorted(COLLECTIONS),
                },
                "source_authority": "NASA LP DAAC",
                "raw_imagery_persisted": False,
                "scoring_performed": False,
                "behavioral_inference_performed": False,
            },
            "scoring_performed": False,
            "behavioral_inference_performed": False,
        })
        print(json.dumps({
            "status": status,
            "property": property_slug,
            "as_of_date": as_of.isoformat(),
            "target_fields": counters.target_fields,
            "discovered_items": counters.discovered_items,
            "complete_asset_items": counters.complete_asset_items,
            "sampled_items": counters.sampled_items,
            "observation_rows": len(observations),
            "current_quality_fields": counters.current_quality_fields,
            "incomplete_catalog_items": len(incomplete),
            "download_errors": len(download_errors),
            "result": result,
        }, indent=2))
        return 0
    except Exception as error:
        if run_id is not None:
            try:
                worker_request({
                    "operation": "fail",
                    "property": property_slug,
                    "as_of_date": as_of.isoformat(),
                    "run_id": run_id,
                    "status": "processing_error",
                    "target_fields": counters.target_fields,
                    "discovered_items": counters.discovered_items,
                    "complete_asset_items": counters.complete_asset_items,
                    "sampled_items": counters.sampled_items,
                    "details": {
                        "failure_stage": "materializer",
                        "error_type": type(error).__name__,
                        "incomplete_catalog_items": incomplete[:25],
                        "download_errors": download_errors[:25],
                        "package_versions": package_versions(),
                    },
                    "error": str(error),
                })
            except Exception as report_error:
                print(
                    f"Failed to report HLS materializer failure: {report_error}",
                    file=sys.stderr,
                )
        raise


if __name__ == "__main__":
    raise SystemExit(main())
