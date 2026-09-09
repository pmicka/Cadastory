#!/usr/bin/env python3
"""Bounded, resumable Scout document-evidence worker.

Source files exist only inside TemporaryDirectory. The worker persists hashes,
page references, short excerpts, normalized facts, and outcomes; never media.
"""
from __future__ import annotations

import hashlib, html, ipaddress, json, os, re, socket, subprocess, tempfile, uuid
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests

SUPABASE_URL=os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY=os.environ["SUPABASE_SERVICE_ROLE_KEY"]
BATCH_SIZE=int(os.getenv("SCOUT_DOCUMENT_BATCH_SIZE","3"))
RULE_PACK=os.getenv("SCOUT_DOCUMENT_RULE_PACK") or None
MIN_PRIORITY=int(os.getenv("SCOUT_DOCUMENT_MIN_PRIORITY","0"))
MAX_SOURCE_BYTES=int(os.getenv("SCOUT_DOCUMENT_MAX_SOURCE_BYTES",str(50*1024*1024)))
WORKER_ID=os.getenv("GITHUB_RUN_ID",f"local-{uuid.uuid4()}")
DRY_RUN=os.getenv("SCOUT_DOCUMENT_DRY_RUN","").lower() in {"1","true","yes"}
TIMEOUT=(20,120)
UA="Scout-Cadastory-Document-Evidence/1.0"

SESSION=requests.Session()
SESSION.headers.update({"User-Agent":UA})
DB=requests.Session()
DB.headers.update({"apikey":SERVICE_KEY,"Authorization":f"Bearer {SERVICE_KEY}","Content-Type":"application/json","User-Agent":UA})

def rpc(name,payload=None):
    r=DB.post(f"{SUPABASE_URL}/rest/v1/rpc/{name}",json=payload or {},timeout=TIMEOUT)
    if not r.ok: raise RuntimeError(f"RPC {name}: HTTP {r.status_code}: {r.text[:1000]}")
    return r.json()

def safe_url(value):
    u=urlparse(value)
    if u.scheme not in {"http","https"} or not u.hostname or u.username or u.password: raise ValueError("only credential-free http(s) URLs are allowed")
    for info in socket.getaddrinfo(u.hostname,u.port or (443 if u.scheme=="https" else 80),type=socket.SOCK_STREAM):
        ip=ipaddress.ip_address(info[4][0])
        if not ip.is_global: raise ValueError("source resolves to a non-public address")
    return value

def fetch(url,dest):
    current=safe_url(url)
    for _ in range(6):
        with SESSION.get(current,stream=True,allow_redirects=False,timeout=TIMEOUT) as r:
            if r.is_redirect:
                current=safe_url(urljoin(current,r.headers["Location"])); continue
            r.raise_for_status()
            total=0; digest=hashlib.sha256()
            with dest.open("wb") as f:
                for chunk in r.iter_content(1024*1024):
                    if not chunk: continue
                    total+=len(chunk)
                    if total>MAX_SOURCE_BYTES: raise ValueError("source exceeds byte limit")
                    digest.update(chunk); f.write(chunk)
            return current,r.status_code,(r.headers.get("Content-Type") or "").split(";")[0].lower(),digest.hexdigest()
    raise ValueError("too many redirects")

def pdf_pages(path):
    info=subprocess.run(["pdfinfo",str(path)],check=True,text=True,capture_output=True).stdout
    match=re.search(r"^Pages:\s+(\d+)",info,re.M); count=int(match.group(1)) if match else 0
    title=(re.search(r"^Title:\s*(.+)$",info,re.M) or [None,None])[1]
    pages=[]
    for n in range(1,count+1):
        p=subprocess.run(["pdftotext","-f",str(n),"-l",str(n),"-layout",str(path),"-"],text=True,capture_output=True,check=True)
        text=re.sub(r"\s+"," ",p.stdout).strip()
        if text: pages.append((n,text))
    return title,count,pages

def html_document(path,base):
    raw=path.read_text("utf-8",errors="replace")
    title_match=re.search(r"<title[^>]*>(.*?)</title>",raw,re.I|re.S)
    title=html.unescape(re.sub(r"<[^>]+>"," ",title_match.group(1))).strip() if title_match else None
    links=[]
    for href in re.findall(r"href\s*=\s*[\"']([^\"']+)",raw,re.I):
        absolute=urljoin(base,html.unescape(href))
        if urlparse(absolute).path.lower().endswith(".pdf"): links.append(absolute)
    text=html.unescape(re.sub(r"<script\b.*?</script>|<style\b.*?</style>|<[^>]+>"," ",raw,flags=re.I|re.S))
    return title,[(1,re.sub(r"\s+"," ",text).strip())],list(dict.fromkeys(links))[:5]

def excerpt(text,match,span=300):
    a=max(0,match.start()-span); b=min(len(text),match.end()+span)
    return text[a:b].strip()

def water_pack(job,pages):
    name=(job["target_context"].get("name") or "").strip()
    identity=re.compile(re.escape(name),re.I) if len(name)>=4 else None
    family=re.compile(r"\b(pede(?:sphere|st[a]?l)|pedosphere|composite elevated|fluted[ -]column|hydropil+l?ar|multi[ -]?column|double ellipsoidal|toro[ -]?ellipsoidal)\b",re.I)
    supports=re.compile(r"\b(\d+|four|five|six|seven|eight)\s*(?:[- ]inch\s+)?(?:tubular\s+)?(?:legs?|columns?)\b|\b(?:support\s+legs?|tank\s+legs?)\b",re.I)
    bracing=re.compile(r"\b(cross[ -]?brac(?:e|ed|ing)|brac(?:e|ed|ing)|struts?|windage rods?)\b",re.I)
    facts=[]
    for page,text in pages:
        if identity and not identity.search(text): continue
        hits=[m for p in (family,supports,bracing) for m in p.finditer(text)]
        if not hits: continue
        f=family.search(text); s=supports.search(text); b=bracing.search(text)
        normalized={"asset_name":name,"family_term":f.group(0).lower() if f else None,"multiple_support_signal":bool(s),"cross_bracing_explicit":bool(b)}
        if f and re.search(r"pedesphere|pedosphere|composite elevated|fluted[ -]column|hydropil",f.group(0),re.I): normalized.update({"support_geometry":"single_pedestal","cross_bracing_status":"absent_by_explicit_taxonomy"})
        elif s and b: normalized.update({"support_geometry":"multi_column","cross_bracing_status":"present","morphology_class":"multi_column_cross_braced","operator_assessment":"challenging"})
        elif s: normalized.update({"support_geometry":"multi_column","cross_bracing_status":"unknown"})
        first=min(hits,key=lambda x:x.start())
        facts.append({"domain_fact_kind":"water_tank_morphology","normalized_fact":normalized,"page_start":page,"page_end":page,"evidence_excerpt":excerpt(text,first),"confidence":0.97 if s and b else 0.86,"classification_reason":"Asset name and explicit structural terminology occur on the same extracted page; absent terms are not treated as negative evidence.","extraction_rule":"water_tank_morphology_v1","extraction_version":"1.0.0","canonical_writeback_status":"pending_review"})
    return facts

def facade_pack(job,pages):
    ctx=job["target_context"]; name=(ctx.get("display_name") or "").strip()
    if ctx.get("identity_status") in {"ambiguous_identity","hold_identity_review"}: return []
    identity=re.compile(re.escape(name),re.I) if len(name)>=6 else None
    terms=re.compile(r"\b(EIFS|stucco|brick veneer|brick|masonry|CMU|precast|cast stone|limestone|sandstone|terra cotta|GFRC|concrete|metal panels?|ACM|aluminum composite|siding|curtain wall|storefront|window wall|unitized|stick-built|aluminum-framed glazing|vision glass|spandrel|IGU|glazing replacement|window replacement)\b",re.I)
    facts=[]
    for page,text in pages:
        if identity and not identity.search(text): continue
        matches=list(terms.finditer(text))
        if not matches: continue
        values=sorted({m.group(0).lower() for m in matches})
        facts.append({"domain_fact_kind":"facade_material_or_glazing","normalized_fact":{"asset_name":name,"documented_terms":values},"page_start":page,"page_end":page,"evidence_excerpt":excerpt(text,matches[0]),"confidence":0.88,"classification_reason":"Identity-qualified document page explicitly names facade/glazing systems; keyword absence is not evidence of absence.","extraction_rule":"facade_material_v1","extraction_version":"1.0.0","canonical_writeback_status":"pending_review"})
    return facts

PACKS={"water_tank_morphology_v1":water_pack,"facade_material_v1":facade_pack,"glazing_system_v1":facade_pack}

def checkpoint(job,state,source=None,evidence=None,summary=None,error=None,next_step=None,retry=0):
    payload={"p_job_id":job["id"],"p_lease_token":job["lease_token"],"p_state":state,"p_source_attempt":source,"p_evidence":evidence or [],"p_result_summary":summary or {},"p_last_error":error,"p_next_research_step":next_step,"p_retry_after_seconds":retry}
    if DRY_RUN: print(json.dumps(payload,indent=2)); return
    print(rpc("internal_checkpoint_document_evidence_job",payload),flush=True)

def process(job):
    pack=PACKS.get(job["rule_pack"])
    if not pack: return checkpoint(job,"needs_human_review",error="unknown rule pack",next_step="install supported rule pack")
    candidates=[x for x in job["target_context"].get("source_candidates",[]) if isinstance(x,dict) and x.get("url")]
    if not candidates: return checkpoint(job,"no_evidence",summary={"reason":"no known source URL"},next_step="discover one bounded authoritative source URL")
    candidate=candidates[min(job["attempt_count"]-1,len(candidates)-1)]
    source={"source_url":candidate["url"],"source_authority":candidate.get("authority"),"retrieval_status":"failed"}
    try:
        with tempfile.TemporaryDirectory(prefix="scout-doc-") as td:
            path=Path(td)/"source"; final,status,ctype,sha=fetch(candidate["url"],path)
            source.update({"final_url":final,"http_status":status,"content_type":ctype,"content_sha256":sha})
            if ctype=="application/pdf" or path.read_bytes()[:5]==b"%PDF-": title,count,pages=pdf_pages(path); linked=[]
            else: title,pages,linked=html_document(path,final); count=1
            source.update({"retrieval_status":"indexed","document_title":title,"page_count":count,"indexed_page_count":len(pages),"extraction_metadata":{"linked_pdf_candidates":linked,"media_retained":False}})
            facts=pack(job,pages)
            if facts:
                complete=any(f["normalized_fact"].get("cross_bracing_status") in {"present","absent_by_explicit_taxonomy"} for f in facts) if job["rule_pack"]=="water_tank_morphology_v1" else False
                return checkpoint(job,"evidence_found" if complete else "partial",source,facts,{"facts":len(facts),"pages_indexed":len(pages)},next_step="canonical review/writeback" if complete else "seek explicit missing structural detail")
            state="needs_human_review" if job["attempt_count"]>=len(candidates) else "no_evidence"
            return checkpoint(job,state,source,summary={"pages_indexed":len(pages)},next_step="try one materially distinct authoritative source" if state=="no_evidence" else "add a new authoritative source candidate")
    except Exception as exc:
        source["failure_reason"]=str(exc)[:1000]
        state="exhausted" if job["attempt_count"]>=job["max_attempts"] else "retryable_failure"
        checkpoint(job,state,source,error=str(exc),next_step="retry or choose a materially distinct source",retry=3600)

def main():
    if not 1<=BATCH_SIZE<=25: raise SystemExit("SCOUT_DOCUMENT_BATCH_SIZE must be 1..25")
    jobs=rpc("internal_claim_document_evidence_jobs",{"p_worker_id":WORKER_ID,"p_batch_size":BATCH_SIZE,"p_lease_minutes":60,"p_rule_pack":RULE_PACK,"p_min_priority":MIN_PRIORITY})
    print(f"claimed={len(jobs)} worker={WORKER_ID}",flush=True)
    for job in jobs: process(job)

if __name__=="__main__": main()
