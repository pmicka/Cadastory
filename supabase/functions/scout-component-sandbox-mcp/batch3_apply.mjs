import { readFile, writeFile } from 'node:fs/promises'

const directory = new URL('./', import.meta.url)

async function edit(relative, mutate) {
  const url = new URL(relative, directory)
  const before = await readFile(url, 'utf8')
  const after = mutate(before)
  if (after === before) throw new Error(`No Batch 3 change applied to ${relative}`)
  await writeFile(url, after)
}

function replaceOnce(source, search, replacement, label) {
  const first = source.indexOf(search)
  if (first < 0) throw new Error(`Missing Batch 3 anchor: ${label}`)
  if (source.indexOf(search, first + search.length) >= 0) throw new Error(`Non-unique Batch 3 anchor: ${label}`)
  return source.slice(0, first) + replacement + source.slice(first + search.length)
}

const OPENFREEMAP_ORIGIN = 'https://tiles.openfreemap.org'
const OPENFREEMAP_STYLE = `${OPENFREEMAP_ORIGIN}/styles/positron`

await edit('contract.ts', (source) => replaceOnce(
  source,
  `export type ScoutSandboxResult = {\n  surface: 'scout_component_sandbox'\n  names: string[]\n  opportunity: ScoutSandboxOpportunity\n}`,
  `export type ScoutSandboxResult = {\n  surface: 'scout_component_sandbox'\n  names: string[]\n  opportunity: ScoutSandboxOpportunity\n  map: ScoutSandboxSingleSiteMap\n}`,
  'ScoutSandboxResult map field',
))

await edit('single_site_map_renderer.ts', (source) => {
  let next = replaceOnce(
    source,
    `  onError?: (error: Error) => void\n}`,
    `  onError?: (error: Error) => void\n  onReady?: () => void\n}`,
    'renderer onReady option',
  )
  next = replaceOnce(
    next,
    `    map.fitBounds(model.bounds, {\n      padding: options.padding ?? 24,\n      maxZoom: options.maxZoom ?? 19,\n      duration: 0,\n    })\n  })`,
    `    map.fitBounds(model.bounds, {\n      padding: options.padding ?? 24,\n      maxZoom: options.maxZoom ?? 19,\n      duration: 0,\n    })\n    options.onReady?.()\n  })`,
    'renderer ready callback',
  )
  return next
})

await edit('index.ts', (source) => {
  let next = replaceOnce(
    source,
    `  normalizeScoutSandboxNames,\n  normalizeScoutSandboxOpportunity,\n  type ScoutSandboxResult,`,
    `  normalizeScoutSandboxNames,\n  normalizeScoutSandboxOpportunity,\n  normalizeScoutSandboxSingleSiteMap,\n  type ScoutSandboxResult,`,
    'server map normalizer import',
  )
  next = replaceOnce(next, `const RESOURCE_URI = 'ui://scout/component-sandbox/v12'`, `const RESOURCE_URI = 'ui://scout/component-sandbox/v13'`, 'server v13 resource URI')
  next = replaceOnce(
    next,
    `const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v11',`,
    `const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v12',\n  'ui://scout/component-sandbox/v11',`,
    'server v12 compatibility URI',
  )
  next = replaceOnce(
    next,
    `const ENUMERATION_CONTRACT = 'scout-enumeration-v1'`,
    `const ENUMERATION_CONTRACT = 'scout-enumeration-v1'\nconst MAP_RESOURCE_ORIGIN = '${OPENFREEMAP_ORIGIN}'`,
    'server map provider origin',
  )
  next = replaceOnce(
    next,
    `async function loadScoutSandboxOpportunity() {\n  const { data, error } = await admin.rpc('scout_get_component_sandbox_opportunity_v1_internal')\n  if (error) throw new Error('Scout sandbox opportunity is unavailable')\n  const opportunity = normalizeScoutSandboxOpportunity(data)\n  if (!opportunity) throw new Error('Scout sandbox opportunity did not satisfy the bounded contract')\n  return opportunity\n}`,
    `async function loadScoutSandboxOpportunity() {\n  const { data, error } = await admin.rpc('scout_get_component_sandbox_opportunity_v1_internal')\n  if (error) throw new Error('Scout sandbox opportunity is unavailable')\n  const opportunity = normalizeScoutSandboxOpportunity(data)\n  if (!opportunity) throw new Error('Scout sandbox opportunity did not satisfy the bounded contract')\n  return opportunity\n}\n\nasync function loadScoutSandboxSingleSiteMap() {\n  const { data, error } = await admin.rpc('scout_get_component_sandbox_premium_exterior_map_v1_internal')\n  if (error) throw new Error('Scout sandbox single-site map is unavailable')\n  const map = normalizeScoutSandboxSingleSiteMap(data)\n  if (!map) throw new Error('Scout sandbox single-site map did not satisfy the bounded contract')\n  return map\n}`,
    'server bounded map loader',
  )
  next = replaceOnce(
    next,
    `function makeServer() {`,
    `const sandboxMapSchema = z.object({\n  contract_version: z.literal('single_site_map_v1'),\n  opportunity_type: z.literal('premium_exterior'),\n  opportunity_id: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i),\n  name: z.string().min(1).max(160),\n  address: z.string().min(1).max(240),\n  site_point: z.object({\n    lon: z.number().min(-180).max(180),\n    lat: z.number().min(-90).max(90),\n    source: z.literal('premium_exterior_target_geocode'),\n    method: z.string().min(1).max(120),\n  }),\n  footprint: z.object({\n    geometry: z.object({\n      type: z.literal('Polygon'),\n      coordinates: z.array(z.array(z.tuple([z.number().min(-180).max(180), z.number().min(-90).max(90)])).min(4).max(2048)).min(1).max(8),\n    }),\n    bounds: z.object({\n      west: z.number().min(-180).max(180),\n      south: z.number().min(-90).max(90),\n      east: z.number().min(-180).max(180),\n      north: z.number().min(-90).max(90),\n    }),\n    footprint_sqft: z.number().min(0).max(1_000_000_000),\n    source: z.object({\n      slug: z.string().min(1).max(120),\n      name: z.string().min(1).max(240),\n      native_id: z.string().min(1).max(240),\n      image_date: z.string().min(1).max(40),\n      validation_method: z.string().min(1).max(120),\n    }),\n  }),\n  linkage: z.object({\n    status: z.literal('reconciled_existing_evidence'),\n    basis: z.string().min(1).max(1000),\n    guardrail: z.string().min(1).max(1000),\n    target_to_footprint_m: z.number().min(0).max(10000),\n    stored_match_distance_m: z.number().min(0).max(10000),\n  }),\n})\n\nfunction makeServer() {`,
    'server bounded map schema',
  )
  next = next.replaceAll(
    `csp: { connectDomains: [], resourceDomains: [] }`,
    `csp: { connectDomains: [MAP_RESOURCE_ORIGIN], resourceDomains: [MAP_RESOURCE_ORIGIN] }`,
  )
  next = replaceOnce(
    next,
    `        opportunity: z.object({\n          name: z.string().min(1).max(160),`,
    `        opportunity: z.object({\n          name: z.string().min(1).max(160),`,
    'server opportunity schema anchor',
  )
  next = replaceOnce(
    next,
    `          guardrail: z.string().min(1).max(1000),\n        }),\n      }),`,
    `          guardrail: z.string().min(1).max(1000),\n        }),\n        map: sandboxMapSchema,\n      }),`,
    'server output map schema',
  )
  next = replaceOnce(
    next,
    `      const [names, opportunity] = await Promise.all([\n        loadScoutSandboxNames(),\n        loadScoutSandboxOpportunity(),\n      ])`,
    `      const [names, opportunity, map] = await Promise.all([\n        loadScoutSandboxNames(),\n        loadScoutSandboxOpportunity(),\n        loadScoutSandboxSingleSiteMap(),\n      ])\n      if (map.name !== opportunity.name || map.address !== opportunity.address) {\n        throw new Error('Scout sandbox opportunity and map identity do not match')\n      }`,
    'server map result loading',
  )
  next = replaceOnce(
    next,
    `        opportunity,\n      }`,
    `        opportunity,\n        map,\n      }`,
    'server structuredContent map field',
  )
  next = replaceOnce(
    next,
    `content: [{ type: 'text', text: \`Scout returned the bounded \${opportunity.name} opportunity card.\` }]`,
    `content: [{ type: 'text', text: \`Scout returned the bounded \${opportunity.name} opportunity card with its single-site map.\` }]`,
    'server text fallback',
  )
  return next
})

const viewSource = `import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'\nimport { normalizeScoutSandboxSingleSiteMap } from './contract.ts'\nimport { mountScoutSingleSiteMap, type ScoutSingleSiteMapRendererHandle } from './single_site_map_renderer.ts'\n\ntype ScoutOpportunity = {\n  name: string\n  address: string\n  opportunity_tier: string\n  opportunity_score: number\n  confidence: number\n  story_count: number\n  height_m: number\n  footprint_sqft: number\n  glazing_status: string\n  observed_at: string\n  target_class: string\n  target_subclass: string\n  buyer_resolvability: string\n  guardrail: string\n}\n\nconst SCOUT_MAP_STYLE = '${OPENFREEMAP_STYLE}'\n\nconst title = document.querySelector<HTMLElement>('[data-scout-title]')\nconst tier = document.querySelector<HTMLElement>('[data-scout-tier]')\nconst meta = document.querySelector<HTMLElement>('[data-scout-meta]')\nconst address = document.querySelector<HTMLElement>('[data-scout-address]')\nconst summary = document.querySelector<HTMLElement>('[data-scout-summary]')\nconst guardrail = document.querySelector<HTMLElement>('[data-scout-guardrail]')\nconst state = document.querySelector<HTMLElement>('[data-scout-state]')\nconst carousel = document.querySelector<HTMLElement>('[data-scout-carousel]')\nconst carouselCount = document.querySelector<HTMLElement>('[data-scout-carousel-count]')\nconst carouselDots = Array.from(document.querySelectorAll<HTMLElement>('[data-scout-carousel-dot]'))\nconst mapContainer = document.querySelector<HTMLElement>('[data-scout-map]')\nconst mapState = document.querySelector<HTMLElement>('[data-scout-map-state]')\nlet mapHandle: ScoutSingleSiteMapRendererHandle | null = null\nlet mapGeneration = 0\n\nfunction setState(message: string) {\n  if (state) state.textContent = message.slice(0, 200)\n}\n\nfunction cleanString(value: unknown, maxLength = 1000) {\n  if (typeof value !== 'string') return null\n  const text = value.trim()\n  return text.length > 0 && text.length <= maxLength ? text : null\n}\n\nfunction cleanNumber(value: unknown, minimum: number, maximum: number) {\n  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum\n    ? value\n    : null\n}\n\nfunction normalizeOpportunity(value: unknown): ScoutOpportunity | null {\n  if (!value || typeof value !== 'object' || Array.isArray(value)) return null\n  const source = value as Record<string, unknown>\n  const candidate: ScoutOpportunity = {\n    name: cleanString(source.name, 160) ?? '',\n    address: cleanString(source.address, 240) ?? '',\n    opportunity_tier: cleanString(source.opportunity_tier, 64) ?? '',\n    opportunity_score: cleanNumber(source.opportunity_score, 0, 100) ?? -1,\n    confidence: cleanNumber(source.confidence, 0, 1) ?? -1,\n    story_count: cleanNumber(source.story_count, 0, 1000) ?? -1,\n    height_m: cleanNumber(source.height_m, 0, 10000) ?? -1,\n    footprint_sqft: cleanNumber(source.footprint_sqft, 0, 1_000_000_000) ?? -1,\n    glazing_status: cleanString(source.glazing_status, 80) ?? '',\n    observed_at: cleanString(source.observed_at, 80) ?? '',\n    target_class: cleanString(source.target_class, 80) ?? '',\n    target_subclass: cleanString(source.target_subclass, 80) ?? '',\n    buyer_resolvability: cleanString(source.buyer_resolvability, 120) ?? '',\n    guardrail: cleanString(source.guardrail, 1000) ?? '',\n  }\n  return candidate.name &&\n      candidate.address &&\n      candidate.opportunity_tier &&\n      candidate.opportunity_score >= 0 &&\n      candidate.confidence >= 0 &&\n      Number.isInteger(candidate.story_count) && candidate.story_count >= 0 &&\n      candidate.height_m >= 0 &&\n      candidate.footprint_sqft >= 0 &&\n      candidate.glazing_status &&\n      candidate.observed_at &&\n      candidate.target_class &&\n      candidate.target_subclass &&\n      candidate.buyer_resolvability &&\n      candidate.guardrail\n    ? candidate\n    : null\n}\n\nfunction label(value: string) {\n  const known: Record<string, string> = {\n    very_high: 'Very high',\n    office_highrise: 'Office high-rise',\n    corporate_office: 'Corporate office',\n    confirmed_glazed: 'Confirmed glazed facade',\n    public_operator_or_site_route: 'Public operator / site route',\n  }\n  return known[value] ?? value.replaceAll('_', ' ').replace(/^./, (character) => character.toUpperCase())\n}\n\nfunction formatObserved(value: string) {\n  const date = new Date(value)\n  if (Number.isNaN(date.valueOf())) return value\n  return new Intl.DateTimeFormat('en-US', {\n    year: 'numeric',\n    month: 'short',\n    day: 'numeric',\n  }).format(date)\n}\n\nfunction formatNumber(value: number, maximumFractionDigits = 0) {\n  return new Intl.NumberFormat('en-US', { maximumFractionDigits }).format(value)\n}\n\nfunction renderOpportunity(value: unknown) {\n  const opportunity = normalizeOpportunity(value)\n  if (!opportunity) {\n    if (title) title.textContent = 'Opportunity unavailable'\n    if (tier) tier.textContent = 'Unavailable'\n    if (meta) meta.textContent = 'Scout did not receive a valid bounded opportunity result.'\n    if (address) address.textContent = ''\n    if (summary) summary.textContent = ''\n    if (guardrail) guardrail.textContent = ''\n    setState('Scout opportunity result failed validation')\n    return\n  }\n\n  if (title) title.textContent = opportunity.name\n  if (tier) tier.textContent = label(opportunity.opportunity_tier)\n  if (meta) {\n    meta.textContent = \`Score \${opportunity.opportunity_score}  •  \${Math.round(opportunity.confidence * 100)}% confidence  •  Observed \${formatObserved(opportunity.observed_at)}\`\n  }\n  if (address) address.textContent = opportunity.address\n  if (summary) {\n    summary.textContent = \`\${label(opportunity.target_subclass)}  •  \${label(opportunity.target_class)}  •  \${label(opportunity.glazing_status)}  •  \${opportunity.story_count} stories  •  \${formatNumber(opportunity.height_m, 1)} m  •  \${formatNumber(opportunity.footprint_sqft)} sq ft  •  \${label(opportunity.buyer_resolvability)}\`\n  }\n  if (guardrail) guardrail.textContent = \`Scout guardrail: \${opportunity.guardrail}\`\n  setState(\`Scout opportunity ready: \${opportunity.name}\`)\n}\n\nfunction destroyMap() {\n  mapGeneration += 1\n  mapHandle?.destroy()\n  mapHandle = null\n}\n\nfunction renderMap(value: unknown) {\n  const mapData = normalizeScoutSandboxSingleSiteMap(value)\n  destroyMap()\n  if (!mapContainer || !mapState) return\n  if (!mapData) {\n    mapState.hidden = false\n    mapState.textContent = 'Site map unavailable'\n    setState('Scout single-site map result failed validation')\n    return\n  }\n\n  const generation = ++mapGeneration\n  let ready = false\n  mapState.hidden = false\n  mapState.textContent = 'Loading site map…'\n  mapContainer.setAttribute('aria-label', \`Site map for \${mapData.name}\`)\n\n  try {\n    mapHandle = mountScoutSingleSiteMap(mapContainer, mapData, {\n      style: SCOUT_MAP_STYLE,\n      onReady: () => {\n        if (generation !== mapGeneration) return\n        ready = true\n        mapState.hidden = true\n        setState(\`Scout site map ready: \${mapData.name}\`)\n      },\n      onError: (error) => {\n        if (generation !== mapGeneration) return\n        if (!ready) {\n          mapState.hidden = false\n          mapState.textContent = 'Site map unavailable'\n        }\n        setState(\`Scout map error: \${error.message}\`)\n      },\n    })\n  } catch (error) {\n    mapState.hidden = false\n    mapState.textContent = 'Site map unavailable'\n    setState(\`Scout map initialization failed: \${error instanceof Error ? error.message : String(error)}\`)\n  }\n}\n\nfunction updateCarouselState() {\n  if (!carousel || !carouselCount || carouselDots.length === 0) return\n  const slides = Array.from(carousel.querySelectorAll<HTMLElement>('.media-slide'))\n  if (slides.length === 0) return\n  const viewportCenter = carousel.scrollLeft + carousel.clientWidth / 2\n  let active = 0\n  let bestDistance = Number.POSITIVE_INFINITY\n  for (let index = 0; index < slides.length; index += 1) {\n    const slide = slides[index]\n    const center = slide.offsetLeft + slide.offsetWidth / 2\n    const distance = Math.abs(center - viewportCenter)\n    if (distance < bestDistance) {\n      bestDistance = distance\n      active = index\n    }\n  }\n  carouselCount.textContent = \`\${active + 1} / \${slides.length}\`\n  for (let index = 0; index < carouselDots.length; index += 1) {\n    carouselDots[index].dataset.active = String(index === active)\n  }\n}\n\ncarousel?.addEventListener('scroll', updateCarouselState, { passive: true })\nwindow.addEventListener('resize', updateCarouselState, { passive: true })\nupdateCarouselState()\n\nconst app = new App({ name: 'scout-ui-foundation', version: '2.1.0' })\napp.ontoolinput = () => setState('Scout tool input received')\napp.ontoolresult = (result) => {\n  renderOpportunity(result?.structuredContent?.opportunity)\n  renderMap(result?.structuredContent?.map)\n}\napp.onerror = (error) => setState(\`Scout SDK error: \${error instanceof Error ? error.message : String(error)}\`)\napp.onteardown = async () => {\n  destroyMap()\n  return {}\n}\n\nconst transport = new PostMessageTransport()\ntry {\n  await app.connect(transport)\n  setState('Scout SDK connected; waiting for opportunity result')\n} catch (error) {\n  setState(\`Scout SDK initialization failed: \${error instanceof Error ? error.message : String(error)}\`)\n}\n`
await writeFile(new URL('view.ts', directory), viewSource)

await edit('view.template.html', (source) => {
  let next = replaceOnce(
    source,
    `      .media-slide:nth-child(1) { background: #dce4d9; }\n      .media-slide:nth-child(2) { background: #e6e0d4; }\n      .media-slide:nth-child(3) { background: #d9e1e6; }`,
    `      .media-slide:nth-child(1) { background: #eef1eb; }\n      .media-slide:nth-child(2) { background: #e6e0d4; }\n      .media-slide:nth-child(3) { background: #d9e1e6; }\n      .scout-map {\n        position: absolute;\n        inset: 0;\n        width: 100%;\n        height: 100%;\n      }\n      .scout-map .maplibregl-canvas { pointer-events: none; }\n      .scout-map-state {\n        position: absolute;\n        inset: 0;\n        z-index: 2;\n        display: grid;\n        place-items: center;\n        padding: 16px;\n        background: #eef1eb;\n        color: #657065;\n        font-size: 12px;\n        font-weight: 500;\n        line-height: 16px;\n        text-align: center;\n        pointer-events: none;\n      }\n      .scout-map-state[hidden] { display: none; }`,
    'map tile CSS',
  )
  next = replaceOnce(
    next,
    `  </head>`,
    `    <style>/*__SCOUT_VIEW_STYLE__*/</style>\n  </head>`,
    'MapLibre bundled CSS slot',
  )
  next = replaceOnce(
    next,
    `        <div class="carousel-viewport" data-scout-carousel aria-label="Scout media placeholders">\n          <div class="carousel-strip">\n            <div class="media-slide">\n              <span class="media-glyph" aria-hidden="true">◇</span>\n              <span class="media-circle" aria-hidden="true"></span>\n              <span class="media-placeholder">Placeholder image 1</span>\n              <span class="media-subtext">Media wiring intentionally deferred</span>\n            </div>`,
    `        <div class="carousel-viewport" data-scout-carousel aria-label="Scout opportunity media">\n          <div class="carousel-strip">\n            <div class="media-slide" aria-label="PNC Tower site map">\n              <div class="scout-map" data-scout-map></div>\n              <div class="scout-map-state" data-scout-map-state>Loading site map…</div>\n            </div>`,
    'first carousel tile map',
  )
  return next
})

const buildSource = `import { build } from "esbuild";\nimport { readFile, writeFile } from "node:fs/promises";\n\nconst directory = new URL("./", import.meta.url);\nconst bundlePath = new URL("./view.bundle.js", directory);\nconst stylePath = new URL("./view.bundle.css", directory);\nconst templatePath = new URL("./view.template.html", directory);\nconst generatedPath = new URL("./view.generated.ts", directory);\n\nawait build({\n  entryPoints: [new URL("./view.ts", directory).pathname],\n  outfile: bundlePath.pathname,\n  bundle: true,\n  format: "esm",\n  platform: "browser",\n  target: "es2022",\n  minify: true,\n  legalComments: "none",\n});\n\nconst [template, bundle, css] = await Promise.all([\n  readFile(templatePath, "utf8"),\n  readFile(bundlePath, "utf8"),\n  readFile(stylePath, "utf8"),\n]);\nconst html = template\n  .replace("/*__SCOUT_VIEW_STYLE__*/", () => css)\n  .replace("/*__SCOUT_VIEW_BUNDLE__*/", () => bundle);\nawait writeFile(generatedPath, \`// Generated by build-view.mjs. Do not edit.\\nexport const SCOUT_VIEW_HTML = \${JSON.stringify(html)};\\n\`);\n`
await writeFile(new URL('build-view.mjs', directory), buildSource)

const gatewayMapSchema = `function sandboxMapSchema(){return {type:'object',properties:{contract_version:{type:'string',enum:['single_site_map_v1']},opportunity_type:{type:'string',enum:['premium_exterior']},opportunity_id:{type:'string',pattern:'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'},name:{type:'string',minLength:1,maxLength:160},address:{type:'string',minLength:1,maxLength:240},site_point:{type:'object',properties:{lon:{type:'number',minimum:-180,maximum:180},lat:{type:'number',minimum:-90,maximum:90},source:{type:'string',enum:['premium_exterior_target_geocode']},method:{type:'string',minLength:1,maxLength:120}},required:['lon','lat','source','method'],additionalProperties:false},footprint:{type:'object',properties:{geometry:{type:'object',properties:{type:{type:'string',enum:['Polygon']},coordinates:{type:'array',minItems:1,maxItems:8,items:{type:'array',minItems:4,maxItems:2048,items:{type:'array',minItems:2,maxItems:2,items:{type:'number'}}}}},required:['type','coordinates'],additionalProperties:false},bounds:{type:'object',properties:{west:{type:'number',minimum:-180,maximum:180},south:{type:'number',minimum:-90,maximum:90},east:{type:'number',minimum:-180,maximum:180},north:{type:'number',minimum:-90,maximum:90}},required:['west','south','east','north'],additionalProperties:false},footprint_sqft:{type:'number',minimum:0,maximum:1000000000},source:{type:'object',properties:{slug:{type:'string',minLength:1,maxLength:120},name:{type:'string',minLength:1,maxLength:240},native_id:{type:'string',minLength:1,maxLength:240},image_date:{type:'string',minLength:1,maxLength:40},validation_method:{type:'string',minLength:1,maxLength:120}},required:['slug','name','native_id','image_date','validation_method'],additionalProperties:false}},required:['geometry','bounds','footprint_sqft','source'],additionalProperties:false},linkage:{type:'object',properties:{status:{type:'string',enum:['reconciled_existing_evidence']},basis:{type:'string',minLength:1,maxLength:1000},guardrail:{type:'string',minLength:1,maxLength:1000},target_to_footprint_m:{type:'number',minimum:0,maximum:10000},stored_match_distance_m:{type:'number',minimum:0,maximum:10000}},required:['status','basis','guardrail','target_to_footprint_m','stored_match_distance_m'],additionalProperties:false}},required:['contract_version','opportunity_type','opportunity_id','name','address','site_point','footprint','linkage'],additionalProperties:false}}\n`

for (const relative of ['../scout-connect/index.ts', '../scout-mcp-contract/index.ts']) {
  await edit(relative, (source) => {
    let next = replaceOnce(source, `const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v12'`, `const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v13'`, `${relative} v13 URI`)
    next = replaceOnce(
      next,
      `const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v11'`,
      `const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v12','ui://scout/component-sandbox/v11'`,
      `${relative} v12 compatibility`,
    )
    next = replaceOnce(next, `function sandboxTool(){`, `${gatewayMapSchema}function sandboxTool(){`, `${relative} map schema helper`)
    next = replaceOnce(
      next,
      `additionalProperties:false}},required:['surface','names','opportunity'],additionalProperties:false},annotations:`,
      `additionalProperties:false},map:sandboxMapSchema()},required:['surface','names','opportunity','map'],additionalProperties:false},annotations:`,
      `${relative} output map schema`,
    )
    next = next.replace(
      `title:'Preview Scout opportunity card',description:'Owner-only read-only developer tool that renders the bounded Scout MCP Apps opportunity card.`,
      `title:'Preview Scout opportunity card',description:'Owner-only read-only developer tool that renders the bounded Scout MCP Apps opportunity card and single-site map.`,
    )
    return next
  })
}

await edit('foundation_test.mjs', (source) => {
  let next = source
  next = replaceOnce(next, `assert.ok(view.includes("structuredContent?.opportunity"));`, `assert.ok(view.includes("structuredContent?.opportunity"));\nassert.ok(view.includes("structuredContent?.map"));\nassert.ok(view.includes("mountScoutSingleSiteMap"));`, 'foundation view map result')
  next = replaceOnce(next, `assert.equal(server.includes("scout_get_component_sandbox_premium_exterior_map_v1_internal"), false);`, `assert.ok(server.includes("scout_get_component_sandbox_premium_exterior_map_v1_internal"));`, 'foundation server map RPC')
  next = replaceOnce(next, `assert.ok(server.includes("opportunity: z.object"));`, `assert.ok(server.includes("opportunity: z.object"));\nassert.ok(server.includes("map: sandboxMapSchema"));\nassert.ok(server.includes("connectDomains: [MAP_RESOURCE_ORIGIN]"));`, 'foundation server map schema/CSP')
  next = replaceOnce(next, `assert.ok(connectGateway.includes("opportunity:{type:'object'"));\nassert.ok(contractGateway.includes("opportunity:{type:'object'"));`, `assert.ok(connectGateway.includes("opportunity:{type:'object'"));\nassert.ok(contractGateway.includes("opportunity:{type:'object'"));\nassert.ok(connectGateway.includes("map:sandboxMapSchema()"));\nassert.ok(contractGateway.includes("map:sandboxMapSchema()"));`, 'foundation gateway map schemas')
  next = replaceOnce(next, `assert.ok(buildView.includes('template.replace("/*__SCOUT_VIEW_BUNDLE__*/", () => bundle)'));`, `assert.ok(buildView.includes('.replace("/*__SCOUT_VIEW_STYLE__*/", () => css)'));\nassert.ok(buildView.includes('.replace("/*__SCOUT_VIEW_BUNDLE__*/", () => bundle)'));`, 'foundation bundled CSS')
  next = replaceOnce(next, `for (const version of ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12"])`, `for (const version of ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13"])`, 'foundation v13 resource coverage')
  next = replaceOnce(next, `assert.equal(template.includes('data-scout-map'), false);\nassert.equal(generated.includes("maplibre"), false);`, `assert.ok(template.includes('data-scout-map'));\nassert.ok(template.includes('data-scout-map-state'));\nassert.ok(generated.includes("maplibre"));\nassert.ok(generated.includes("${OPENFREEMAP_STYLE}"));\nassert.equal(generated.includes("Placeholder image 1"), false);`, 'foundation visible map integration')
  next = replaceOnce(next, `assert.ok(generated.includes("Media wiring intentionally deferred"));`, `assert.ok(generated.includes("Media wiring intentionally deferred"));\nassert.ok(generated.includes("Site map for"));`, 'foundation map accessibility copy')
  return next
})

await edit('single_site_map_renderer_test.mjs', (source) => {
  let next = source
  next = replaceOnce(next, `assert.equal(view.includes('single_site_map_renderer'), false)`, `assert.ok(view.includes('single_site_map_renderer'))`, 'renderer test View import')
  next = replaceOnce(next, `assert.equal(view.includes('mountScoutSingleSiteMap'), false)`, `assert.ok(view.includes('mountScoutSingleSiteMap'))`, 'renderer test View mount')
  next = replaceOnce(next, `assert.equal(server.includes('scout_get_component_sandbox_premium_exterior_map_v1_internal'), false)`, `assert.ok(server.includes('scout_get_component_sandbox_premium_exterior_map_v1_internal'))`, 'renderer test server map RPC')
  next = replaceOnce(next, `assert.equal(template.includes('data-scout-map'), false)`, `assert.ok(template.includes('data-scout-map'))`, 'renderer test template map')
  next = replaceOnce(next, `assert.equal(generated.includes('maplibre'), false)`, `assert.ok(generated.includes('maplibre'))`, 'renderer test generated MapLibre')
  next = replaceOnce(next, `assert.equal(generated.includes('scout-single-site-footprint'), false)`, `assert.ok(generated.includes('scout-single-site-footprint'))`, 'renderer test footprint bundle')
  next = replaceOnce(next, `assert.ok(mapContract.includes('Batch 2 adds the isolated renderer implementation only'))`, `assert.ok(mapContract.includes('Batch 2 adds the isolated renderer implementation only'))\nassert.ok(mapContract.includes('Batch 3 integration scope'))\nassert.ok(mapContract.includes('${OPENFREEMAP_STYLE}'))`, 'renderer test Batch 3 contract')
  next = replaceOnce(next, `assert.ok(designContract.includes('Batch 2 implements the renderer only'))`, `assert.ok(designContract.includes('Batch 2 implements the renderer only'))\nassert.ok(designContract.includes('Batch 3 integrates exactly one map tile'))`, 'renderer test Batch 3 design')
  return next
})

await edit('MAP_CONTRACT.md', (source) => {
  let next = replaceOnce(
    source,
    `- A future integration must pass an approved \`style\` into the renderer. Provider selection and the corresponding \`_meta.ui.csp\` origins are an integration concern, not a renderer default.`,
    `- Batch 3 passes the approved OpenFreeMap Positron style (\`${OPENFREEMAP_STYLE}\`) into the renderer. The renderer itself remains provider-agnostic.`,
    'map contract provider integration',
  )
  next = replaceOnce(
    next,
    `## Next integration boundary\n\nA later batch may expose \`single_site_map_v1\` through the sandbox result and replace exactly one approved media placeholder with the PNC map. That integration must preserve the full-width carousel contract and must define an approved basemap provider plus modern \`_meta.ui.csp\` origins before deployment.`,
    `## Batch 3 integration scope\n\nBatch 3 is the deliberately bounded first live integration of the PNC single-site renderer:\n\n- \`single_site_map_v1\` is added to the sandbox tool's \`structuredContent.map\`.\n- The server calls only \`public.scout_get_component_sandbox_premium_exterior_map_v1_internal()\`; generalized legacy map RPCs remain quarantined.\n- The first of the existing three carousel placeholders becomes the PNC map. The other two placeholders, 100%-width swipe geometry, count, and dots remain unchanged.\n- Basemap provider: OpenFreeMap public instance using the minimal Positron style at \`${OPENFREEMAP_STYLE}\`.\n- MCP Apps resource CSP declares only \`${OPENFREEMAP_ORIGIN}\` in both \`connectDomains\` and \`resourceDomains\`. No wildcard domains, CDN runtime library, geolocation permission, or nested frame is introduced.\n- MapLibre JS/CSS remain locally bundled. Provider attribution remains enabled.\n- The View URI advances to \`ui://scout/component-sandbox/v13\`; \`v12\` remains a compatibility resource URI.\n- The map remains non-interactive and renders only Scout's reconciled footprint, never the Census geocode as a competing marker.\n- View teardown and rerender paths destroy the MapLibre instance with \`map.remove()\`.\n\nNo second opportunity type, portfolio semantics, clustering, territory layer, contacts, competitors, routing, user-location access, or map-driven discovery is introduced by Batch 3.\n\n## Next integration boundary\n\nThe next boundary is lifecycle verification of this exact PNC map inside ChatGPT on desktop and mobile. Do not broaden map scope until that rendering, carousel gesture behavior, CSP/network behavior, and teardown path are verified in the host.`,
    'map contract Batch 3 boundary',
  )
  return next
})

await edit('DESIGN_CONTRACT.md', (source) => {
  let next = replaceOnce(
    source,
    `- After the isolated renderer is verified, a later approved integration batch may replace exactly one existing media placeholder tile with the PNC map while preserving the full-width carousel geometry, count, dots, and swipe behavior.`,
    `- Batch 3 replaces exactly one existing media placeholder tile with the PNC map while preserving the full-width carousel geometry, count, dots, and swipe behavior.`,
    'design approved map tile integration',
  )
  next = replaceOnce(
    next,
    `Batch 2 implements the renderer only and intentionally makes no visible View change.`,
    `Batch 2 implements the renderer only and intentionally makes no visible View change.\n\nBatch 3 integrates exactly one map tile. It uses OpenFreeMap Positron as a restrained basemap, keeps MapLibre non-interactive, keeps the two remaining placeholders unchanged, and does not add any new map controls or card chrome.`,
    'design Batch 3 statement',
  )
  next = replaceOnce(
    next,
    `The approved PNC map may later consume only the bounded \`single_site_map_v1\` payload defined in \`MAP_CONTRACT.md\`.`,
    `The approved PNC map consumes only the bounded \`single_site_map_v1\` payload defined in \`MAP_CONTRACT.md\`.`,
    'design live map payload wording',
  )
  next = replaceOnce(
    next,
    `The generated View must continue to have exactly one \`<!doctype html>\`, contain no \`window.openai\`, and preserve the callback replacement in \`build-view.mjs\`:\n\n\`template.replace("/*__SCOUT_VIEW_BUNDLE__*/", () => bundle)\``,
    `The generated View must continue to have exactly one \`<!doctype html>\`, contain no \`window.openai\`, and preserve callback replacements in \`build-view.mjs\` for both locally bundled MapLibre CSS and the JavaScript bundle:\n\n\`template.replace("/*__SCOUT_VIEW_STYLE__*/", () => css)\`\n\n\`template.replace("/*__SCOUT_VIEW_BUNDLE__*/", () => bundle)\``,
    'design bundled CSS lifecycle invariant',
  )
  return next
})

console.log('Scout Batch 3 integration transform applied.')
