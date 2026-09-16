from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SHARED=ROOT/'supabase/functions/_shared'
COMP=ROOT/'supabase/functions/scout-component-sandbox-mcp'
MIG=ROOT/'supabase/migrations/20260916043000_add_spine_single_asset_sandbox.sql'

def replace_once(path, old, new):
    text=path.read_text()
    if old not in text:
        raise RuntimeError(f'anchor missing in {path}: {old[:120]!r}')
    path.write_text(text.replace(old,new,1))

# Add event_detailing to the generic single-asset contract/config.
p=SHARED/'scout_sandbox_spine_single_asset_config.ts'
text=p.read_text()
text=text.replace(" 'bridge','construction_site','dam','mine_quarry','landfill','rail_crossing','roof_lifecycle','solar_lifecycle',", " 'bridge','construction_site','event_detailing','dam','mine_quarry','landfill','rail_crossing','roof_lifecycle','solar_lifecycle',",1)
anchor=" construction_site:{label:'construction lifecycle',sourceKind:'construction_window',signalKinds:['construction_lifecycle'],displayName:'Commercial Alteration — 700 CENTRAL AVE',center:{lon:-85.77176682,lat:38.20415465},zoom:16,statusLabel:'Construction lifecycle signal',factLabels:['Address','Project type','Stage','Project value','Project area','Contractor'],guardrail:'The permit record supports a newly permitted construction-lifecycle signal. Stage is inferred from permit status and timing, not observed field progress. This does not prove a drone scope, active procurement, site access, buyer intent, or work availability.'},\n"
entry=" event_detailing:{label:'event-timed detailing',sourceKind:'event_detailing',signalKinds:['marquee_event_pre_detailing'],displayName:'2600 S FLOYD STREET',center:{lon:-85.7582934172167,lat:38.2083681570736},zoom:17,statusLabel:'Event-timed detailing signal',factLabels:['Event','Event date','Venue proximity','Timing basis','Independent need','Attendance context'],guardrail:'Independent exterior-cleaning evidence exists separately for this building. The marquee event may amplify timing only; event presence does not establish cleaning need. Attendance is a venue-capacity proxy, not an attendance forecast. This does not prove visible staining, procurement intent, site access, service authorization, or work availability.'},\n"
if anchor not in text: raise RuntimeError('event config insertion anchor missing')
text=text.replace(anchor,anchor+entry,1)
p.write_text(text)

# Register map center/metadata in shared manifest.
p=SHARED/'scout_sandbox_manifest.ts';text=p.read_text()
anchor="""  construction_site: {
    slug: 'construction_site',
    label: SCOUT_SPINE_SINGLE_ASSET_CONFIG.construction_site.label,
    mapKind: 'single_site',
    markerSemantics: 'bounded source opportunity point; no parcel, access, service-radius, or operating boundary implied',
    hostNormalization: 'strict',
    rasterFrames: [{ width: 456, height: 210 }],
    tileRanges: [],
    tileCenters: singleSiteCenter(SCOUT_SPINE_SINGLE_ASSET_CONFIG.construction_site.center.lon, SCOUT_SPINE_SINGLE_ASSET_CONFIG.construction_site.center.lat),
  },
"""
entry="""  event_detailing: {
    slug: 'event_detailing',
    label: SCOUT_SPINE_SINGLE_ASSET_CONFIG.event_detailing.label,
    mapKind: 'single_site',
    markerSemantics: 'bounded target-building point; event venue is timing context only and no event footprint, service radius, or access area is implied',
    hostNormalization: 'strict',
    rasterFrames: [{ width: 456, height: 210 }],
    tileRanges: [],
    tileCenters: singleSiteCenter(SCOUT_SPINE_SINGLE_ASSET_CONFIG.event_detailing.center.lon, SCOUT_SPINE_SINGLE_ASSET_CONFIG.event_detailing.center.lat),
  },
"""
if anchor not in text: raise RuntimeError('manifest event insertion anchor missing')
p.write_text(text.replace(anchor,anchor+entry,1))

# Register runtime and View adapters.
for name in ['single_site_registry.ts','single_site_view_registry.ts']:
    p=COMP/name;t=p.read_text()
    old="bridge:spine('bridge'),construction_site:spine('construction_site'),dam:spine('dam')"
    new="bridge:spine('bridge'),construction_site:spine('construction_site'),event_detailing:spine('event_detailing'),dam:spine('dam')"
    if old not in t: raise RuntimeError(f'{name} registry anchor missing')
    p.write_text(t.replace(old,new,1))

# Extend one service-role-only generic RPC with a stable event+target selector and separate independent-need lineage.
p=MIG;text=p.read_text()
old=" or (p_opportunity_type='construction_site' and o.source_kind='construction_window' and o.signal_kind='construction_lifecycle' and o.details->>'address'='700 CENTRAL AVE' and o.details->>'project_type'='Commercial Alteration' and o.details->>'contractor_name'='CALHOUN CONSTRUCTION SERV INC' and o.details->>'project_value'='3000000' and o.details->>'square_feet'='6800')\n"
new=old+" or (p_opportunity_type='event_detailing' and o.source_kind='event_detailing' and o.signal_kind='marquee_event_pre_detailing' and o.display_name='2600 S FLOYD STREET' and o.target_resolution_status='canonical_asset' and o.buyer_name='University of Louisville' and o.event_title='Louisville vs. #16 SMU' and o.event_start='2026-09-19'::date and o.event_context->>'event_family'='louisville_football_16_smu' and o.details->>'action_basis'='independent_need_plus_marquee_timing')\n"
if old not in text: raise RuntimeError('migration chosen event anchor missing')
text=text.replace(old,new,1)
old="""), rel as(
 select jsonb_build_array(jsonb_build_object('candidate_key',f.candidate_key,'source_kind',f.source_kind,'signal_kind',f.signal_kind,'summary',f.why_now,'confidence',f.confidence)) v
 from scout.opportunity_search_spine f where p_opportunity_type='bridge' and f.source_kind='funded_pain' and f.signal_kind='bridge_condition_or_planned_work' and f.why_now ilike 'Bridge 037B00052R%'
 order by f.refreshed_at desc nulls last limit 1
)
"""
new="""), bridge_rel as(
 select jsonb_build_array(jsonb_build_object('candidate_key',f.candidate_key,'source_kind',f.source_kind,'signal_kind',f.signal_kind,'summary',f.why_now,'confidence',f.confidence)) v
 from scout.opportunity_search_spine f where p_opportunity_type='bridge' and f.source_kind='funded_pain' and f.signal_kind='bridge_condition_or_planned_work' and f.why_now ilike 'Bridge 037B00052R%'
 order by f.refreshed_at desc nulls last limit 1
), event_rel as(
 select jsonb_build_array(jsonb_build_object('candidate_key',f.candidate_key,'source_kind',f.source_kind,'signal_kind',f.signal_kind,'summary',f.why_now,'confidence',f.confidence)) v
 from scout.opportunity_search_spine f where p_opportunity_type='event_detailing' and f.source_kind='exterior_cleaning' and f.signal_kind='cleaning_need_proxy' and f.display_name='2600 S FLOYD STREET' and f.target_resolution_status='canonical_asset' and f.buyer_name='University of Louisville'
 order by f.refreshed_at desc nulls last,f.observed_at desc nulls last limit 1
)
"""
if old not in text: raise RuntimeError('migration relation CTE anchor missing')
text=text.replace(old,new,1)
text=text.replace("when 'construction_site' then 'Construction lifecycle signal' when 'dam'", "when 'construction_site' then 'Construction lifecycle signal' when 'event_detailing' then 'Event-timed detailing signal' when 'dam'",1)
text=text.replace("when 'construction_site' then o.details->>'address' when 'rail_crossing'", "when 'construction_site' then o.details->>'address' when 'event_detailing' then o.display_name when 'rail_crossing'",1)
text=text.replace("coalesce((select r.v->0->>'summary' from rel r),'No separate planned-work signal attached')", "coalesce((select r.v->0->>'summary' from bridge_rel r),'No separate planned-work signal attached')",1)
anchor="  when 'construction_site' then jsonb_build_array(jsonb_build_object('label','Address','value',o.details->>'address'),jsonb_build_object('label','Project type','value',o.details->>'project_type'),jsonb_build_object('label','Stage','value',o.details->>'current_stage'),jsonb_build_object('label','Project value','value',pg_catalog.concat('$',pg_catalog.to_char((o.details->>'project_value')::numeric,'FM999,999,999,990'))),jsonb_build_object('label','Project area','value',pg_catalog.concat(pg_catalog.to_char((o.details->>'square_feet')::numeric,'FM999,999,990'),' sq ft')),jsonb_build_object('label','Contractor','value',o.details->>'contractor_name'))\n"
entry="  when 'event_detailing' then jsonb_build_array(jsonb_build_object('label','Event','value',o.event_title),jsonb_build_object('label','Event date','value',o.event_start::text),jsonb_build_object('label','Venue proximity','value',pg_catalog.concat(pg_catalog.round((o.details->>'distance_m')::numeric),' m to ',o.event_context->>'venue_name')),jsonb_build_object('label','Timing basis','value',o.details->>'action_basis'),jsonb_build_object('label','Independent need','value',coalesce((select r.v->0->>'summary' from event_rel r),'Independent signal unavailable')),jsonb_build_object('label','Attendance context','value',pg_catalog.concat(o.event_context->>'attendance_max',' venue-capacity proxy; not an attendance forecast')))\n"
if anchor not in text: raise RuntimeError('migration event facts anchor missing')
text=text.replace(anchor,anchor+entry,1)
old=" 'related_signals',coalesce((select r.v from rel r),'[]'::jsonb),\n"
new=" 'related_signals',case p_opportunity_type when 'bridge' then coalesce((select r.v from bridge_rel r),'[]'::jsonb) when 'event_detailing' then coalesce((select r.v from event_rel r),'[]'::jsonb) else '[]'::jsonb end,\n"
if old not in text: raise RuntimeError('migration related signals anchor missing')
text=text.replace(old,new,1)
old="when 'construction_site' then 'The permit record supports a newly permitted construction-lifecycle signal. Stage is inferred from permit status and timing, not observed field progress. This does not prove a drone scope, active procurement, site access, buyer intent, or work availability.' when 'dam'"
new="when 'construction_site' then 'The permit record supports a newly permitted construction-lifecycle signal. Stage is inferred from permit status and timing, not observed field progress. This does not prove a drone scope, active procurement, site access, buyer intent, or work availability.' when 'event_detailing' then 'Independent exterior-cleaning evidence exists separately for this building. The marquee event may amplify timing only; event presence does not establish cleaning need. Attendance is a venue-capacity proxy, not an attendance forecast. This does not prove visible staining, procurement intent, site access, service authorization, or work availability.' when 'dam'"
if old not in text: raise RuntimeError('migration guardrail event anchor missing')
p.write_text(text.replace(old,new,1))

# Predeploy smoke explicitly invokes event_detailing.
p=COMP/'sandbox_predeploy_smoke_test.mjs';text=p.read_text()
old="  construction_site: 'spine_single_asset_map_renderer_test.mjs',\n  dam:"
new="  construction_site: 'spine_single_asset_map_renderer_test.mjs',\n  event_detailing: 'spine_single_asset_map_renderer_test.mjs',\n  dam:"
if old not in text: raise RuntimeError('predeploy event smoke anchor missing')
p.write_text(text.replace(old,new,1))

# Strengthen the generic test around event timing/independent-need separation.
p=COMP/'spine_single_asset_map_renderer_test.mjs';text=p.read_text()
old="assert.ok(migration.includes(\"o.details->>'square_feet'='6800'\"));"
new=old+"assert.ok(migration.includes(\"o.event_context->>'event_family'='louisville_football_16_smu'\"));assert.ok(migration.includes(\"f.source_kind='exterior_cleaning'\"));assert.ok(migration.includes(\"f.signal_kind='cleaning_need_proxy'\"));assert.ok(migration.includes('venue-capacity proxy; not an attendance forecast'));assert.ok(migration.includes('event presence does not establish cleaning need'));"
if old not in text: raise RuntimeError('generic test event assertion anchor missing')
p.write_text(text.replace(old,new,1))

# Append the resolved evidence decision to both design contracts.
section='''\n\n### Event-detailing single-asset resolution — 2026-09-16\n\n`event_detailing` is included in the remaining single-asset batch only when a separate independent need signal exists for the exact target asset. The exemplar is 2600 S Floyd Street: its exterior-cleaning proxy exists independently of the Louisville vs. #16 SMU event. The event may amplify timing but cannot create cleaning need. Attendance is rendered only as a venue-capacity proxy, never as a forecast. The target-building point is mapped; the event venue does not create a service radius, site boundary, access area, or work authorization.\n'''
for name in ['DESIGN_CONTRACT.md','MAP_CONTRACT.md']:
    p=COMP/name;p.write_text(p.read_text()+section)

print('Added defensible event-detailing to the generic single-asset batch.')
