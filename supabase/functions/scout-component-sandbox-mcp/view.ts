const status = document.querySelector<HTMLElement>("[data-scout-status]");
const detail = document.querySelector<HTMLElement>("[data-scout-detail]");
const count = document.querySelector<HTMLElement>("[data-scout-count]");
const list = document.querySelector<HTMLUListElement>("[data-scout-exemplars]");

function cleanText(value: unknown, maxLength: number) {
  if (typeof value !== "string") return null;
  const cleaned = value.trim();
  return cleaned.length > 0 && cleaned.length <= maxLength ? cleaned : null;
}

function normalizeExemplars(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value.map((raw) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    const item = raw as Record<string, unknown>;
    const name = cleanText(item.name, 160);
    const kind = item.kind === "property" || item.kind === "group" ? item.kind : null;
    if (!name || !kind) return null;
    return {
      name,
      kind,
      archetype: cleanText(item.archetype, 100),
      resolution_status: cleanText(item.resolution_status, 100),
    };
  }).filter((item): item is NonNullable<typeof item> => item !== null).slice(0, 4);
}

function displayValue(value: string | null) {
  return value ?? "Not available";
}

function renderExemplars(value: unknown) {
  const exemplars = normalizeExemplars(value);
  if (status) status.textContent = "Scout View ready";
  if (detail) detail.textContent = "Real Scout data reached this View through the standard MCP Apps tool-result notification.";
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

window.addEventListener("message", (event) => {
  if (event.source !== window.parent) return;
  const message = event.data;
  if (!message || message.jsonrpc !== "2.0") return;
  if (message.method === "ui/notifications/tool-input") {
    if (status) status.textContent = "Scout View connected";
    if (detail) detail.textContent = "Tool input reached the standard MCP Apps bridge listener.";
  }
  if (message.method === "ui/notifications/tool-result") {
    renderExemplars(message.params?.structuredContent?.exemplars);
  }
}, { passive: true });

if (status) status.textContent = "Scout View listening";
if (detail) detail.textContent = "Standard MCP Apps tool-result listener ready.";
