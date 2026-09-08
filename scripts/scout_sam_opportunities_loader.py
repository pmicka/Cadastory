#!/usr/bin/env python3
"""Populate Scout's registered SAM Contract Opportunities source.

Uses SAM.gov's public daily full Contract Opportunities CSV extract, so the
initial/current snapshot does not require a SAM API key. Only Scout-relevant
rows are retained in Supabase; the downloaded national CSV is temporary.

Required env:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Optional env:
  SCOUT_SAM_STATES=KY,IN,OH
  SCOUT_SAM_BATCH_SIZE=100
  SCOUT_SAM_INCLUDE_STRATEGIC_NATIONAL=1
  SCOUT_SAM_BULK_URL=<override for controlled recovery/testing>
"""
from __future__ import annotations

import csv
import hashlib
import json
import os
import re
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
from dateutil import parser as date_parser

SOURCE_SLUG = "sam-opportunities"
DEFAULT_BULK_URL = (
    "https://s3.amazonaws.com/falextracts/Contract%20Opportunities/"
    "datagov/ContractOpportunitiesFullCSV.csv"
)
BULK_URL = os.getenv("SCOUT_SAM_BULK_URL", DEFAULT_BULK_URL)
STATES = {s.strip().upper() for s in os.getenv("SCOUT_SAM_STATES", "KY,IN,OH").split(",") if s.strip()}
BATCH_SIZE = int(os.getenv("SCOUT_SAM_BATCH_SIZE", "100"))
INCLUDE_STRATEGIC_NATIONAL = os.getenv("SCOUT_SAM_INCLUDE_STRATEGIC_NATIONAL", "1") not in {"0", "false", "False"}
SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
TIMEOUT = (30, 240)
MAX_RPC_ATTEMPTS = 7
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}
MIN_DOWNLOAD_BYTES = 1_000_000
MIN_TOTAL_ROWS = 1_000

REQUIRED_HEADERS = {"Title", "NoticeId", "Department/Ind.Agency", "PostedDate"}
FM_RE = re.compile(
    r"facilit(?:y|ies)\s+(?:management|maintenance|support|operations)|"
    r"base operations support|operations\s*(?:and|&)\s*maintenance|"
    r"building maintenance|maintenance and repair|repair and maintenance|property management",
    re.I,
)
VEHICLE_RE = re.compile(
    r"on[- ]call|as[- ]needed|indefinite delivery|indefinite quantity|\bIDIQ\b|"
    r"\bMATOC\b|\bSATOC\b|job[- ]order contract|\bJOC\b|task order|"
    r"requirements contract|blanket purchase|\bBPA\b|statewide|multi[- ]site|"
    r"multiple (?:sites|facilities|locations)|base[- ]wide|installation[- ]wide|portfolio",
    re.I,
)
SURFACE_RE = re.compile(
    r"paint(?:ing)?|repaint|coat(?:ing)?|pressure wash|power wash|exterior clean|"
    r"fa[cç]ade|masonry|tuckpoint|waterproof|sealant|caulk|roof|building envelope|concrete clean",
    re.I,
)
MILITARY_RE = re.compile(
    r"department of defense|department of the army|dept of the army|department of the navy|"
    r"dept of the navy|department of the air force|dept of the air force|defense logistics agency|"
    r"u\.?s\.? army|u\.?s\.? navy|u\.?s\.? air force|marine corps|army corps of engineers|"
    r"\bUSACE\b|space force",
    re.I,
)

session = requests.Session()
session.headers.update({
    "User-Agent": "Scout-Cadastory-SAM-Collector/1.0",
})
supabase = requests.Session()
supabase.headers.update({
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "User-Agent": "Scout-Cadastory-SAM-Collector/1.0",
})


def clean(value: Any) -> str:
    return str(value or "").strip()


def first(row: dict[str, str], *keys: str) -> str:
    for key in keys:
        value = clean(row.get(key))
        if value:
            return value
    return ""


def iso_datetime(value: str) -> str | None:
    value = clean(value)
    if not value:
        return None
    try:
        dt = date_parser.parse(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat()
    except (ValueError, TypeError, OverflowError):
        return None


def boolish(value: str) -> bool:
    return clean(value).lower() in {"yes", "y", "true", "1", "active"}


def content_hash(payload: dict[str, Any]) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def retry_delay(attempt: int, response: requests.Response | None = None) -> float:
    if response is not None:
        retry_after = response.headers.get("Retry-After")
        if retry_after:
            try:
                return min(60.0, max(1.0, float(retry_after)))
            except ValueError:
                pass
    return float(min(30, 2 ** attempt))


def rpc(name: str, payload: dict[str, Any]) -> Any:
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    last_error: Exception | None = None
    for attempt in range(1, MAX_RPC_ATTEMPTS + 1):
        response = None
        try:
            response = supabase.post(url, json=payload, timeout=TIMEOUT)
            if response.ok:
                if not response.text:
                    return None
                return response.json()
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"RPC {name} HTTP {response.status_code}: {response.text[:1500]}")
            last_error = RuntimeError(f"RPC {name} transient HTTP {response.status_code}: {response.text[:400]}")
        except requests.RequestException as exc:
            last_error = exc
        if attempt >= MAX_RPC_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"RPC {name} failed after {MAX_RPC_ATTEMPTS} attempts: {last_error}") from last_error


def set_quality(status: str, reason: str, metadata: dict[str, Any]) -> None:
    rpc("internal_set_source_quality_gate", {
        "p_source_slug": SOURCE_SLUG,
        "p_status": status,
        "p_reason": reason,
        "p_validation_version": "sam-opportunities-v1",
        "p_metadata": metadata,
    })


def download_to_temp() -> tuple[Path, int]:
    fd, name = tempfile.mkstemp(prefix="scout-sam-opportunities-", suffix=".csv")
    os.close(fd)
    path = Path(name)
    seen = 0
    try:
        with session.get(BULK_URL, stream=True, timeout=TIMEOUT, allow_redirects=True) as response:
            response.raise_for_status()
            with path.open("wb") as fh:
                for chunk in response.iter_content(chunk_size=1024 * 1024):
                    if not chunk:
                        continue
                    fh.write(chunk)
                    seen += len(chunk)
        if seen < MIN_DOWNLOAD_BYTES:
            raise RuntimeError(f"SAM bulk extract too small: {seen:,} bytes")
        return path, seen
    except Exception:
        path.unlink(missing_ok=True)
        raise


def strategic_keep(row: dict[str, str]) -> bool:
    if not INCLUDE_STRATEGIC_NATIONAL:
        return False
    agency = " ".join([first(row, "Department/Ind.Agency"), first(row, "Sub-Tier"), first(row, "Office")])
    text = " ".join([first(row, "Title"), first(row, "Description"), agency])
    fm = bool(FM_RE.search(text))
    surface = bool(SURFACE_RE.search(text))
    military = bool(MILITARY_RE.search(agency))
    vehicle = bool(VEHICLE_RE.search(text))
    return (military and (fm or surface or vehicle)) or (fm and vehicle)


def normalize(row: dict[str, str]) -> dict[str, Any] | None:
    notice_id = first(row, "NoticeId")
    title = first(row, "Title")
    if not notice_id or not title:
        return None
    active_value = first(row, "Active")
    active = boolish(active_value) if active_value else True
    state = first(row, "PopState", "State").upper()
    canonical_url = first(row, "Link", "AdditionalInfoLink") or f"https://sam.gov/opp/{notice_id}/view"
    normalized = {
        "jurisdiction": "federal",
        "solicitation_number": first(row, "Sol#", "SolicitationNumber", "Solicitation Number") or None,
        "title": title,
        "notice_type": first(row, "Type") or None,
        "base_type": first(row, "BaseType") or None,
        "buyer_name": first(row, "Department/Ind.Agency") or None,
        "buyer_subtier": first(row, "Sub-Tier") or None,
        "buyer_office": first(row, "Office") or None,
        "buyer_code": first(row, "OrganizationCode", "OfficeCode") or None,
        "naics_code": first(row, "NaicsCode") or None,
        "psc_code": first(row, "ClassificationCode", "ProductServiceCode") or None,
        "set_aside": first(row, "SetASide", "SetAside") or None,
        "posted_at": iso_datetime(first(row, "PostedDate")),
        "response_deadline": iso_datetime(first(row, "ResponseDeadLine", "ResponseDeadline")),
        "archive_at": iso_datetime(first(row, "ArchiveDate")),
        "active": active,
        "place_city": first(row, "PopCity") or None,
        "place_state": state or None,
        "place_zip": first(row, "PopZip", "PopZipCode") or None,
        "place_country": first(row, "PopCountry") or None,
        "description": first(row, "Description") or None,
        "canonical_url": canonical_url,
        "contact": {
            "name": first(row, "PrimaryContactFullname", "PrimaryContactFullName") or None,
            "email": first(row, "PrimaryContactEmail") or None,
            "phone": first(row, "PrimaryContactPhone") or None,
        },
        "award": {
            "number": first(row, "AwardNumber") or None,
            "amount": first(row, "AwardAmount") or None,
            "awardee": first(row, "Awardee") or None,
        },
        "attributes": {
            "set_aside_code": first(row, "SetASideCode") or None,
            "additional_info_link": first(row, "AdditionalInfoLink") or None,
            "active_source_value": active_value or None,
        },
    }
    return {
        "source_native_id": notice_id,
        "source_url": canonical_url,
        "content_hash": content_hash(row),
        "normalized": normalized,
        "source_payload": row,
    }


def load(path: Path, observed_at: str) -> dict[str, int]:
    total = active_rows = local_rows = strategic_rows = invalid = 0
    retained: dict[str, dict[str, Any]] = {}
    with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as fh:
        reader = csv.DictReader(fh)
        headers = set(reader.fieldnames or [])
        missing = sorted(REQUIRED_HEADERS - headers)
        if missing:
            raise RuntimeError(f"SAM extract schema drift; missing required headers: {missing}")
        for row in reader:
            total += 1
            active_value = first(row, "Active")
            if active_value and not boolish(active_value):
                continue
            active_rows += 1
            state = first(row, "PopState", "State").upper()
            local = state in STATES
            strategic = strategic_keep(row)
            if not local and not strategic:
                continue
            item = normalize(row)
            if item is None:
                invalid += 1
                continue
            if local:
                local_rows += 1
            elif strategic:
                strategic_rows += 1
            retained[item["source_native_id"]] = item

    if total < MIN_TOTAL_ROWS:
        raise RuntimeError(f"SAM extract row count implausibly low: {total:,}")
    if active_rows == 0:
        raise RuntimeError("SAM extract produced zero active rows")
    if local_rows == 0:
        raise RuntimeError(f"SAM extract produced zero local rows for states {sorted(STATES)}")
    if not retained:
        raise RuntimeError("SAM scope selector retained zero opportunities")

    items = list(retained.values())
    raw_inserted = upserted = 0
    for start in range(0, len(items), BATCH_SIZE):
        batch = items[start:start + BATCH_SIZE]
        result = rpc("internal_ingest_procurement_opportunity_batch", {
            "p_source_slug": SOURCE_SLUG,
            "p_records": batch,
            "p_observed_at": observed_at,
        })
        raw_inserted += int((result or {}).get("raw_inserted", 0))
        upserted += int((result or {}).get("opportunities_upserted", 0))
        print(f"SAM upload {min(start+BATCH_SIZE,len(items)):,}/{len(items):,}", flush=True)

    closed = int(rpc("internal_finalize_procurement_opportunity_snapshot", {
        "p_source_slug": SOURCE_SLUG,
        "p_snapshot_observed_at": observed_at,
    }) or 0)
    return {
        "total_rows": total,
        "active_rows": active_rows,
        "local_rows": local_rows,
        "strategic_national_rows": strategic_rows,
        "retained_unique": len(items),
        "invalid_retained": invalid,
        "raw_inserted": raw_inserted,
        "opportunities_upserted": upserted,
        "closed_stale": closed,
    }


def main() -> None:
    observed_at = datetime.now(timezone.utc).isoformat()
    path: Path | None = None
    try:
        path, byte_count = download_to_temp()
        stats = load(path, observed_at)
        stats["download_bytes"] = byte_count
        stats["states"] = sorted(STATES)
        set_quality(
            "healthy",
            "Public SAM Contract Opportunities full extract passed schema, size, row-count, local-scope and identity checks.",
            stats,
        )
        print(json.dumps(stats, indent=2, sort_keys=True), flush=True)
    except Exception as exc:
        try:
            set_quality("degraded", f"SAM collector failed closed: {exc}", {"bulk_url": BULK_URL, "states": sorted(STATES)})
        except Exception as quality_exc:
            print(f"quality-gate update also failed: {quality_exc}", flush=True)
        raise
    finally:
        if path is not None:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
