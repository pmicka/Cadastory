import {
  categoricalPatchMetrics,
  buildMetricGrid,
  buildTerrainFormArtifact,
  buildSpatialPatternArtifact,
} from './farm-watch-neutral-primitives.ts'
import {
  validateSpatialPatternArtifact,
  validateTerrainFormArtifact,
} from './farm-watch-neutral-primitives-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

const square = {
  type: 'Polygon' as const,
  coordinates: [[
    [-84.8900,38.3200],
    [-84.8840,38.3200],
    [-84.8840,38.3260],
    [-84.8900,38.3260],
    [-84.8900,38.3200],
  ]],
}

function demFetch(_url: string | URL | Request, init?: RequestInit) {
  const params=new URLSearchParams(String(init?.body||''))
  const geometry=JSON.parse(params.get('geometry')||'{}')
  const points=Array.isArray(geometry.points)?geometry.points:[]
  const samples=points.map((point:number[],index:number)=>{
    const lon=Number(point[0])
    const lat=Number(point[1])
    const x=(lon+84.887)*85000
    const y=(lat-38.323)*111000
    const value=700 + 0.035*x + 0.02*y + 18*Math.exp(-((x*x)+(y*y))/8000) - 12*Math.exp(-(((x-80)*(x-80))+((y+50)*(y+50)))/4000)
    return {locationId:index,value}
  })
  return Promise.resolve(new Response(JSON.stringify({samples}),{status:200,headers:{'content-type':'application/json'}}))
}

function encodeU8(values:Uint8Array){
  let binary=''
  for(const value of values) binary+=String.fromCharCode(value)
  return btoa(binary)
}
function encodeU16(values:Uint16Array){
  return btoa(String.fromCharCode(...new Uint8Array(values.buffer)))
}

function syntheticStructureArtifact(width=8,height=8){
  const count=width*height
  const domain=new Uint8Array(count).fill(1)
  const property=new Uint8Array(count)
  const lidarValid=new Uint8Array(count).fill(1)
  const lidarDominant=new Uint8Array(count)
  const leafValid=new Uint8Array(count).fill(1)
  const leafScore=new Uint8Array(count)
  const confidence=new Uint8Array(count).fill(220)
  const spectral=new Uint8Array(count).fill(180)
  const total=new Uint16Array(count).fill(50)
  const shares=[
    new Uint8Array(count),
    new Uint8Array(count),
    new Uint8Array(count),
    new Uint8Array(count),
    new Uint8Array(count),
  ]
  for(let row=0;row<height;row+=1){
    for(let col=0;col<width;col+=1){
      const index=row*width+col
      property[index]=col<4?1:0
      lidarDominant[index]=col<4?1:3
      leafScore[index]=Math.round((col/(width-1))*255)
      shares[1][index]=col<4?180:20
      shares[3][index]=col<4?40:200
      shares[0][index]=10
      shares[2][index]=15
      shares[4][index]=10
    }
  }
  return {
    combined_grid:{
      native_crs:'EPSG:6473',
      bbox:{west:680000,east:680040,south:4242000,north:4242040},
      cell_meters:5,
      width,height,
      domain_valid_base64:encodeU8(domain),
      property_mask_base64:encodeU8(property),
      lidar_valid_base64:encodeU8(lidarValid),
      lidar_dominant_band_base64:encodeU8(lidarDominant),
      lidar_band_shares_base64:shares.map(encodeU8),
      lidar_total_returns_u16_base64:encodeU16(total),
      leaf_valid_base64:encodeU8(leafValid),
      leaf_score_base64:encodeU8(leafScore),
      leaf_confidence_base64:encodeU8(confidence),
      leaf_spectral_support_base64:encodeU8(spectral),
    },
  }
}

Deno.test('metric grid is fixed-meter and respects analysis geometry',()=>{
  const grid=buildMetricGrid(square,10)
  assert(grid.native_crs==='EPSG:32616')
  assert(grid.cell_meters===10)
  assert(grid.width>10 && grid.height>10)
  const valid=grid.domain_valid.reduce((sum,value)=>sum+value,0)
  assert(valid>0)
  assert(valid<grid.width*grid.height)
})

Deno.test('categorical patches honor explicit 8-neighbor rule and report transition edge',()=>{
  const classes=new Uint8Array([
    1,1,2,
    1,2,2,
    3,3,2,
  ])
  const valid=new Uint8Array(9).fill(1)
  const result=categoricalPatchMetrics(classes,valid,3,3,10,8)
  assert(result.patches.length===3)
  assert(result.transition_edge_m>0)
  assert(Number(result.transition_edge_density_m_per_ha)>0)
  assert(result.patchIds.every((value)=>value>0))
})

Deno.test('terrain form/permeability artifact remains neutral and validates',async()=>{
  const built=await buildTerrainFormArtifact({
    localGeometry:square,
    landscapeGeometry:square,
    domainIdentitySha256:'a'.repeat(64),
    domainAlgorithmVersion:'test-domain-v1',
    landscapePhysicalIdentitySha256:'b'.repeat(64),
    fetchImpl:demFetch as typeof fetch,
  })
  assert(validateTerrainFormArtifact(built.artifact))
  assert(built.artifact.scoring_performed===false)
  assert(built.artifact.behavioral_inference_performed===false)
  assert(!JSON.stringify(built.artifact).includes('deer_score'))
  assert(Number(built.artifact.summary.local_valid_cell_count)>0)
})

Deno.test('spatial pattern artifact derives from existing compact structure without raw-source recompute',async()=>{
  const resourceEdge={
    context:{
      boundary_quality:[],
      nearest_mapped_field:null,
    },
    field_area_geojson:{
      type:'Polygon',
      coordinates:[[[-84.889,38.321],[-84.888,38.321],[-84.888,38.322],[-84.889,38.322],[-84.889,38.321]]],
    },
    field_edge_geojson:{
      type:'LineString',
      coordinates:[[-84.889,38.321],[-84.888,38.321],[-84.888,38.322]],
    },
  }
  const built=await buildSpatialPatternArtifact({
    localGeometry:square,
    domainIdentitySha256:'a'.repeat(64),
    domainAlgorithmVersion:'test-domain-v1',
    landscapePhysicalIdentitySha256:'b'.repeat(64),
    resourceEdgeIdentitySha256:'c'.repeat(64),
    resourceEdgeContext:resourceEdge,
    landscapeStructureIdentitySha256:'d'.repeat(64),
    landscapeStructureArtifactSha256:'e'.repeat(64),
    landscapeStructureArtifact:syntheticStructureArtifact(),
    fetchImpl:demFetch as typeof fetch,
  })
  assert(validateSpatialPatternArtifact(built.artifact))
  assert(built.artifact.structure_pattern.grid.native_crs==='EPSG:6473')
  assert(built.artifact.scoring_performed===false)
  assert(built.artifact.behavioral_inference_performed===false)
  assert(built.artifact.source_provenance.structure_reuse.includes('no COPC or imagery recomputation'))
  assert(Number(built.artifact.structure_pattern.summary.leaf_quartile_patches.transition_edge_m)>0)
})
