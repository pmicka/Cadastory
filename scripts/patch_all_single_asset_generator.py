from pathlib import Path

path = Path('scripts/apply_all_single_asset_sandbox.py')
text = path.read_text()
old = '''entries="""
for typ in ['bridge','construction_site','dam','mine_quarry','landfill','rail_crossing','roof_lifecycle','solar_lifecycle']:
    entries+=f"""  {typ}: {{\\n    slug: '{typ}',\\n    label: SCOUT_SPINE_SINGLE_ASSET_CONFIG.{typ}.label,\\n    mapKind: 'single_site',\\n    markerSemantics: 'bounded source opportunity point; no parcel, access, service-radius, or operating boundary implied',\\n    hostNormalization: 'strict',\\n    rasterFrames: [{{ width: 456, height: 210 }}],\\n    tileRanges: [],\\n    tileCenters: singleSiteCenter(SCOUT_SPINE_SINGLE_ASSET_CONFIG.{typ}.center.lon, SCOUT_SPINE_SINGLE_ASSET_CONFIG.{typ}.center.lat),\\n  }},\\n"""
'''
new = '''entries=""
for typ in ['bridge','construction_site','dam','mine_quarry','landfill','rail_crossing','roof_lifecycle','solar_lifecycle']:
    entries += (
        "  " + typ + ": {\\n"
        "    slug: '" + typ + "',\\n"
        "    label: SCOUT_SPINE_SINGLE_ASSET_CONFIG." + typ + ".label,\\n"
        "    mapKind: 'single_site',\\n"
        "    markerSemantics: 'bounded source opportunity point; no parcel, access, service-radius, or operating boundary implied',\\n"
        "    hostNormalization: 'strict',\\n"
        "    rasterFrames: [{ width: 456, height: 210 }],\\n"
        "    tileRanges: [],\\n"
        "    tileCenters: singleSiteCenter(SCOUT_SPINE_SINGLE_ASSET_CONFIG." + typ + ".center.lon, SCOUT_SPINE_SINGLE_ASSET_CONFIG." + typ + ".center.lat),\\n"
        "  },\\n"
    )
'''
if old not in text:
    raise RuntimeError('manifest generator block not found')
text = text.replace(old, new, 1)
old_smoke = "if anchor not in text:raise RuntimeError('predeploy smoke anchor missing');path.write_text(text.replace(anchor,addition,1))"
new_smoke = "if anchor not in text:raise RuntimeError('predeploy smoke anchor missing')\npath.write_text(text.replace(anchor,addition,1))"
if old_smoke not in text:
    raise RuntimeError('predeploy smoke write block not found')
text = text.replace(old_smoke, new_smoke, 1)
path.write_text(text)
print('Patched single-asset generator bootstrap issues.')
