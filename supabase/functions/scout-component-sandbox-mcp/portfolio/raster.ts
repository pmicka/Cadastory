import { buildPortfolioFrame } from './frame.ts'

// Logical keys only: the portfolio View never requests this single-site proxy.
export const PORTFOLIO_TILE_TEMPLATE = 'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/scout-component-sandbox-mcp/map-tile/{z}/{x}/{y}.png'
export const MAX_TILE_BYTES = 140_000
export const MAX_PORTFOLIO_TILES = 12
export type EmbeddedTile = { url: string; data_url: string }

export function requiredPortfolioTiles(value: unknown) {
  const tiles = new Map<string, ReturnType<typeof buildPortfolioFrame>['tiles'][number]>()
  // All supported integer widths, including any fitted-zoom transition.
  for (let width = 280; width <= 456; width++) {
    for (const tile of buildPortfolioFrame(value, width, 210, PORTFOLIO_TILE_TEMPLATE).tiles) tiles.set(tile.url, tile)
  }
  if (tiles.size > MAX_PORTFOLIO_TILES) throw new Error('Portfolio tile budget exceeded')
  return [...tiles.values()]
}

export function isTilePng(bytes: Uint8Array) {
  if (bytes.length < 33 || bytes.length > MAX_TILE_BYTES) return false
  const signature = [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82]
  if (!signature.every((b,i) => bytes[i] === b)) return false
  const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  return header.getUint32(16) === 256 && header.getUint32(20) === 256
}

export function decodeTileBytes(dataUrl: string) {
  const prefix = 'data:image/png;base64,'
  if (!dataUrl.startsWith(prefix) || dataUrl.length > 187_000) throw new Error('Invalid raster payload')
  const encoded = dataUrl.slice(prefix.length)
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) throw new Error('Invalid raster encoding')
  const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0))
  if (!isTilePng(bytes)) throw new Error('Invalid raster dimensions or format')
  return bytes
}

export function validatePortfolioTiles(value: unknown, entries: unknown) {
  const required = requiredPortfolioTiles(value)
  if (!Array.isArray(entries) || entries.length !== required.length) throw new Error('Portfolio raster coverage mismatch')
  const expected = new Set(required.map(tile => tile.url)), tiles = new Map<string, Uint8Array>()
  for (const entry of entries) {
    if (!entry || typeof entry.url !== 'string' || typeof entry.data_url !== 'string' || !expected.has(entry.url) || tiles.has(entry.url)) throw new Error('Portfolio raster identity mismatch')
    tiles.set(entry.url, decodeTileBytes(entry.data_url))
  }
  return tiles
}
