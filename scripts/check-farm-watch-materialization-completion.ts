const completionHelper = await Deno.readTextFile(
  "supabase/functions/_shared/farm-watch-materialization-completion.ts",
);
const terrainCli = await Deno.readTextFile(
  "scripts/farm-watch-terrain-materialize.ts",
);
const synthesisWorker = await Deno.readTextFile(
  "supabase/functions/farm-watch-structure-synthesis-worker/index.ts",
);
const materializationEdge = await Deno.readTextFile(
  "supabase/functions/farm-watch-materialization/index.ts",
);

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function section(source: string, start: string, end: string) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  assert(from >= 0 && to > from, "cannot locate source section: " + start);
  return source.slice(from, to);
}

const uploadHelper = section(
  materializationEdge,
  "async function uploadNeutralPrimitive(",
  "async function buildTerrainFormMaterialization(",
);
const uploadIndex = uploadHelper.indexOf(".upload(path, bytes");
const recheckIndex = uploadHelper.indexOf("if (args.recheckDependencies)");
const completeIndex = uploadHelper.indexOf("await completeBuild({");
assert(
  uploadIndex >= 0 && uploadIndex < recheckIndex &&
    recheckIndex < completeIndex,
  "neutral products must re-resolve dependencies after artifact upload and before completion",
);

for (
  const [product, start, end] of [
    [
      "terrain-form-permeability",
      "async function buildTerrainFormMaterialization(",
      "async function buildSpatialPatternMaterialization(",
    ],
    [
      "spatial-edge-patch-context",
      "async function buildSpatialPatternMaterialization(",
      "async function buildSolarTerrainMaterialization(",
    ],
    [
      "solar-terrain-context",
      "async function buildSolarTerrainMaterialization(",
      "async function buildSolarExposureMaterialization(",
    ],
    [
      "solar-exposure-context",
      "async function buildSolarExposureMaterialization(",
      "async function buildThermalExposureMaterialization(",
    ],
    [
      "thermal-exposure-context",
      "async function buildThermalExposureMaterialization(",
      "async function buildHorizontalVisibilityMaterialization(",
    ],
    [
      "horizontal-visibility-context",
      "async function buildHorizontalVisibilityMaterialization(",
      "async function prepareHorizontalVisibilityMaterialization(",
    ],
  ] as const
) {
  const body = section(materializationEdge, start, end);
  assert(
    body.includes("recheckDependencies:"),
    product + " build is missing its completion-time dependency recheck",
  );
}

const twoPhaseVisibility = section(
  materializationEdge,
  "async function completeHorizontalVisibilityMaterialization(",
  "async function failHorizontalVisibilityMaterialization(",
);
assert(
  twoPhaseVisibility.includes("recheckDependencies:") &&
    twoPhaseVisibility.includes(
      "horizontalVisibilityDependencies(slug, false)",
    ),
  "two-phase horizontal visibility completion must re-resolve its current dependencies",
);

for (
  const [product, start, end] of [
    [
      "terrain",
      "async function buildTerrainMaterialization(",
      "async function buildLidarSourceMaterialization(",
    ],
    [
      "LiDAR source",
      "async function buildLidarSourceMaterialization(",
      "async function uploadNeutralPrimitive(",
    ],
  ] as const
) {
  const body = section(materializationEdge, start, end);
  const uploadIndex = body.indexOf(".upload(path, bytes");
  const recheckIndex = body.indexOf("recheckFarmWatchMaterializationIdentity({");
  const completeIndex = body.indexOf("await completeBuild({");
  assert(
    uploadIndex >= 0 && uploadIndex < recheckIndex &&
      recheckIndex < completeIndex,
    product + " source identity must be rechecked after upload and before completion",
  );
}

const terrainUploadIndex = terrainCli.indexOf(
  ".upload(artifactPath, artifactBytes",
);
const terrainRecheckIndex = terrainCli.indexOf(
  "recheckFarmWatchMaterializationIdentity({",
);
const terrainCompleteIndex = terrainCli.indexOf(
  "'farm_watch_complete_materialization_build_v1_internal'",
);
assert(
  terrainUploadIndex >= 0 && terrainUploadIndex < terrainRecheckIndex &&
    terrainRecheckIndex < terrainCompleteIndex &&
    terrainCli.includes(
      "expectedSourceSignature: authoritativeSource.sourceSignature",
    ),
  "legacy terrain CLI must re-resolve its DEM identity immediately before build completion",
);

const synthesisUploadIndex = synthesisWorker.indexOf(
  ".upload(artifactPath, bytes",
);
const synthesisRecheckIndex = synthesisWorker.indexOf(
  "const completionDependencies = await recheckFarmWatchMaterializationIdentity({",
);
const synthesisCompleteIndex = synthesisWorker.indexOf(
  "'farm_watch_complete_materialization_build_v1_internal'",
);
assert(
  synthesisUploadIndex >= 0 && synthesisUploadIndex < synthesisRecheckIndex &&
    synthesisRecheckIndex < synthesisCompleteIndex &&
    synthesisWorker.includes(
      "expectedSourceSignature: dependencies.sourceSignature",
    ) &&
    synthesisWorker.includes("resolveCurrent: () => resolveDependencies(slug)"),
  "structure synthesis must re-resolve its current LiDAR and leaf-off dependencies before completion",
);

for (
  const forbidden of [
    "deer_score",
    "habitat_score",
    "bedding_score",
    "movement_score",
  ]
) {
  assert(
    !materializationEdge.includes(forbidden),
    "forbidden deer scoring term: " + forbidden,
  );
  assert(
    !synthesisWorker.includes(forbidden),
    "forbidden deer scoring term: " + forbidden,
  );
}

assert(
  completionHelper.includes(
    "dependency identity changed during materialization build",
  ) &&
    completionHelper.includes("resolveCurrent"),
  "completion identity helper must reject changed or unavailable current identities",
);

console.log("Farm Watch completion-drift invariants passed");
