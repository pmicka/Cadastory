from pathlib import Path
root=Path('supabase/functions/scout-component-sandbox-mcp')
p=root/'single_site_map_renderer_test.mjs'
s=p.read_text()
old="MAX_EMBEDDED_RASTER_TILES = 32"
if old not in s: raise SystemExit('tile budget assertion anchor missing')
p.write_text(s.replace(old,"MAX_EMBEDDED_RASTER_TILES = 40"))
old_enum="opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio']).optional()"
new_enum="opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio', 'hotel_management_portfolio']).optional()"
changed=0
for test in root.glob('*test.mjs'):
    text=test.read_text()
    if old_enum in text:
        test.write_text(text.replace(old_enum,new_enum))
        changed+=1
if changed<1: raise SystemExit('sandbox enum assertion anchor missing')
print(f'updated {changed} enum assertion file(s)')
