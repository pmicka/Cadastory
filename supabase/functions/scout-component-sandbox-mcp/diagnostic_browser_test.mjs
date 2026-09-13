// Local Chromium harness: simulated App delivery, not ChatGPT host verification.
// PLAYWRIGHT_MODULE must point to an installed playwright index.mjs.
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { build } from 'esbuild'
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright')
const browser = await chromium.launch({headless:true, executablePath:process.env.CHROMIUM_EXECUTABLE, args:process.env.CHROMIUM_EXECUTABLE ? ['--no-sandbox','--disable-dev-shm-usage','--no-zygote','--single-process'] : []})
const context = await browser.newContext({viewport:{width:400,height:1000}})
const fixtureText = await readFile(new URL('./swppp_site_map_renderer_test.mjs', import.meta.url), 'utf8')
const start = fixtureText.indexOf('const exemplar = ')
const end = fixtureText.indexOf('\n}\n', start) + 2
const exemplar = Function(fixtureText.slice(start,end) + '; return exemplar')()
const bundle = await build({entryPoints:['view.ts'],bundle:true,write:false,format:'esm',plugins:[{name:'test-host',setup(b){b.onResolve({filter:/^@modelcontextprotocol\/ext-apps$/},()=>({path:'stub',namespace:'stub'}));b.onLoad({filter:/.*/,namespace:'stub'},()=>({contents:'export class App { constructor(){globalThis.testApp=this} async connect(){} } export class PostMessageTransport {}'}))}}]})
const frameBundle = await build({entryPoints:['swppp_site_map_renderer.ts'],bundle:true,write:false,format:'esm'})
const {buildScoutSwpppSiteRasterFrame} = await import('data:text/javascript;base64,'+Buffer.from(frameBundle.outputFiles[0].text).toString('base64'))
const modelBundle = await build({entryPoints:['swppp_site_map_model.ts'],bundle:true,write:false,format:'esm'})
const {buildScoutSandboxSwpppSiteOpportunity} = await import('data:text/javascript;base64,'+Buffer.from(modelBundle.outputFiles[0].text).toString('base64'))
const frame = buildScoutSwpppSiteRasterFrame(exemplar,456,210,{tileUrlTemplate:'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/scout-component-sandbox-mcp/map-tile/{z}/{x}/{y}.png'})
const transportBundle = await build({entryPoints:['swppp_site_transport.ts'],bundle:true,write:false,format:'esm'})
const {buildScoutSwpppSiteTransport} = await import('data:text/javascript;base64,'+Buffer.from(transportBundle.outputFiles[0].text).toString('base64'))
const template = await readFile('view.template.html','utf8')
try {
 for (const scenario of ['success','empty','invalid_json','invalid_map','no_bitmap','decode_reject','no_context','draw_reject']) {
  const page = await context.newPage()
  await page.route('**/map-tile/**', route=>route.abort())
  const png = await page.evaluate(()=>{const c=document.createElement('canvas');c.width=c.height=256;c.getContext('2d').fillRect(0,0,256,256);return c.toDataURL('image/png')})
  const tiles = frame.tiles.map(tile=>({url:tile.url,data_url:png}))
  const payload = scenario==='empty' ? '[]' : scenario==='invalid_json' ? 'broken' : JSON.stringify(tiles)
  await page.setContent(template.replace('__SCOUT_EMBEDDED_RASTER_TILES__',payload).replace('__SCOUT_DIAGNOSTIC_RESOURCE_URI__','ui://scout/component-sandbox/v23'))
  await page.evaluate(s=>{
   if(s==='no_bitmap')globalThis.createImageBitmap=undefined
   if(s==='decode_reject')globalThis.createImageBitmap=async()=>{throw new DOMException('PRIVATE RAW ERROR','InvalidStateError')}
   if(s==='no_context')HTMLCanvasElement.prototype.getContext=()=>null
   if(s==='draw_reject')CanvasRenderingContext2D.prototype.drawImage=()=>{throw new DOMException('PRIVATE RAW ERROR','InvalidStateError')}
  },scenario)
  await page.addScriptTag({type:'module',content:bundle.outputFiles[0].text})
  await page.waitForFunction(()=>Boolean(globalThis.testApp?.ontoolresult))
  await page.evaluate(({map,opportunity,scenario})=>globalThis.testApp.ontoolresult({structuredContent:{opportunity_type:'swppp_site',map:scenario==='invalid_map'?{}:map,opportunity}}),{map:buildScoutSwpppSiteTransport(exemplar),opportunity:buildScoutSandboxSwpppSiteOpportunity(exemplar),scenario})
  await page.waitForFunction(()=>document.querySelector('[data-scout-diagnostic-report]').textContent.includes('viewReady: true') || document.querySelector('[data-scout-map-state]').textContent==='Site map unavailable')
  await page.locator('summary').click()
  const report=await page.locator('[data-scout-diagnostic-report]').innerText()
  assert.ok(!report.includes('PRIVATE RAW ERROR'))
  assert.ok(report.includes('resource: ui://scout/component-sandbox/v23'))
  if(scenario==='success') {assert.ok(report.includes('branch: canvas'));assert.ok(report.includes('viewReady: true'));assert.ok(report.includes('overlayHidden: true'))}
  if(scenario==='empty'||scenario==='invalid_json') assert.ok(report.includes('branch: image'))
  if(scenario==='invalid_json') assert.ok(report.includes('jsonParse: failed'))
  if(scenario==='invalid_map') assert.ok(report.includes('mapNormalizer: rejected'))
  if(scenario==='no_bitmap') assert.ok(report.includes('bitmapAvailable: false'))
  if(scenario==='decode_reject') assert.ok(report.includes('lastError: InvalidStateError'))
  if(scenario==='no_context') assert.ok(report.includes('context2d: unavailable'))
  if(scenario==='draw_reject') assert.match(report,/drawFailed: [1-9]/)
  console.log(`${scenario}: passed`)
  await page.close()
 }
} finally {await browser.close()}
