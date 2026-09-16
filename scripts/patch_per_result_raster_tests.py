from pathlib import Path

path = Path('supabase/functions/scout-component-sandbox-mcp/single_site_map_renderer_test.mjs')
text = path.read_text()
old = '''assert.ok(server.includes('loadEmbeddedSandboxTiles'))
assert.ok(server.includes('SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES'))
assert.ok(server.includes('buildScoutSingleSiteRasterFrame(premiumMap, 456, 210'))
assert.ok(server.includes('buildScoutWaterTankRasterFrame(waterTankMap, 456, 210'))
assert.ok(server.includes('for (const type of SCOUT_SANDBOX_PORTFOLIO_TYPES)'))'''
new = '''assert.equal(server.includes('loadEmbeddedSandboxTiles'), false)
assert.ok(server.includes('SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES'))
assert.ok(server.includes('loadEmbeddedRasterTilesForSelection'))
assert.ok(server.includes('selectedRasterFrames'))
assert.ok(server.includes("'scout/rasterTiles'"))
assert.ok(server.includes(".replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]')"))'''
if old not in text:
    raise RuntimeError('legacy global raster assertions not found')
text = text.replace(old,new,1)
old2 = "assert.ok(server.includes('scoutSandboxCompatibilityUsesEmbeddedRaster(compatibilityUri)'))"
new2 = "assert.equal(server.includes('scoutSandboxCompatibilityUsesEmbeddedRaster'), false)"
if old2 not in text:
    raise RuntimeError('legacy compatibility raster assertion not found')
path.write_text(text.replace(old2,new2,1))
print('Updated legacy raster resource assertions.')
