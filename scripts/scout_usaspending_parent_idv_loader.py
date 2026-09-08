#!/usr/bin/env python3
"""Collect authoritative USAspending detail for resolved physical-FM parent IDVs."""
from __future__ import annotations
import hashlib, json, os, time
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote
import requests

API_ROOT="https://api.usaspending.gov/api/v2"
SUPABASE_URL=os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY=os.environ["SUPABASE_SERVICE_ROLE_KEY"]
TIMEOUT=(30,120)
api=requests.Session(); api.headers.update({"Accept":"application/json","User-Agent":"Scout-Cadastory-USAspending-Parent-IDV/1.0"})
supa=requests.Session(); supa.headers.update({"apikey":SERVICE_KEY,"Authorization":f"Bearer {SERVICE_KEY}","Content-Type":"application/json"})

def rpc(name:str,payload:dict[str,Any]|None=None)->Any:
    r=supa.post(f"{SUPABASE_URL}/rest/v1/rpc/{name}",json=payload or {},timeout=TIMEOUT)
    if not r.ok: raise RuntimeError(f"RPC {name} HTTP {r.status_code}: {r.text[:1000]}")
    return r.json() if r.text else None

def nested(d:dict[str,Any],*keys:str)->Any:
    x:Any=d
    for k in keys:
        if not isinstance(x,dict): return None
        x=x.get(k)
    return x

def clean(v:Any)->str|None:
    if v is None:return None
    s=str(v).strip(); return s or None

def sha(d:dict[str,Any])->str:
    return hashlib.sha256(json.dumps(d,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()

def main()->None:
    observed=datetime.now(timezone.utc).isoformat()
    targets=rpc("internal_get_usaspending_physical_fm_parent_idvs",{}) or []
    resolved=[t for t in targets if t.get("parent_generated_award_id")]
    records=[]; skipped=len(targets)-len(resolved)
    for i,t in enumerate(resolved,1):
        piid=str(t["parent_piid"]); gid=str(t["parent_generated_award_id"])
        r=api.get(f"{API_ROOT}/awards/{quote(gid,safe='')}/",timeout=TIMEOUT)
        if not r.ok: raise RuntimeError(f"parent {piid} detail HTTP {r.status_code}: {r.text[:600]}")
        d=r.json()
        if str(d.get("piid") or "").upper()!=piid.upper() or str(d.get("generated_unique_award_id") or "")!=gid or str(d.get("category") or "").lower()!="idv":
            raise RuntimeError(f"parent {piid} verification mismatch")
        rec=d.get("recipient") or {}; period=d.get("period_of_performance") or {}; awarding=d.get("awarding_agency") or {}; funding=d.get("funding_agency") or {}; latest=d.get("latest_transaction_contract_data") or {}; naics=nested(d,"naics_hierarchy","base_code") or {}; psc=nested(d,"psc_hierarchy","base_code") or {}
        norm={
            "generated_award_id":gid,"piid":piid,"award_type":clean(d.get("type_description")),"description":clean(d.get("description")),
            "recipient_name":clean(rec.get("recipient_name")),"recipient_uei":clean(rec.get("recipient_uei")),"ultimate_parent_recipient_name":clean(rec.get("parent_recipient_name")),"ultimate_parent_recipient_uei":clean(rec.get("parent_recipient_uei")),
            "total_obligation":d.get("total_obligation"),"base_exercised_options":d.get("base_exercised_options"),"base_and_all_options":d.get("base_and_all_options"),"date_signed":clean(d.get("date_signed")),"pop_start_date":clean(period.get("start_date")),"pop_end_date":clean(period.get("end_date")),"pop_potential_end_date":clean(period.get("potential_end_date")),
            "awarding_agency_name":clean(nested(awarding,"toptier_agency","name")),"awarding_subtier_name":clean(nested(awarding,"subtier_agency","name")),"awarding_office_name":clean(awarding.get("office_agency_name")),"funding_agency_name":clean(nested(funding,"toptier_agency","name")),"funding_subtier_name":clean(nested(funding,"subtier_agency","name")),"funding_office_name":clean(funding.get("office_agency_name")),
            "naics_code":clean(naics.get("code")) or clean(latest.get("naics")),"naics_description":clean(naics.get("description")) or clean(latest.get("naics_description")),"psc_code":clean(psc.get("code")) or clean(latest.get("product_or_service_code")),"psc_description":clean(psc.get("description")) or clean(latest.get("product_or_service_description")),
            "attributes":{"program_key":t.get("program_key"),"program_title":t.get("program_title"),"program_scope_class":t.get("program_scope_class"),"site_scope_status":t.get("site_scope_status"),"identifier_resolution":t.get("identifier_resolution")}
        }
        records.append({"source_native_id":f"parent:{gid}","source_url":f"{API_ROOT}/awards/{quote(gid,safe='')}/","content_hash":sha(d),"normalized":norm,"source_payload":d})
        print(f"parent {i}/{len(resolved)} {piid}: {norm['recipient_name']} / {norm['recipient_uei']}",flush=True); time.sleep(0.05)
    result=rpc("internal_ingest_usaspending_parent_idv_batch",{"p_records":records,"p_observed_at":observed}) if records else {"received":0,"raw_inserted":0,"parent_idvs_upserted":0}
    print(json.dumps({"targets":len(targets),"resolved_targets":len(resolved),"unresolved_skipped":skipped,"ingest":result},indent=2,sort_keys=True),flush=True)

if __name__=="__main__": main()
