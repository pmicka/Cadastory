from pathlib import Path
import re

root = Path('supabase/functions/scout-component-sandbox-mcp')
changed = []
for path in root.glob('*test*.mjs'):
    text = path.read_text()
    original = text

    text = re.sub(
        r'''assert\.ok\((?P<var>[A-Za-z_][A-Za-z0-9_]*)\.includes\(["']text: \(await loadScoutViewHtml\(\)\)["']\)\)''',
        lambda m: f'''assert.ok({m.group('var')}.includes("text: staticScoutViewHtml("))''',
        text,
    )
    text = re.sub(
        r'''assert\.ok\((?P<var>[A-Za-z_][A-Za-z0-9_]*)\.includes\(["']SCOUT_VIEW_HTML\.replace\('__SCOUT_EMBEDDED_RASTER_TILES__', JSON\.stringify\(tiles\)\)["']\)\)''',
        lambda m: f'''assert.ok({m.group('var')}.includes(".replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]')"))''',
        text,
    )
    text = text.replace(
        '''assert.equal(server.includes("_meta: { 'scout/rasterTiles': await loadEmbeddedSwpppTiles(map) }"), false)''',
        '''assert.ok(server.includes("_meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('swppp_site', map) }"))''',
    )

    if text != original:
        path.write_text(text)
        changed.append(str(path))

stale = []
for path in root.glob('*test*.mjs'):
    text = path.read_text()
    if 'loadScoutViewHtml' in text or "JSON.stringify(tiles))" in text:
        stale.append(str(path))
if stale:
    raise RuntimeError('stale global resource-raster assertions remain: ' + ', '.join(stale))

print('Migrated per-result resource assertions in', len(changed), 'test files')
