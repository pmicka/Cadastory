import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1.0.14'
import { SCOUT_VIEW_HTML } from './view.generated.ts'

Deno.test('minimal View uses the standard MCP Apps notification lifecycle', () => {
  assertStringIncludes(SCOUT_VIEW_HTML, 'Scout View v5 loaded')
  assertEquals(SCOUT_VIEW_HTML.includes('ui/notifications/tool-result'), true)
  assertEquals(SCOUT_VIEW_HTML.includes('window.openai'), false)
  assertEquals(SCOUT_VIEW_HTML.includes('component_v'), false)
  assertEquals(SCOUT_VIEW_HTML.includes('https://unpkg.com'), false)
  assertEquals(SCOUT_VIEW_HTML.includes('https://cdn.'), false)
})
