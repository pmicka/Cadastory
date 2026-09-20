import {
  FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT,
  landscapeStructureSourceSignature,
  validateLandscapeStructureArtifact,
} from './farm-watch-landscape-structure-contract.ts'

Deno.test('landscape structure source identity binds the exact local domain', () => {
  const domainA = 'a'.repeat(64)
  const domainB = 'b'.repeat(64)
  const a = landscapeStructureSourceSignature({
    landscapeDomainIdentitySha256: domainA,
    landscapeDomainAlgorithmVersion: 'barrier-aware-landscape-domain-v3',
    lidarSourceContractSignature: 'lidar-source-contract-v1',
  })
  const b = landscapeStructureSourceSignature({
    landscapeDomainIdentitySha256: domainB,
    landscapeDomainAlgorithmVersion: 'barrier-aware-landscape-domain-v3',
    lidarSourceContractSignature: 'lidar-source-contract-v1',
  })
  if (a === b) throw new Error('domain identity must affect source signature')
  if (!a.includes('scope=barrier-aware-local-500m')) {
    throw new Error('local 500 m scope missing from source signature')
  }
})

Deno.test('landscape structure source identity rejects malformed domain SHA', () => {
  let threw = false
  try {
    landscapeStructureSourceSignature({
      landscapeDomainIdentitySha256: 'not-a-sha',
      landscapeDomainAlgorithmVersion: 'barrier-aware-landscape-domain-v3',
      lidarSourceContractSignature: 'lidar-source-contract-v1',
    })
  } catch {
    threw = true
  }
  if (!threw) throw new Error('malformed domain SHA should be rejected')
})

Deno.test('landscape structure artifact validator requires reusable fine structure grids', () => {
  const artifact = {
    schema: FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.algorithmVersion,
    status: 'available',
    domain: {
      identity_sha256: 'c'.repeat(64),
      radius_m: 500,
    },
    source_provenance: {
      lidar: {},
      leaf_off: {},
    },
    leaf_off_2024: {
      sourceId: FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.leafSourceId,
      grid: {
        encoding: 'base64-u8-v1',
        score_base64: 'AA==',
        valid_base64: 'AQ==',
      },
    },
    combined_grid: {
      width: 1,
      height: 1,
      cell_meters: 5,
      encoding: 'base64-u8-v1',
      domain_valid_base64: 'AQ==',
      property_mask_base64: 'AQ==',
      lidar_valid_base64: 'AQ==',
      lidar_dominant_band_base64: 'AA==',
      lidar_total_returns_u16_base64: 'CgA=',
      lidar_band_shares_base64: ['AA==', 'AA==', 'AA==', 'AA==', '/w=='],
      leaf_valid_base64: 'AQ==',
      leaf_score_base64: '/w==',
      leaf_confidence_base64: '/w==',
      leaf_spectral_support_base64: '/w==',
    },
    summary: {
      domain_cell_count: 1,
      property_cell_count: 1,
      local_ring_cell_count: 1,
      lidar: { property: {}, local_ring: {} },
      leaf_off: { property: {}, local_ring: {} },
      cross_boundary_adjacency: {},
    },
  }
  if (!validateLandscapeStructureArtifact(artifact)) {
    throw new Error('valid landscape structure fixture rejected')
  }
  artifact.combined_grid.lidar_band_shares_base64 = ['AA==']
  if (validateLandscapeStructureArtifact(artifact)) {
    throw new Error('incomplete LiDAR profile grid should be rejected')
  }
})
