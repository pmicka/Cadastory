from pathlib import Path
root=Path('supabase/functions/scout-component-sandbox-mcp')
p=root/'single_site_map_renderer_test.mjs'
s=p.read_text()
old="MAX_EMBEDDED_RASTER_TILES = 32"
if old not in s: raise SystemExit('tile budget assertion anchor missing')
p.write_text(s.replace(old,"MAX_EMBEDDED_RASTER_TILES = 40"))
old_enum="opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio']).optional()"
new_enum="opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio', 'hotel_management_portfolio']).optional()"
old_compact="enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio','dealership_group_portfolio']"
new_compact="enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio','dealership_group_portfolio','hotel_management_portfolio']"
changed=0
compact_changed=0
for test in root.glob('*test.mjs'):
    text=test.read_text()
    original=text
    if old_enum in text:
        text=text.replace(old_enum,new_enum)
        changed+=1
    if old_compact in text:
        text=text.replace(old_compact,new_compact)
        compact_changed+=1
    if text!=original: test.write_text(text)
if changed<1: raise SystemExit('sandbox enum assertion anchor missing')
if compact_changed<1: raise SystemExit('compact gateway enum assertion anchor missing')
hotel=root/'hotel_portfolio_map_renderer_test.mjs'
ht=hotel.read_text()
needle="modelSource.includes('linkConfidenceValue == null')"
if needle not in ht: raise SystemExit('hotel compatibility assertion anchor missing')
hotel.write_text(ht.replace(needle,"modelSource.includes('confidenceValue==null')"))
print(f'updated {changed} component enum, {compact_changed} compact gateway, and hotel compatibility assertions')
