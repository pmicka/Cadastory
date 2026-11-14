#!/usr/bin/env python3
"""Direct HTTP bypass tests against local PostgREST + real migrated PostGIS.

First run test-farm-watch-map-pins.py in an EMPTY database. Start PostgREST with
that database, public schema, anon role, and the fixture JWT secret below.
Only loopback URLs are accepted. This never uses production accounts or keys.
"""
import base64
import hashlib
import hmac
import json
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

SECRET = 'farm-watch-local-authorization-test-secret-only'
base = sys.argv[1] if len(sys.argv)>1 else 'http://127.0.0.1:55440'
assert urlparse(base).hostname in ('127.0.0.1','localhost'), 'local scratch API only'
def token(actor):
    encode = lambda obj: base64.urlsafe_b64encode(json.dumps(obj,separators=(',',':')).encode()).decode().rstrip('=')
    content=encode({'alg':'HS256','typ':'JWT'})+'.'+encode({'sub':actor,'role':'authenticated','exp':int(time.time())+300})
    return content+'.'+base64.urlsafe_b64encode(hmac.new(SECRET.encode(),content.encode(),hashlib.sha256).digest()).decode().rstrip('=')
def request(path,args=None,actor=None,method='POST'):
    headers={'content-type':'application/json'}
    if actor: headers['authorization']='Bearer '+token(actor)
    req=Request(base+path,data=json.dumps(args).encode() if args is not None else None,headers=headers,method=method)
    try:
        with urlopen(req,timeout=10) as response: return response.status,json.load(response)
    except HTTPError as error: return error.code,json.load(error)
creator='00000000-0000-0000-0000-000000000001'
other='00000000-0000-0000-0000-000000000002'
outsider='00000000-0000-0000-0000-000000000003'
def rpc(actor,**args):return request('/rpc/farm_watch_map_pins_v1',{'p_property_slug':'one',**args},actor)
pin={'p_action':'create','p_title':'HTTP persisted pin','p_notes':'<script>plain text</script>','p_longitude':0,'p_latitude':1,'p_color':'#2463EB'}
assert rpc(None,p_action='list')[0] in (401,403)
assert rpc(outsider,**pin)[0]==403
assert rpc(outsider,p_action='list')[0]==403
assert rpc(creator,p_action='list',p_property_slug='missing')[0]==403
status,created=rpc(creator,**pin);assert status==200,(status,created)
id=created['pin']['id'];revision=created['pin']['revision']
assert created['pin']['color']=='#2463eb'
status,shared=rpc(other,p_action='list');assert status==200
visible=next(p for p in shared['pins'] if p['id']==id)
assert visible['can_edit'] is False and visible['creator_label']=='Property member'
assert visible['color']=='#2463eb'
assert 'created_by' not in visible
assert all(p['id']!=id for p in rpc(creator,p_action='list',p_property_slug='two')[1]['pins'])
update={**pin,'p_action':'update','p_pin_id':id,'p_expected_revision':revision,'p_title':'HTTP moved','p_longitude':1.5,'p_latitude':1.5}
assert rpc(other,**update)[0]==403
assert rpc(other,p_action='delete',p_pin_id=id,p_expected_revision=revision)[0]==403
assert rpc(creator,**{**update,'p_property_slug':'two'})[0]==403
for field in ['created_by','property_id']:
    assert rpc(creator,**{**update,'p_'+field:other})[0]==404
    assert request('/property_map_pins_v1', {field:other}, creator,'PATCH')[0] in (401,403,404)
assert rpc(creator,**{**pin,'p_longitude':'NaN'})[0]==400
assert rpc(creator,**{**pin,'p_title':'x'*101})[0]==400
assert rpc(creator,**{**pin,'p_notes':'x'*2001})[0]==400
assert rpc(creator,**{**pin,'p_longitude':3})[0]==400
assert rpc(creator,**{**pin,'p_color':'red;fill:url(x)'})[0]==400
status,updated=rpc(creator,**update);assert status==200,(status,updated)
assert updated['pin']['revision']==revision+1
# The former request shape still updates successfully without erasing color.
legacy={k:v for k,v in update.items() if k!='p_color'}
legacy['p_expected_revision']=revision+1
status,preserved=rpc(creator,**legacy);assert status==200,(status,preserved)
assert preserved['pin']['color']=='#2463eb'
assert rpc(creator,**update)[0]==409
assert rpc(creator,p_action='delete',p_pin_id=id,p_expected_revision=revision)[0]==409
assert rpc(creator,p_action='delete',p_pin_id=id,p_expected_revision=revision+2)[0]==200
assert all(p['id']!=id for p in rpc(creator,p_action='list')[1]['pins'])
print('PASS: signed HTTP JWTs against actual PostgREST/PostGIS; shared reads, persistent CRUD, property scope, noncreator denial, transfer/reassignment denial, invalid input, stale writes and deletes.')
