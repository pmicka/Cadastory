import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { build, transform } from "esbuild";

const directory = new URL("./", import.meta.url);
const [view, server, generated, buildView, connectGateway, contractGateway, template, designContract, mapContract] = await Promise.all([
  readFile(new URL("view.ts", directory), "utf8"),
  readFile(new URL("index.ts", directory), "utf8"),
  readFile(new URL("view.generated.ts", directory), "utf8"),
  readFile(new URL("build-view.mjs", directory), "utf8"),
  readFile(new URL("../scout-connect/index.ts", directory), "utf8"),
  readFile(new URL("../scout-mcp-contract/index.ts", directory), "utf8"),
  readFile(new URL("view.template.html", directory), "utf8"),
  readFile(new URL("DESIGN_CONTRACT.md", directory), "utf8"),
  readFile(new URL("MAP_CONTRACT.md", directory), "utf8"),
]);

assert.equal((view.match(/\.connect\(/g) || []).length, 1);
assert.ok(view.indexOf("app.ontoolinput") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.ontoolresult") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.onerror") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.onteardown") < view.indexOf("app.connect("));
assert.ok(view.includes("new PostMessageTransport()"));
assert.ok(view.includes("structuredContent?.opportunity"));
assert.equal(view.includes("innerHTML"), false);
assert.equal(generated.includes("https://unpkg.com"), false);
assert.equal(generated.includes("https://cdn."), false);
assert.ok(server.includes("_meta: { ui: { resourceUri: RESOURCE_URI } }"));
assert.ok(server.includes("scout_get_component_sandbox_names_v1_internal"));
assert.ok(server.includes("scout_get_component_sandbox_opportunity_v1_internal"));
assert.equal(server.includes("scout_get_component_sandbox_map_targets_internal"), false);
assert.equal(server.includes("scout_get_component_sandbox_map_targets_v2_internal"), false);
assert.equal(server.includes("scout_get_component_sandbox_map_targets_v3_internal"), false);
assert.equal(server.includes("scout_get_component_sandbox_premium_exterior_map_v1_internal"), false);
assert.ok(server.includes("names: z.array"));
assert.ok(server.includes("opportunity: z.object"));
assert.ok(connectGateway.includes("opportunity:{type:'object'"));
assert.ok(contractGateway.includes("opportunity:{type:'object'"));
assert.equal(server.includes("exemplars:"), false);
assert.ok(buildView.includes('template.replace("/*__SCOUT_VIEW_BUNDLE__*/", () => bundle)'));

for (const source of [view, server, generated, connectGateway, contractGateway, template]) {
  assert.equal(source.includes("window.openai"), false);
  assert.equal(source.includes("openai/outputTemplate"), false);
  assert.equal(source.includes("openai/widgetAccessible"), false);
  assert.equal(source.includes("openai/widgetDescription"), false);
  assert.equal(source.includes("openai/widgetCSP"), false);
}

const contractBuild = await build({
  entryPoints: [new URL("contract.ts", directory).pathname],
  bundle: true,
  format: "esm",
  platform: "node",
  target: "node20",
  write: false,
});
const contractUrl = `data:text/javascript;base64,${Buffer.from(contractBuild.outputFiles[0].text).toString("base64")}`;
const {
  SCOUT_SANDBOX_MAX_NAMES,
  normalizeScoutSandboxNames,
  normalizeScoutSandboxOpportunity,
  normalizeScoutSandboxSingleSiteMap,
} = await import(contractUrl);
assert.deepEqual(normalizeScoutSandboxNames(["  Denton Floyd  ", "PNC Tower"]), ["Denton Floyd", "PNC Tower"]);
assert.deepEqual(normalizeScoutSandboxNames([null, "", "x".repeat(161), "Valid"]), ["Valid"]);
assert.equal(normalizeScoutSandboxNames(Array.from({ length: 10 }, (_, i) => `Name ${i}`)).length, SCOUT_SANDBOX_MAX_NAMES);

const exemplar = {
  name: "PNC Tower",
  address: "101 S 5th St, Louisville, KY 40202",
  height_m: 156,
  guardrail: "Facility archetype/geometry is a target qualifier only; verify actual facade material, condition, access, owner requirements and current need before outreach.",
  confidence: 0.94,
  observed_at: "2026-09-06T19:44:19.694243+00:00",
  story_count: 38,
  target_class: "corporate_office",
  footprint_sqft: 71721.90625,
  glazing_status: "confirmed_glazed",
  target_subclass: "office_highrise",
  opportunity_tier: "very_high",
  opportunity_score: 91,
  buyer_resolvability: "public_operator_or_site_route",
};
assert.deepEqual(normalizeScoutSandboxOpportunity(exemplar), exemplar);
assert.equal(normalizeScoutSandboxOpportunity({ ...exemplar, confidence: 2 }), null);
assert.equal(normalizeScoutSandboxOpportunity({ ...exemplar, name: "" }), null);

const mapExemplar = {
  contract_version: "single_site_map_v1",
  opportunity_type: "premium_exterior",
  opportunity_id: "0edb82cd-7487-4f72-a036-8faa8a40bd54",
  name: "PNC Tower",
  address: "101 S 5th St, Louisville, KY 40202",
  site_point: {
    lon: -85.758115986691,
    lat: 38.256732011411,
    source: "premium_exterior_target_geocode",
    method: "US Census exact address match",
  },
  footprint: {
    geometry: {
      type: "Polygon",
      coordinates: [[
        [-85.756794, 38.256496],
        [-85.757636, 38.256585],
        [-85.758163, 38.255961],
        [-85.756887, 38.255947],
        [-85.756794, 38.256496],
      ]],
    },
    bounds: {
      west: -85.7581632620074,
      south: 38.2559260667489,
      east: -85.7567941378868,
      north: 38.2565851603231,
    },
    footprint_sqft: 71721.90625,
    source: {
      slug: "ky-ornl-building-footprints",
      name: "Kentucky ORNL / FEMA USA Structures Building Footprints",
      native_id: "{0927eebf-03a7-40c5-99c8-1cd889ec008e}",
      image_date: "2011-07-06",
      validation_method: "Unverified",
    },
  },
  linkage: {
    status: "reconciled_existing_evidence",
    basis: "first_party_story_count corroborated by matched OSM/Overture building evidence",
    guardrail: "Facility geocode is not itself building identity; link selected by corroborating physical evidence.",
    target_to_footprint_m: 24.21606122,
    stored_match_distance_m: 76.97888474,
  },
};
assert.deepEqual(normalizeScoutSandboxSingleSiteMap(mapExemplar), mapExemplar);
assert.equal(normalizeScoutSandboxSingleSiteMap({ ...mapExemplar, opportunity_type: "property_management" }), null);
assert.equal(normalizeScoutSandboxSingleSiteMap({ ...mapExemplar, linkage: { ...mapExemplar.linkage, status: "unverified" } }), null);
assert.equal(normalizeScoutSandboxSingleSiteMap({ ...mapExemplar, footprint: { ...mapExemplar.footprint, geometry: { type: "Point", coordinates: [-85.75, 38.25] } } }), null);
assert.equal(normalizeScoutSandboxSingleSiteMap({ ...mapExemplar, footprint: { ...mapExemplar.footprint, bounds: { ...mapExemplar.footprint.bounds, east: -86 } } }), null);

for (const source of [server, connectGateway, contractGateway]) {
  for (const version of ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12"]) {
    assert.ok(source.includes(`ui://scout/component-sandbox/${version}`));
  }
}
assert.ok(designContract.includes("12:7"));
assert.ok(designContract.includes("visual source of truth"));
assert.ok(mapContract.includes("scout_get_component_sandbox_premium_exterior_map_v1_internal"));
assert.ok(mapContract.includes("one opportunity type at a time"));
assert.ok(mapContract.includes("legacy reference only"));
assert.ok(mapContract.includes("openai/outputTemplate"));
assert.ok(template.includes('class="scout-header"'));
assert.ok(template.includes('class="carousel-viewport"'));
assert.ok(designContract.includes('100% of the visible carousel viewport width'));
assert.ok(template.includes('flex: 0 0 100%;'));
assert.ok(template.includes('gap: 0;'));
assert.equal(template.includes('flex: 0 0 330px;'), false);
assert.equal(template.includes('width: 330px;'), false);
assert.ok(template.includes('Save for later'));
assert.ok(template.includes('Investigate'));
assert.ok(template.includes('#ffffff'));
assert.ok(template.includes('border-radius: 24px'));
assert.equal(template.includes('light-dark('), false);
assert.equal(template.includes('class="metrics"'), false);
assert.equal(template.includes('class="details"'), false);
assert.equal(template.includes('class="guardrail"'), false);
assert.equal(template.includes('Scout by Cadastory'), false);
assert.equal(template.includes('data-scout-map'), false);
assert.equal(generated.includes("maplibre"), false);
assert.equal(generated.includes("Scout lifecycle"), false);
assert.ok(generated.includes("Component preview"));
assert.ok(generated.includes("Media wiring intentionally deferred"));
assert.ok(generated.includes("Scout guardrail:"));
assert.ok(generated.includes("opportunity"));
assert.equal((generated.match(/<!doctype html>/g) || []).length, 1);
assert.equal((generated.match(/window\.openai/g) || []).length, 0);

const exportPrefix = "export const SCOUT_VIEW_HTML = ";
const exportStart = generated.indexOf(exportPrefix);
assert.notEqual(exportStart, -1);
const htmlLiteral = generated.slice(exportStart + exportPrefix.length).trim().replace(/;$/, "");
const html = JSON.parse(htmlLiteral);
assert.equal((html.match(/<!doctype html>/g) || []).length, 1);
assert.equal(html.includes("window.openai"), false);
const scriptMatch = html.match(/<script type="module">([\s\S]*?)<\/script>/);
assert.ok(scriptMatch?.[1]);
await transform(scriptMatch[1], { loader: "js", format: "esm", target: "es2022" });

console.log("Scout opportunity-card and single-site map contract checks passed.");
