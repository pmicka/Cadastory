#!/usr/bin/env python3
"""Load Indiana IDOA Current Business Opportunities into Scout.

The source is the official current-opportunity table. Bid-document links are
preserved as evidence pointers; this collector does not download/interpret every
attachment. Solicitation numbers are normalized so current RFPs can join Scout's
existing IDOA Award Recommendations corpus after award.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import time
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup
from dateutil import parser as date_parser

SOURCE_SLUG = "indiana-idoa-current-opportunities"
SOURCE_URL = "https://www.in.gov/idoa/procurement/current-business-opportunities/"
SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
BATCH_SIZE = int(os.getenv("SCOUT_IDOA_CURRENT_BATCH_SIZE", "100"))
TIMEOUT = (30, 180)
MAX_RPC_ATTEMPTS = 7
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}
MIN_ROWS = 5
SHORT_SOL_RE = re.compile(r"\b(\d{2}-\d{5})\b")
NOTICE_RE = re.compile(r"^\s*(RFP|RFQ|RFS|ITB|IFB|NB|QPA)\b", re.I)

web = requests.Session()
web.headers.update({"User-Agent": "Scout-Cadastory-IDOA-Collector/1.0"})
supabase = requests.Session()
supabase.headers.update({
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "User-Agent": "Scout-Cadastory-IDOA-Collector/1.0",
})


def clean(value: Any) -> str:
    return " ".join(str(value or "").replace("\xa0", " ").split())


def stable_hash(payload: Any) -> str:
    blob = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def iso_datetime(value: str) -> str | None:
    value = clean(value)
    if not value:
        return None
    try:
        dt = date_parser.parse(value, tzinfos={"EST": -5 * 3600, "EDT": -4 * 3600})
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat()
    except (ValueError, TypeError, OverflowError):
        return None


def retry_delay(attempt: int, response: requests.Response | None = None) -> float:
    if response is not None:
        value = response.headers.get("Retry-After")
        if value:
            try:
                return min(60.0, max(1.0, float(value)))
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
                return response.json() if response.text else None
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"RPC {name} HTTP {response.status_code}: {response.text[:1200]}")
            last_error = RuntimeError(f"RPC {name} transient HTTP {response.status_code}: {response.text[:300]}")
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
        "p_validation_version": "indiana-idoa-current-v1",
        "p_metadata": metadata,
    })


def solicitation_number(title: str, description: str, event_id: str) -> str | None:
    match = SHORT_SOL_RE.search(f"{title} {description}")
    if match:
        return match.group(1)
    return event_id or None


def notice_type(title: str, description: str) -> str:
    match = NOTICE_RE.search(title) or NOTICE_RE.search(description)
    if match:
        return match.group(1).upper()
    if "bid" in title.lower() or "bid" in description.lower():
        return "Bid"
    return "Solicitation"


def parse() -> tuple[list[dict[str, Any]], dict[str, int]]:
    response = web.get(SOURCE_URL, timeout=TIMEOUT)
    response.raise_for_status()
    if len(response.content) < 10_000:
        raise RuntimeError(f"IDOA current-opportunity page implausibly small: {len(response.content):,} bytes")
    soup = BeautifulSoup(response.text, "html.parser")
    records: dict[str, dict[str, Any]] = {}
    candidate_rows = 0
    invalid = 0

    for tr in soup.find_all("tr"):
        cells = tr.find_all("td", recursive=False)
        if len(cells) < 6:
            continue
        candidate_rows += 1
        title = clean(cells[0].get_text(" ", strip=True)).replace(" Bid Documents", "").strip()
        agency = clean(cells[1].get_text(" ", strip=True))
        event_id = clean(cells[2].get_text(" ", strip=True))
        description = clean(cells[3].get_text(" ", strip=True))
        due_text = clean(cells[4].get_text(" ", strip=True))
        contact_text = clean(cells[5].get_text(" ", strip=True))
        if not title or title.lower() == "event name":
            continue
        if event_id.upper() == "NA":
            event_id = ""
        native_id = event_id or f"title:{stable_hash({'title': title, 'due': due_text})[:24]}"
        links = [urljoin(SOURCE_URL, a.get("href")) for a in cells[0].find_all("a", href=True)]
        links = list(dict.fromkeys(links))
        bid_url = links[0] if links else SOURCE_URL
        sol = solicitation_number(title, description, event_id)
        source_payload = {
            "event_name": title,
            "agency": agency,
            "event_id": event_id or None,
            "event_description": description,
            "response_due_by": due_text,
            "contact": contact_text,
            "bid_document_links": links,
            "source_page": SOURCE_URL,
        }
        due = iso_datetime(due_text)
        if event_id and not event_id.isdigit():
            invalid += 1
        normalized = {
            "jurisdiction": "Indiana",
            "solicitation_number": sol,
            "title": title,
            "notice_type": notice_type(title, description),
            "base_type": None,
            "buyer_name": "State of Indiana",
            "buyer_subtier": agency or None,
            "buyer_office": "Indiana Department of Administration - Procurement",
            "buyer_code": None,
            "naics_code": None,
            "psc_code": None,
            "set_aside": None,
            "posted_at": None,
            "response_deadline": due,
            "archive_at": None,
            "active": True,
            "place_city": None,
            "place_state": "IN",
            "place_zip": None,
            "place_country": "USA",
            "description": description or None,
            "canonical_url": bid_url,
            "contact": {"display": contact_text or None},
            "award": {},
            "attributes": {
                "event_id": event_id or None,
                "bid_document_links": links,
                "due_text": due_text or None,
            },
        }
        records[native_id] = {
            "source_native_id": native_id,
            "source_url": bid_url,
            "content_hash": stable_hash(source_payload),
            "normalized": normalized,
            "source_payload": source_payload,
        }

    if candidate_rows < MIN_ROWS or len(records) < MIN_ROWS:
        raise RuntimeError(f"IDOA parser retained too few rows: candidates={candidate_rows}, unique={len(records)}")
    return list(records.values()), {
        "page_bytes": len(response.content),
        "candidate_rows": candidate_rows,
        "retained_unique": len(records),
        "non_numeric_event_ids": invalid,
    }


def main() -> None:
    observed_at = datetime.now(timezone.utc).isoformat()
    try:
        items, stats = parse()
        raw_inserted = upserted = 0
        for start in range(0, len(items), BATCH_SIZE):
            batch = items[start:start+BATCH_SIZE]
            result = rpc("internal_ingest_procurement_opportunity_batch", {
                "p_source_slug": SOURCE_SLUG,
                "p_records": batch,
                "p_observed_at": observed_at,
            }) or {}
            raw_inserted += int(result.get("raw_inserted", 0))
            upserted += int(result.get("opportunities_upserted", 0))
        closed = int(rpc("internal_finalize_procurement_opportunity_snapshot", {
            "p_source_slug": SOURCE_SLUG,
            "p_snapshot_observed_at": observed_at,
        }) or 0)
        stats.update({
            "raw_inserted": raw_inserted,
            "opportunities_upserted": upserted,
            "closed_stale": closed,
        })
        set_quality(
            "healthy",
            "Official Indiana IDOA current-opportunity table passed page-size, table-shape, event-identity and minimum-row checks.",
            stats,
        )
        print(json.dumps(stats, indent=2, sort_keys=True), flush=True)
    except Exception as exc:
        try:
            set_quality("degraded", f"Indiana IDOA current-opportunity collector failed closed: {exc}", {"source_url": SOURCE_URL})
        except Exception as quality_exc:
            print(f"quality-gate update also failed: {quality_exc}", flush=True)
        raise


if __name__ == "__main__":
    main()
