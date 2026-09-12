import { readFile, writeFile } from 'node:fs/promises'

const pncPath = 'supabase/functions/scout-component-sandbox-mcp/single_site_map_renderer_test.mjs'
let pnc = await readFile(pncPath, 'utf8')

function replacePnc(before, after) {
  const index = pnc.indexOf(before)
  if (index < 0) throw new Error(`Missing expected PNC regression text: ${before}`)
  pnc = pnc.slice(0, index) + after + pnc.slice(index + before.length)
}

replacePnc(
  "assert.ok(server.includes(\"const RESOURCE_URI = 'ui://scout/component-sandbox/v15'\"))",
  "assert.ok(server.includes(\"const RESOURCE_URI = 'ui://scout/component-sandbox/v16'\"))\nassert.ok(server.includes(\"'ui://scout/component-sandbox/v15'\"))",
)
replacePnc(
  "assert.ok(mapContract.includes('mobile ChatGPT host: **verified working**'))\nassert.ok(mapContract.includes('desktop ChatGPT host: still requires explicit visual verification'))",
  "assert.ok(mapContract.includes('mobile ChatGPT host / PNC premium exterior: **verified working**'))\nassert.ok(mapContract.includes('desktop ChatGPT host / PNC premium exterior: still requires explicit visual verification'))",
)

await writeFile(pncPath, pnc)
