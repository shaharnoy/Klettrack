import { renderEmptyState, renderWorkspaceShell } from "../components/workspaceLayout.js";

export function renderDomainPlaceholderView({ title, description, entities }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  root.innerHTML = renderWorkspaceShell({
    title,
    description,
    pills: entities || [],
    bodyHTML: renderEmptyState({
      title: "Workspace In Progress",
      message: "UI for this domain is being implemented as part of the v2 web UX plan."
    })
  });
}
