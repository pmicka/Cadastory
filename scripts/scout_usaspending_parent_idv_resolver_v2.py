#!/usr/bin/env python3
"""Resolve unresolved qualified parent IDVs through one exact-PIID USAspending search.

This is supplemental enrichment. If USAspending advanced search is temporarily unavailable,
existing verified parent IDs remain usable and this step exits successfully without inventing IDs.
"""
from __future__ import annotations
import json, os, time
from typing import Any
from urllib.parse import quote
import requests

API_ROOT="https://api.usaspending.gov/api/v2"
SUPABASE_URL=os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY=os.environ["SUPABASE_SERVICE_ROLE_KEY"]
TIMEOUT=(30,120)
IDV_CODES=["IDV_A","IDV_B","IDV_B_A","IDV_B_B","IDV_B_C","IDV_C","IDV_D","IDV_E"]
api=requests.Session(); api.headers.update({"Accept":"application/json","Content-Type":"application/json","User-Agent":"Scout-Cadastory-USAspending-IDV-Resolver/2.0"})
supa=requests.Session(); supa.headers.update({"apikey":SERVICE_KEY,"Authorization":f"Bearer {SERVICE_KEY}","Content-Type":"application/json"})

def rpc(name:str,payload:dict[str,Any]|None=None)->Any:
    r=supa.post(f"{SUPABASE_URL}/rest/v1/rpc/{name}",json=payload or {},timeout=TIMEOUT)
    if not r.ok: raise RuntimeError(f"RPC {name} HTTP {r.status_code}: {r.text[:1000]}")
    return r.json() if r.text else None

def verify(piid:str,gid:str)->dict[str,Any]:
    r=api.get(f"{API_ROOT}/awards/{quote(gid,safe='')}/",timeout=TIMEOUT)
    if not r.ok: raise RuntimeError(f"detail HTTP {r.status_code}: {r.text[:500]}")
    d=r.json()
    if str(d.get("piid") or "").upper()!=piid.upper() or str(d.get("generated_unique_award_id") or "")!=gid or str(d.get("category") or "").lower()!="idv":
        raise RuntimeError("award-detail verification mismatch")
    return d

def main()->None:
    targets=rpc("internal_get_usaspending_physical_fm_parent_idvs",{}) or []
    queue=[t for t in targets if not t.get("parent_generated_award_id") or t.get("identifier_resolution")=="usaspending_exact_piid_search_required"]
    if not queue:
        print(json.dumps({"queued":0,"resolved":0,"status":"nothing_to_resolve"}),flush=True); return
    piids=[str(t["parent_piid"]).strip() for t in queue]
    payload={"subawards":False,"limit":100,"page":1,"filters":{"award_type_codes":IDV_CODES,"award_ids":[f'"{p}"' for p in piids]},"fields":["Award ID","Recipient Name","Recipient UEI","Awarding Agency Code","Awarding Sub Agency Code","generated_internal_id","Description","Contract Award Type"]}
    try:
        r=api.post(f"{API_ROOT}/search/spending_by_award/",json=payload,timeout=TIMEOUT)
    except requests.RequestException as exc:
        print(json.dumps({"queued":len(queue),"resolved":0,"status":"advanced_search_unavailable","error":str(exc)[:500]}),flush=True); return
    if r.status_code in (429,500,502,503,504):
        print(json.dumps({"queued":len(queue),"resolved":0,"status":"advanced_search_unavailable","http_status":r.status_code}),flush=True); return
    if not r.ok:
        raise RuntimeError(f"advanced search HTTP {r.status_code}: {r.text[:1200]}")
    data=r.json(); rows=data.get("results") or []
    by_piid:dict[str,list[dict[str,Any]]]={p.upper():[] for p in piids}
    for row in rows:
        p=str(row.get("Award ID") or "").strip().upper()
        if p in by_piid: by_piid[p].append(row)
    resolved=[]; unresolved=[]; ambiguous=[]
    for piid in piids:
        matches=by_piid.get(piid.upper(),[])
        gids=sorted({str(m.get("generated_internal_id") or "").strip() for m in matches if str(m.get("generated_internal_id") or "").strip()})
        if not gids: unresolved.append(piid); continue
        if len(gids)!=1: ambiguous.append({"piid":piid,"generated_ids":gids}); continue
        gid=gids[0]; detail=verify(piid,gid)
        rpc("internal_set_usaspending_parent_idv_identifier",{"p_parent_piid":piid,"p_generated_award_id":gid,"p_resolved_award_piid":str(detail.get("piid") or "")})
        resolved.append({"piid":piid,"generated_award_id":gid,"recipient_name":(detail.get("recipient") or {}).get("recipient_name"),"recipient_uei":(detail.get("recipient") or {}).get("recipient_uei")})
        time.sleep(0.05)
    print(json.dumps({"queued":len(queue),"resolved":len(resolved),"unresolved":unresolved,"ambiguous":ambiguous,"results":resolved,"status":"complete"},indent=2,sort_keys=True),flush=True)
    if ambiguous: raise SystemExit(1)

if __name__=="__main__": main()
