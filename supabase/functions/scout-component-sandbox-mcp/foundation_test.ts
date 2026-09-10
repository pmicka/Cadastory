import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1.0.14'
import { SCOUT_VIEW_HTML } from './view.generated.ts'

Deno.test('minimal View uses one current MCP Apps lifecycle', () => {
  assertStringIncludes(SCOUT_VIEW_HTML, 'Scout View rendered')
  assertEquals((SCOUT_VIEW_HTML.match(/\.connect\(\)/g) || []).length, 1)
  assertEquals(SCOUT_VIEW_HTML.includes('window.openai'), false)
  assertEquals(SCOUT_VIEW_HTML.includes('component_v'), false)
  assertEquals(SCOUT_VIEW_HTML.includes('https://unpkg.com'), false)
  assertEquals(SCOUT_VIEW_HTML.includes('https://cdn.'), false)
})
