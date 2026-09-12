import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { build, transform } from "esbuild";

const directory = new URL("./", import.meta.url);
const [view, server, generated, buildView, connectGateway, contractGateway, template, designContract] = await Promise.all([
  readFile(new URL("view.ts", directory), "utf8"),
  readFile(new URL("index.ts", directory), "utf8"),
  readFile(new URL("view.generated.ts", directory), "utf8"),
  readFile(new URL("build-view.mjs", directory), "utf8"),
  readFile(new URL("../scout-connect/index.ts", directory), "utf8"),
  readFile(new URL("../scout-mcp-contract/index.ts", directory), "utf8"),
  readFile(new URL("view.template.html", directory), "utf8"),
  readFile(new URL("DESIGN_CONTRACT.md", directory), "utf8"),
]);

assert.equal((view.match(/\.connect\(/g) || []).length, 1);
assert.ok(view.indexOf("app.ontoolinput") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.ontoolresult") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.onerror") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.onteardown") < view.indexOf("app.connect("));
assert.ok(view.includes("new PostMessageTransport()"));
assert.ok(view.includes("structuredContent?.opportunity"));
assert.equal(view.includes("window.openai"), false);
assert.equal(view.includes("innerHTML"), false);
assert.equal(generated.includes("https://unpkg.com"), false);
assert.equal(generated.includes("https://cdn."), false);
assert.equal(generated.includes("window.openai"), false);
assert.ok(server.includes("_meta: { ui: { resourceUri: RESOURCE_URI } }"));
assert.equal(server.includes("'openai/outputTemplate'"), false);
assert.ok(server.includes("scout_get_component_sandbox_names_v1_internal"));
assert.ok(server.includes("scout_get_component_sandbox_opportunity_v1_internal"));
assert.equal(server.includes("scout_get_component_sandbox_map_targets_v3_internal"), false);
assert.ok(server.includes("names: z.array"));
assert.ok(server.includes("opportunity: z.object"));
assert.ok(connectGateway.includes("opportunity:{type:'object'"));
assert.ok(contractGateway.includes("opportunity:{type:'object'"));
assert.equal(server.includes("exemplars:"), false);
assert.ok(buildView.includes('template.replace("/*__SCOUT_VIEW_BUNDLE__*/", () => bundle)'));

const contractBuild = await build({
  entryPoints: [new URL("contract.ts", directory).pathname],
  bundle: true,
  format: "esm",
  platform: "node",
  target: "node20",
  write: false,
});
const contractUrl = `data:text/javascript;base64,${Buffer.from(contractBuild.outputFiles[0].text).toString("base64")}`;
const { SCOUT_SANDBOX_MAX_NAMES, normalizeScoutSandboxNames, normalizeScoutSandboxOpportunity } = await import(contractUrl);
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

for (const source of [server, connectGateway, contractGateway]) {
  for (const version of ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11"]) {
    assert.ok(source.includes(`ui://scout/component-sandbox/${version}`));
  }
}
assert.ok(designContract.includes("12:7"));
assert.ok(designContract.includes("visual source of truth"));
assert.ok(template.includes('class="scout-header"'));
assert.ok(template.includes('class="carousel-viewport"'));
assert.ok(template.includes('Save for later'));
assert.ok(template.includes('Investigate'));
assert.ok(template.includes('#ffffff'));
assert.ok(template.includes('border-radius: 24px'));
assert.equal(template.includes('light-dark('), false);
assert.equal(template.includes('class="metrics"'), false);
assert.equal(template.includes('class="details"'), false);
assert.equal(template.includes('class="guardrail"'), false);
assert.equal(template.includes('Scout by Cadastory'), false);
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

console.log("Scout opportunity-card MCP Apps lifecycle checks passed.");
