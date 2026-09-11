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

assert.equal(view.includes("App"), false);
assert.equal(view.includes(".connect("), false);
assert.ok(view.includes('ui/notifications/tool-input'));
assert.ok(view.includes('ui/notifications/tool-result'));
assert.equal(view.includes("window.openai"), false);
assert.equal(generated.includes("https://unpkg.com"), false);
assert.equal(generated.includes("https://cdn."), false);
assert.equal(server.includes("'openai/outputTemplate'"), false);
assert.equal(server.includes("'ui/resourceUri'"), false);
assert.ok(server.includes("_meta: { ui: { resourceUri: RESOURCE_URI } }"));
assert.ok(server.includes("RESOURCE_MIME_TYPE"));

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
  SCOUT_SANDBOX_MAX_EXEMPLARS,
  normalizeScoutSandboxExemplar,
  normalizeScoutSandboxExemplars,
  normalizeScoutSandboxRpcExemplars,
} = await import(contractUrl);

assert.deepEqual(normalizeScoutSandboxRpcExemplars([{
  kind: "group",
  label: "  Example Group  ",
  portfolio_archetype: "hotel_management",
  contact_card: { resolution_status: "organization_resolved" },
}]), [{
  name: "Example Group",
  kind: "group",
  archetype: "hotel_management",
  resolution_status: "organization_resolved",
}]);
assert.deepEqual(normalizeScoutSandboxRpcExemplars([{
  kind: "property",
  label: "Example Property",
  contact_card: { organization_type: "hotel", resolution_status: "lead_identified" },
}]), [{
  name: "Example Property",
  kind: "property",
  archetype: "hotel",
  resolution_status: "lead_identified",
}]);
assert.deepEqual(normalizeScoutSandboxExemplar({ name: "Valid", kind: "group" }), {
  name: "Valid",
  kind: "group",
  archetype: null,
  resolution_status: null,
});
for (const malformed of [null, [], {}, { name: "", kind: "group" }, { name: "x", kind: "unknown" }, { name: "x".repeat(161), kind: "property" }]) {
  assert.doesNotThrow(() => normalizeScoutSandboxExemplar(malformed));
  assert.equal(normalizeScoutSandboxExemplar(malformed), null);
}
assert.deepEqual(normalizeScoutSandboxExemplars({ exemplars: [] }), []);
assert.equal(normalizeScoutSandboxExemplars(Array.from({ length: 20 }, (_, index) => ({
  name: `Example ${index}`,
  kind: "property",
}))).length, SCOUT_SANDBOX_MAX_EXEMPLARS);
assert.equal(view.includes("innerHTML"), false);
assert.ok(view.includes("normalizeScoutSandboxExemplars"));
assert.ok(server.includes("normalizeScoutSandboxRpcExemplars(data)"));
assert.ok(server.includes("business_data: true"));
assert.ok(server.includes("const RPC_LIMIT_PER_KIND = 1"));
for (const source of [server, connectGateway, contractGateway]) {
  assert.ok(source.includes("ui://scout/component-sandbox/v1"));
  assert.ok(source.includes("ui://scout/component-sandbox/v2"));
  assert.ok(source.includes("ui://scout/component-sandbox/v3"));
  assert.ok(source.includes("ui://scout/component-sandbox/v4"));
  assert.ok(source.includes("ui://scout/component-sandbox/v5"));
}
assert.ok(server.includes("COMPATIBILITY_RESOURCE_URIS"));
assert.ok(connectGateway.includes("SANDBOX_COMPATIBILITY_RESOURCE_URIS"));
assert.ok(contractGateway.includes("SANDBOX_COMPATIBILITY_RESOURCE_URIS"));
assert.ok(generated.includes("Scout View v5 loaded"));
assert.ok(server.includes("SCOUT_SANDBOX_RESULT_VERSION"));

console.log("Scout MCP Apps foundation and bounded data-contract checks passed.");
