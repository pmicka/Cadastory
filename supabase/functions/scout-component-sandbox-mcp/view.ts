import { App } from "@modelcontextprotocol/ext-apps/app-with-deps";

const status = document.querySelector<HTMLElement>("[data-scout-status]");
const detail = document.querySelector<HTMLElement>("[data-scout-detail]");

const app = new App({ name: "scout-ui-foundation", version: "1.0.0" });

app.ontoolinput = () => {
  if (status) status.textContent = "Scout View connected";
  if (detail) detail.textContent = "Tool input received through the MCP Apps host bridge.";
};

app.ontoolresult = (result) => {
  const foundation = result?.structuredContent?.foundation;
  if (status) status.textContent = foundation === "ready" ? "Scout View ready" : "Scout View connected";
  if (detail) detail.textContent = "The sandbox tool result reached this View successfully.";
};

app.onerror = (error) => {
  console.error("Scout MCP Apps View error", error);
  if (status) status.textContent = "Scout View rendered";
  if (detail) detail.textContent = "The UI is visible, but the host bridge reported an error.";
};

await app.connect();
