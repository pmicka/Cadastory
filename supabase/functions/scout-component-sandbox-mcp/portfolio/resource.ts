import { loadWarrenPortfolio } from './backend.ts'
import { requiredPortfolioTiles, isTilePng, MAX_TILE_BYTES, type EmbeddedTile } from './raster.ts'

// Preparation helper only. A future registered resource MUST authenticate the owner
// and preserve existing service/profile/exposure gates before calling this helper.
export async function prepareWarrenResource(db: Parameters<typeof loadWarrenPortfolio>[0], html: string, fetchTile: typeof fetch = fetch) {
  const portfolio = await loadWarrenPortfolio(db)
  const tiles: EmbeddedTile[] = []
  for (const tile of requiredPortfolioTiles(portfolio)) {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 8000)
    try {
      const response = await fetchTile(`https://a.tile.openstreetmap.fr/hot/${tile.z}/${tile.x}/${tile.y}.png`, {
        signal: controller.signal, redirect: 'error',
        headers: { 'user-agent': 'Scout-by-Cadastory-Sandbox/1.0 (+https://github.com/pmicka/Cadastory)' },
      })
      if (!response.ok || response.headers.get('content-type')?.split(';')[0] !== 'image/png' || !response.body) throw new Error('Portfolio raster unavailable')
      const reader = response.body.getReader(), chunks: Uint8Array[] = []
      let size = 0
      try {
        for (;;) {
          const {done,value} = await reader.read()
          if (done) break
          size += value.length
          if (size > MAX_TILE_BYTES) throw new Error('Portfolio raster budget exceeded')
          chunks.push(value)
        }
      } finally { await reader.cancel().catch(() => {}); reader.releaseLock() }
      const bytes = new Uint8Array(size)
      let offset = 0
      for (const chunk of chunks) { bytes.set(chunk,offset); offset += chunk.length }
      if (!isTilePng(bytes)) throw new Error('Portfolio raster format rejected')
      let binary = ''
      for (const byte of bytes) binary += String.fromCharCode(byte)
      tiles.push({url:tile.url,data_url:`data:image/png;base64,${btoa(binary)}`})
    } finally { clearTimeout(timeout) }
  }
  if (!html.includes('__SCOUT_EMBEDDED_RASTER_TILES__')) throw new Error('Portfolio resource placeholder missing')
  return {
    portfolio,
    html: html.replace('__SCOUT_EMBEDDED_RASTER_TILES__', () => JSON.stringify(tiles).replaceAll('<','\\u003c')),
  }
}
