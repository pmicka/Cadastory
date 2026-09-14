import assert from 'node:assert/strict'
import { build } from 'esbuild'

const directory = new URL('./', import.meta.url)
const gateways = [
  new URL('../scout-connect/index.ts', directory),
  new URL('../scout-mcp-contract/index.ts', directory),
]

for (const entry of gateways) {
  const result = await build({
    entryPoints: [entry.pathname],
    bundle: true,
    format: 'esm',
    platform: 'neutral',
    target: 'es2022',
    write: false,
    external: ['jsr:*', 'npm:*'],
    logLevel: 'silent',
  })
  assert.ok(result.outputFiles[0]?.text.length > 0)
}

console.log('Scout sandbox gateway TypeScript syntax/bundle checks passed.')
