#!/usr/bin/env python3
"""Load authoritative KYTC/INDOT bridge surface-work letting evidence into Scout.

Research ingestion only. The loader writes item/project records to ingest.raw_records through
public.internal_ingest_raw_records(). It does NOT create opportunities or alter scoring.

Requirements:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Optional:
  SCOUT_BRIDGE_SURFACE_SOURCE=both|kytc|indot
  SCOUT_BRIDGE_SURFACE_MAX_DOCUMENTS=30
  SCOUT_BRIDGE_SURFACE_LOOKBACK_YEARS=5
  SCOUT_BRIDGE_SURFACE_BATCH_SIZE=100

Dependencies:
  requests beautifulsoup4 pypdf
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import re
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup
from pypdf import PdfReader

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
SOURCE_MODE = os.getenv("SCOUT_BRIDGE_SURFACE_SOURCE", "both").strip().lower()
MAX_DOCUMENTS = int(os.getenv("SCOUT_BRIDGE_SURFACE_MAX_DOCUMENTS", "30"))
LOOKBACK_YEARS = int(os.getenv("SCOUT_BRIDGE_SURFACE_LOOKBACK_YEARS", "5"))
BATCH_SIZE = int(os.getenv("SCOUT_BRIDGE_SURFACE_BATCH_SIZE", "100"))
TIMEOUT = (30, 180)
MAX_ATTEMPTS = 6
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}

if SOURCE_MODE not in {"both", "kytc", "indot"}:
    raise SystemExit("SCOUT_BRIDGE_SURFACE_SOURCE must be both, kytc, or indot")
if not 1 <= MAX_DOCUMENTS <= 500:
    raise SystemExit("SCOUT_BRIDGE_SURFACE_MAX_DOCUMENTS must be 1..500")
if not 1 <= LOOKBACK_YEARS <= 15:
    raise SystemExit("SCOUT_BRIDGE_SURFACE_LOOKBACK_YEARS must be 1..15")
if not 1 <= BATCH_SIZE <= 500:
    raise SystemExit("SCOUT_BRIDGE_SURFACE_BATCH_SIZE must be 1..500")

KYTC_INDEX = "https://transportation.ky.gov/Construction-Procurement/Pages/Unit-Bid-Tabulations.aspx"
INDOT_CONTRACTS = "https://www.in.gov/indot/doing-business-with-indot/home/contracts/"

HTTP = requests.Session()
HTTP.headers.update({"User-Agent": "Scout-Cadastory-Bridge-Surface-Loader/1.0"})
DB = requests.Session()
DB.headers.update(
    {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Scout-Cadastory-Bridge-Surface-Loader/1.0",
    }
)

DATE_RE = re.compile(r"\b(0?[1-9]|1[0-2])/(0?[1-9]|[12]\d|3[01])/(20\d{2})\b")
KY_BRIDGE_RE = re.compile(r"\b\d{3}B\d{5}[A-Z]?\b", re.I)
CONTRACT_KY_RE = re.compile(r"\b(?:CONTRACT\s*(?:ID)?\s*[:#]?\s*)?(\d{6})\b", re.I)
INDOT_CONTRACT_RE = re.compile(r"\b([BRMRS]+\s*-?\s*\d{4,6}(?:-A)?)\b", re.I)
INDOT_PROJECT_RE = re.compile(r"\b(20\d{5})\b")

POSITIVE_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("steel_clean_and_paint", re.compile(r"CLEAN\s*&\s*PAINT\s+STRUCTURAL\s+STEEL", re.I)),
    ("steel_cleaning_prep", re.compile(r"CLEAN\s+STEEL\s+BRIDGE", re.I)),
    ("steel_coating", re.compile(r"COAT\s+STEEL\s+BRIDGE", re.I)),
    ("abrasive_blast_prep", re.compile(r"\bBLAST\s+CLEANING\b", re.I)),
    ("bridge_cleaning", re.compile(r"\bBRIDGE\s+CLEANING\b", re.I)),
    ("concrete_coating", re.compile(r"\bCONCRETE\s+COATING\b", re.I)),
    ("concrete_sealing", re.compile(r"\bCONCRETE\s+SEALING\b", re.I)),
    ("bearing_clean_and_coat", re.compile(r"(?:CLEAN.*COAT.*BEARING|BEARING.*CLEAN.*COAT)", re.I)),
]
NEGATIVE_RE = re.compile(
    r"PAVE(?:MENT)?\s+STRIP|PAVEMENT\s+MARK|REINFORCEMENT.*EPOXY[- ]*COATED|"
    r"EPOXY[- ]*COATED.*REINFORCEMENT",
    re.I,
)
ITEM_CODE_RE = re.compile(
    r"\b(08434|08549|24981EC|24982EC|23378EC|619-11052|619-51859|619-12459)\b",
    re.I,
)


@dataclass(frozen=True)
class Document:
    url: str
    letting_date: date | None
    kind: str


def retry_delay(attempt: int, response: requests.Response | None = None) -> float:
    if response is not None:
        value = response.headers.get("Retry-After")
        if value:
            try:
                return min(60.0, max(1.0, float(value)))
            except ValueError:
                pass
    return float(min(30, 2**attempt))


def get(url: str) -> requests.Response:
    last_error: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        response = None
        try:
            response = HTTP.get(url, timeout=TIMEOUT)
            if response.ok:
                return response
            if response.status_code not in TRANSIENT_HTTP:
                response.raise_for_status()
            last_error = RuntimeError(f"HTTP {response.status_code}: {url}")
        except requests.RequestException as exc:
            last_error = exc
        if attempt == MAX_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"GET failed after {MAX_ATTEMPTS} attempts: {url}: {last_error}")


def rpc(name: str, payload: dict) -> object:
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    last_error: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        response = None
        try:
            response = DB.post(url, json=payload, timeout=TIMEOUT)
            if response.ok:
                return response.json()
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"RPC {name}: HTTP {response.status_code}: {response.text[:1200]}")
            last_error = RuntimeError(f"RPC {name}: transient HTTP {response.status_code}")
        except requests.RequestException as exc:
            last_error = exc
        if attempt == MAX_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"RPC {name} failed: {last_error}")


def parse_date(text: str | None) -> date | None:
    if not text:
        return None
    match = DATE_RE.search(text)
    if match:
        month, day, year = map(int, match.groups())
        try:
            return date(year, month, day)
        except ValueError:
            return None
    for fmt in ("%B %d, %Y", "%b %d, %Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(text.strip(), fmt).date()
        except ValueError:
            pass
    return None


def cutoff_date() -> date:
    return date.today() - timedelta(days=LOOKBACK_YEARS * 366)


def absolute_links(page_url: str, html: str) -> list[tuple[str, str]]:
    soup = BeautifulSoup(html, "html.parser")
    out: list[tuple[str, str]] = []
    for anchor in soup.find_all("a", href=True):
        href = urljoin(page_url, anchor.get("href", "").strip())
        label = " ".join(anchor.stripped_strings)
        if href.startswith("http"):
            out.append((href, label))
    return out


def pdf_pages(url: str) -> list[str]:
    response = get(url)
    reader = PdfReader(io.BytesIO(response.content))
    pages: list[str] = []
    for page in reader.pages:
        try:
            pages.append(page.extract_text() or "")
        except Exception as exc:  # malformed public PDFs should not kill the whole run
            print(f"WARN PDF page extraction failed {url}: {exc}", flush=True)
            pages.append("")
    return pages


def classify(text: str) -> str | None:
    if NEGATIVE_RE.search(text):
        return None
    for family, pattern in POSITIVE_PATTERNS:
        if pattern.search(text):
            return family
    return None


def content_hash(payload: dict) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def raw_record(source_slug: str, native_id: str, source_url: str, payload: dict, observed: date | None) -> dict:
    return {
        "source_slug": source_slug,
        "source_native_id": native_id,
        "source_url": source_url,
        "observed_at": datetime.combine(observed, datetime.min.time(), tzinfo=timezone.utc).isoformat() if observed else None,
        "content_hash": content_hash(payload),
        "parser_version": "bridge-surface-v1",
        "provisional_entity_type": "bridge_surface_work_item" if payload.get("item_description") else "bridge_surface_project",
        "longitude": None,
        "latitude": None,
        "within_pilot_radius": None,
        "raw_payload": payload,
    }


def upload(records: list[dict]) -> int:
    inserted = 0
    for start in range(0, len(records), BATCH_SIZE):
        batch = records[start : start + BATCH_SIZE]
        inserted += int(rpc("internal_ingest_raw_records", {"records": batch}) or 0)
    return inserted


def discover_kytc() -> list[Document]:
    response = get(KYTC_INDEX)
    links = absolute_links(KYTC_INDEX, response.text)
    docs: dict[str, Document] = {}
    soup = BeautifulSoup(response.text, "html.parser")
    for anchor in soup.find_all("a", href=True):
        href = urljoin(KYTC_INDEX, anchor["href"])
        context = " ".join(anchor.parent.stripped_strings) if anchor.parent else " ".join(anchor.stripped_strings)
        label = " ".join(anchor.stripped_strings)
        if "unit bid tab" not in (label + " " + context).lower():
            continue
        if ".pdf" not in href.lower():
            continue
        letting = parse_date(context)
        if letting and letting < cutoff_date():
            continue
        docs[href] = Document(href, letting, "kytc_unit_bid")
    ordered = sorted(docs.values(), key=lambda d: d.letting_date or date.min, reverse=True)
    return ordered[:MAX_DOCUMENTS]


def parse_kytc_document(doc: Document) -> list[dict]:
    records: list[dict] = []
    pages = pdf_pages(doc.url)
    for page_no, page_text in enumerate(pages, start=1):
        normalized = re.sub(r"[\t ]+", " ", page_text)
        if not any(pattern.search(normalized) for _, pattern in POSITIVE_PATTERNS):
            continue
        contract_candidates = re.findall(r"(?:Contract\s*(?:ID)?\s*[:#]?\s*)(\d{6})", normalized, re.I)
        contract_id = contract_candidates[-1] if contract_candidates else None
        lines = [line.strip() for line in normalized.splitlines() if line.strip()]
        for idx, line in enumerate(lines):
            window = " ".join(lines[max(0, idx - 1) : min(len(lines), idx + 2)])
            family = classify(window)
            if not family:
                continue
            code_match = ITEM_CODE_RE.search(window)
            code = code_match.group(1).upper() if code_match else None
            bridge_match = KY_BRIDGE_RE.search(window)
            bridge_ref = bridge_match.group(0).upper() if bridge_match else None
            description = line
            if family == "abrasive_blast_prep" and not bridge_ref:
                # Generic blasting can be roadway/overlay work; retain only when bridge context is explicit.
                if "BRIDGE" not in window.upper() and not contract_id:
                    continue
            native = f"{doc.letting_date or 'unknown'}|{contract_id or 'unknown'}|p{page_no}|{code or family}|{bridge_ref or hashlib.sha1(window.encode()).hexdigest()[:10]}"
            payload = {
                "state_code": "KY",
                "record_kind": "bid_item",
                "letting_date": doc.letting_date.isoformat() if doc.letting_date else None,
                "contract_id": contract_id,
                "project_id": None,
                "bridge_reference": bridge_ref,
                "item_code": code,
                "item_description": description[:1000],
                "surface_work_family_hint": family,
                "vendor_name": None,
                "page_number": page_no,
                "raw_context": window[:2500],
            }
            records.append(raw_record("kytc-unit-bid-tabulations", native, doc.url, payload, doc.letting_date))
    return dedupe(records)


def discover_indot_letting_pages() -> list[str]:
    # Breadth-first discovery restricted to INDOT's contract-letting pages.
    queue = [INDOT_CONTRACTS]
    seen: set[str] = set()
    letting_pages: list[str] = []
    max_pages = max(30, MAX_DOCUMENTS * 4)
    while queue and len(seen) < max_pages:
        url = queue.pop(0)
        if url in seen:
            continue
        seen.add(url)
        try:
            response = get(url)
        except Exception as exc:
            print(f"WARN INDOT page fetch failed {url}: {exc}", flush=True)
            continue
        links = absolute_links(url, response.text)
        if url != INDOT_CONTRACTS:
            text = BeautifulSoup(response.text, "html.parser").get_text(" ", strip=True)
            if re.search(r"\b20\d{2}\b", text) and "letting" in text.lower():
                letting_pages.append(url)
        for href, label in links:
            parsed = urlparse(href)
            if parsed.netloc not in {"www.in.gov", "secure.in.gov"}:
                continue
            lower = href.lower()
            if "/indot/doing-business-with-indot/home/contracts/" not in lower:
                continue
            if ".pdf" in lower or ".xls" in lower or ".xlsx" in lower:
                continue
            if href not in seen and ("letting" in lower or "archive" in lower or "letting" in label.lower()):
                queue.append(href)
    # Freshest pages tend to be exposed first by INDOT; cap crawler work deterministically.
    return letting_pages[:MAX_DOCUMENTS]


def indot_documents() -> list[Document]:
    docs: dict[str, Document] = {}
    for page_url in discover_indot_letting_pages():
        try:
            response = get(page_url)
        except Exception:
            continue
        page_text = BeautifulSoup(response.text, "html.parser").get_text(" ", strip=True)
        letting = parse_date(page_text)
        if letting and letting < cutoff_date():
            continue
        for href, label in absolute_links(page_url, response.text):
            lower = (href + " " + label).lower()
            if ".pdf" not in href.lower():
                continue
            if "notice to contractor" in lower or "reg-ntc" in lower:
                docs[href] = Document(href, letting, "indot_notice")
            elif any(term in lower for term in ("bid tab", "unit tab", "official tab", "tabulation")):
                docs[href] = Document(href, letting, "indot_bid_tab")
    ordered = sorted(docs.values(), key=lambda d: d.letting_date or date.min, reverse=True)
    return ordered[:MAX_DOCUMENTS]


def normalize_indot_contract(value: str | None) -> str | None:
    if not value:
        return None
    return re.sub(r"\s+", "", value.upper()).replace("--", "-")


def parse_indot_notice(doc: Document) -> list[dict]:
    text = "\n".join(pdf_pages(doc.url))
    # Project blocks are intentionally kept even when bridge matching is unresolved.
    starts = [m.start() for m in re.finditer(r"PROJECT\s+NO\s*:", text, re.I)]
    if not starts:
        starts = [m.start() for m in re.finditer(r"\bDES\s*:", text, re.I)]
    starts.append(len(text))
    records: list[dict] = []
    for i in range(len(starts) - 1):
        block = re.sub(r"[\t ]+", " ", text[starts[i] : starts[i + 1]])
        if not re.search(r"BRIDGE\s+(?:PAINT|COAT)", block, re.I):
            continue
        project_match = INDOT_PROJECT_RE.search(block)
        project_id = project_match.group(0) if project_match else None
        contract_matches = INDOT_CONTRACT_RE.findall(block)
        contract_id = normalize_indot_contract(contract_matches[-1] if contract_matches else None)
        route = None
        route_match = re.search(r"\bROUTE\s*:\s*([^\n]+)", block, re.I)
        if route_match:
            route = route_match.group(1).strip()[:80]
        county = None
        county_match = re.search(r"\bCOUNTY\s*:\s*([^\n]+)", block, re.I)
        if county_match:
            county = county_match.group(1).strip()[:120]
        # Keep the full local context; downstream resolver can compare it to NBI route/location text.
        native = f"notice|{doc.letting_date or 'unknown'}|{contract_id or 'unknown'}|{project_id or hashlib.sha1(block.encode()).hexdigest()[:10]}"
        payload = {
            "state_code": "IN",
            "record_kind": "project_notice",
            "letting_date": doc.letting_date.isoformat() if doc.letting_date else None,
            "contract_id": contract_id,
            "project_id": project_id,
            "work_type": "BRIDGE PAINTING" if re.search(r"BRIDGE\s+PAINTING", block, re.I) else "BRIDGE COATING",
            "route": route,
            "county_name": county,
            "location_text": block[:3000],
        }
        records.append(raw_record("indot-notice-to-highway-contractors", native, doc.url, payload, doc.letting_date))
    return dedupe(records)


def parse_indot_bid_tab(doc: Document) -> list[dict]:
    records: list[dict] = []
    pages = pdf_pages(doc.url)
    for page_no, page_text in enumerate(pages, start=1):
        normalized = re.sub(r"[\t ]+", " ", page_text)
        if not any(pattern.search(normalized) for _, pattern in POSITIVE_PATTERNS):
            continue
        contract_match = re.search(r"Contract\s*ID\s*:\s*([^\n]+)", normalized, re.I)
        if not contract_match:
            values = INDOT_CONTRACT_RE.findall(normalized)
            contract_id = normalize_indot_contract(values[0] if values else None)
        else:
            contract_id = normalize_indot_contract(contract_match.group(1).split()[0])
        projects = sorted(set(INDOT_PROJECT_RE.findall(normalized)))
        completion_match = re.search(r"(\d{2}/\d{2}/\d{2})\s+COMPLETION\s+DATE", normalized, re.I)
        completion = None
        if completion_match:
            try:
                completion = datetime.strptime(completion_match.group(1), "%m/%d/%y").date()
            except ValueError:
                pass
        bidder_match = re.search(r"\(1\)\s+([A-Z0-9 &'.,-]+?)(?:\s+Unit\s+Price|\s+\(2\)|\n)", normalized, re.I)
        low_bidder = bidder_match.group(1).strip()[:200] if bidder_match else None
        lines = [line.strip() for line in normalized.splitlines() if line.strip()]
        for idx, line in enumerate(lines):
            window = " ".join(lines[max(0, idx - 1) : min(len(lines), idx + 2)])
            family = classify(window)
            if not family:
                continue
            code_match = ITEM_CODE_RE.search(window)
            code = code_match.group(1).upper() if code_match else None
            local_bridge_match = re.search(r"BRIDGE\s+NO\.?\s*(\d+)", window, re.I)
            bridge_ref = f"BRIDGE NO. {local_bridge_match.group(1)}" if local_bridge_match else None
            native = f"bidtab|{doc.letting_date or 'unknown'}|{contract_id or 'unknown'}|p{page_no}|{code or family}|{bridge_ref or hashlib.sha1(window.encode()).hexdigest()[:10]}"
            payload = {
                "state_code": "IN",
                "record_kind": "bid_item",
                "letting_date": doc.letting_date.isoformat() if doc.letting_date else None,
                "completion_date": completion.isoformat() if completion else None,
                "contract_id": contract_id,
                "project_id": projects[0] if len(projects) == 1 else None,
                "project_ids": projects,
                "bridge_reference": bridge_ref,
                "item_code": code,
                "item_description": line[:1000],
                "surface_work_family_hint": family,
                "vendor_name": low_bidder,
                "page_number": page_no,
                "raw_context": window[:2500],
            }
            records.append(raw_record("indot-bridge-bid-tabs", native, doc.url, payload, doc.letting_date))
    return dedupe(records)


def dedupe(records: list[dict]) -> list[dict]:
    by_key: dict[tuple[str, str], dict] = {}
    for record in records:
        by_key[(record["source_slug"], record["source_native_id"])] = record
    return list(by_key.values())


def run_kytc() -> tuple[int, int]:
    docs = discover_kytc()
    print(f"KYTC documents discovered: {len(docs)}", flush=True)
    records: list[dict] = []
    for doc in docs:
        try:
            parsed = parse_kytc_document(doc)
            print(f"KYTC {doc.letting_date} {doc.url}: {len(parsed)} surface-work records", flush=True)
            records.extend(parsed)
        except Exception as exc:
            print(f"WARN KYTC parse failed {doc.url}: {exc}", flush=True)
    records = dedupe(records)
    return len(records), upload(records) if records else 0


def run_indot() -> tuple[int, int]:
    docs = indot_documents()
    print(f"INDOT documents discovered: {len(docs)}", flush=True)
    records: list[dict] = []
    for doc in docs:
        try:
            parsed = parse_indot_notice(doc) if doc.kind == "indot_notice" else parse_indot_bid_tab(doc)
            print(f"INDOT {doc.kind} {doc.letting_date} {doc.url}: {len(parsed)} records", flush=True)
            records.extend(parsed)
        except Exception as exc:
            print(f"WARN INDOT parse failed {doc.url}: {exc}", flush=True)
    records = dedupe(records)
    return len(records), upload(records) if records else 0


def main() -> None:
    totals: dict[str, tuple[int, int]] = {}
    if SOURCE_MODE in {"both", "kytc"}:
        totals["kytc"] = run_kytc()
    if SOURCE_MODE in {"both", "indot"}:
        totals["indot"] = run_indot()
    print("Bridge surface-work ingestion complete:", totals, flush=True)
    if sum(found for found, _ in totals.values()) == 0:
        raise RuntimeError("No authoritative bridge surface-work records were parsed; investigate source/layout drift")


if __name__ == "__main__":
    main()
