#!/usr/bin/env python3
"""Scout public-document evidence worker.

Claims durable enrichment jobs from Supabase, downloads source documents only
into a temporary directory, extracts text with Poppler, applies conservative
rule packs, and sends derived evidence/provenance back through service-role RPCs.
Original PDFs/images are never retained by Scout or uploaded as artifacts.

Required:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
  pdftotext and pdfinfo on PATH

Optional:
  SCOUT_DOCUMENT_BATCH_SIZE=6
  SCOUT_DOCUMENT_RULE_PACK=water_tank_morphology_v1|facade_material_glazing_v1
  SCOUT_DOCUMENT_MAX_BYTES=41943040
"""
from __future__ import annotations

import argparse
import hashlib
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
from urllib.parse import urljoin, urlparse
import urllib.robotparser

import requests

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
BATCH_SIZE = int(os.getenv("SCOUT_DOCUMENT_BATCH_SIZE", "6"))
RULE_PACK = os.getenv("SCOUT_DOCUMENT_RULE_PACK") or None
MAX_BYTES = int(os.getenv("SCOUT_DOCUMENT_MAX_BYTES", str(40 * 1024 * 1024)))
TIMEOUT = (20, 120)
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}
USER_AGENT = "Scout-Cadastory-Document-Evidence/1.0 (+public-evidence; no-source-media-retention)"
PSC_CASE_YEAR_URL = "https://psc.ky.gov/Case/searchCases/{year}"
PSC_CASE_URL = "https://psc.ky.gov/Case/ViewCaseFilings/{case_number}"
GENERIC_TOKENS = {
    "water", "tank", "tanks", "elevated", "storage", "street", "st", "road", "rd",
    "drive", "dr", "lane", "ln", "highway", "hwy", "building", "center", "centre",
}
WORD_NUMBERS = {"three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10}

SESSION = requests.Session()
SESSION.headers.update({"User-Agent": USER_AGENT, "Accept": "text/html,application/pdf;q=0.9,*/*;q=0.5"})
if SUPABASE_URL and SERVICE_KEY:
    API = requests.Session()
    API.headers.update({
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
    })
else:
    API = None


class LinkExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[tuple[str, str]] = []
        self._href: str | None = None
        self._parts: list[str] = []
        self.text_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag.lower() == "a":
            self._href = dict(attrs).get("href")
            self._parts = []

    def handle_data(self, data: str) -> None:
        clean = " ".join(data.split())
        if clean:
            self.text_parts.append(clean)
            if self._href is not None:
                self._parts.append(clean)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self._href is not None:
            self.links.append((self._href, " ".join(self._parts)))
            self._href = None
            self._parts = []

    @property
    def text(self) -> str:
        return "\n".join(self.text_parts)


def norm(value: object) -> str:
    text = html.unescape(str(value or "")).lower()
    text = text.replace("&", " and ").replace("#", " no ")
    text = re.sub(r"\bnumber\b", " no ", text)
    text = re.sub(r"\bno\.?\s*", " no ", text)
    return " ".join(re.findall(r"[a-z0-9]+", text))


def core_tokens(value: object) -> list[str]:
    return [t for t in norm(value).split() if t not in GENERIC_TOKENS and len(t) >= 3]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def finding_fingerprint(job_id: str, url: str, page: int | None, codes: list[str], excerpt: str) -> str:
    payload = "|".join([job_id, url, str(page or 0), ",".join(sorted(codes)), norm(excerpt)])
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def rpc(name: str, payload: dict | None = None):
    if API is None:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    last_error: Exception | None = None
    for attempt in range(1, 7):
        response = None
        try:
            response = API.post(url, json=payload or {}, timeout=TIMEOUT)
            if response.ok:
                return response.json()
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"RPC {name}: HTTP {response.status_code}: {response.text[:1200]}")
            last_error = RuntimeError(f"RPC {name}: transient HTTP {response.status_code}")
        except requests.RequestException as exc:
            last_error = exc
        if attempt < 6:
            time.sleep(min(20, 2 ** attempt))
    raise RuntimeError(f"RPC {name} failed after retries: {last_error}")


def require_poppler() -> None:
    for binary in ("pdftotext", "pdfinfo"):
        try:
            subprocess.run([binary, "-v"], capture_output=True, check=False, timeout=10)
        except FileNotFoundError as exc:
            raise SystemExit(f"{binary} is required on PATH") from exc


_ROBOTS: dict[str, urllib.robotparser.RobotFileParser] = {}


def robots_allows(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.hostname in {"psc.ky.gov", "www.psc.ky.gov"}:
        return True
    root = f"{parsed.scheme}://{parsed.netloc}"
    if root not in _ROBOTS:
        rp = urllib.robotparser.RobotFileParser()
        robots_url = urljoin(root, "/robots.txt")
        try:
            response = SESSION.get(robots_url, timeout=(8, 15), allow_redirects=True)
            if response.status_code == 404:
                rp.parse([])
            elif response.ok:
                rp.parse(response.text.splitlines())
            else:
                return False
        except requests.RequestException:
            return False
        _ROBOTS[root] = rp
    return _ROBOTS[root].can_fetch(USER_AGENT, url)


def fetch(url: str) -> tuple[bytes, str, str | None]:
    if not url.lower().startswith(("http://", "https://")):
        raise ValueError("unsupported URL scheme")
    if not robots_allows(url):
        raise PermissionError(f"robots policy does not allow fetch: {url}")
    with SESSION.get(url, stream=True, allow_redirects=True, timeout=TIMEOUT) as response:
        response.raise_for_status()
        length = int(response.headers.get("Content-Length") or 0)
        if length and length > MAX_BYTES:
            raise RuntimeError(f"document exceeds {MAX_BYTES} byte limit: {length}")
        chunks: list[bytes] = []
        total = 0
        for chunk in response.iter_content(1024 * 1024):
            if not chunk:
                continue
            total += len(chunk)
            if total > MAX_BYTES:
                raise RuntimeError(f"download exceeded {MAX_BYTES} byte limit")
            chunks.append(chunk)
        data = b"".join(chunks)
        return data, response.url, response.headers.get("Content-Type")


def parse_html(data: bytes) -> LinkExtractor:
    parser = LinkExtractor()
    parser.feed(data.decode("utf-8", errors="replace"))
    return parser


def document_authority(url: str) -> str:
    host = (urlparse(url).hostname or "").lower()
    if host.endswith("psc.ky.gov"):
        return "Kentucky Public Service Commission"
    if host.endswith("ky.gov") or host.endswith("kentucky.gov"):
        return "Commonwealth of Kentucky public source"
    if host.endswith(".gov"):
        return f"Public agency source ({host})"
    return host or "Public source"


def pdf_pages(data: bytes, work: Path) -> tuple[list[str], str | None]:
    pdf = work / "source.pdf"
    txt = work / "source.txt"
    pdf.write_bytes(data)
    title = None
    try:
        info = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True, timeout=30, check=False)
        for line in info.stdout.splitlines():
            if line.lower().startswith("title:"):
                title = line.split(":", 1)[1].strip() or None
                break
    except subprocess.TimeoutExpired:
        pass
    proc = subprocess.run(
        ["pdftotext", "-layout", "-enc", "UTF-8", str(pdf), str(txt)],
        capture_output=True, text=True, timeout=150, check=False,
    )
    if proc.returncode != 0 or not txt.exists():
        return [], title
    return [p.strip() for p in txt.read_text("utf-8", errors="replace").split("\f")], title


def identity_confidence(job: dict, text: str) -> float:
    ntext = f" {norm(text)} "
    candidates: list[str] = [str(job.get("display_name") or "")]
    ctx = job.get("context") or {}
    for key in ("tank_name", "historic_address_text"):
        if ctx.get(key):
            candidates.append(str(ctx[key]))
    for value in ctx.get("historic_resource_names") or []:
        if value:
            candidates.append(str(value))
    ref = norm(ctx.get("historic_reference_number"))
    if ref and len(ref) >= 4 and f" {ref} " in ntext:
        return 0.995
    for candidate in candidates:
        nc = norm(candidate)
        if len(nc) >= 4 and f" {nc} " in ntext:
            return 0.995
    tokens = core_tokens(job.get("display_name"))
    if tokens and all(re.search(rf"\b{re.escape(t)}\b", ntext) for t in tokens):
        if len(tokens) >= 2 or (len(tokens) == 1 and len(tokens[0]) >= 5):
            return 0.96
    return 0.55


def excerpt_around(text: str, patterns: list[re.Pattern[str]], radius: int = 550) -> str:
    hits = [m.start() for p in patterns for m in p.finditer(text)]
    if not hits:
        return ""
    start = max(0, min(hits) - radius)
    end = min(len(text), max(hits) + radius)
    return " ".join(text[start:end].split())


WATER_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("tank.explicit_pedesphere", re.compile(r"\bped[eo]sphere\b", re.I)),
    ("tank.explicit_composite", re.compile(r"\bcomposite\s+(?:elevated\s+)?(?:water\s+)?(?:storage\s+)?tank\b|\bcomposite\s+elevated\b", re.I)),
    ("tank.explicit_fluted_column", re.compile(r"\bfluted[-\s]+column\b", re.I)),
    ("tank.explicit_multi_column", re.compile(r"\bmulti[-\s]+column\b", re.I)),
    ("tank.explicit_bracing", re.compile(r"\b(?:cross|diagonal)[-\s]+brac(?:e|es|ed|ing)\b|\bbracing\b", re.I)),
    ("tank.explicit_struts", re.compile(r"\bstruts?\b", re.I)),
    ("tank.explicit_windage_rods", re.compile(r"\bwindage[-\s]+rods?\b", re.I)),
    ("tank.explicit_standpipe", re.compile(r"\bstandpipe\b", re.I)),
    ("tank.explicit_ground_storage", re.compile(r"\bground[-\s]+storage\s+tank\b|\bground[-\s]+supported\s+tank\b", re.I)),
    ("tank.design_double_ellipsoidal", re.compile(r"\bdouble[-\s]+ellipsoid(?:al)?\b", re.I)),
    ("tank.design_toroellipsoidal", re.compile(r"\btoro[-\s]*ellipsoid(?:al)?\b", re.I)),
]
LEG_RE = re.compile(r"\b(?P<count>\d+|three|four|five|six|seven|eight|nine|ten)\s+(?:[\w.-]+\s+){0,4}(?:support\s+)?legs?\b", re.I)

FACADE_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("facade.glazing.curtain_wall", re.compile(r"\bcurtain[-\s]+wall\b", re.I)),
    ("facade.glazing.window_wall", re.compile(r"\bwindow[-\s]+wall\b", re.I)),
    ("facade.glazing.unitized", re.compile(r"\bunitized\s+(?:curtain\s+wall|glazing|wall)\b", re.I)),
    ("facade.glazing.stick_built", re.compile(r"\bstick[-\s]+built\s+(?:curtain\s+wall|glazing|wall)\b", re.I)),
    ("facade.glazing.storefront", re.compile(r"\b(?:aluminum[-\s]+)?storefront\b", re.I)),
    ("facade.material.brick", re.compile(r"\bbrick\s+veneer\b|\bexterior\s+brick\b", re.I)),
    ("facade.material.precast_concrete", re.compile(r"\bprecast\s+concrete(?:\s+(?:panel|panels|wall|walls))?\b", re.I)),
    ("facade.material.concrete", re.compile(r"\bexposed\s+concrete\b|\bconcrete\s+facade\b", re.I)),
    ("facade.material.cmu", re.compile(r"\b(?:exterior\s+)?(?:cmu|concrete\s+masonry\s+unit(?:s)?)\b", re.I)),
    ("facade.material.eifs", re.compile(r"\bEIFS\b|\bexterior\s+insulation\s+and\s+finish\s+system\b", re.I)),
    ("facade.material.stucco", re.compile(r"\bstucco\b", re.I)),
    ("facade.material.metal_panel", re.compile(r"\b(?:architectural\s+)?metal\s+(?:wall\s+)?panels?\b", re.I)),
    ("facade.material.limestone", re.compile(r"\blimestone\s+(?:veneer|cladding|facade|panel|panels)\b", re.I)),
    ("facade.material.stone", re.compile(r"\bstone\s+(?:veneer|cladding|facade)\b", re.I)),
    ("facade.material.glass", re.compile(r"\bglass\s+(?:curtain\s+wall|facade|wall|cladding)\b", re.I)),
    ("facade.material.wood", re.compile(r"\bwood\s+(?:siding|cladding|facade)\b", re.I)),
]
PRIMARY_MATERIAL_RE = re.compile(
    r"\b(?:primary|predominant|main)\s+(?:exterior|facade)\s+(?:material|finish|cladding)\s*[:=-]?\s*"
    r"(?P<material>brick|precast\s+concrete|concrete|cmu|eifs|stucco|metal\s+panels?|limestone|stone|glass|wood)", re.I,
)


def analyze_page(job: dict, text: str, source_url: str, source_sha: str, page_number: int | None, title: str | None) -> dict | None:
    rule_pack = job["rule_pack"]
    identity = identity_confidence(job, text)
    if rule_pack == "water_tank_morphology_v1":
        matches = [(code, pattern) for code, pattern in WATER_PATTERNS if pattern.search(text)]
        leg = LEG_RE.search(text)
        codes = [c for c, _ in matches]
        extracted: dict[str, object] = {}
        if leg:
            codes.append("tank.explicit_multiple_legs")
            raw = leg.group("count").lower()
            extracted["support_leg_count"] = int(raw) if raw.isdigit() else WORD_NUMBERS.get(raw)
        if not codes:
            return None
        patterns = [p for _, p in matches]
        if leg:
            patterns.append(LEG_RE)
        excerpt = excerpt_around(text, patterns)
    elif rule_pack == "facade_material_glazing_v1":
        matches = [(code, pattern) for code, pattern in FACADE_PATTERNS if pattern.search(text)]
        primary = PRIMARY_MATERIAL_RE.search(text)
        codes = [c for c, _ in matches]
        extracted = {}
        if primary:
            raw = norm(primary.group("material"))
            extracted["primary_material_phrase"] = primary.group(0)
            mapping = {
                "brick": "facade.material.brick", "precast concrete": "facade.material.precast_concrete",
                "concrete": "facade.material.concrete", "cmu": "facade.material.cmu", "eifs": "facade.material.eifs",
                "stucco": "facade.material.stucco", "metal panels": "facade.material.metal_panel",
                "metal panel": "facade.material.metal_panel", "limestone": "facade.material.limestone",
                "stone": "facade.material.stone", "glass": "facade.material.glass", "wood": "facade.material.wood",
            }
            if mapping.get(raw):
                extracted["primary_material_code"] = mapping[raw]
                extracted["raw_facade_material"] = primary.group("material")
        if not codes and not primary:
            return None
        patterns = [p for _, p in matches] + ([PRIMARY_MATERIAL_RE] if primary else [])
        excerpt = excerpt_around(text, patterns)
    else:
        return None

    codes = sorted(set(codes))
    confidence = 0.99 if identity >= 0.95 else 0.72
    return {
        "fingerprint": finding_fingerprint(str(job["id"]), source_url, page_number, codes, excerpt),
        "source_url": source_url,
        "source_authority": document_authority(source_url),
        "source_kind": "public_document",
        "document_title": title,
        "page_number": page_number,
        "evidence_excerpt": excerpt[:4000],
        "evidence_codes": codes,
        "extracted_values": extracted,
        "confidence": confidence,
        "identity_confidence": identity,
        "decision_state": "documented" if identity >= 0.95 else "signal_to_investigate",
        "source_sha256": source_sha,
        "auto_apply": False,
    }


def aggregate_auto_candidate(job: dict, findings: list[dict]) -> tuple[dict | None, bool]:
    exact = [f for f in findings if float(f.get("identity_confidence", 0)) >= 0.95]
    if not exact:
        return None, False
    by_doc: dict[tuple[str, str], list[dict]] = {}
    for f in exact:
        by_doc.setdefault((f["source_url"], f.get("source_sha256") or ""), []).append(f)

    candidates: list[dict] = []
    categories: set[str] = set()
    for (url, source_sha), items in by_doc.items():
        codes = sorted({c for item in items for c in item.get("evidence_codes", [])})
        extracted: dict[str, object] = {}
        for item in items:
            if item.get("extracted_values", {}).get("support_leg_count"):
                extracted["support_leg_count"] = item["extracted_values"]["support_leg_count"]
        chosen_codes = list(codes)
        category = None
        if job["rule_pack"] == "water_tank_morphology_v1":
            code_set = set(codes)
            families: list[str] = []
            favorable_codes = {
                "tank.explicit_pedesphere", "tank.explicit_composite", "tank.explicit_fluted_column"
            } & code_set
            ground_codes = {"tank.explicit_standpipe", "tank.explicit_ground_storage"} & code_set
            multi_codes = {"tank.explicit_multi_column", "tank.explicit_multiple_legs"} & code_set
            bracing_codes = {"tank.explicit_bracing", "tank.explicit_struts", "tank.explicit_windage_rods"} & code_set
            if favorable_codes:
                families.append("favorable")
            if ground_codes:
                families.append("not_applicable")
            if multi_codes and bracing_codes:
                families.append("challenging")
            elif multi_codes:
                families.append("partial")
            if len(set(families)) > 1:
                return None, True
            if len(favorable_codes) > 1 or len(ground_codes) > 1:
                return None, True
            category = families[0] if families else None
            if category is None:
                continue
        else:
            glazing = [c for c in codes if c.startswith("facade.glazing.")]
            primary_material_codes = {
                item.get("extracted_values", {}).get("primary_material_code") for item in items
                if item.get("extracted_values", {}).get("primary_material_code")
            }
            chosen_codes = []
            if glazing:
                chosen_codes.extend(glazing)
            if len(primary_material_codes) == 1:
                chosen_codes.extend(primary_material_codes)
                for item in items:
                    if item.get("extracted_values", {}).get("raw_facade_material"):
                        extracted["raw_facade_material"] = item["extracted_values"]["raw_facade_material"]
                        break
            if not chosen_codes:
                continue
            category = "facade_direct"
        categories.add(category)
        excerpt = " | ".join(item["evidence_excerpt"] for item in items[:3])[:4000]
        candidates.append({
            "_category": category,
            "fingerprint": finding_fingerprint(str(job["id"]), url, None, chosen_codes, excerpt + "|aggregate"),
            "source_url": url,
            "source_authority": items[0].get("source_authority"),
            "source_kind": "public_document",
            "document_title": items[0].get("document_title"),
            "page_number": None,
            "evidence_excerpt": excerpt,
            "evidence_codes": sorted(set(chosen_codes)),
            "extracted_values": extracted,
            "confidence": 0.995,
            "identity_confidence": max(float(i["identity_confidence"]) for i in items),
            "decision_state": "documented",
            "source_sha256": source_sha,
            "auto_apply": True,
        })

    if job["rule_pack"] == "water_tank_morphology_v1":
        terminal = categories - {"partial"}
        if len(terminal) > 1 or (terminal and "partial" in categories and terminal != {"challenging"}):
            return None, True
        rank = {"challenging": 4, "favorable": 4, "not_applicable": 4, "partial": 1}
        candidates.sort(key=lambda c: rank.get(c.get("_category", "partial"), 0), reverse=True)
    if job["rule_pack"] == "facade_material_glazing_v1" and len(candidates) > 1:
        sigs = {tuple(sorted(c["evidence_codes"])) for c in candidates}
        if len(sigs) > 1:
            common = set(candidates[0]["evidence_codes"])
            for c in candidates[1:]:
                common &= set(c["evidence_codes"])
            common = {c for c in common if c.startswith("facade.glazing.")}
            if not common:
                return None, True
            chosen = candidates[0].copy()
            chosen["evidence_codes"] = sorted(common)
            chosen["extracted_values"] = {}
            chosen["fingerprint"] = finding_fingerprint(str(job["id"]), chosen["source_url"], None, chosen["evidence_codes"], chosen["evidence_excerpt"] + "|common")
            chosen.pop("_category", None)
            return chosen, False
    if candidates:
        candidates[0].pop("_category", None)
    return (candidates[0] if candidates else None), False


def case_years(attempt: int) -> range:
    current = time.gmtime().tm_year
    if attempt <= 1:
        return range(max(2018, current - 8), current + 1)
    if attempt == 2:
        return range(2010, current + 1)
    return range(2005, current + 1)


_PSC_YEAR_CACHE: dict[int, list[tuple[str, str]]] = {}


def psc_cases_for_organization(organization: str, attempt: int, project_numbers: list[str]) -> list[tuple[str, int]]:
    orgn = norm(organization)
    org_tokens = set(t for t in core_tokens(organization) if t not in {"district", "system", "works", "utilities", "utility", "department", "commission", "association"})
    found: list[tuple[str, int]] = []
    for year in case_years(attempt):
        if year not in _PSC_YEAR_CACHE:
            try:
                data, _, _ = fetch(PSC_CASE_YEAR_URL.format(year=year))
                parser = parse_html(data)
                text = parser.text
                matches = list(re.finditer(r"Case\s+Number:\s*(\d{4}-\d+)", text, re.I))
                rows: list[tuple[str, str]] = []
                for idx, match in enumerate(matches):
                    end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
                    rows.append((match.group(1), text[match.start():end]))
                _PSC_YEAR_CACHE[year] = rows
            except Exception as exc:
                print(f"PSC year {year} fetch failed: {exc}", flush=True)
                _PSC_YEAR_CACHE[year] = []
        for case_number, segment in _PSC_YEAR_CACHE[year]:
            nseg = norm(segment)
            match_org = orgn in nseg
            if not match_org and org_tokens:
                present = sum(1 for t in org_tokens if re.search(rf"\b{re.escape(t)}\b", nseg))
                match_org = present / len(org_tokens) >= 0.8
            if not match_org or "service type water" not in nseg:
                continue
            score = 0
            if any(norm(p) and norm(p) in nseg for p in project_numbers):
                score += 15
            if any(t in nseg for t in core_tokens(organization)):
                score += 1
            if any(x in nseg for x in ("certificate", "construction", "financing", "rate adjustment", "regular")):
                score += 4
            if any(x in nseg for x in ("purchased water adjustment", "training", "alleged failure")):
                score -= 6
            found.append((case_number, score))
    found.sort(key=lambda x: (-x[1], x[0]))
    max_cases = 4 if attempt <= 1 else (8 if attempt == 2 else 12)
    return found[:max_cases]


def link_score(href: str, anchor: str, job: dict) -> int:
    text = norm(href + " " + anchor)
    score = 0
    for word, points in {
        "engineering": 8, "inspection": 9, "contract": 6, "drawing": 8, "drawings": 8,
        "specification": 7, "specifications": 7, "application": 5, "exhibit": 4,
        "response": 3, "tank": 6, "rehab": 5, "rehabilitation": 5,
    }.items():
        if word in text:
            score += points
    for token in core_tokens(job.get("display_name")):
        if token in text:
            score += 6
    for p in (job.get("context") or {}).get("project_numbers") or []:
        if norm(p) in text:
            score += 8
    return score


def discover_psc_documents(job: dict) -> list[str]:
    org = job.get("organization_name") or ""
    if not org:
        return []
    attempt = int(job.get("attempt_count") or 1)
    pnums = [str(x) for x in (job.get("context") or {}).get("project_numbers") or []]
    urls: list[tuple[str, int]] = []
    for case_number, case_score in psc_cases_for_organization(org, attempt, pnums):
        try:
            data, final, _ = fetch(PSC_CASE_URL.format(case_number=case_number))
            parser = parse_html(data)
            page_identity = identity_confidence(job, parser.text)
            case_bonus = 10 if page_identity >= 0.95 else case_score
            docs: list[tuple[str, int]] = []
            for href, anchor in parser.links:
                absolute = urljoin(final, href)
                if ".pdf" not in absolute.lower():
                    continue
                docs.append((absolute, link_score(absolute, anchor, job) + case_bonus))
            docs.sort(key=lambda x: x[1], reverse=True)
            limit = 6 if attempt <= 1 else (12 if attempt == 2 else 20)
            urls.extend(docs[:limit])
        except Exception as exc:
            print(f"PSC case {case_number} discovery failed: {exc}", flush=True)
    seen = set()
    result = []
    for url, _ in sorted(urls, key=lambda x: x[1], reverse=True):
        if url not in seen:
            seen.add(url)
            result.append(url)
    return result[:30]


def discover_from_root(root: str, job: dict) -> list[str]:
    attempt = int(job.get("attempt_count") or 1)
    max_pages = 6 if attempt <= 1 else (15 if attempt == 2 else 30)
    max_depth = 1 if attempt <= 1 else 2
    queue = [(root, 0)]
    seen: set[str] = set()
    documents: list[tuple[str, int]] = []
    host = urlparse(root).hostname
    while queue and len(seen) < max_pages:
        url, depth = queue.pop(0)
        if url in seen:
            continue
        seen.add(url)
        if ".pdf" in urlparse(url).path.lower():
            documents.append((url, link_score(url, "", job) + 20))
            continue
        try:
            data, final, content_type = fetch(url)
        except Exception as exc:
            print(f"crawl fetch failed {url}: {exc}", flush=True)
            continue
        if "pdf" in (content_type or "").lower():
            documents.append((final, link_score(final, "", job) + 20))
            continue
        parser = parse_html(data)
        if identity_confidence(job, parser.text) >= 0.95:
            documents.append((final + "#scout-html", 30))
        if depth >= max_depth:
            continue
        links = []
        for href, anchor in parser.links:
            absolute = urljoin(final, href).split("#", 1)[0]
            parsed = urlparse(absolute)
            if parsed.scheme not in {"http", "https"} or parsed.hostname != host:
                continue
            score = link_score(absolute, anchor, job)
            if ".pdf" in parsed.path.lower():
                documents.append((absolute, score + 15))
            elif score > 0 or any(t in norm(anchor + " " + absolute) for t in core_tokens(job.get("display_name"))):
                links.append((absolute, score))
        links.sort(key=lambda x: x[1], reverse=True)
        queue.extend((u, depth + 1) for u, _ in links[:8])
    documents.sort(key=lambda x: x[1], reverse=True)
    out, used = [], set()
    for url, _ in documents:
        if url not in used:
            used.add(url)
            out.append(url)
    return out[:25]


def process_document(job: dict, url: str, work: Path) -> tuple[list[dict], str | None]:
    html_marker = url.endswith("#scout-html")
    fetch_url = url[:-11] if html_marker else url
    try:
        data, final, content_type = fetch(fetch_url)
    except Exception as exc:
        return [], str(exc)
    source_sha = sha256_bytes(data)
    findings: list[dict] = []
    if html_marker or (content_type and "html" in content_type.lower()):
        parser = parse_html(data)
        f = analyze_page(job, parser.text, final, source_sha, None, Path(urlparse(final).path).name or final)
        if f:
            findings.append(f)
        return findings, None
    if ".pdf" in urlparse(final).path.lower() or (content_type and "pdf" in content_type.lower()) or data.startswith(b"%PDF"):
        try:
            pages, title = pdf_pages(data, work)
        except subprocess.TimeoutExpired:
            return [], "pdftotext timeout"
        if not pages or not any(p.strip() for p in pages):
            return [], "PDF contains no extractable text"
        document_identity = max((identity_confidence(job, page) for page in pages if page.strip()), default=0.55)
        for index, page in enumerate(pages, 1):
            if not page.strip():
                continue
            f = analyze_page(job, page, final, source_sha, index, title or Path(urlparse(final).path).name)
            if f:
                if document_identity >= 0.95:
                    f["identity_confidence"] = max(float(f["identity_confidence"]), document_identity)
                    f["confidence"] = max(float(f["confidence"]), 0.99)
                    f["decision_state"] = "documented"
                    f["extracted_values"]["document_identity_basis"] = "exact_identity_elsewhere_in_same_document"
                findings.append(f)
        return findings, None
    return [], f"unsupported content type: {content_type}"


def process_job(job: dict) -> tuple[str, list[dict], str | None]:
    urls: list[str] = []
    errors: list[str] = []
    for root in job.get("source_roots") or []:
        if isinstance(root, str) and root.startswith(("http://", "https://")):
            try:
                urls.extend(discover_from_root(root, job))
            except Exception as exc:
                errors.append(f"root {root}: {exc}")
    if job.get("rule_pack") == "water_tank_morphology_v1":
        try:
            urls.extend(discover_psc_documents(job))
        except Exception as exc:
            errors.append(f"PSC discovery: {exc}")
    urls = list(dict.fromkeys(urls))
    doc_limit = 18 if int(job.get("attempt_count") or 1) <= 1 else 30
    urls = urls[:doc_limit]
    findings: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="scout-document-evidence-") as temp_dir:
        work_root = Path(temp_dir)
        for idx, url in enumerate(urls):
            work = work_root / str(idx)
            work.mkdir()
            result, error = process_document(job, url, work)
            findings.extend(result)
            if error:
                errors.append(f"{url}: {error}")
            time.sleep(0.15)
    auto, conflict = aggregate_auto_candidate(job, findings)
    if conflict:
        return "needs_review", findings, "conflicting direct document evidence"
    if auto:
        findings = [f for f in findings if f["fingerprint"] != auto["fingerprint"]]
        findings.append(auto)
        return "completed", findings, None
    if findings:
        return "no_evidence", findings, None
    if urls and errors and len(errors) >= len(urls):
        return "failed", [], "; ".join(errors[:8])
    return "no_evidence", [], None


def self_test() -> None:
    water = {
        "id": "00000000-0000-0000-0000-000000000001", "rule_pack": "water_tank_morphology_v1",
        "display_name": "DRISCOLL", "context": {"tank_name": "DRISCOLL"},
    }
    text = "DRISCOLL TANK. The structure has four 20-inch tubular legs, two sets of channel struts, and windage-rod connections."
    f = analyze_page(water, text, "https://psc.ky.gov/test.pdf", "abc", 12, "Inspection")
    assert f and f["identity_confidence"] >= 0.95
    assert "tank.explicit_multiple_legs" in f["evidence_codes"]
    assert "tank.explicit_struts" in f["evidence_codes"] and "tank.explicit_windage_rods" in f["evidence_codes"]
    auto, conflict = aggregate_auto_candidate(water, [f])
    assert auto and not conflict and auto["auto_apply"]

    facade = {
        "id": "00000000-0000-0000-0000-000000000002", "rule_pack": "facade_material_glazing_v1",
        "display_name": "Jefferson Medical Pavilion", "context": {},
    }
    text2 = "Jefferson Medical Pavilion - Exterior elevations. Primary exterior material: brick. New unitized curtain wall at the east facade."
    f2 = analyze_page(facade, text2, "https://example.gov/drawings.pdf", "def", 4, "A201")
    assert f2 and "facade.glazing.curtain_wall" in f2["evidence_codes"]
    assert f2["extracted_values"].get("primary_material_code") == "facade.material.brick"
    auto2, conflict2 = aggregate_auto_candidate(facade, [f2])
    assert auto2 and not conflict2
    assert "facade.material.brick" in auto2["evidence_codes"]
    print("self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not SUPABASE_URL or not SERVICE_KEY:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    if not 1 <= BATCH_SIZE <= 50:
        raise SystemExit("SCOUT_DOCUMENT_BATCH_SIZE must be between 1 and 50")
    require_poppler()
    seed = rpc("internal_seed_document_evidence_jobs")
    print(f"seed={json.dumps(seed, sort_keys=True)}", flush=True)
    jobs = rpc("internal_claim_document_evidence_jobs", {"p_limit": BATCH_SIZE, "p_rule_pack": RULE_PACK})
    print(f"claimed={len(jobs)}", flush=True)
    for job in jobs:
        print(f"job {job['id']} {job['rule_pack']} {job['display_name']} attempt={job['attempt_count']}", flush=True)
        try:
            outcome, findings, error = process_job(job)
        except Exception as exc:
            outcome, findings, error = "failed", [], f"unhandled worker error: {type(exc).__name__}: {exc}"
        result = rpc("internal_complete_document_evidence_job", {
            "p_job_id": job["id"], "p_outcome": outcome, "p_findings": findings, "p_error": error,
        })
        print(f"complete={json.dumps(result, sort_keys=True)}", flush=True)


if __name__ == "__main__":
    main()
