import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";

const directory = new URL("./", import.meta.url);
const [view, server, generated] = await Promise.all([
  readFile(new URL("view.ts", directory), "utf8"),
  readFile(new URL("index.ts", directory), "utf8"),
  readFile(new URL("view.generated.ts", directory), "utf8"),
]);

assert.equal((view.match(/\.connect\(\)/g) || []).length, 1);
assert.ok(view.indexOf("app.ontoolinput") < view.indexOf("app.connect()"));
assert.ok(view.indexOf("app.ontoolresult") < view.indexOf("app.connect()"));
assert.ok(view.indexOf("app.onerror") < view.indexOf("app.connect()"));
assert.equal(view.includes("window.openai"), false);
assert.equal(generated.includes("https://unpkg.com"), false);
assert.equal(generated.includes("https://cdn."), false);
assert.equal(server.includes("'openai/outputTemplate'"), false);
assert.equal(server.includes("'ui/resourceUri'"), false);
assert.ok(server.includes("_meta: { ui: { resourceUri: RESOURCE_URI } }"));
assert.ok(server.includes("RESOURCE_MIME_TYPE"));

console.log("Scout MCP Apps foundation checks passed.");
