function escapeHTML(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function renderWorkspaceShell({ title, description, bodyHTML = "" }) {
  return `
    <section class="workspace-shell">
      <header class="workspace-shell-header">
        <h2>${escapeHTML(title)}</h2>
        <p class="muted">${escapeHTML(description)}</p>
      </header>
      <div class="workspace-shell-body">
        ${bodyHTML}
      </div>
    </section>
  `;
}

export function renderEmptyState({ title, message }) {
  return `
    <section class="workspace-empty-state">
      <h3>${escapeHTML(title)}</h3>
      <p class="muted">${escapeHTML(message)}</p>
    </section>
  `;
}
