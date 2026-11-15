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
symbol={**pin,'p_icon':'deerstand'}
assert rpc(other,p_action='list')[1]['capabilities']['can_use_pin_icons'] is True
assert rpc(creator,p_action='list')[1]['capabilities']['can_use_pin_icons'] is False
assert rpc(creator,**symbol)[0]==403
for actor in ['00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006']:
    assert rpc(actor,p_action='list')[1]['capabilities']['can_use_pin_icons'] is False
    assert rpc(actor,**symbol)[0]==403, 'another authorized owner/admin must not inherit icons'
    status,plain=rpc(actor,**pin);assert status==200,(status,plain)
    assert plain['pin']['icon']=='pin'
    assert rpc(actor,p_action='delete',p_pin_id=plain['pin']['id'],p_expected_revision=1)[0]==200
status,created=rpc(other,**symbol);assert status==200,(status,created)
saved=created['pin'];assert saved['icon']=='deerstand'
assert any(p['id']==saved['id'] and p['icon']=='deerstand' and not p['can_edit'] for p in rpc(creator,p_action='list')[1]['pins'])
icon_update={**symbol,'p_action':'update','p_pin_id':saved['id'],'p_expected_revision':1,'p_icon':'trail_camera'}
assert rpc(creator,**icon_update)[0]==403
assert rpc(other,**icon_update)[1]['pin']['icon']=='trail_camera'
assert rpc(other,**icon_update)[0]==409
legacy_icon={k:v for k,v in icon_update.items() if k!='p_icon'};legacy_icon['p_expected_revision']=2
assert rpc(other,**legacy_icon)[1]['pin']['icon']=='trail_camera'
assert rpc(other,p_action='delete',p_pin_id=saved['id'],p_expected_revision=3)[0]==200
assert rpc(other,**{**symbol,'p_icon':'<img src=x onerror=alert(1)>'})[0]==400
assert rpc(creator,**{**symbol,'p_can_use_pin_icons':True})[0]==404
assert request('/map_pin_icon_users_v1',{'user_id':creator},creator)[0] in (401,403,404)
print('PASS: signed HTTP JWTs against actual PostgREST/PostGIS; account-only icons, shared icon views, other-owner/admin denial, legacy icon preservation, persistent CRUD, property scope, creator-only mutations, invalid input and concurrency.')

for icon in ['dot','corn_feeder','salt_mineral_block','tree','pop_up_blind','ladder_stand']:
    for actor in [creator,'00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006']:
        assert rpc(actor,**{**pin,'p_icon':icon})[0]==403, (actor,icon)
    status,data=rpc(other,**{**pin,'p_icon':icon}); assert status==200,(icon,data)
    saved=data['pin']; assert saved['icon']==icon
    visible=next(p for p in rpc(creator,p_action='list')[1]['pins'] if p['id']==saved['id'])
    assert visible['icon']==icon and not visible['can_edit']
    assert rpc(creator,p_action='update',p_pin_id=saved['id'],p_expected_revision=1,p_title='Stolen',p_longitude=0,p_latitude=1)[0]==403
    assert rpc(creator,p_action='delete',p_pin_id=saved['id'],p_expected_revision=1)[0]==403
    status,data=rpc(other,p_action='update',p_pin_id=saved['id'],p_expected_revision=1,p_title='Legacy edit',p_longitude=0,p_latitude=1)
    assert status==200 and data['pin']['icon']==icon
    assert rpc(other,p_action='delete',p_pin_id=saved['id'],p_expected_revision=2)[0]==200
print('PASS: small dot and five added symbols persist over signed HTTP; sharing, creator-only updates/deletes and owner/admin/viewer denials are server-enforced.')

# Migrated historical fixture copies use the exact same server authorization.
legacy_property='validation-property-01'
status,migrated=rpc(other,p_property_slug=legacy_property,p_action='list');assert status==200
saved=migrated['pins'][0];assert saved['title']=='Migrated feeder edited' and saved['revision']==2
for actor in [creator,'00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006']:
 status,shared=rpc(actor,p_property_slug=legacy_property,p_action='list');assert status==200
 assert shared['pins'][0]['can_edit'] is False
 args={'p_property_slug':legacy_property,'p_pin_id':saved['id'],'p_expected_revision':2}
 assert rpc(actor,**args,p_action='delete')[0]==403
 assert rpc(actor,**args,p_action='update',p_title='Stolen legacy fixture',p_longitude=1,p_latitude=1)[0]==403
assert rpc(None,p_property_slug=legacy_property,p_action='list')[0] in (401,403)
assert rpc(outsider,p_property_slug=legacy_property,p_action='list')[0]==403
assert request('/property_map_pin_fixture_links_v1',actor=other,method='GET')[0] in (401,403,404)
assert rpc(other,p_property_slug=legacy_property,p_action='update',p_pin_id=saved['id'],p_expected_revision=2,p_title='HTTP migrated feeder',p_longitude=1.3,p_latitude=1.4)[0]==200
assert rpc(other,p_property_slug=legacy_property,p_action='delete',p_pin_id=saved['id'],p_expected_revision=2)[0]==409
print('PASS: migrated fixtures use creator-only signed HTTP CRUD; viewer/other-owner/admin/unauthenticated/outsider denial and private migration ledger')

for category in ['auto','general','hunting','farming-orchard']:
 status,data=rpc(creator,**{**pin,'p_category':category});assert status==200,(category,data)
 saved=data['pin'];assert saved['category']==category
 shared=next(p for p in rpc(other,p_action='list')[1]['pins'] if p['id']==saved['id'])
 assert shared['category']==category and not shared['can_edit']
 update={**pin,'p_action':'update','p_pin_id':saved['id'],'p_expected_revision':1,'p_category':'general','p_longitude':1.5,'p_latitude':1.5}
 for actor in [other,'00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006']:
  assert rpc(actor,**update)[0]==403
  assert rpc(actor,p_action='delete',p_pin_id=saved['id'],p_expected_revision=1)[0]==403
 assert rpc(creator,**{**update,'p_property_slug':'two'})[0]==403
 status,data=rpc(creator,**update);assert status==200 and data['pin']['category']=='general'
 assert rpc(creator,**update)[0]==409
 legacy={k:v for k,v in update.items() if k!='p_category'};legacy['p_expected_revision']=2
 status,data=rpc(creator,**legacy);assert status==200 and data['pin']['category']=='general'
 status,data=rpc(creator,**{**legacy,'p_expected_revision':3,'p_category':'auto'});assert status==200 and data['pin']['category']=='auto'
 assert rpc(creator,p_action='delete',p_pin_id=saved['id'],p_expected_revision=4)[0]==200
for category in ['','Hunting','water','__proto__','<svg/>',{'category':'hunting'}]:
 assert rpc(creator,**{**pin,'p_category':category})[0]==400
assert rpc(outsider,**{**pin,'p_category':'hunting'})[0]==403
assert rpc(None,**{**pin,'p_category':'general'})[0] in (401,403)
assert rpc(creator,**{**pin,'p_category':'hunting','p_created_by':other})[0]==404
print('PASS: categories over signed HTTP: persistent sharing, creator-only changes/moves/deletes, owner/admin/outsider/anonymous denial, isolation, stale revisions, legacy omission and explicit automatic reset.')

# New fields are tested directly at the signed PostgREST boundary, bypassing Edge/UI.
camera={**pin,'p_icon':'trail_camera','p_camera_bearing_deg':90,'p_camera_range_m':24.384,'p_camera_fov_deg':40}
assert rpc(creator,**camera)[0]==403
assert rpc(outsider,**camera)[0]==403
assert rpc(None,**camera)[0] in (401,403)
status,data=rpc(other,**camera);assert status==200,(status,data)
saved=data['pin'];camera_id=saved['id']
shared=next(p for p in rpc(creator,p_action='list')[1]['pins'] if p['id']==camera_id)
assert shared['camera_bearing_deg']==90 and shared['camera_range_m']==24.384 and shared['camera_fov_deg']==40 and not shared['can_edit']
assert all(p['id']!=camera_id for p in rpc(creator,p_property_slug='two',p_action='list')[1]['pins'])
update={**camera,'p_action':'update','p_pin_id':camera_id,'p_expected_revision':1,'p_longitude':1.5,'p_latitude':1.5,'p_camera_bearing_deg':270,'p_camera_range_m':30.48,'p_camera_fov_deg':60}
for actor in [creator,'00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006',outsider]:
 assert rpc(actor,**update)[0]==403
 assert rpc(actor,p_action='delete',p_pin_id=camera_id,p_expected_revision=1)[0]==403
assert rpc(other,**{**update,'p_property_slug':'two'})[0]==403
for key in ['p_created_by','p_property_id','p_geometry']:
 assert rpc(other,**{**update,key:creator})[0]==404
for key,values in {'p_camera_bearing_deg':[-1,360,1.5],'p_camera_range_m':[0,1.523,91.441,'NaN','Infinity'],'p_camera_fov_deg':[9,121,40.5]}.items():
 for value in values:assert rpc(other,**{**update,key:value})[0]==400,(key,value)
status,data=rpc(other,**update);assert status==200 and data['pin']['camera_bearing_deg']==270 and data['pin']['latitude']==1.5
assert rpc(other,**update)[0]==409
assert rpc(other,p_action='delete',p_pin_id=camera_id,p_expected_revision=1)[0]==409
legacy={k:v for k,v in update.items() if not k.startswith('p_camera_')};legacy['p_expected_revision']=2
status,data=rpc(other,**legacy);assert status==200 and data['pin']['camera_range_m']==30.48 and data['pin']['camera_fov_deg']==60
status,data=rpc(other,**{**legacy,'p_expected_revision':3,'p_icon':'container'});assert status==200
assert all(data['pin'][key] is None for key in ['camera_bearing_deg','camera_range_m','camera_fov_deg'])
assert rpc(other,p_action='delete',p_pin_id=camera_id,p_expected_revision=4)[0]==200
assert all(p['id']!=camera_id for p in rpc(creator,p_action='list')[1]['pins'])
print('PASS: signed HTTP camera sharing/persistence, creator-only direction/range/FOV/move/delete, role/anonymous/outsider denial, isolation, transfer bypass denial, invalid settings and stale revisions.')

# Photo RPC requests bypass the UI/Edge. Only the synthetic service can model a
# processed Storage object; ordinary users cannot seed/alter the private bucket.
import uuid
def service_request(path,args=None):
 encode=lambda obj:base64.urlsafe_b64encode(json.dumps(obj,separators=(',',':')).encode()).decode().rstrip('=')
 content=encode({'alg':'HS256','typ':'JWT'})+'.'+encode({'role':'service_role','exp':int(time.time())+300})
 jwt=content+'.'+base64.urlsafe_b64encode(hmac.new(SECRET.encode(),content.encode(),hashlib.sha256).digest()).decode().rstrip('=')
 req=Request(base+path,data=json.dumps(args or {}).encode(),headers={'content-type':'application/json','authorization':'Bearer '+jwt})
 try:
  with urlopen(req,timeout=10) as response:return response.status,json.load(response)
 except HTTPError as error:return error.code,json.load(error)
status,data=rpc(creator,**pin);assert status==200
photo_pin=data['pin'];assert photo_pin['photo_count']==0
revision=photo_pin['revision'];ids=[]
def photos(actor,action,**kwargs):
 return request('/rpc/farm_watch_pin_photos_v1',{'p_property_slug':'one','p_pin_id':photo_pin['id'],'p_action':action,**kwargs},actor)
assert photos(None,'list')[0] in (401,403)
assert photos(outsider,'list')[0]==403
for index in range(4):
 photo_id=str(uuid.uuid4());ids.append(photo_id)
 assert photos(creator,'prepare',p_photo_id=photo_id,p_expected_revision=revision)[0]==200
 assert photos(creator,'attach',p_photo_id=photo_id,p_expected_revision=revision)[0]==400,'unprocessed object cannot be attached'
 seed={'p_pin_id':photo_pin['id'],'p_photo_id':photo_id}
 assert request('/rpc/pin_test_seed_photo_v1',seed,creator)[0]==403
 assert service_request('/rpc/pin_test_seed_photo_v1',seed)[0]==200
 for actor in [other,'00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006']:
  assert photos(actor,'attach',p_photo_id=photo_id,p_expected_revision=revision)[0]==403
 status,data=photos(creator,'attach',p_photo_id=photo_id,p_expected_revision=revision);assert status==200,(status,data)
 revision=data['revision']
 assert photos(creator,'attach',p_photo_id=photo_id,p_expected_revision=revision-1)[0]==409
 assert all(p['id'] in ids for p in photos(other,'list')[1]['photos'])
 assert photos(other,'read',p_photo_id=photo_id)[0]==200
 assert photos(other,'delete',p_photo_id=photo_id,p_expected_revision=revision)[0]==403
 assert photos(creator,'read',p_photo_id=photo_id,p_property_slug='two')[0]==403
 assert photos(creator,'attach',p_photo_id=photo_id,p_expected_revision=revision,p_created_by=other)[0]==404
 assert photos(creator,'attach',p_photo_id=photo_id,p_expected_revision=revision,p_object_path='other/property/photo.webp')[0]==404
assert len(photos(creator,'list')[1]['photos'])==4
assert photos(creator,'prepare',p_photo_id=str(uuid.uuid4()),p_expected_revision=revision)[0]==409
assert request('/rpc/farm_watch_pin_photo_cleanup_v1',{},creator)[0]==403
status,data=photos(creator,'delete',p_photo_id=ids[0],p_expected_revision=revision);assert status==200
revision=data['revision']
assert photos(creator,'read',p_photo_id=ids[0])[0]==403
assert photos(creator,'delete',p_photo_id=ids[0],p_expected_revision=revision-1)[0]==409
assert rpc(creator,p_action='delete',p_pin_id=photo_pin['id'],p_expected_revision=revision)[0]==200
assert photos(other,'list')[0]==403
status,data=service_request('/rpc/farm_watch_pin_photo_cleanup_v1');assert status==200 and len(data['paths'])>=4
print('PASS: signed HTTP photo sharing, creator-only attach/remove, no arbitrary object/ownership fields, missing processed-object denial, four-photo cap, stale revisions, private service helpers and pin-delete cleanup queue.')

# Privacy enforced by the real signed PostgREST boundary, including known photo IDs.
status,data=rpc(creator,**pin,p_is_private=True);assert status==200,(status,data)
photo_pin=data['pin'];assert photo_pin['is_private'] is True
photo_id=str(uuid.uuid4())
assert service_request('/rpc/pin_test_seed_photo_v1',{'p_pin_id':photo_pin['id'],'p_photo_id':photo_id})[0]==200
status,data=photos(creator,'attach',p_photo_id=photo_id,p_expected_revision=1);assert status==200
revision=data['revision']
for actor in [other,'00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006']:
 assert all(p['id']!=photo_pin['id'] for p in rpc(actor,p_action='list')[1]['pins'])
 for action,extra in [('list',{}),('read',{'p_photo_id':photo_id}),('prepare',{'p_photo_id':str(uuid.uuid4()),'p_expected_revision':revision})]:
  assert photos(actor,action,**extra)[0]==403,(actor,action)
 assert rpc(actor,p_action='update',p_pin_id=photo_pin['id'],p_expected_revision=revision,p_title='Hijack',p_longitude=0,p_latitude=1,p_is_private=False)[0]==403
 assert rpc(actor,p_action='delete',p_pin_id=photo_pin['id'],p_expected_revision=revision)[0]==403
assert photos(creator,'read',p_photo_id=photo_id)[0]==200
update={**pin,'p_action':'update','p_pin_id':photo_pin['id'],'p_expected_revision':revision}
status,data=rpc(creator,**update);assert status==200 and data['pin']['is_private'] is True,'legacy edits retain privacy'
revision=data['pin']['revision']
assert rpc(creator,**{**update,'p_is_private':False})[0]==409
assert rpc(creator,**{**update,'p_property_slug':'two','p_expected_revision':revision,'p_is_private':False})[0]==403
for private in [False,True]:
 status,data=rpc(creator,**{**update,'p_expected_revision':revision,'p_is_private':private});assert status==200
 revision=data['pin']['revision'];assert data['pin']['is_private'] is private
 assert photos(other,'read',p_photo_id=photo_id)[0]==(403 if private else 200)
assert rpc(None,p_action='list')[0] in (401,403)
assert rpc(outsider,p_action='list')[0]==403
assert rpc(creator,**{**pin,'p_is_private':'not boolean'})[0]==400
assert rpc(creator,p_action='delete',p_pin_id=photo_pin['id'],p_expected_revision=revision)[0]==200
assert photos(creator,'read',p_photo_id=photo_id)[0]==403
print('PASS: signed HTTP creator-only private pin/photo reads across viewer, owner and admin roles; legacy preservation, sharing/unsharing, stale and property-scope guards.')

# Independent WGS84 ground-distance probes at the selected property's west edge.
# A latitude-dependent metres/degree conversion is sufficient at this 30 m scale;
# probes straddle 100 ft by 0.01 ft, well above conversion rounding error.
import math
lat_rad=math.radians(1)
lon_m_per_degree=math.pi/180*6378137/math.sqrt(1-0.00669437999014*math.sin(lat_rad)**2)*math.cos(lat_rad)
def nearby(feet):return {'p_longitude':-feet*.3048/lon_m_per_degree,'p_latitude':1}
for feet in [1,50,99.99]:
 coordinates=nearby(feet)
 status,data=rpc(creator,**{**pin,**coordinates});assert status==200,(feet,status,data)
 saved=data['pin'];assert saved['longitude']==coordinates['p_longitude'],'coordinates must not snap'
 assert any(p['id']==saved['id'] for p in rpc(other,p_action='list')[1]['pins'])
 update={**pin,**coordinates,'p_action':'update','p_pin_id':saved['id'],'p_expected_revision':1,'p_is_private':True}
 assert rpc(other,**update)[0]==403
 assert rpc(creator,**{**update,'p_property_slug':'two'})[0]==403
 status,data=rpc(creator,**update);assert status==200 and data['pin']['is_private'] is True
 assert all(p['id']!=saved['id'] for p in rpc(other,p_action='list')[1]['pins'])
 # Failed far moves leave both the location and revision usable for next edit.
 assert rpc(creator,**{**update,**nearby(100.01),'p_expected_revision':2})[0]==400
 status,data=rpc(creator,**{**update,**nearby(99.99),'p_expected_revision':2,'p_is_private':False});assert status==200 and data['pin']['revision']==3
 assert rpc(creator,**update)[0]==409
 assert rpc(creator,p_action='delete',p_pin_id=saved['id'],p_expected_revision=3)[0]==200
for feet in [100.01,101,500]:
 status,data=rpc(creator,**{**pin,**nearby(feet)});assert status==400,(feet,status,data)
assert rpc(None,**{**pin,**nearby(50)})[0] in (401,403)
assert rpc(outsider,**{**pin,**nearby(50)})[0]==403
# Restricted icons obey the same distance limit and original account grant.
assert rpc(creator,**{**pin,**nearby(50),'p_icon':'corn_feeder'})[0]==403
status,data=rpc(other,**{**pin,**nearby(50),'p_icon':'trail_camera','p_camera_bearing_deg':90});assert status==200,(status,data)
saved=data['pin'];assert saved['camera_bearing_deg']==90
assert rpc(other,p_action='delete',p_pin_id=saved['id'],p_expected_revision=1)[0]==200
# Photo attachment/revision authorization also works on a nearby off-property pin.
status,data=rpc(creator,**{**pin,**nearby(50),'p_is_private':True});assert status==200
photo_pin=data['pin'];photo_id=str(uuid.uuid4())
assert service_request('/rpc/pin_test_seed_photo_v1',{'p_pin_id':photo_pin['id'],'p_photo_id':photo_id})[0]==200
assert photos(creator,'prepare',p_photo_id=photo_id,p_expected_revision=1)[0]==200
status,data=photos(creator,'attach',p_photo_id=photo_id,p_expected_revision=1);assert status==200 and data['revision']==2
assert photos(creator,'read',p_photo_id=photo_id)[0]==200
assert photos(other,'read',p_photo_id=photo_id)[0]==403
assert rpc(creator,p_action='delete',p_pin_id=photo_pin['id'],p_expected_revision=2)[0]==200
print('PASS: signed HTTP off-property 100 ft limit, exact coordinate persistence, move/edit/privacy/photos, restricted icons, creator/property/anonymous/outsider denial and unchanged conflict behavior.')
