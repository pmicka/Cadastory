#!/usr/bin/env python3
"""Bounded Scout responsible-party worker for public ArcGIS parcel-owner sources.

This worker exists because Schneider's public ArcGIS services reset connections from
Supabase Edge egress. It is an unattended developer-side enrichment worker, not an
MCP/runtime dependency. It claims only active `arcgis_point_owner` jobs through a
service-role RPC and completes them through Scout's existing responsible-party
completion contract.

Property owner != property manager != operator != buyer. The completion RPC and
existing database guards retain those role semantics and block person/household
promotion into buyer identity.
"""
from __future__ import annotations

import argparse
import json
import os
import time
from typing import Any
from urllib.parse import urlparse

import requests

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
BATCH_SIZE = max(1, min(int(os.getenv("SCOUT_RESPONSIBLE_PARTY_BATCH_SIZE", "8")), 20))
TIMEOUT = (12, 35)
USER_AGENT = "Scout-by-Cadastory/1.0 property-party-evidence"
ALLOWED_SOURCE_HOSTS = {"wfs.schneidercorp.com"}

API = requests.Session()
API.headers.update({
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "User-Agent": USER_AGENT,
})
HTTP = requests.Session()
HTTP.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})

# Public smoke-test points are current Scout opportunity locations already used in
# deployment diagnostics. Probe output never prints owner names or parcel IDs.
PROBES = (
    {
        "name": "Nelson",
        "url": "https://wfs.schneidercorp.com/arcgis/rest/services/NelsonCountyKY_WFS/MapServer/2/query",
        "lat": 37.8025405771944,
        "lon": -85.4681395946761,
        "owner_field": "OwnerName1",
        "parcel_field": "PARCEL_ID",
    },
    {
        "name": "Daviess",
        "url": "https://wfs.schneidercorp.com/arcgis/rest/services/DaviessCountyKY_WFS/MapServer/0/query",
        "lat": 37.7783894662794,
        "lon": -87.1413399456086,
        "owner_field": "Name",
        "parcel_field": "PARCEL_ID",
    },
)


def rpc(name: str, payload: dict[str, Any] | None = None) -> Any:
    if not SUPABASE_URL or not SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    response = API.post(
        f"{SUPABASE_URL}/rest/v1/rpc/{name}",
        json=payload or {},
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    return response.json()


def source_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("ArcGIS responsible-party source must use HTTPS")
    if parsed.hostname.lower() not in ALLOWED_SOURCE_HOSTS:
        raise ValueError(f"ArcGIS responsible-party host is not allowlisted: {parsed.hostname}")
    return value


def query_params(lat: float, lon: float, owner_field: str, parcel_field: str, sr: int) -> dict[str, str]:
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("invalid ArcGIS point coordinates")
    if not owner_field or not parcel_field:
        raise ValueError("owner and parcel fields are required")
    return {
        "where": "1=1",
        "geometry": f"{lon},{lat}",
        "geometryType": "esriGeometryPoint",
        "inSR": str(sr),
        "spatialRel": "esriSpatialRelIntersects",
        "outFields": f"{parcel_field},{owner_field}",
        "returnGeometry": "false",
        "f": "json",
    }


def fetch_arcgis(url: str, params: dict[str, str]) -> tuple[dict[str, Any], str]:
    source_url(url)
    last_error: Exception | None = None
    for attempt in range(2):
        try:
            response = HTTP.get(url, params=params, timeout=TIMEOUT, allow_redirects=True)
            if response.status_code in (429, 500, 502, 503, 504):
                raise requests.HTTPError(f"transient ArcGIS status {response.status_code}")
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict):
                raise ValueError("ArcGIS source returned non-object JSON")
            return payload, response.url
        except (requests.RequestException, ValueError) as exc:
            last_error = exc
            if attempt == 0:
                time.sleep(1.0)
    raise RuntimeError(f"ArcGIS request failed: {type(last_error).__name__}: {last_error}")


def interpret(payload: dict[str, Any], owner_field: str, parcel_field: str) -> dict[str, Any]:
    if payload.get("error"):
        error = payload.get("error") or {}
        raise RuntimeError(f"ArcGIS service error: {str(error.get('message') or 'unknown')[:250]}")
    features = payload.get("features")
    if not isinstance(features, list):
        raise RuntimeError("ArcGIS response missing features array")
    if len(features) == 0:
        return {"outcome": "no_evidence", "error": "public parcel point query returned no parcel"}
    if len(features) != 1:
        return {"outcome": "needs_review", "error": f"public parcel point query returned {len(features)} parcels"}
    attrs = features[0].get("attributes") if isinstance(features[0], dict) else None
    if not isinstance(attrs, dict):
        return {"outcome": "needs_review", "error": "public parcel feature missing attributes"}
    owner = str(attrs.get(owner_field) or "").strip()
    parcel = str(attrs.get(parcel_field) or "").strip()
    if not owner:
        return {"outcome": "no_evidence", "error": "public parcel point query returned no owner"}
    if not parcel:
        return {"outcome": "needs_review", "error": "public parcel point query returned no parcel identifier"}
    return {"outcome": "completed", "owner": owner, "parcel_id": parcel}


def complete(job: dict[str, Any], result: dict[str, Any], exact_url: str | None = None, worker_error: str | None = None) -> Any:
    attrs = job.get("profile_attributes") or {}
    lat = job.get("lookup_latitude")
    lon = job.get("lookup_longitude")
    evidence_attrs: dict[str, Any] = {}
    if result["outcome"] == "completed":
        evidence_attrs = {
            "provider_kind": "arcgis_point_owner",
            "lookup_key": job.get("lookup_key"),
            "parcel_match_method": "authoritative_arcgis_point_intersection",
            "lookup_latitude": lat,
            "lookup_longitude": lon,
            "query_sr": int(attrs.get("query_sr") or 4326),
            "owner_field": attrs.get("owner_field"),
            "parcel_id_field": attrs.get("parcel_id_field"),
            "public_detail_fields_only": True,
            "bulk_mirror": False,
            "source_media_retained": False,
            "buyer_authority_not_implied": True,
            "property_manager_not_implied": True,
            "operator_not_implied": True,
            "acquisition_transport": "github_actions",
        }
    return rpc("internal_complete_responsible_party_resolution_job_v1", {
        "p_job_id": job["id"],
        "p_outcome": result["outcome"],
        "p_party_name": result.get("owner"),
        "p_site_address": job.get("lookup_address"),
        "p_parcel_id": result.get("parcel_id"),
        "p_source_url": exact_url if result["outcome"] == "completed" else None,
        "p_source_authority": job.get("source_authority") if result["outcome"] == "completed" else None,
        "p_observed_on": None,
        "p_attributes": evidence_attrs,
        "p_error": worker_error or result.get("error"),
    })


def process(job: dict[str, Any]) -> dict[str, Any]:
    if job.get("provider_kind") != "arcgis_point_owner":
        result = {"outcome": "needs_review", "error": "remote worker received unsupported provider kind"}
        complete(job, result)
        return result
    attrs = job.get("profile_attributes") or {}
    owner_field = str(attrs.get("owner_field") or "")
    parcel_field = str(attrs.get("parcel_id_field") or "")
    sr = int(attrs.get("query_sr") or 4326)
    try:
        lat = float(job["lookup_latitude"])
        lon = float(job["lookup_longitude"])
        params = query_params(lat, lon, owner_field, parcel_field, sr)
        payload, exact_url = fetch_arcgis(str(job.get("owner_lookup_url_template") or ""), params)
        result = interpret(payload, owner_field, parcel_field)
        complete(job, result, exact_url=exact_url)
        return result
    except Exception as exc:
        message = f"{type(exc).__name__}: {exc}"[:1000]
        result = {"outcome": "failed", "error": message}
        complete(job, result, worker_error=message)
        return result


def self_test() -> None:
    params = query_params(37.8, -85.4, "Owner", "PARCEL_ID", 4326)
    assert params["geometryType"] == "esriGeometryPoint"
    assert params["returnGeometry"] == "false"
    assert interpret({"features": []}, "Owner", "PARCEL_ID")["outcome"] == "no_evidence"
    assert interpret({"features": [{"attributes": {"Owner": "Example LLC", "PARCEL_ID": "A1"}}]}, "Owner", "PARCEL_ID")["outcome"] == "completed"
    assert interpret({"features": [{"attributes": {"Owner": "A", "PARCEL_ID": "1"}}, {"attributes": {"Owner": "B", "PARCEL_ID": "2"}}]}, "Owner", "PARCEL_ID")["outcome"] == "needs_review"
    try:
        source_url("https://example.com/query")
    except ValueError:
        pass
    else:
        raise AssertionError("non-allowlisted ArcGIS host was accepted")
    print("responsible-party ArcGIS worker self-test passed", flush=True)


def probe() -> None:
    for item in PROBES:
        params = query_params(item["lat"], item["lon"], item["owner_field"], item["parcel_field"], 4326)
        payload, _ = fetch_arcgis(item["url"], params)
        result = interpret(payload, item["owner_field"], item["parcel_field"])
        if result["outcome"] != "completed":
            raise RuntimeError(f"{item['name']} ArcGIS probe did not resolve exactly one owner-bearing parcel: {result['outcome']}")
        print(f"{item['name']} ArcGIS probe passed: one owner-bearing parcel", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.probe:
        probe()
        return
    if not SUPABASE_URL or not SERVICE_KEY:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")

    jobs = rpc("internal_claim_remote_responsible_party_resolution_jobs_v1", {"p_limit": BATCH_SIZE})
    if not isinstance(jobs, list):
        raise RuntimeError("remote responsible-party claim RPC returned non-list payload")
    print(f"claimed={len(jobs)}", flush=True)
    outcomes: dict[str, int] = {}
    for job in jobs:
        result = process(job)
        outcome = str(result.get("outcome") or "unknown")
        outcomes[outcome] = outcomes.get(outcome, 0) + 1
        print(f"job={job.get('id')} profile={job.get('profile_key')} outcome={outcome}", flush=True)
    print(f"outcomes={json.dumps(outcomes, sort_keys=True)}", flush=True)


if __name__ == "__main__":
    main()
