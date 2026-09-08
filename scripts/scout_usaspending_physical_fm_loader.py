#!/usr/bin/env python3
"""Collect USAspending child awards under Scout-qualified physical-FM parent IDVs.

This is intentionally NOT a comprehensive USAspending mirror. The target parent IDVs
come from Scout's research-only physical facilities-management classifier. For each
qualified IDV this collector:

1. verifies the parent award on USAspending,
2. enumerates child awards through /api/v2/idvs/awards/,
3. fetches each child award detail,
4. requires an exact parent PIID/generated-ID match,
5. preserves the source payload in ingest.raw_records, and
6. upserts normalized evidence into procurement.federal_task_orders.

Minimum-guarantee orders are retained as award provenance but are excluded from site
evidence by the database research view.

Required env:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Optional env:
  SCOUT_USASPENDING_BATCH_SIZE=25
  SCOUT_USASPENDING_PAGE_SIZE=100
  SCOUT_USASPENDING_REQUEST_DELAY=0.10
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

import requests

SOURCE_SLUG = "usaspending"
API_ROOT = "https://api.usaspending.gov/api/v2"
SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
BATCH_SIZE = max(1, int(os.getenv("SCOUT_USASPENDING_BATCH_SIZE", "25")))
PAGE_SIZE = min(100, max(1, int(os.getenv("SCOUT_USASPENDING_PAGE_SIZE", "100"))))
REQUEST_DELAY = max(0.0, float(os.getenv("SCOUT_USASPENDING_REQUEST_DELAY", "0.10")))
TIMEOUT = (30, 120)
MAX_ATTEMPTS = 6
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}

api = requests.Session()
api.headers.update({
    "Accept": "application/json",
    "Content-Type": "application/json",
    "User-Agent": "Scout-Cadastory-USAspending-Physical-FM/1.0",
})

supabase = requests.Session()
supabase.headers.update({
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "User-Agent": "Scout-Cadastory-USAspending-Physical-FM/1.0",
})


def retry_delay(attempt: int, response: requests.Response | None = None) -> float:
    if response is not None:
        retry_after = response.headers.get("Retry-After")
        if retry_after:
            try:
                return min(60.0, max(1.0, float(retry_after)))
            except ValueError:
                pass
    return float(min(30, 2 ** max(0, attempt - 1)))


def request_json(method: str, url: str, *, payload: dict[str, Any] | None = None) -> Any:
    last_error: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        response: requests.Response | None = None
        try:
            if method == "GET":
                response = api.get(url, timeout=TIMEOUT)
            elif method == "POST":
                response = api.post(url, json=payload, timeout=TIMEOUT)
            else:
                raise ValueError(f"Unsupported method {method}")
            if response.ok:
                if REQUEST_DELAY:
                    time.sleep(REQUEST_DELAY)
                return response.json()
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"USAspending {method} {url} HTTP {response.status_code}: {response.text[:1200]}")
            last_error = RuntimeError(f"USAspending transient HTTP {response.status_code}: {response.text[:400]}")
        except (requests.RequestException, ValueError) as exc:
            last_error = exc
        if attempt >= MAX_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"USAspending request failed after {MAX_ATTEMPTS} attempts: {url}: {last_error}") from last_error


def rpc(name: str, payload: dict[str, Any] | None = None) -> Any:
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    body = payload or {}
    last_error: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        response: requests.Response | None = None
        try:
            response = supabase.post(url, json=body, timeout=TIMEOUT)
            if response.ok:
                return response.json() if response.text else None
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"RPC {name} HTTP {response.status_code}: {response.text[:1200]}")
            last_error = RuntimeError(f"RPC {name} transient HTTP {response.status_code}: {response.text[:400]}")
        except requests.RequestException as exc:
            last_error = exc
        if attempt >= MAX_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"RPC {name} failed after {MAX_ATTEMPTS} attempts: {last_error}") from last_error


def set_quality(status: str, reason: str, metadata: dict[str, Any]) -> None:
    rpc("internal_set_source_quality_gate", {
        "p_source_slug": SOURCE_SLUG,
        "p_status": status,
        "p_reason": reason,
        "p_validation_version": "usaspending-physical-fm-v1",
        "p_metadata": {"scope": "qualified_physical_fm_parent_idvs", **metadata},
    })


def nested(data: dict[str, Any] | None, *keys: str) -> Any:
    value: Any = data
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def clean(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def content_hash(payload: dict[str, Any]) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def award_detail_url(generated_id: str) -> str:
    return f"{API_ROOT}/awards/{quote(generated_id, safe='')}/"


def verify_parent(target: dict[str, Any]) -> dict[str, Any]:
    generated = clean(target.get("parent_generated_award_id"))
    piid = clean(target.get("parent_piid"))
    if not generated or not piid:
        raise RuntimeError(f"Unresolved parent target identifier: {target}")
    detail = request_json("GET", award_detail_url(generated))
    if clean(detail.get("generated_unique_award_id")) != generated:
        raise RuntimeError(f"Parent generated award ID mismatch for {piid}")
    if clean(detail.get("piid")) != piid:
        raise RuntimeError(f"Parent PIID mismatch: expected {piid}, got {detail.get('piid')}")
    if clean(detail.get("category")) != "idv":
        raise RuntimeError(f"Qualified parent {piid} resolved to non-IDV category {detail.get('category')}")
    return detail


def enumerate_children(target: dict[str, Any]) -> list[dict[str, Any]]:
    generated = str(target["parent_generated_award_id"])
    page = 1
    rows: list[dict[str, Any]] = []
    while True:
        payload = {
            "award_id": generated,
            "type": "child_awards",
            "limit": PAGE_SIZE,
            "page": page,
            "sort": "period_of_performance_start_date",
            "order": "desc",
        }
        response = request_json("POST", f"{API_ROOT}/idvs/awards/", payload=payload)
        page_rows = response.get("results") or []
        if not isinstance(page_rows, list):
            raise RuntimeError(f"Unexpected child-awards payload for {generated}: results is not an array")
        rows.extend(x for x in page_rows if isinstance(x, dict))
        meta = response.get("page_metadata") or {}
        if not meta.get("hasNext"):
            break
        next_page = meta.get("next")
        page = int(next_page) if next_page else page + 1
        if page > 1000:
            raise RuntimeError(f"Pagination runaway for parent {generated}")
    return rows


def normalize_child(target: dict[str, Any], summary: dict[str, Any], detail: dict[str, Any]) -> dict[str, Any]:
    expected_parent_id = clean(target.get("parent_generated_award_id"))
    expected_parent_piid = clean(target.get("parent_piid"))
    parent = detail.get("parent_award") or {}
    actual_parent_id = clean(parent.get("generated_unique_award_id"))
    actual_parent_piid = clean(parent.get("piid"))
    if actual_parent_id != expected_parent_id or actual_parent_piid != expected_parent_piid:
        raise ValueError(
            f"Child {detail.get('generated_unique_award_id')} parent mismatch: "
            f"expected {expected_parent_piid}/{expected_parent_id}, got {actual_parent_piid}/{actual_parent_id}"
        )

    child_generated = clean(detail.get("generated_unique_award_id"))
    if not child_generated:
        raise ValueError("Child award detail is missing generated_unique_award_id")
    summary_generated = clean(summary.get("generated_unique_award_id"))
    if summary_generated and summary_generated != child_generated:
        raise ValueError(f"Child summary/detail generated ID mismatch: {summary_generated} != {child_generated}")

    recipient = detail.get("recipient") or {}
    pop = detail.get("place_of_performance") or {}
    period = detail.get("period_of_performance") or {}
    awarding = detail.get("awarding_agency") or {}
    funding = detail.get("funding_agency") or {}
    latest = detail.get("latest_transaction_contract_data") or {}
    naics_base = nested(detail, "naics_hierarchy", "base_code") or {}
    psc_base = nested(detail, "psc_hierarchy", "base_code") or {}

    naics_code = clean(naics_base.get("code")) or clean(latest.get("naics"))
    naics_desc = clean(naics_base.get("description")) or clean(latest.get("naics_description"))
    psc_code = clean(psc_base.get("code")) or clean(latest.get("product_or_service_code"))
    psc_desc = clean(psc_base.get("description")) or clean(latest.get("product_or_service_description"))

    normalized = {
        "parent_generated_award_id": actual_parent_id,
        "parent_piid": actual_parent_piid,
        "child_generated_award_id": child_generated,
        "child_piid": clean(detail.get("piid")),
        "award_type": clean(detail.get("type_description")) or clean(summary.get("award_type")),
        "description": clean(detail.get("description")) or clean(summary.get("description")),
        "recipient_name": clean(recipient.get("recipient_name")),
        "recipient_uei": clean(recipient.get("recipient_uei")),
        "parent_recipient_name": clean(recipient.get("parent_recipient_name")),
        "parent_recipient_uei": clean(recipient.get("parent_recipient_uei")),
        "total_obligation": detail.get("total_obligation"),
        "date_signed": clean(detail.get("date_signed")),
        "pop_start_date": clean(period.get("start_date")),
        "pop_end_date": clean(period.get("end_date")),
        "pop_potential_end_date": clean(period.get("potential_end_date")),
        "awarding_agency_name": clean(nested(awarding, "toptier_agency", "name")),
        "awarding_subtier_name": clean(nested(awarding, "subtier_agency", "name")),
        "awarding_office_name": clean(awarding.get("office_agency_name")),
        "funding_agency_name": clean(nested(funding, "toptier_agency", "name")),
        "funding_subtier_name": clean(nested(funding, "subtier_agency", "name")),
        "funding_office_name": clean(funding.get("office_agency_name")),
        "place_country_code": clean(pop.get("location_country_code")),
        "place_country_name": clean(pop.get("country_name")),
        "place_state_code": clean(pop.get("state_code")),
        "place_state_name": clean(pop.get("state_name")),
        "place_city_name": clean(pop.get("city_name")),
        "place_county_name": clean(pop.get("county_name")),
        "place_zip5": clean(pop.get("zip5")),
        "place_address_line1": clean(pop.get("address_line1")),
        "naics_code": naics_code,
        "naics_description": naics_desc,
        "psc_code": psc_code,
        "psc_description": psc_desc,
        "attributes": {
            "program_key": target.get("program_key"),
            "program_title": target.get("program_title"),
            "program_scope_class": target.get("program_scope_class"),
            "parent_site_scope_status": target.get("site_scope_status"),
            "parent_has_surface_work_scope": bool(target.get("has_surface_work_scope")),
            "award_type_code": detail.get("type"),
            "category": detail.get("category"),
            "base_exercised_options": detail.get("base_exercised_options"),
            "base_and_all_options": detail.get("base_and_all_options"),
            "summary_obligated_amount": summary.get("obligated_amount"),
            "summary_pop_start_date": summary.get("period_of_performance_start_date"),
            "summary_pop_end_date": summary.get("period_of_performance_current_end_date"),
            "solicitation_identifier": latest.get("solicitation_identifier"),
            "set_aside": latest.get("type_set_aside_description"),
        },
    }
    return {
        "source_native_id": child_generated,
        "source_url": award_detail_url(child_generated),
        "content_hash": content_hash(detail),
        "normalized": normalized,
        "source_payload": detail,
    }


def upload(records: list[dict[str, Any]], observed_at: str) -> dict[str, int]:
    raw_inserted = upserted = 0
    for start in range(0, len(records), BATCH_SIZE):
        batch = records[start:start + BATCH_SIZE]
        result = rpc("internal_ingest_usaspending_task_order_batch", {
            "p_records": batch,
            "p_observed_at": observed_at,
        }) or {}
        raw_inserted += int(result.get("raw_inserted", 0))
        upserted += int(result.get("task_orders_upserted", 0))
        print(f"USAspending upload {min(start+BATCH_SIZE,len(records)):,}/{len(records):,}", flush=True)
    return {"raw_inserted": raw_inserted, "task_orders_upserted": upserted}


def main() -> None:
    observed_at = datetime.now(timezone.utc).isoformat()
    stats: dict[str, Any] = {
        "parents_targeted": 0,
        "parents_resolved": 0,
        "parents_failed": 0,
        "child_summaries": 0,
        "child_details_normalized": 0,
        "child_parent_mismatches": 0,
        "child_detail_failures": 0,
        "raw_inserted": 0,
        "task_orders_upserted": 0,
    }
    parent_failures: list[dict[str, str]] = []
    try:
        targets = rpc("internal_get_usaspending_physical_fm_parent_idvs", {}) or []
        if not isinstance(targets, list) or not targets:
            raise RuntimeError("Scout returned zero qualified physical-FM parent IDV targets")
        stats["parents_targeted"] = len(targets)
        records: list[dict[str, Any]] = []

        for index, target in enumerate(targets, start=1):
            piid = clean(target.get("parent_piid")) or "unknown"
            generated = clean(target.get("parent_generated_award_id"))
            try:
                verify_parent(target)
                stats["parents_resolved"] += 1
                children = enumerate_children(target)
                stats["child_summaries"] += len(children)
                print(f"parent {index}/{len(targets)} {piid}: {len(children)} child awards", flush=True)
                for summary in children:
                    child_id = clean(summary.get("generated_unique_award_id"))
                    if not child_id:
                        stats["child_detail_failures"] += 1
                        continue
                    try:
                        detail = request_json("GET", award_detail_url(child_id))
                        records.append(normalize_child(target, summary, detail))
                        stats["child_details_normalized"] += 1
                    except ValueError as exc:
                        stats["child_parent_mismatches"] += 1
                        print(f"parent mismatch skipped for {child_id}: {exc}", flush=True)
                    except Exception as exc:
                        stats["child_detail_failures"] += 1
                        print(f"child detail failed for {child_id}: {exc}", flush=True)
            except Exception as exc:
                stats["parents_failed"] += 1
                parent_failures.append({"parent_piid": piid, "generated_id": generated or "", "error": str(exc)[:500]})
                print(f"parent failed {piid}: {exc}", flush=True)

        # Deduplicate in case USAspending ever emits a child twice across pagination.
        deduped = {r["source_native_id"]: r for r in records}
        upload_stats = upload(list(deduped.values()), observed_at) if deduped else {"raw_inserted": 0, "task_orders_upserted": 0}
        stats.update(upload_stats)
        stats["unique_child_awards"] = len(deduped)
        stats["parent_failures"] = parent_failures[:20]

        if stats["parents_failed"] or stats["child_parent_mismatches"] or stats["child_detail_failures"]:
            status = "degraded"
            reason = (
                "USAspending targeted physical-FM collector completed with partial coverage; "
                "failed or mismatched parent/child records were rejected and no relationship propagation occurred."
            )
        else:
            status = "healthy"
            reason = (
                "USAspending targeted physical-FM parent IDVs resolved and child awards were verified against exact parent PIIDs/generated IDs before ingestion."
            )
        set_quality(status, reason, stats)
        print(json.dumps(stats, indent=2, sort_keys=True), flush=True)
    except Exception as exc:
        try:
            set_quality("degraded", f"USAspending targeted physical-FM collector failed closed: {exc}", stats)
        except Exception as quality_exc:
            print(f"quality-gate update also failed: {quality_exc}", flush=True)
        raise


if __name__ == "__main__":
    main()
