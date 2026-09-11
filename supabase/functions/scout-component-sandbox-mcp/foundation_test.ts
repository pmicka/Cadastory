import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1.0.14'
import { SCOUT_VIEW_HTML } from './view.generated.ts'

Deno.test('minimal View uses the current MCP Apps lifecycle', () => {
  assertStringIncludes(SCOUT_VIEW_HTML, 'Scout View v6 loaded')
  assertStringIncludes(SCOUT_VIEW_HTML, 'structuredContent?.names')
  assertStringIncludes(SCOUT_VIEW_HTML, 'new In()')
  assertEquals(SCOUT_VIEW_HTML.includes('window.openai'), false)
  assertEquals(SCOUT_VIEW_HTML.includes('https://unpkg.com'), false)
  assertEquals(SCOUT_VIEW_HTML.includes('https://cdn.'), false)
})
