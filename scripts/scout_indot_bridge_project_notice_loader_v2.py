#!/usr/bin/env python3
"""Load authoritative INDOT Notice-to-Highway-Contractors bridge surface-work project context.

Research ingestion only. This collector intentionally handles only INDOT REG-NTC
notices. Bid tabs remain a separate source, and KYTC uses its dedicated v2 loader.

The current INDOT notice format exposes contract ID, contract description,
Project Control No. values, district/county and route/location context. Those
fields provide the deterministic project/asset crosswalk needed to resolve bid
items to Scout bridges without relying on contract-local "Bridge No." labels.

Required env:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Optional env:
  SCOUT_INDOT_NTC_LOOKBACK_YEARS=5
  SCOUT_INDOT_NTC_MAX_DOCUMENTS=120
  SCOUT_INDOT_NTC_MAX_PAGES=300
  SCOUT_INDOT_NTC_BATCH_SIZE=100
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
LOOKBACK_YEARS = int(os.getenv("SCOUT_INDOT_NTC_LOOKBACK_YEARS", "5"))
MAX_DOCUMENTS = int(os.getenv("SCOUT_INDOT_NTC_MAX_DOCUMENTS", "120"))
MAX_PAGES = int(os.getenv("SCOUT_INDOT_NTC_MAX_PAGES", "300"))
BATCH_SIZE = int(os.getenv("SCOUT_INDOT_NTC_BATCH_SIZE", "100"))
ROOT_URL = "https://secure.in.gov/indot/doing-business-with-indot/home/contracts/"
SOURCE_SLUG = "indot-notice-to-highway-contractors"
TIMEOUT = (30, 180)
MAX_ATTEMPTS = 6
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}

if not 1 <= LOOKBACK_YEARS <= 15:
    raise SystemExit("SCOUT_INDOT_NTC_LOOKBACK_YEARS must be 1..15")
if not 1 <= MAX_DOCUMENTS <= 500:
    raise SystemExit("SCOUT_INDOT_NTC_MAX_DOCUMENTS must be 1..500")
if not 20 <= MAX_PAGES <= 1000:
    raise SystemExit("SCOUT_INDOT_NTC_MAX_PAGES must be 20..1000")
if not 1 <= BATCH_SIZE <= 500:
    raise SystemExit("SCOUT_INDOT_NTC_BATCH_SIZE must be 1..500")

HTTP = requests.Session()
HTTP.headers.update({"User-Agent": "Scout-Cadastory-INDOT-Bridge-Notice/2.0"})
DB = requests.Session()
DB.headers.update({
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "User-Agent": "Scout-Cadastory-INDOT-Bridge-Notice/2.0",
})

NTC_FILE_RE = re.compile(r"(?P<date>20\d{6})-REG-NTC(?:[-_A-Za-z0-9.]*)?\.pdf(?:$|\?)", re.I)
CONTRACT_RE = re.compile(r"\b([BRMS]\s*-?\s*\d{4,6}(?:-A)?)\b", re.I)
PROJECT_RE = re.compile(r"\b(20\d{5}|25\d{5}|24\d{5}|23\d{5}|22\d{5}|21\d{5})\b")
DATE_TEXT_RE = re.compile(r"Letting\s+Date\s*&?\s*Time\s*:\s*([A-Za-z]+\s+\d{1,2},\s+20\d{2})", re.I)
COUNTY_RE = re.compile(r"\b([A-Z][A-Z .'-]*(?:,\s*[A-Z][A-Z .'-]*)*)\s+COUNT(?:Y|IES)\b")
ROUTE_RE = re.compile(r"\b(?:ON\s+)?((?:I|US|SR)\s*-?\s*\d{1,4})\b", re.I)

# Keep the project-scope family narrow. Generic bridge maintenance is useful
# context but is not surface-preservation evidence by itself.
SURFACE_CONTRACT_RE = re.compile(
    r"\bBRIDGE\s+(?:PAINTING|PAINT|COATING|COAT(?:ING)?)\b|"
    r"\bCLEAN\s*(?:&|AND)\s*PAINT\s+STRUCTURAL\s+STEEL\b",
    re.I,
)


@dataclass(frozen=True)
class NoticeDoc:
    url: str
    letting_date: date


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
    last: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        response = None
        try:
            response = HTTP.get(url, timeout=TIMEOUT)
            if response.ok:
                return response
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"HTTP {response.status_code}: {url}: {response.text[:500]}")
            last = RuntimeError(f"transient HTTP {response.status_code}: {url}")
        except requests.RequestException as exc:
            last = exc
        if attempt >= MAX_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"GET failed after {MAX_ATTEMPTS} attempts: {url}: {last}") from last


def rpc(name: str, payload: dict):
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    last: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        response = None
        try:
            response = DB.post(url, json=payload, timeout=TIMEOUT)
            if response.ok:
                return response.json() if response.text else None
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"RPC {name} HTTP {response.status_code}: {response.text[:1500]}")
            last = RuntimeError(f"RPC {name} transient HTTP {response.status_code}")
        except requests.RequestException as exc:
            last = exc
        if attempt >= MAX_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"RPC {name} failed: {last}") from last


def absolute_links(page_url: str, html: str) -> list[tuple[str, str, str]]:
    soup = BeautifulSoup(html, "html.parser")
    out: list[tuple[str, str, str]] = []
    for anchor in soup.find_all("a", href=True):
        href = urljoin(page_url, anchor.get("href", "").strip())
        label = " ".join(anchor.stripped_strings)
        row = anchor.find_parent("tr")
        context = " ".join(row.stripped_strings) if row else (
            " ".join(anchor.parent.stripped_strings) if anchor.parent else label
        )
        if href.startswith("http"):
            out.append((href, label, context))
    return out


def ntc_date_from_url(url: str) -> date | None:
    m = NTC_FILE_RE.search(url)
    if not m:
        return None
    try:
        return datetime.strptime(m.group("date"), "%Y%m%d").date()
    except ValueError:
        return None


def discover_notice_docs() -> list[NoticeDoc]:
    """Crawl only INDOT contract pages and collect authoritative REG-NTC PDFs."""
    cutoff = date.today() - timedelta(days=LOOKBACK_YEARS * 366)
    queue = [ROOT_URL]
    seen_pages: set[str] = set()
    docs: dict[str, NoticeDoc] = {}

    while queue and len(seen_pages) < MAX_PAGES:
        url = queue.pop(0)
        if url in seen_pages:
            continue
        seen_pages.add(url)
        try:
            response = get(url)
        except Exception as exc:
            print(f"WARN INDOT discovery page failed {url}: {exc}", flush=True)
            continue

        for href, label, context in absolute_links(url, response.text):
            parsed = urlparse(href)
            if parsed.netloc not in {"secure.in.gov", "www.in.gov", "in.gov"}:
                continue
            lower_href = href.lower()

            letting = ntc_date_from_url(href)
            if letting is not None:
                if letting >= cutoff:
                    docs[href] = NoticeDoc(href, letting)
                continue

            # Follow only HTML-ish pages within INDOT's contract-information tree.
            if "/indot/doing-business-with-indot/home/contracts/" not in lower_href:
                continue
            if any(lower_href.split("?", 1)[0].endswith(ext) for ext in (".pdf", ".xls", ".xlsx", ".doc", ".docx", ".zip")):
                continue
            if href not in seen_pages and href not in queue:
                # Contract archives/letting pages are discoverable either by URL or label/context.
                haystack = f"{href} {label} {context}".lower()
                if any(term in haystack for term in ("letting", "contract", "archive", "202")):
                    queue.append(href)

    ordered = sorted(docs.values(), key=lambda d: d.letting_date, reverse=True)
    print(
        f"INDOT NTC discovery pages={len(seen_pages)} docs={len(ordered)} "
        f"cutoff={cutoff.isoformat()}",
        flush=True,
    )
    return ordered[:MAX_DOCUMENTS]


def pdf_text(url: str) -> str:
    response = get(url)
    reader = PdfReader(io.BytesIO(response.content))
    parts: list[str] = []
    for page_no, page in enumerate(reader.pages, start=1):
        try:
            parts.append(f"\n[[PAGE {page_no}]]\n" + (page.extract_text() or ""))
        except Exception as exc:
            print(f"WARN PDF page extraction failed {url} p{page_no}: {exc}", flush=True)
    return "\n".join(parts)


def normalize_contract(value: str) -> str:
    value = re.sub(r"\s+", "", value.upper())
    if value and value[0].isalpha() and not value.startswith(value[0] + "-"):
        value = value[0] + "-" + value[1:].lstrip("-")
    return value


def normalize_excerpt(value: str, limit: int = 3500) -> str:
    return re.sub(r"\s+", " ", value).strip()[:limit]


def contract_blocks(text: str) -> list[tuple[str, str]]:
    matches = list(CONTRACT_RE.finditer(text))
    out: list[tuple[str, str]] = []
    for idx, match in enumerate(matches):
        start = match.start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        block = text[start:end]
        # Avoid duplicating references to a contract ID in prose by requiring the
        # contract section to contain a Project Control header or Call/District cues.
        if not re.search(r"Project\s+Control\s+No\.|\bCall\b.*\bDistrict\b", block[:1800], re.I | re.S):
            continue
        out.append((normalize_contract(match.group(1)), block))
    return out


def contract_description(contract_id: str, block: str) -> str | None:
    # Modern NTC: "B -46898-A IDIQ, BRIDGE MAINTENANCE AND REPAIR" followed by Call/District.
    normalized = re.sub(r"[\t ]+", " ", block.replace("\r", "\n"))
    first_lines = [ln.strip() for ln in normalized.splitlines()[:12] if ln.strip()]
    for line in first_lines:
        if re.search(re.escape(contract_id.replace("-", "")), line.replace(" ", "").replace("-", ""), re.I):
            # Remove the contract token even if source spacing differs.
            desc = CONTRACT_RE.sub("", line, count=1).strip(" :-")
            if desc:
                return desc[:500]
    # Fallback to text between the first contract token and Call.
    m = re.search(CONTRACT_RE.pattern + r"\s+(.{3,500}?)\s+Call\b", normalize_excerpt(block, 1800), re.I)
    return m.group(2).strip()[:500] if m else None


def parse_notice(doc: NoticeDoc) -> list[dict]:
    text = pdf_text(doc.url).replace("\r", "\n")
    text_date = None
    date_match = DATE_TEXT_RE.search(text)
    if date_match:
        try:
            text_date = datetime.strptime(date_match.group(1), "%B %d, %Y").date()
        except ValueError:
            pass
    letting = text_date or doc.letting_date

    records: list[dict] = []
    for contract_id, block in contract_blocks(text):
        desc = contract_description(contract_id, block)
        scope_text = f"{desc or ''} {block[:2200]}"
        if not SURFACE_CONTRACT_RE.search(scope_text):
            continue

        project_ids = sorted(set(PROJECT_RE.findall(block)))
        counties = sorted(set(m.group(1).strip() for m in COUNTY_RE.finditer(block)))
        routes = sorted(set(re.sub(r"\s*-?\s*", " ", m.group(1).upper()).strip() for m in ROUTE_RE.finditer(block)))
        district_match = re.search(r"Call\s+([A-Za-z ]+?)\s+District\b", block, re.I)
        district = district_match.group(1).strip() if district_match else None
        completion_match = re.search(r"([A-Za-z]+\s+\d{1,2},\s+20\d{2})\s+\n?\s*[A-Z]?\(?[A-Z]?\)?\s*\n?\s*Completion\s+Date", block, re.I)
        completion = None
        if completion_match:
            try:
                completion = datetime.strptime(completion_match.group(1), "%B %d, %Y").date()
            except ValueError:
                pass

        work_type = "BRIDGE PAINTING" if re.search(r"BRIDGE\s+PAINT", scope_text, re.I) else "BRIDGE COATING"
        context = normalize_excerpt(block)
        ids = project_ids or [None]
        for project_id in ids:
            native = f"notice-v2|{letting.isoformat()}|{contract_id}|{project_id or 'contract'}"
            payload = {
                "state_code": "IN",
                "record_kind": "project_notice",
                "letting_date": letting.isoformat(),
                "completion_date": completion.isoformat() if completion else None,
                "contract_id": contract_id,
                "project_id": project_id,
                "project_ids": project_ids,
                "contract_description": desc,
                "work_type": work_type,
                "district": district,
                "county_names": counties,
                "route_candidates": routes,
                "location_text": context,
                "surface_work_family_hint": "steel_coating" if work_type == "BRIDGE PAINTING" else "protective_coating",
                "source_document_family": "INDOT_REG_NTC",
            }
            encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            records.append({
                "source_slug": SOURCE_SLUG,
                "source_native_id": native,
                "source_url": doc.url,
                "observed_at": datetime.combine(letting, datetime.min.time(), tzinfo=timezone.utc).isoformat(),
                "content_hash": hashlib.sha256(encoded).hexdigest(),
                "parser_version": "bridge-surface-indot-notice-v2",
                "provisional_entity_type": "bridge_surface_project",
                "longitude": None,
                "latitude": None,
                "within_pilot_radius": None,
                "raw_payload": payload,
            })

    return list({(r["source_slug"], r["source_native_id"]): r for r in records}.values())


def upload(rows: list[dict]) -> int:
    inserted = 0
    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start:start + BATCH_SIZE]
        inserted += int(rpc("internal_ingest_raw_records", {"records": batch}) or 0)
    return inserted


def main() -> None:
    docs = discover_notice_docs()
    if not docs:
        raise RuntimeError("INDOT NTC discovery found zero REG-NTC documents; source layout may have drifted")

    all_rows: list[dict] = []
    docs_with_surface = 0
    for doc in docs:
        try:
            rows = parse_notice(doc)
            if rows:
                docs_with_surface += 1
                print(f"INDOT NTC {doc.letting_date} {doc.url}: {len(rows)} surface project records", flush=True)
            all_rows.extend(rows)
        except Exception as exc:
            print(f"WARN INDOT NTC parse failed {doc.url}: {exc}", flush=True)

    all_rows = list({(r["source_slug"], r["source_native_id"]): r for r in all_rows}.values())
    if not all_rows:
        raise RuntimeError(
            f"INDOT NTC parsed zero bridge painting/coating project records across {len(docs)} notices"
        )

    inserted = upload(all_rows)
    contracts = len({r["raw_payload"].get("contract_id") for r in all_rows})
    projects = len({r["raw_payload"].get("project_id") for r in all_rows if r["raw_payload"].get("project_id")})
    stats = {
        "documents_checked": len(docs),
        "documents_with_surface_scope": docs_with_surface,
        "surface_project_records": len(all_rows),
        "contracts": contracts,
        "projects": projects,
        "new_raw_versions": inserted,
        "parser_version": "bridge-surface-indot-notice-v2",
    }
    print(json.dumps(stats, indent=2, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
