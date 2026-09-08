#!/usr/bin/env python3
"""Deterministic KYTC bridge surface-work loader v2.

Parses authoritative Unit Bid Tabulation PDFs by complete Call blocks so each
surface-work line inherits its contract ID, letting date, county, call number,
project title and apparent low bidder. Research ingestion only.
"""
from __future__ import annotations

import hashlib
import io
import json
import os
import re
import time
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup
from pypdf import PdfReader

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
MAX_DOCUMENTS = int(os.getenv("SCOUT_KYTC_BRIDGE_MAX_DOCUMENTS", "40"))
LOOKBACK_YEARS = int(os.getenv("SCOUT_KYTC_BRIDGE_LOOKBACK_YEARS", "5"))
BATCH_SIZE = int(os.getenv("SCOUT_KYTC_BRIDGE_BATCH_SIZE", "100"))
INDEX_URL = "https://transportation.ky.gov/Construction-Procurement/Pages/Unit-Bid-Tabulations.aspx"
TIMEOUT = (30, 180)
MAX_ATTEMPTS = 5

HTTP = requests.Session()
HTTP.headers.update({"User-Agent": "Scout-Cadastory-KYTC-Bridge-Surface/2.0"})
DB = requests.Session()
DB.headers.update({
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "User-Agent": "Scout-Cadastory-KYTC-Bridge-Surface/2.0",
})

DATE_URL_RE = re.compile(r"/Publications/(20\d{2})-(\d{2})-(\d{2})/", re.I)
DATE_LET_RE = re.compile(r"Date\s+Let\s*:\s*(\d{1,2}/\d{1,2}/\d{2,4})", re.I)
CALL_RE = re.compile(r"(?=\bCall:\s*\d+\b)", re.I)
CONTRACT_RE = re.compile(r"\bContid:\s*(\d{2}-\d{4})\b", re.I)
COUNTY_RE = re.compile(r"\bCounty:\s*(.+?)\s+District:\s*\d+\b", re.I)
CALL_NO_RE = re.compile(r"\bCall:\s*(\d+)\b", re.I)
LOW_BIDDER_RE = re.compile(r"Apparent\s+Low\s+Bidder\s+Low\s*>\s*(.+?)(?:\n|Prop\s+Line)", re.I | re.S)
PROPOSAL_RE = re.compile(r"Proposal\s+Description:\s*(.+?)\s+Length:", re.I | re.S)
KY_BRIDGE_RE = re.compile(r"\b\d{3}B\d{5}[A-Z]?\b", re.I)
ITEM_LINE_RE = re.compile(r"^\s*(\d{4})\s+(.+?)\s*$")

SURFACE_PATTERNS = [
    ("steel_clean_and_paint", re.compile(r"\bCLEAN\s*&\s*PAINT\s+STRUCTURAL\s+STEEL\b", re.I)),
    ("bridge_cleaning", re.compile(r"\bBRIDGE\s+CLEANING\b", re.I)),
    ("concrete_coating", re.compile(r"\bCONCRETE\s+COATING\b", re.I)),
    ("concrete_sealing", re.compile(r"\bCONCRETE\s+SEALING\b", re.I)),
    ("abrasive_blast_prep", re.compile(r"\bBLAST\s+CLEANING\b", re.I)),
    ("bearing_clean_and_coat", re.compile(r"(?:\bCLEAN\b.*\bCOAT\b.*\bBEARING\b|\bBEARING\b.*\bCLEAN\b.*\bCOAT\b)", re.I)),
]
NEGATIVE_RE = re.compile(r"PAVE(?:MENT)?\s+STRIP|PAVEMENT\s+MARK|EPOXY[- ]*COATED\s+STEEL\s+REINFORCEMENT|STEEL\s+REINFORCEMENT[- ]*EPOXY\s+COATED", re.I)


def get(url: str) -> requests.Response:
    last = None
    for attempt in range(MAX_ATTEMPTS):
        try:
            r = HTTP.get(url, timeout=TIMEOUT)
            if r.ok:
                return r
            last = RuntimeError(f"HTTP {r.status_code}: {url}")
        except requests.RequestException as exc:
            last = exc
        time.sleep(min(20, 2 ** (attempt + 1)))
    raise RuntimeError(f"GET failed: {url}: {last}")


def rpc(name: str, payload: dict):
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    r = DB.post(url, json=payload, timeout=TIMEOUT)
    if not r.ok:
        raise RuntimeError(f"RPC {name} HTTP {r.status_code}: {r.text[:1500]}")
    return r.json()


def pdf_text(url: str) -> str:
    r = get(url)
    reader = PdfReader(io.BytesIO(r.content))
    parts = []
    for page_no, page in enumerate(reader.pages, start=1):
        try:
            parts.append(f"\n[[PAGE {page_no}]]\n" + (page.extract_text() or ""))
        except Exception as exc:
            print(f"WARN page {page_no} extraction failed {url}: {exc}", flush=True)
    return "\n".join(parts)


def url_date(url: str) -> date | None:
    m = DATE_URL_RE.search(url)
    if not m:
        return None
    try:
        return date(*map(int, m.groups()))
    except ValueError:
        return None


def parse_short_date(value: str) -> date | None:
    for fmt in ("%m/%d/%y", "%m/%d/%Y"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            pass
    return None


def classify(line: str, block: str) -> str | None:
    if NEGATIVE_RE.search(line):
        return None
    for family, pattern in SURFACE_PATTERNS:
        if pattern.search(line):
            if family == "abrasive_blast_prep" and not re.search(
                r"CLEAN\s*&\s*PAINT\s+STRUCTURAL\s+STEEL|BRIDGE\s+CLEANING|CONCRETE\s+COATING|BRIDGE\s+(?:REPAIR|REHAB|PRESERV)",
                block,
                re.I,
            ):
                return None
            if family == "concrete_sealing" and not re.search(r"\bBRIDGE\b", block, re.I):
                return None
            return family
    return None


def content_hash(payload: dict) -> str:
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def record(native_id: str, source_url: str, observed: date | None, payload: dict) -> dict:
    return {
        "source_slug": "kytc-unit-bid-tabulations",
        "source_native_id": native_id,
        "source_url": source_url,
        "observed_at": datetime.combine(observed, datetime.min.time(), tzinfo=timezone.utc).isoformat() if observed else None,
        "content_hash": content_hash(payload),
        "parser_version": "bridge-surface-kytc-v2",
        "provisional_entity_type": "bridge_surface_work_item",
        "longitude": None,
        "latitude": None,
        "within_pilot_radius": None,
        "raw_payload": payload,
    }


def discover() -> list[tuple[str, date | None]]:
    html = get(INDEX_URL).text
    soup = BeautifulSoup(html, "html.parser")
    cutoff = date.today() - timedelta(days=LOOKBACK_YEARS * 366)
    docs: dict[str, date | None] = {}
    for a in soup.find_all("a", href=True):
        href = urljoin(INDEX_URL, a["href"])
        label = " ".join(a.stripped_strings).lower()
        context = " ".join(a.parent.stripped_strings).lower() if a.parent else label
        if ".pdf" not in href.lower() or "unit bid tab" not in label + " " + context:
            continue
        d = url_date(href)
        if d and d < cutoff:
            continue
        docs[href] = d
    return sorted(docs.items(), key=lambda x: x[1] or date.min, reverse=True)[:MAX_DOCUMENTS]


def parse_document(url: str, fallback_date: date | None) -> list[dict]:
    text = pdf_text(url).replace("\r", "\n")
    blocks = [b for b in CALL_RE.split(text) if re.search(r"\bCall:\s*\d+\b", b, re.I)]
    out: list[dict] = []
    for block in blocks:
        contract_match = CONTRACT_RE.search(block)
        if not contract_match:
            continue
        contract_id = contract_match.group(1)
        call_match = CALL_NO_RE.search(block)
        call_no = call_match.group(1) if call_match else None
        let_match = DATE_LET_RE.search(block)
        letting = parse_short_date(let_match.group(1)) if let_match else fallback_date
        county_match = COUNTY_RE.search(block)
        county = re.sub(r"\s+", " ", county_match.group(1)).strip() if county_match else None
        low_match = LOW_BIDDER_RE.search(block)
        low_bidder = re.sub(r"\s+", " ", low_match.group(1)).strip()[:250] if low_match else None
        prop_match = PROPOSAL_RE.search(block)
        proposal = re.sub(r"\s+", " ", prop_match.group(1)).strip()[:500] if prop_match else None
        header_lines = [x.strip() for x in block.splitlines()[:12] if x.strip()]
        project_title = next((x for x in header_lines if not re.search(r"^(Call:|KYTC|BID TABS|Date Run|Number of Bidders|ENGINEERS ESTIMATE|Apparent Low Bidder|Prop Line)", x, re.I)), None)
        bridge_refs_block = sorted(set(m.group(0).upper() for m in KY_BRIDGE_RE.finditer(block)))
        for line in block.splitlines():
            m = ITEM_LINE_RE.match(line)
            if not m:
                continue
            proposal_line, body = m.groups()
            family = classify(body, block)
            if not family:
                continue
            bridge_match = KY_BRIDGE_RE.search(body)
            bridge_ref = bridge_match.group(0).upper() if bridge_match else (bridge_refs_block[0] if len(bridge_refs_block) == 1 else None)
            payload = {
                "state_code": "KY",
                "record_kind": "bid_item",
                "letting_date": letting.isoformat() if letting else None,
                "contract_id": contract_id,
                "call_number": call_no,
                "county_name": county,
                "project_title": project_title,
                "proposal_description": proposal,
                "bridge_reference": bridge_ref,
                "bridge_references_in_contract": bridge_refs_block,
                "proposal_line": proposal_line,
                "item_code": None,
                "item_description": body[:1200],
                "surface_work_family_hint": family,
                "vendor_name": low_bidder,
                "contract_context": re.sub(r"\s+", " ", block[:2500]).strip(),
            }
            native = f"{letting or fallback_date or 'unknown'}|{contract_id}|{proposal_line}|{family}|{bridge_ref or 'contract'}"
            out.append(record(native, url, letting or fallback_date, payload))
    dedup = {(r["source_slug"], r["source_native_id"]): r for r in out}
    return list(dedup.values())


def upload(rows: list[dict]) -> int:
    inserted = 0
    for i in range(0, len(rows), BATCH_SIZE):
        inserted += int(rpc("internal_ingest_raw_records", {"records": rows[i:i+BATCH_SIZE]}) or 0)
    return inserted


def main() -> None:
    docs = discover()
    print(f"KYTC v2 documents: {len(docs)}", flush=True)
    all_rows: list[dict] = []
    for url, d in docs:
        rows = parse_document(url, d)
        print(f"KYTC v2 {d} {url}: {len(rows)} records", flush=True)
        all_rows.extend(rows)
    all_rows = list({(r["source_slug"], r["source_native_id"]): r for r in all_rows}.values())
    if not all_rows:
        raise RuntimeError("KYTC v2 parsed zero bridge surface-work records")
    inserted = upload(all_rows)
    print(f"KYTC v2 complete: parsed={len(all_rows)} ingested={inserted}", flush=True)


if __name__ == "__main__":
    main()
