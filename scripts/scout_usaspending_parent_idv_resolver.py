#!/usr/bin/env python3
"""Resolve qualified Scout parent IDVs to USAspending generated award IDs.

Uses the public advanced award-search endpoint with an exact quoted PIID across all IDV
award-type codes. Every candidate is then verified through the award-detail endpoint before
Scout's target snapshot is updated. No guessed agency suffix is persisted by this resolver.
"""
from __future__ import annotations

import json
import os
import time
from typing import Any
from urllib.parse import quote

import requests

API_ROOT = "https://api.usaspending.gov/api/v2"
SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
TIMEOUT = (30, 120)
MAX_ATTEMPTS = 5
TRANSIENT_HTTP = {408,425,429,500,502,503,504,520,521,522,523,524}
IDV_CODES = ["IDV_A","IDV_B","IDV_B_A","IDV_B_B","IDV_B_C","IDV_C","IDV_D","IDV_E"]

api = requests.Session()
api.headers.update({"Accept":"application/json","Content-Type":"application/json","User-Agent":"Scout-Cadastory-USAspending-IDV-Resolver/1.0"})
supa = requests.Session()
supa.headers.update({"apikey":SERVICE_KEY,"Authorization":f"Bearer {SERVICE_KEY}","Content-Type":"application/json","User-Agent":"Scout-Cadastory-USAspending-IDV-Resolver/1.0"})


def _request(session: requests.Session, method: str, url: str, payload: dict[str,Any] | None=None) -> requests.Response:
    last: Exception | None = None
    for attempt in range(1,MAX_ATTEMPTS+1):
        try:
            r = session.request(method,url,json=payload,timeout=TIMEOUT)
            if r.ok or r.status_code not in TRANSIENT_HTTP:
                return r
            last = RuntimeError(f"HTTP {r.status_code}: {r.text[:400]}")
        except requests.RequestException as exc:
            last = exc
        if attempt < MAX_ATTEMPTS:
            time.sleep(min(20,2**(attempt-1)))
    raise RuntimeError(f"request failed after {MAX_ATTEMPTS} attempts: {url}: {last}")


def rpc(name: str, payload: dict[str,Any] | None=None) -> Any:
    r = _request(supa,"POST",f"{SUPABASE_URL}/rest/v1/rpc/{name}",payload or {})
    if not r.ok:
        raise RuntimeError(f"RPC {name} HTTP {r.status_code}: {r.text[:1200]}")
    return r.json() if r.text else None


def search_exact_piid(piid: str) -> list[dict[str,Any]]:
    payload = {
        "subawards": False,
        "limit": 25,
        "page": 1,
        "filters": {
            "award_type_codes": IDV_CODES,
            # USAspending documents quoted award_ids as exact rather than fuzzy matching.
            "award_ids": [f'"{piid}"'],
        },
        "fields": [
            "Award ID","Recipient Name","Recipient UEI","Awarding Agency",
            "Awarding Agency Code","Awarding Sub Agency","Awarding Sub Agency Code",
            "Contract Award Type","Description","Start Date","Last Date to Order",
            "generated_internal_id"
        ],
    }
    r = _request(api,"POST",f"{API_ROOT}/search/spending_by_award/",payload)
    if not r.ok:
        raise RuntimeError(f"USAspending exact PIID search {piid} HTTP {r.status_code}: {r.text[:1200]}")
    data = r.json()
    results = data.get("results") or []
    if not isinstance(results,list):
        raise RuntimeError(f"USAspending exact PIID search returned non-list results for {piid}")
    return [x for x in results if isinstance(x,dict) and str(x.get("Award ID") or "").strip().upper()==piid.upper()]


def verify_candidate(piid: str, generated_id: str) -> dict[str,Any]:
    r = _request(api,"GET",f"{API_ROOT}/awards/{quote(generated_id,safe='')}/")
    if not r.ok:
        raise RuntimeError(f"USAspending award detail {generated_id} HTTP {r.status_code}: {r.text[:1200]}")
    detail = r.json()
    if str(detail.get("generated_unique_award_id") or "").strip() != generated_id:
        raise RuntimeError(f"generated ID mismatch for {piid}")
    if str(detail.get("piid") or "").strip().upper() != piid.upper():
        raise RuntimeError(f"PIID mismatch for {piid}: {detail.get('piid')}")
    if str(detail.get("category") or "").strip().lower() != "idv":
        raise RuntimeError(f"resolved {piid} to non-IDV category {detail.get('category')}")
    return detail


def main() -> None:
    targets = rpc("internal_get_usaspending_physical_fm_parent_idvs",{}) or []
    if not isinstance(targets,list):
        raise RuntimeError("target RPC returned non-list")
    queue = [t for t in targets if not t.get("parent_generated_award_id") or t.get("identifier_resolution")=="usaspending_exact_piid_search_required"]
    stats: dict[str,Any] = {"queued":len(queue),"resolved":0,"not_found":0,"ambiguous":0,"failed":0,"results":[]}
    for i,target in enumerate(queue,1):
        piid = str(target.get("parent_piid") or "").strip()
        if not piid:
            stats["failed"] += 1
            continue
        try:
            matches = search_exact_piid(piid)
            if not matches:
                stats["not_found"] += 1
                print(f"{i}/{len(queue)} {piid}: not yet present in USAspending exact IDV search",flush=True)
                continue
            generated_ids = sorted({str(m.get("generated_internal_id") or "").strip() for m in matches if str(m.get("generated_internal_id") or "").strip()})
            if len(generated_ids)!=1:
                stats["ambiguous"] += 1
                print(f"{i}/{len(queue)} {piid}: ambiguous generated IDs {generated_ids}",flush=True)
                continue
            generated_id = generated_ids[0]
            detail = verify_candidate(piid,generated_id)
            result = rpc("internal_set_usaspending_parent_idv_identifier",{
                "p_parent_piid":piid,
                "p_generated_award_id":generated_id,
                "p_resolved_award_piid":str(detail.get("piid") or ""),
            })
            stats["resolved"] += 1
            stats["results"].append({"parent_piid":piid,"generated_award_id":generated_id,"recipient":(detail.get("recipient") or {}).get("recipient_name")})
            print(f"{i}/{len(queue)} {piid}: resolved {generated_id}",flush=True)
        except Exception as exc:
            stats["failed"] += 1
            print(f"{i}/{len(queue)} {piid}: resolver error: {exc}",flush=True)
    print(json.dumps(stats,indent=2,sort_keys=True),flush=True)
    # Unresolved IDs are not fatal: very recent federal awards can lag in USAspending.
    # Hard resolver/API failures are fatal because they indicate contract drift.
    if stats["failed"]:
        raise SystemExit(1)


if __name__=="__main__":
    main()
