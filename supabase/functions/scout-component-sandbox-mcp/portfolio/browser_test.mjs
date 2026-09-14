// Local Chromium with simulated App delivery and synthetic PNGs; not host verification.
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { build } from 'esbuild'
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright')
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE,args:process.env.CHROMIUM_EXECUTABLE?['--no-sandbox','--disable-dev-shm-usage','--no-zygote','--single-process']:[]})
const context=await browser.newContext({viewport:{width:400,height:1200}})
const load=async file=>{const b=await build({entryPoints:[file],bundle:true,write:false,format:'esm'});return import('data:text/javascript;base64,'+Buffer.from(b.outputFiles[0].text).toString('base64'))}
const {requiredPortfolioTiles}=await load('portfolio/raster.ts'),{buildPortfolioResult}=await load('portfolio/result.ts')
const fixture=JSON.parse(await readFile('portfolio/warren_fixture.json','utf8')),result=buildPortfolioResult(fixture)
const bundle=await build({entryPoints:['view.ts'],bundle:true,write:false,format:'esm',plugins:[{name:'test-host',setup(b){b.onResolve({filter:/^@modelcontextprotocol\/ext-apps$/},()=>({path:'stub',namespace:'stub'}));b.onLoad({filter:/.*/,namespace:'stub'},()=>({contents:'export class App { constructor(){globalThis.testApp=this} async connect(){} } export class PostMessageTransport {}'}))}}]})
const template=await readFile('view.template.html','utf8')
try {
 for(const scenario of ['success','missing_tile','wrong_identity','no_context','no_decoder','decode_failure','paint_failure','late_decode']) {
  const page=await context.newPage();let requests=0
  await page.route('**/map-tile/**',route=>{requests++;return route.abort()})
  const png=await page.evaluate(()=>{const c=document.createElement('canvas');c.width=c.height=256;const x=c.getContext('2d');x.fillStyle='#d0e1ca';x.fillRect(0,0,256,256);return c.toDataURL()})
  let entries=requiredPortfolioTiles(fixture).map(tile=>({url:tile.url,data_url:png}));if(scenario==='missing_tile')entries.pop()
  await page.setContent(template.replace('__SCOUT_EMBEDDED_RASTER_TILES__',JSON.stringify(entries)).replace('__SCOUT_DIAGNOSTIC_RESOURCE_URI__','ui://scout/portfolio-test'))
  await page.evaluate(s=>{
   if(s==='no_context')HTMLCanvasElement.prototype.getContext=()=>null
   if(s==='no_decoder')globalThis.createImageBitmap=undefined
   if(s==='decode_failure')globalThis.createImageBitmap=async()=>{throw new Error('PRIVATE ERROR')}
   if(s==='paint_failure')CanvasRenderingContext2D.prototype.drawImage=()=>{throw new Error('PRIVATE ERROR')}
   if(s==='late_decode'){const original=createImageBitmap;globalThis.releaseDecodes=[];globalThis.createImageBitmap=(...args)=>new Promise(resolve=>globalThis.releaseDecodes.push(async()=>resolve(await original(...args))))}
  },scenario)
  await page.addScriptTag({type:'module',content:bundle.outputFiles[0].text});await page.waitForFunction(()=>Boolean(globalThis.testApp?.ontoolresult))
  const payload=structuredClone(result);if(scenario==='wrong_identity')payload.opportunity.organization_id='wrong'
  await page.evaluate(value=>globalThis.testApp.ontoolresult({structuredContent:value}),payload)
  if(scenario==='late_decode') {
    await page.evaluate(async()=>{await globalThis.testApp.onteardown();await Promise.all(globalThis.releaseDecodes.map(release=>release()))})
    await page.waitForFunction(()=>document.querySelectorAll('[data-scout-map] canvas').length===0)
    assert.equal(await page.locator('[data-scout-portfolio-controls] select').count(),0)
  } else if(scenario==='success') {
    await page.waitForFunction(()=>document.querySelector('[data-scout-map-state]').hidden)
    assert.equal(await page.locator('[data-scout-map] [data-member-id]').count(),24)
    assert.equal(await page.locator('[data-scout-portfolio-controls] option').count(),25)
    for(const member of fixture.members) {
      await page.locator('[data-scout-portfolio-controls] select').selectOption(member.id)
      assert.ok((await page.locator('[data-scout-portfolio-controls] [role=status]').innerText()).includes(member.name))
      assert.equal(await page.locator(`[data-member-id="${member.id}"]`).evaluate(e=>e.style.zIndex),'5')
    }
    const selected=fixture.members.at(-1).id
    for(const viewportWidth of [340,520]) {
      await page.setViewportSize({width:viewportWidth,height:1200})
      await page.waitForFunction(()=>document.querySelector('[data-scout-map] canvas').width===Math.max(280,Math.min(456,Math.round(document.querySelector('[data-scout-map]').clientWidth))))
      assert.equal(await page.locator('[data-scout-portfolio-controls] select').inputValue(),selected)
    }
    await page.waitForFunction(()=>document.querySelector('[data-scout-diagnostic-report]').textContent.includes('rendererReady: true'))
    const pixel=await page.locator('[data-scout-map] canvas').evaluate(c=>Array.from(c.getContext('2d').getImageData(1,1,1,1).data))
    await page.waitForFunction(()=>document.querySelector('[data-scout-diagnostic-report]').textContent.includes('rendererReady: true'))
    assert.deepEqual(pixel,[208,225,202,255])
    if(process.env.PORTFOLIO_SCREENSHOT)await page.screenshot({path:process.env.PORTFOLIO_SCREENSHOT,fullPage:true})
    await page.evaluate(()=>globalThis.testApp.ontoolresult({structuredContent:{opportunity_type:'premium_exterior',opportunity:null,map:null}}))
    assert.equal(await page.locator('[data-scout-portfolio-controls]').isHidden(),true)
    assert.equal(await page.locator('[data-scout-map] canvas').count(),0)
  } else {
    await page.waitForFunction(()=>document.querySelector('[data-scout-map-state]').textContent==='Portfolio map unavailable')
    assert.equal(await page.locator('[data-scout-map-state]').isVisible(),true)
    assert.ok(!(await page.locator('[data-scout-diagnostic-report]').textContent()).includes('PRIVATE ERROR'))
  }
  assert.equal(requests,0);console.log(`${scenario}: passed`);await page.close()
 }
} finally {await browser.close()}
