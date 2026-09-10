import { App } from "@modelcontextprotocol/ext-apps/app-with-deps";
import { normalizeScoutSandboxExemplars } from "./contract";

const status = document.querySelector<HTMLElement>("[data-scout-status]");
const detail = document.querySelector<HTMLElement>("[data-scout-detail]");
const count = document.querySelector<HTMLElement>("[data-scout-count]");
const list = document.querySelector<HTMLUListElement>("[data-scout-exemplars]");

function displayValue(value: string | null) {
  return value ?? "Not available";
}

function renderExemplars(value: unknown) {
  const exemplars = normalizeScoutSandboxExemplars(value);
  if (count) count.textContent = exemplars.length === 0
    ? "No valid exemplars were returned."
    : `${exemplars.length} real Scout exemplar${exemplars.length === 1 ? "" : "s"} received`;
  if (!list) return;
  const items = exemplars.map((exemplar) => {
    const item = document.createElement("li");
    const name = document.createElement("strong");
    const details = document.createElement("span");
    name.textContent = exemplar.name;
    details.textContent = `${exemplar.kind} · Archetype: ${displayValue(exemplar.archetype)} · Resolution: ${displayValue(exemplar.resolution_status)}`;
    item.append(name, details);
    return item;
  });
  list.replaceChildren(...items);
}

const app = new App({ name: "scout-ui-foundation", version: "2.0.0" });

app.ontoolinput = () => {
  if (status) status.textContent = "Scout View connected";
  if (detail) detail.textContent = "Tool input received through the MCP Apps host bridge.";
};

app.ontoolresult = (result) => {
  const foundation = result?.structuredContent?.foundation;
  if (status) status.textContent = foundation === "ready" ? "Scout View ready" : "Scout View connected";
  if (detail) detail.textContent = "Real Scout data reached this View through structured tool content.";
  renderExemplars(result?.structuredContent?.exemplars);
};

app.onerror = (error) => {
  console.error("Scout MCP Apps View error", error);
  if (status) status.textContent = "Scout View rendered";
  if (detail) detail.textContent = "The UI is visible, but the host bridge reported an error.";
};

await app.connect();
