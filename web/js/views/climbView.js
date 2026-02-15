import { showToast } from "../components/toasts.js";
import { renderWorkspaceShell } from "../components/workspaceLayout.js";

const MAX_TEXT_LENGTH = 160;

export function renderClimbView({ store, selection, onSelect, onSave, onDelete }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  const entries = store
    .active("climb_entries")
    .slice()
    .sort((a, b) => String(b.date_logged || "").localeCompare(String(a.date_logged || "")));
  const climbSearch = String(selection.climbSearch || "").trim().toLocaleLowerCase();
  const climbOnlyWip = Boolean(selection.climbOnlyWip);
  const filteredEntries = entries.filter((entry) => {
    if (climbOnlyWip && !entry.is_work_in_progress) {
      return false;
    }
    if (!climbSearch) {
      return true;
    }
    const haystack = [
      entry.grade,
      entry.style,
      entry.gym,
      entry.climb_type,
      entry.notes,
      entry.hold_color
    ]
      .filter(Boolean)
      .join(" ")
      .toLocaleLowerCase();
    return haystack.includes(climbSearch);
  });
  const styles = store.active("climb_styles");
  const gyms = store.active("climb_gyms");
  const selectedEntry = store.get("climb_entries", selection.climbEntryId);

  if (!selection.climbEntryId && entries.length > 0) {
    onSelect({ climbEntryId: entries[0].id });
    return;
  }

  root.innerHTML = renderWorkspaceShell({
    title: "Climb Log",
    description: "Log climbs, manage style/gym metadata, and edit entry details.",
    pills: ["climb_entries", "climb_styles", "climb_gyms"],
    bodyHTML: `
      <div class="workspace-grid climb-grid workspace-stage-grid">
        <section class="pane workspace-pane-list">
          <h2>Styles</h2>
          <form id="new-style-form" class="inline-form">
            <input id="new-style-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" required />
            <button class="btn" type="submit">Add</button>
          </form>
          ${renderMetaList("style-list", styles, "name", "No styles yet.")}
          <h2 style="margin-top: 16px;">Gyms</h2>
          <form id="new-gym-form" class="inline-form">
            <input id="new-gym-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" required />
            <button class="btn" type="submit">Add</button>
          </form>
          ${renderMetaList("gym-list", gyms, "name", "No gyms yet.")}
        </section>
        <section class="pane workspace-pane-detail">
          <h2>Entries</h2>
          <form id="entry-filter-form" class="editor-form compact">
            <label>Search
              <input id="entry-filter-search" class="input" type="search" placeholder="Grade, style, gym..." value="${escapeHTML(selection.climbSearch || "")}" />
            </label>
            <label><input id="entry-filter-wip" type="checkbox" ${selection.climbOnlyWip ? "checked" : ""} /> Only work in progress</label>
          </form>
          <form id="new-entry-form" class="editor-form compact">
            <label>Date <input id="new-entry-date" class="input" type="date" required /></label>
            <label>Type <input id="new-entry-type" class="input" type="text" maxlength="40" placeholder="Boulder / Route" required /></label>
            <label>Grade <input id="new-entry-grade" class="input" type="text" maxlength="40" required /></label>
            <label>Style
              <select id="new-entry-style" class="input" required>
                ${renderSelectOptions(styles, "name")}
              </select>
            </label>
            <label>Gym
              <select id="new-entry-gym" class="input" required>
                ${renderSelectOptions(gyms, "name")}
              </select>
            </label>
            <label><input id="new-entry-wip" type="checkbox" /> Work in progress</label>
            <button class="btn primary" type="submit">Add Entry</button>
          </form>
          ${renderEntryList(filteredEntries, selection.climbEntryId)}
        </section>
        <section class="pane workspace-pane-edit">
          <h2>Entry Editor</h2>
          ${renderEntryEditor(selectedEntry, styles, gyms)}
        </section>
      </div>
    `
  });

  bindClimbEvents({ store, selection, onSelect, onSave, onDelete });
}

function bindClimbEvents({ store, selection, onSelect, onSave, onDelete }) {
  document.getElementById("entry-filter-search")?.addEventListener("input", (event) => {
    const value = String(event.target?.value || "");
    onSelect({ climbSearch: value });
  });

  document.getElementById("entry-filter-wip")?.addEventListener("change", (event) => {
    onSelect({ climbOnlyWip: Boolean(event.target?.checked) });
  });

  document.getElementById("style-list")?.addEventListener("click", async (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    if (!confirmDelete("style", button.dataset.label || "this style")) {
      return;
    }
    await onDelete({ entity: "climb_styles", id: button.dataset.id });
    showToast("Style deleted", "info");
  });

  document.getElementById("gym-list")?.addEventListener("click", async (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    if (!confirmDelete("gym", button.dataset.label || "this gym")) {
      return;
    }
    await onDelete({ entity: "climb_gyms", id: button.dataset.id });
    showToast("Gym deleted", "info");
  });

  document.getElementById("entry-list")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    const climbEntryId = button.dataset.id;
    if (!climbEntryId) {
      return;
    }
    onSelect({ climbEntryId });
  });

  document.getElementById("new-style-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const name = sanitizedValue("new-style-name");
    if (!name) {
      return;
    }
    await onSave({
      entity: "climb_styles",
      id: crypto.randomUUID(),
      payload: { name, is_default: false, is_hidden: false }
    });
    showToast("Style saved", "success");
  });

  document.getElementById("new-gym-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const name = sanitizedValue("new-gym-name");
    if (!name) {
      return;
    }
    await onSave({
      entity: "climb_gyms",
      id: crypto.randomUUID(),
      payload: { name, is_default: false }
    });
    showToast("Gym saved", "success");
  });

  document.getElementById("new-entry-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const style = optionalValue("new-entry-style");
    const gym = optionalValue("new-entry-gym");
    const date = optionalValue("new-entry-date");
    const climbType = sanitizedValue("new-entry-type");
    const grade = sanitizedValue("new-entry-grade");
    if (!style || !gym || !date || !climbType || !grade) {
      return;
    }
    const id = crypto.randomUUID();
    await onSave({
      entity: "climb_entries",
      id,
      payload: {
        climb_type: climbType,
        rope_climb_type: null,
        grade,
        feels_like_grade: null,
        angle_degrees: null,
        style,
        attempts: null,
        is_work_in_progress: Boolean(document.getElementById("new-entry-wip")?.checked),
        is_previously_climbed: false,
        hold_color: null,
        gym,
        notes: null,
        date_logged: `${date}T00:00:00.000Z`,
        tb2_climb_uuid: null
      }
    });
    onSelect({ climbEntryId: id });
    showToast("Entry saved", "success");
  });

  document.getElementById("entry-editor")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.climbEntryId) {
      return;
    }
    const current = store.get("climb_entries", selection.climbEntryId);
    if (!current) {
      return;
    }
    const dateLogged = optionalValue("entry-date");
    await onSave({
      entity: "climb_entries",
      id: selection.climbEntryId,
      payload: {
        climb_type: sanitizedValue("entry-type"),
        rope_climb_type: optionalSanitizedValue("entry-rope-type"),
        grade: sanitizedValue("entry-grade"),
        feels_like_grade: optionalSanitizedValue("entry-feels-like-grade"),
        angle_degrees: optionalNumberValue("entry-angle"),
        style: optionalValue("entry-style"),
        attempts: optionalNumberValue("entry-attempts"),
        is_work_in_progress: Boolean(document.getElementById("entry-wip")?.checked),
        is_previously_climbed: Boolean(document.getElementById("entry-prev")?.checked),
        hold_color: optionalSanitizedValue("entry-hold-color"),
        gym: optionalValue("entry-gym"),
        notes: optionalSanitizedValue("entry-notes"),
        date_logged: dateLogged ? `${dateLogged}T00:00:00.000Z` : current.date_logged,
        tb2_climb_uuid: optionalSanitizedValue("entry-tb2")
      }
    });
    showToast("Entry updated", "success");
  });

  document.getElementById("entry-delete")?.addEventListener("click", async () => {
    if (!selection.climbEntryId) {
      return;
    }
    const row = store.get("climb_entries", selection.climbEntryId);
    if (!confirmDelete("entry", row?.grade || "this entry")) {
      return;
    }
    await onDelete({ entity: "climb_entries", id: selection.climbEntryId });
    onSelect({ climbEntryId: null });
    showToast("Entry deleted", "info");
  });
}

function renderMetaList(id, rows, key, emptyLabel) {
  if (!rows.length) {
    return `<p class="muted">${emptyLabel}</p>`;
  }
  return `
    <ul id="${id}" class="select-list">
      ${rows
        .map(
          (row) => `<li><button type="button" class="list-btn" data-id="${row.id}" data-label="${escapeHTML(row[key] || row.id)}">${escapeHTML(row[key] || row.id)}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderEntryList(entries, selectedEntryId) {
  if (!entries.length) {
    return `<p class="muted">No entries yet.</p>`;
  }
  return `
    <ul id="entry-list" class="select-list">
      ${entries
        .map(
          (entry) =>
            `<li><button type="button" data-id="${entry.id}" class="list-btn${entry.id === selectedEntryId ? " active" : ""}">${escapeHTML(
              `${dateInputValue(entry.date_logged)} · ${entry.grade || "Unknown"} · ${entry.style || "No style"}`
            )}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderEntryEditor(entry, styles, gyms) {
  if (!entry) {
    return `<p class="muted">Select an entry to edit.</p>`;
  }
  return `
    <form id="entry-editor" class="editor-form">
      <label>Date <input id="entry-date" class="input" type="date" value="${escapeHTML(dateInputValue(entry.date_logged))}" required /></label>
      <label>Type <input id="entry-type" class="input" type="text" maxlength="40" value="${escapeHTML(entry.climb_type || "")}" required /></label>
      <label>Rope Type <input id="entry-rope-type" class="input" type="text" maxlength="40" value="${escapeHTML(entry.rope_climb_type || "")}" /></label>
      <label>Grade <input id="entry-grade" class="input" type="text" maxlength="40" value="${escapeHTML(entry.grade || "")}" required /></label>
      <label>Feels Like Grade <input id="entry-feels-like-grade" class="input" type="text" maxlength="40" value="${escapeHTML(entry.feels_like_grade || "")}" /></label>
      <label>Angle <input id="entry-angle" class="input" type="number" step="any" value="${escapeHTML(numberValue(entry.angle_degrees))}" /></label>
      <label>Style <select id="entry-style" class="input">${renderSelectOptions(styles, "name", entry.style)}</select></label>
      <label>Gym <select id="entry-gym" class="input">${renderSelectOptions(gyms, "name", entry.gym)}</select></label>
      <label>Attempts <input id="entry-attempts" class="input" type="number" step="any" value="${escapeHTML(numberValue(entry.attempts))}" /></label>
      <label>Hold Color <input id="entry-hold-color" class="input" type="text" maxlength="40" value="${escapeHTML(entry.hold_color || "")}" /></label>
      <label>TB2 UUID <input id="entry-tb2" class="input" type="text" maxlength="80" value="${escapeHTML(entry.tb2_climb_uuid || "")}" /></label>
      <label><input id="entry-wip" type="checkbox" ${entry.is_work_in_progress ? "checked" : ""} /> Work in progress</label>
      <label><input id="entry-prev" type="checkbox" ${entry.is_previously_climbed ? "checked" : ""} /> Previously climbed</label>
      <label>Notes <textarea id="entry-notes" class="input" rows="4" maxlength="500">${escapeHTML(entry.notes || "")}</textarea></label>
      <div class="actions">
        <button class="btn primary" type="submit">Save</button>
        <button id="entry-delete" class="btn" type="button">Delete</button>
      </div>
    </form>
  `;
}

function renderSelectOptions(rows, key, selectedValue = "") {
  if (!rows.length) {
    return `<option value="">No options</option>`;
  }
  return rows
    .map((row) => `<option value="${row[key]}" ${row[key] === selectedValue ? "selected" : ""}>${escapeHTML(row[key])}</option>`)
    .join("");
}

function optionalNumberValue(id) {
  const value = String(document.getElementById(id)?.value || "").trim();
  if (!value) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function numberValue(value) {
  return Number.isFinite(Number(value)) ? String(value) : "";
}

function optionalValue(id) {
  const value = String(document.getElementById(id)?.value || "").trim();
  return value || null;
}

function dateInputValue(value) {
  if (!value) {
    return "";
  }
  return String(value).slice(0, 10);
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
