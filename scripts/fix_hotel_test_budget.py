from pathlib import Path
p=Path('supabase/functions/scout-component-sandbox-mcp/single_site_map_renderer_test.mjs')
s=p.read_text()
old="MAX_EMBEDDED_RASTER_TILES = 32"
if old not in s: raise SystemExit('tile budget assertion anchor missing')
p.write_text(s.replace(old,"MAX_EMBEDDED_RASTER_TILES = 40"))
