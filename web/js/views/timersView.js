import { showToast } from "../components/toasts.js";
import { renderWorkspaceShell } from "../components/workspaceLayout.js";

const MAX_TEXT_LENGTH = 160;
const DELETE_ICON = `<span class="icon-trash" aria-hidden="true"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span>`;

export function renderTimersView({ store, selection, onSelect, onSave, onDelete }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  const templates = store.active("timer_templates");
  const selectedTemplate = store.get("timer_templates", selection.timerTemplateId);
  const intervals = store
    .active("timer_intervals")
    .filter((item) => item.timer_template_id === selection.timerTemplateId)
    .slice()
    .sort((a, b) => Number(a.display_order || 0) - Number(b.display_order || 0));
  const selectedInterval = store.get("timer_intervals", selection.timerIntervalId);

  const timerSessions = store
    .active("timer_sessions")
    .slice()
    .sort((a, b) => String(b.start_date || "").localeCompare(String(a.start_date || "")));
  const selectedTimerSession = store.get("timer_sessions", selection.timerSessionId);
  const timerLaps = store
    .active("timer_laps")
    .filter((item) => item.timer_session_id === selection.timerSessionId)
    .slice()
    .sort((a, b) => Number(a.lap_number || 0) - Number(b.lap_number || 0));

  if (!selection.timerTemplateId && templates.length > 0) {
    onSelect({ timerTemplateId: templates[0].id, timerIntervalId: null });
    return;
  }

  root.innerHTML = renderWorkspaceShell({
    title: "Timers",
    description: "Manage timer templates/intervals and review timer session history.",
    pills: ["timer_templates", "timer_intervals", "timer_sessions", "timer_laps"],
    bodyHTML: `
      <div class="workspace-grid timers-grid workspace-stage-grid">
        <section class="pane workspace-pane-list">
          <h2>Templates</h2>
          <form id="new-template-form" class="inline-form">
            <input id="new-template-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" required />
            <button class="btn primary" type="submit">Add</button>
          </form>
          ${renderTemplateList(templates, selection.timerTemplateId)}
          <h3 style="margin-top: 16px;">Template Editor</h3>
          ${renderTemplateEditor(selectedTemplate)}
        </section>
        <section class="pane workspace-pane-detail">
          <h2>Intervals</h2>
          <form id="new-interval-form" class="editor-form compact">
            <label>Name <input id="new-interval-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" ${selection.timerTemplateId ? "" : "disabled"} required /></label>
            <label>Work (sec) <input id="new-interval-work" class="input" type="number" step="1" min="0" ${selection.timerTemplateId ? "" : "disabled"} required /></label>
            <label>Rest (sec) <input id="new-interval-rest" class="input" type="number" step="1" min="0" ${selection.timerTemplateId ? "" : "disabled"} required /></label>
            <label>Repetitions <input id="new-interval-repetitions" class="input" type="number" step="1" min="1" ${selection.timerTemplateId ? "" : "disabled"} required /></label>
            <button class="btn" type="submit" ${selection.timerTemplateId ? "" : "disabled"}>Add Interval</button>
          </form>
          ${renderIntervalList(intervals, selection.timerIntervalId)}
          <h3 style="margin-top: 16px;">Interval Editor</h3>
          ${renderIntervalEditor(selectedInterval)}
        </section>
        <section class="pane workspace-pane-edit">
          <h2>Timer Sessions</h2>
          ${renderTimerSessionList(timerSessions, selection.timerSessionId)}
          <h3 style="margin-top: 16px;">Laps</h3>
          ${renderTimerLapList(timerLaps)}
        </section>
      </div>
    `
  });

  bindTimersEvents({ store, selection, onSelect, onSave, onDelete, intervals });
}

function bindTimersEvents({ store, selection, onSelect, onSave, onDelete, intervals }) {
  document.getElementById("template-list")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    const timerTemplateId = button.dataset.id;
    if (!timerTemplateId) {
      return;
    }
    onSelect({ timerTemplateId, timerIntervalId: null });
  });

  document.getElementById("interval-list")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    const timerIntervalId = button.dataset.id;
    if (!timerIntervalId) {
      return;
    }
    onSelect({ timerIntervalId });
  });

  document.getElementById("timer-session-list")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    const timerSessionId = button.dataset.id;
    if (!timerSessionId) {
      return;
    }
    onSelect({ timerSessionId });
  });

  document.getElementById("new-template-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const name = sanitizedValue("new-template-name");
    if (!name) {
      return;
    }
    const id = crypto.randomUUID();
    await onSave({
      entity: "timer_templates",
      id,
      payload: {
        name,
        template_description: null,
        total_time_seconds: null,
        is_repeating: false,
        repeat_count: null,
        rest_time_between_intervals: null,
        created_date: new Date().toISOString(),
        last_used_date: null,
        use_count: 0
      }
    });
    onSelect({ timerTemplateId: id, timerIntervalId: null });
    showToast("Template saved", "success");
  });

  document.getElementById("template-editor")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.timerTemplateId) {
      return;
    }
    const current = store.get("timer_templates", selection.timerTemplateId);
    if (!current) {
      return;
    }
    await onSave({
      entity: "timer_templates",
      id: selection.timerTemplateId,
      payload: {
        name: sanitizedValue("template-name"),
        template_description: optionalSanitizedValue("template-description"),
        total_time_seconds: optionalIntegerValue("template-total-time"),
        is_repeating: Boolean(document.getElementById("template-is-repeating")?.checked),
        repeat_count: optionalIntegerValue("template-repeat-count"),
        rest_time_between_intervals: optionalIntegerValue("template-rest-between"),
        created_date: current.created_date || new Date().toISOString(),
        last_used_date: current.last_used_date || null,
        use_count: Number.isFinite(Number(current.use_count)) ? Number(current.use_count) : 0
      }
    });
    showToast("Template updated", "success");
  });

  document.getElementById("template-delete")?.addEventListener("click", async () => {
    if (!selection.timerTemplateId) {
      return;
    }
    const row = store.get("timer_templates", selection.timerTemplateId);
    if (!confirmDelete("template", row?.name || "this template")) {
      return;
    }
    await onDelete({ entity: "timer_templates", id: selection.timerTemplateId });
    onSelect({ timerTemplateId: null, timerIntervalId: null });
    showToast("Template deleted", "info");
  });

  document.getElementById("new-interval-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.timerTemplateId) {
      return;
    }
    const name = sanitizedValue("new-interval-name");
    const work = integerValue("new-interval-work");
    const rest = integerValue("new-interval-rest");
    const reps = integerValue("new-interval-repetitions");
    if (!name || work === null || rest === null || reps === null) {
      return;
    }
    const id = crypto.randomUUID();
    await onSave({
      entity: "timer_intervals",
      id,
      payload: {
        timer_template_id: selection.timerTemplateId,
        name,
        work_time_seconds: work,
        rest_time_seconds: rest,
        repetitions: reps,
        display_order: intervals.length
      }
    });
    onSelect({ timerIntervalId: id });
    showToast("Interval saved", "success");
  });

  document.getElementById("interval-editor")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.timerIntervalId) {
      return;
    }
    const current = store.get("timer_intervals", selection.timerIntervalId);
    const name = sanitizedValue("interval-name");
    const work = integerValue("interval-work");
    const rest = integerValue("interval-rest");
    const reps = integerValue("interval-repetitions");
    if (!name || work === null || rest === null || reps === null) {
      return;
    }
    await onSave({
      entity: "timer_intervals",
      id: selection.timerIntervalId,
      payload: {
        timer_template_id: current?.timer_template_id || selection.timerTemplateId,
        name,
        work_time_seconds: work,
        rest_time_seconds: rest,
        repetitions: reps,
        display_order: integerValue("interval-order") ?? Number(current?.display_order || 0)
      }
    });
    showToast("Interval updated", "success");
  });

  document.getElementById("interval-delete")?.addEventListener("click", async () => {
    if (!selection.timerIntervalId) {
      return;
    }
    const row = store.get("timer_intervals", selection.timerIntervalId);
    if (!confirmDelete("interval", row?.name || "this interval")) {
      return;
    }
    await onDelete({ entity: "timer_intervals", id: selection.timerIntervalId });
    onSelect({ timerIntervalId: null });
    showToast("Interval deleted", "info");
  });
}

function renderTemplateList(templates, selectedTemplateId) {
  if (!templates.length) {
    return `<p class="muted">No templates yet.</p>`;
  }
  return `
    <ul id="template-list" class="select-list">
      ${templates
        .map(
          (template) =>
            `<li><button type="button" data-id="${template.id}" class="list-btn${template.id === selectedTemplateId ? " active" : ""}">${escapeHTML(
              template.name || template.id
            )}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderIntervalList(intervals, selectedIntervalId) {
  if (!intervals.length) {
    return `<p class="muted">No intervals yet.</p>`;
  }
  return `
    <ul id="interval-list" class="select-list">
      ${intervals
        .map(
          (interval) =>
            `<li><button type="button" data-id="${interval.id}" class="list-btn${interval.id === selectedIntervalId ? " active" : ""}">${escapeHTML(
              `${interval.name || interval.id} (${interval.work_time_seconds || 0}s / ${interval.rest_time_seconds || 0}s)`
            )}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderTimerSessionList(sessions, selectedSessionId) {
  if (!sessions.length) {
    return `<p class="muted">No timer sessions yet.</p>`;
  }
  return `
    <ul id="timer-session-list" class="select-list">
      ${sessions
        .map(
          (session) =>
            `<li><button type="button" data-id="${session.id}" class="list-btn${session.id === selectedSessionId ? " active" : ""}">${escapeHTML(
              `${dateLabel(session.start_date)} · ${(session.template_name || "Unnamed template")}`
            )}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderTimerLapList(laps) {
  if (!laps.length) {
    return `<p class="muted">Select a timer session to view laps.</p>`;
  }
  return `
    <ul class="select-list">
      ${laps
        .map(
          (lap) =>
            `<li><div class="list-btn">Lap ${escapeHTML(String(lap.lap_number || 0))} · ${escapeHTML(String(lap.elapsed_seconds || 0))}s</div></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderTemplateEditor(template) {
  if (!template) {
    return `<p class="muted">Select a template to edit.</p>`;
  }
  return `
    <form id="template-editor" class="editor-form compact">
      <label>Name <input id="template-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(template.name || "")}" required /></label>
      <label>Description <input id="template-description" class="input" type="text" maxlength="260" value="${escapeHTML(template.template_description || "")}" /></label>
      <label>Total Time (sec) <input id="template-total-time" class="input" type="number" step="1" min="0" value="${escapeHTML(numberValue(template.total_time_seconds))}" /></label>
      <label><input id="template-is-repeating" type="checkbox" ${template.is_repeating ? "checked" : ""} /> Repeating</label>
      <label>Repeat Count <input id="template-repeat-count" class="input" type="number" step="1" min="1" value="${escapeHTML(numberValue(template.repeat_count))}" /></label>
      <label>Rest Between (sec) <input id="template-rest-between" class="input" type="number" step="1" min="0" value="${escapeHTML(numberValue(template.rest_time_between_intervals))}" /></label>
      <div class="actions">
        <button class="btn primary" type="submit">Save</button>
        <button id="template-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>
      </div>
    </form>
  `;
}

function renderIntervalEditor(interval) {
  if (!interval) {
    return `<p class="muted">Select an interval to edit.</p>`;
  }
  return `
    <form id="interval-editor" class="editor-form compact">
      <label>Name <input id="interval-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(interval.name || "")}" required /></label>
      <label>Work (sec) <input id="interval-work" class="input" type="number" step="1" min="0" value="${escapeHTML(numberValue(interval.work_time_seconds))}" required /></label>
      <label>Rest (sec) <input id="interval-rest" class="input" type="number" step="1" min="0" value="${escapeHTML(numberValue(interval.rest_time_seconds))}" required /></label>
      <label>Repetitions <input id="interval-repetitions" class="input" type="number" step="1" min="1" value="${escapeHTML(numberValue(interval.repetitions))}" required /></label>
      <label>Order <input id="interval-order" class="input" type="number" step="1" min="0" value="${escapeHTML(numberValue(interval.display_order))}" /></label>
      <div class="actions">
        <button class="btn primary" type="submit">Save</button>
        <button id="interval-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>
      </div>
    </form>
  `;
}

function integerValue(id) {
  const raw = String(document.getElementById(id)?.value || "").trim();
  if (!raw) {
    return null;
  }
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function optionalIntegerValue(id) {
  const value = integerValue(id);
  return value === null ? null : value;
}

function numberValue(value) {
  return Number.isFinite(Number(value)) ? String(value) : "";
}

function optionalSanitizedValue(id) {
  const value = sanitizedValue(id);
  return value || null;
}

function sanitizedValue(id) {
  return sanitizeText(String(document.getElementById(id)?.value || ""));
}

function sanitizeText(value) {
  return value.replaceAll(/[\u0000-\u001F\u007F]/g, "").trim();
}

function dateLabel(value) {
  if (!value) {
    return "Unknown";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return String(value);
  }
  return date.toLocaleDateString();
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
