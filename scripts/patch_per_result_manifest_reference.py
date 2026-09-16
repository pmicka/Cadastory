from pathlib import Path

path = Path('supabase/functions/scout-component-sandbox-mcp/index.ts')
text = path.read_text()
if '  SCOUT_SANDBOX_OPPORTUNITY_TYPES,\n' not in text:
    anchor = '  SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES,\n'
    if anchor not in text:
        raise RuntimeError('manifest import anchor missing')
    text = text.replace(anchor, anchor + '  SCOUT_SANDBOX_OPPORTUNITY_TYPES,\n', 1)
path.write_text(text)
print('Preserved canonical opportunity-type manifest reference.')
