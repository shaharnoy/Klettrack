import { showToast } from "../components/toasts.js";
import { renderWorkspaceShell } from "../components/workspaceLayout.js";

const MAX_TEXT_LENGTH = 160;

export function renderSessionsView({ store, selection, onSelect, onSave, onDelete }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  const sessions = store
    .active("sessions")
    .slice()
    .sort((a, b) => String(b.session_date || "").localeCompare(String(a.session_date || "")));
  const selectedSession = store.get("sessions", selection.sessionId);
  const sessionItems = store
    .active("session_items")
    .filter((item) => item.session_id === selection.sessionId)
    .slice()
    .sort((a, b) => Number(a.sort_order || 0) - Number(b.sort_order || 0));
  const selectedItem = store.get("session_items", selection.sessionItemId);

  if (!selection.sessionId && sessions.length > 0) {
    onSelect({ sessionId: sessions[0].id, sessionItemId: null });
    return;
  }

  root.innerHTML = renderWorkspaceShell({
    title: "Sessions",
    description: "Track completed sessions and what you performed in each one.",
    pills: ["sessions", "session_items"],
    bodyHTML: `
      <div class="workspace-grid sessions-grid workspace-stage-grid">
        <section class="pane workspace-pane-list">
          <h2>Sessions</h2>
          <form id="new-session-form" class="inline-form">
            <input id="new-session-date" class="input" type="date" required />
            <button class="btn primary" type="submit">Add</button>
          </form>
          ${renderSessionList(sessions, selection.sessionId)}
        </section>
        <section class="pane workspace-pane-detail">
          <h2>Session Details</h2>
          ${renderSessionEditor(selectedSession)}
          <h3 style="margin-top: 14px;">Items</h3>
          <form id="new-session-item-form" class="editor-form compact">
            <label>Exercise Name
              <input id="new-session-item-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" ${selection.sessionId ? "" : "disabled"} required />
            </label>
            <label>Notes
              <input id="new-session-item-notes" class="input" type="text" maxlength="260" ${selection.sessionId ? "" : "disabled"} />
            </label>
            <button class="btn" type="submit" ${selection.sessionId ? "" : "disabled"}>Add Item</button>
          </form>
          ${renderSessionItemList(sessionItems, selection.sessionItemId)}
        </section>
        <section class="pane workspace-pane-edit">
          <h2>Item Editor</h2>
          ${renderSessionItemEditor(selectedItem)}
        </section>
      </div>
    `
  });

  bindSessionEvents({ store, selection, onSelect, onSave, onDelete, sessionItems });
}

function bindSessionEvents({ store, selection, onSelect, onSave, onDelete, sessionItems }) {
  document.getElementById("session-list")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    const sessionId = button.dataset.id;
    if (!sessionId) {
      return;
    }
    onSelect({ sessionId, sessionItemId: null });
  });

  document.getElementById("session-item-list")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    const sessionItemId = button.dataset.id;
    if (!sessionItemId) {
      return;
    }
    onSelect({ sessionItemId });
  });

  document.getElementById("new-session-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const date = document.getElementById("new-session-date")?.value;
    if (!date) {
      return;
    }
    const id = crypto.randomUUID();
    await onSave({
      entity: "sessions",
      id,
      payload: {
        session_date: `${date}T00:00:00.000Z`
      }
    });
    onSelect({ sessionId: id, sessionItemId: null });
    showToast("Session saved", "success");
  });

  document.getElementById("session-editor")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.sessionId) {
      return;
    }
    const current = store.get("sessions", selection.sessionId);
    const date = document.getElementById("session-date")?.value;
    if (!date) {
      return;
    }
    await onSave({
      entity: "sessions",
      id: selection.sessionId,
      payload: {
        session_date: date ? `${date}T00:00:00.000Z` : current?.session_date
      }
    });
    showToast("Session updated", "success");
  });

  document.getElementById("session-delete")?.addEventListener("click", async () => {
    if (!selection.sessionId) {
      return;
    }
    const row = store.get("sessions", selection.sessionId);
    if (!confirmDelete("session", formatDate(row?.session_date))) {
      return;
    }
    await onDelete({ entity: "sessions", id: selection.sessionId });
    onSelect({ sessionId: null, sessionItemId: null });
    showToast("Session deleted", "info");
  });

  document.getElementById("new-session-item-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.sessionId) {
      return;
    }
    const exerciseName = sanitizedValue("new-session-item-name");
    if (!exerciseName) {
      return;
    }
    const id = crypto.randomUUID();
    await onSave({
      entity: "session_items",
      id,
      payload: {
        session_id: selection.sessionId,
        source_tag: null,
        exercise_name: exerciseName,
        sort_order: sessionItems.length,
        plan_source_id: null,
        plan_name: null,
        reps: null,
        sets: null,
        weight_kg: null,
        grade: null,
        notes: optionalSanitizedValue("new-session-item-notes"),
        duration: null
      }
    });
    onSelect({ sessionItemId: id });
    showToast("Session item saved", "success");
  });

  document.getElementById("session-item-editor")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.sessionItemId) {
      return;
    }
    const current = store.get("session_items", selection.sessionItemId);
    const exerciseName = sanitizedValue("session-item-name");
    if (!exerciseName) {
      return;
    }
    await onSave({
      entity: "session_items",
      id: selection.sessionItemId,
      payload: {
        session_id: current?.session_id || selection.sessionId,
        source_tag: optionalSanitizedValue("session-item-source-tag"),
        exercise_name: exerciseName,
        sort_order: Number(document.getElementById("session-item-sort-order")?.value || "0"),
        plan_source_id: optionalUUIDValue("session-item-plan-source-id"),
        plan_name: optionalSanitizedValue("session-item-plan-name"),
        reps: optionalNumberValue("session-item-reps"),
        sets: optionalNumberValue("session-item-sets"),
        weight_kg: optionalNumberValue("session-item-weight-kg"),
        grade: optionalSanitizedValue("session-item-grade"),
        notes: optionalSanitizedValue("session-item-notes"),
        duration: optionalNumberValue("session-item-duration")
      }
    });
    showToast("Session item updated", "success");
  });

  document.getElementById("session-item-delete")?.addEventListener("click", async () => {
    if (!selection.sessionItemId) {
      return;
    }
    const row = store.get("session_items", selection.sessionItemId);
    if (!confirmDelete("session item", row?.exercise_name || "this item")) {
      return;
    }
    await onDelete({ entity: "session_items", id: selection.sessionItemId });
    onSelect({ sessionItemId: null });
    showToast("Session item deleted", "info");
  });
}

function renderSessionList(sessions, selectedSessionId) {
  if (!sessions.length) {
    return `<p class="muted">No sessions yet.</p>`;
  }
  return `
    <ul id="session-list" class="select-list">
      ${sessions
        .map(
          (session) =>
            `<li><button type="button" data-id="${session.id}" class="list-btn${session.id === selectedSessionId ? " active" : ""}">${escapeHTML(
              formatDate(session.session_date)
            )}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderSessionItemList(items, selectedItemId) {
  if (!items.length) {
    return `<p class="muted">No items yet.</p>`;
  }
  return `
    <ul id="session-item-list" class="select-list">
      ${items
        .map(
          (item) =>
            `<li><button type="button" data-id="${item.id}" class="list-btn${item.id === selectedItemId ? " active" : ""}">${escapeHTML(
              item.exercise_name || item.id
            )}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderSessionEditor(session) {
  if (!session) {
    return `<p class="muted">Select a session to edit details.</p>`;
  }
  return `
    <form id="session-editor" class="editor-form compact">
      <label>Date
        <input id="session-date" class="input" type="date" value="${escapeHTML(dateInputValue(session.session_date))}" required />
      </label>
      <div class="actions">
        <button class="btn primary" type="submit">Save</button>
        <button id="session-delete" class="btn" type="button">Delete</button>
      </div>
    </form>
  `;
}

function renderSessionItemEditor(item) {
  if (!item) {
    return `<p class="muted">Select a session item to edit.</p>`;
  }
  return `
    <form id="session-item-editor" class="editor-form">
      <label>Exercise Name <input id="session-item-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(item.exercise_name || "")}" required /></label>
      <label>Source Tag <input id="session-item-source-tag" class="input" type="text" maxlength="60" value="${escapeHTML(item.source_tag || "")}" /></label>
      <label>Sort Order <input id="session-item-sort-order" class="input" type="number" value="${Number(item.sort_order || 0)}" /></label>
      <label>Plan Source ID <input id="session-item-plan-source-id" class="input" type="text" maxlength="80" value="${escapeHTML(item.plan_source_id || "")}" /></label>
      <label>Plan Name <input id="session-item-plan-name" class="input" type="text" maxlength="120" value="${escapeHTML(item.plan_name || "")}" /></label>
      <label>Reps <input id="session-item-reps" class="input" type="number" step="any" value="${escapeHTML(numberValue(item.reps))}" /></label>
      <label>Sets <input id="session-item-sets" class="input" type="number" step="any" value="${escapeHTML(numberValue(item.sets))}" /></label>
      <label>Weight (kg) <input id="session-item-weight-kg" class="input" type="number" step="any" value="${escapeHTML(numberValue(item.weight_kg))}" /></label>
      <label>Grade <input id="session-item-grade" class="input" type="text" maxlength="40" value="${escapeHTML(item.grade || "")}" /></label>
      <label>Duration (sec) <input id="session-item-duration" class="input" type="number" step="any" value="${escapeHTML(numberValue(item.duration))}" /></label>
      <label>Notes <textarea id="session-item-notes" class="input" rows="3" maxlength="500">${escapeHTML(item.notes || "")}</textarea></label>
      <div class="actions">
        <button class="btn primary" type="submit">Save</button>
        <button id="session-item-delete" class="btn" type="button">Delete</button>
      </div>
    </form>
  `;
}

function formatDate(value) {
  if (!value) {
    return "Unknown date";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return String(value);
  }
  return date.toLocaleDateString();
}

function dateInputValue(value) {
  if (!value) {
    return "";
  }
  return String(value).slice(0, 10);
}

function optionalNumberValue(id) {
  const value = String(document.getElementById(id)?.value || "").trim();
  if (!value) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function optionalUUIDValue(id) {
  const value = String(document.getElementById(id)?.value || "").trim();
  return value || null;
}

function numberValue(value) {
  return Number.isFinite(Number(value)) ? String(value) : "";
}

function sanitizedValue(id) {
  return sanitizeText(String(document.getElementById(id)?.value || ""));
}

function optionalSanitizedValue(id) {
  const value = sanitizedValue(id);
  return value || null;
}

function sanitizeText(value) {
  return value.replaceAll(/[\u0000-\u001F\u007F]/g, "").trim();
}

function escapeHTML(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function confirmDelete(typeLabel, labelValue) {
  return window.confirm(`Delete ${typeLabel} "${labelValue}"? This cannot be undone.`);
}
