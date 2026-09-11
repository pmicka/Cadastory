import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { build } from "esbuild";

const directory = new URL("./", import.meta.url);
const [view, server, generated, connectGateway, contractGateway] = await Promise.all([
  readFile(new URL("view.ts", directory), "utf8"),
  readFile(new URL("index.ts", directory), "utf8"),
  readFile(new URL("view.generated.ts", directory), "utf8"),
  readFile(new URL("../scout-connect/index.ts", directory), "utf8"),
  readFile(new URL("../scout-mcp-contract/index.ts", directory), "utf8"),
]);

assert.equal((view.match(/\.connect\(/g) || []).length, 1);
assert.ok(view.indexOf("app.ontoolinput") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.ontoolresult") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.onerror") < view.indexOf("app.connect("));
assert.ok(view.indexOf("app.onteardown") < view.indexOf("app.connect("));
assert.ok(view.includes("new PostMessageTransport()"));
assert.equal(view.includes("window.openai"), false);
assert.equal(view.includes("innerHTML"), false);
assert.equal(generated.includes("https://unpkg.com"), false);
assert.equal(generated.includes("https://cdn."), false);
assert.ok(server.includes("_meta: { ui: { resourceUri: RESOURCE_URI } }"));
assert.equal(server.includes("'openai/outputTemplate'"), false);
assert.ok(server.includes("scout_get_component_sandbox_names_v1_internal"));
assert.equal(server.includes("scout_get_component_sandbox_map_targets_v3_internal"), false);
assert.ok(server.includes("names: z.array"));
assert.equal(server.includes("exemplars:"), false);

const contractBuild = await build({
  entryPoints: [new URL("contract.ts", directory).pathname],
  bundle: true,
  format: "esm",
  platform: "node",
  target: "node20",
  write: false,
});
const contractUrl = `data:text/javascript;base64,${Buffer.from(contractBuild.outputFiles[0].text).toString("base64")}`;
const { SCOUT_SANDBOX_MAX_NAMES, normalizeScoutSandboxNames } = await import(contractUrl);
assert.deepEqual(normalizeScoutSandboxNames(["  Denton Floyd  ", "PNC Tower"]), ["Denton Floyd", "PNC Tower"]);
assert.deepEqual(normalizeScoutSandboxNames([null, "", "x".repeat(161), "Valid"]), ["Valid"]);
assert.equal(normalizeScoutSandboxNames(Array.from({ length: 10 }, (_, i) => `Name ${i}`)).length, SCOUT_SANDBOX_MAX_NAMES);

for (const source of [server, connectGateway, contractGateway]) {
  for (const version of ["v1", "v2", "v3", "v4", "v5", "v6"]) {
    assert.ok(source.includes(`ui://scout/component-sandbox/${version}`));
  }
}
assert.ok(generated.includes("Scout View v6 loaded"));
assert.ok(generated.includes("structuredContent?.names"));

console.log("Scout names-only MCP Apps lifecycle checks passed.");
