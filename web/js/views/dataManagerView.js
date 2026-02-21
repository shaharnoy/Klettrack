import { showToast } from "../components/toasts.js";
import { renderWorkspaceShell } from "../components/workspaceLayout.js";

const MAX_TEXT_LENGTH = 160;
const DELETE_ICON = `<span class="icon-trash" aria-hidden="true"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span>`;

export function renderDataManagerView({ store, selection, onSelect, onSave, onDelete }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  const dayTypes = store.active("day_types");
  const climbStyles = store.active("climb_styles");
  const climbGyms = store.active("climb_gyms");
  const timerTemplates = store.active("timer_templates");

  const section = selection.metaSection || "day_types";
  const selectedId = selection.metaItemId || null;
  const rows = rowsBySection(section, { dayTypes, climbStyles, climbGyms, timerTemplates });
  const selected = rows.find((row) => row.id === selectedId) || null;

  root.innerHTML = renderWorkspaceShell({
    title: "Data Manager",
    description: "Manage training days, styles, gyms, and timer templates.",
    bodyHTML: `
      <div class="workspace-grid data-manager-grid workspace-stage-grid">
        <section class="pane workspace-pane-list">
          <h2>Data Groups</h2>
          <div class="select-list" id="meta-sections">
            ${renderSectionButton("day_types", "Training Days", section)}
            ${renderSectionButton("climb_styles", "Styles", section)}
            ${renderSectionButton("climb_gyms", "Gyms", section)}
            ${renderSectionButton("timer_templates", "Timer Templates", section)}
          </div>
        </section>

        <section class="pane workspace-pane-list">
          <div class="pane-header-row">
            <h2>Items</h2>
            <button id="meta-clear-selection" class="btn primary btn-compact" type="button">Add</button>
          </div>
          <label>Search
            <input id="meta-search" class="input" type="search" value="${escapeHTML(selection.metaSearch || "")}" placeholder="Search ${escapeHTML(sectionLabel(section).toLowerCase())}" />
          </label>
          ${renderItemList(rows, selectedId, selection.metaSearch || "")}
        </section>

        <section class="pane workspace-pane-edit">
          <h2>${selected ? "Edit Item" : `Add ${escapeHTML(sectionItemLabel(section))}`}</h2>
          ${selected ? renderEditForm(section, selected) : renderCreateForm(section)}
          ${section === "timer_templates" && selected && timerTemplateMode(selected) === "intervals" ? renderTimerIntervalsList(store, selected, selection.timerIntervalId) : ""}
          ${section === "timer_templates" && selected && timerTemplateMode(selected) === "intervals" ? renderTimerIntervalEditor(store, selection.timerIntervalId) : ""}
        </section>
      </div>
    `
  });

  wireTimerTemplateModeUI();
  bindEvents({ store, selection, onSelect, onSave, onDelete, rows, selected });
}

function bindEvents({ store, selection, onSelect, onSave, onDelete, rows, selected }) {
  document.getElementById("meta-sections")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-section]");
    if (!button) {
      return;
    }
    const nextSection = button.dataset.section;
    onSelect({ metaSection: nextSection, metaItemId: null, metaSearch: "", timerTemplateId: null, timerIntervalId: null });
  });

  document.getElementById("meta-search")?.addEventListener("input", (event) => {
    onSelect({ metaSearch: String(event.target?.value || "") });
  });

  document.getElementById("meta-item-list")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    const id = button.dataset.id || null;
    if (!id) {
      return;
    }
    if (selection.metaSection === "timer_templates") {
      onSelect({ metaItemId: id, timerTemplateId: id, timerIntervalId: null });
      return;
    }
    onSelect({ metaItemId: id });
  });

  document.getElementById("meta-clear-selection")?.addEventListener("click", () => {
    onSelect({ metaItemId: null, timerIntervalId: null });
  });

  document.getElementById("meta-create-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const section = String(selection.metaSection || "day_types");
    const payload = buildPayloadForSection(section, "create", store, null);
    if (!payload) {
      showToast("Complete required fields", "error");
      return;
    }
    if (hasNameConflict(rows, payload.name)) {
      showToast("Name already exists", "error");
      return;
    }
    const id = crypto.randomUUID();
    await onSave({ entity: section, id, payload });
    onSelect({ metaItemId: id, timerTemplateId: section === "timer_templates" ? id : selection.timerTemplateId });
    showToast(`${sectionItemLabel(section)} added`, "success");
  });

  document.getElementById("meta-edit-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.metaItemId) {
      return;
    }
    const section = String(selection.metaSection || "day_types");
    const current = store.get(section, selection.metaItemId);
    if (!current) {
      return;
    }
    const payload = buildPayloadForSection(section, "edit", store, current);
    if (!payload) {
      showToast("Complete required fields", "error");
      return;
    }
    if (hasNameConflict(rows, payload.name, current.id)) {
      showToast("Name already exists", "error");
      return;
    }
    await onSave({ entity: section, id: selection.metaItemId, payload });
    if (section === "timer_templates" && timerModeFromForm("meta-edit-mode") === "total" && selection.metaItemId) {
      const intervals = store
        .active("timer_intervals")
        .filter((item) => item.timer_template_id === selection.metaItemId);
      for (const interval of intervals) {
        await onDelete({ entity: "timer_intervals", id: interval.id });
      }
      onSelect({ timerIntervalId: null });
    }
    showToast(`${sectionItemLabel(section)} updated`, "success");
  });

  document.getElementById("meta-delete")?.addEventListener("click", async () => {
    if (!selection.metaItemId) {
      return;
    }
    const section = String(selection.metaSection || "day_types");
    const current = rows.find((row) => row.id === selection.metaItemId);
    if (!window.confirm(`Delete ${sectionItemLabel(section).toLowerCase()} "${current?.name || "this item"}"? This cannot be undone.`)) {
      return;
    }
    await onDelete({ entity: section, id: selection.metaItemId });
    onSelect({ metaItemId: null, timerIntervalId: null });
    showToast(`${sectionItemLabel(section)} deleted`, "info");
  });

  if (selection.metaSection !== "timer_templates") {
    return;
  }

  document.getElementById("new-interval-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.metaItemId) {
      return;
    }
    const payload = buildIntervalPayload("create", selection.metaItemId);
    if (!payload) {
      return;
    }
    payload.display_order = store
      .active("timer_intervals")
      .filter((row) => row.timer_template_id === selection.metaItemId).length;
    const id = crypto.randomUUID();
    await onSave({ entity: "timer_intervals", id, payload });
    onSelect({ timerIntervalId: id });
    showToast("Interval added", "success");
  });

  document.getElementById("interval-list")?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }
    onSelect({ timerIntervalId: button.dataset.id || null });
  });

  document.getElementById("interval-editor")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.timerIntervalId || !selection.metaItemId) {
      return;
    }
    const payload = buildIntervalPayload("edit", selection.metaItemId, store.get("timer_intervals", selection.timerIntervalId));
    if (!payload) {
      return;
    }
    await onSave({ entity: "timer_intervals", id: selection.timerIntervalId, payload });
    showToast("Interval updated", "success");
  });

  document.getElementById("interval-delete")?.addEventListener("click", async () => {
    if (!selection.timerIntervalId) {
      return;
    }
    const interval = store.get("timer_intervals", selection.timerIntervalId);
    if (!window.confirm(`Delete interval "${interval?.name || "this interval"}"? This cannot be undone.`)) {
      return;
    }
    await onDelete({ entity: "timer_intervals", id: selection.timerIntervalId });
    onSelect({ timerIntervalId: null });
    showToast("Interval deleted", "info");
  });
}

function renderSectionButton(value, label, selected) {
  return `<button class="list-btn${selected === value ? " active" : ""}" type="button" data-section="${value}">${label}</button>`;
}

function renderItemList(rows, selectedId, search) {
  const needle = String(search || "").trim().toLocaleLowerCase();
  const filtered = rows.filter((row) => String(row.name || "").toLocaleLowerCase().includes(needle));
  if (!filtered.length) {
    return `<p class="muted">No items found.</p>`;
  }
  return `
    <ul id="meta-item-list" class="select-list">
      ${filtered
        .map(
          (row) => `<li><button type="button" data-id="${row.id}" class="list-btn${row.id === selectedId ? " active" : ""}">${escapeHTML(
            row.name || row.id
          )}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderCreateForm(section) {
  if (section === "timer_templates") {
    return `
      <form id="meta-create-form" class="editor-form compact">
        <label>Name <input id="meta-new-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" required /></label>
        <label>Description <input id="meta-new-description" class="input" type="text" maxlength="260" /></label>
        <fieldset>
          <legend>Timer Type</legend>
          <div class="segmented-control">
            <label class="checkbox-row"><input id="meta-new-mode-intervals" type="radio" name="meta-new-mode" value="intervals" checked /> Intervals</label>
            <label class="checkbox-row"><input id="meta-new-mode-total" type="radio" name="meta-new-mode" value="total" /> Total Time</label>
          </div>
        </fieldset>
        <div data-mode-group="meta-new-mode" data-mode-value="total" class="hidden">
          <label>Total Minutes <input id="meta-new-total-minutes" class="input" type="number" min="0" step="1" value="3" /></label>
          <label>Total Seconds <input id="meta-new-total-seconds" class="input" type="number" min="0" max="59" step="1" value="0" /></label>
        </div>
        <div data-mode-group="meta-new-mode" data-mode-value="intervals">
          <label class="checkbox-row"><input id="meta-new-repeating" type="checkbox" /> Repeat sets</label>
          <label data-repeat-for="meta-new-repeating" class="hidden">Repeat Count <input id="meta-new-repeat-count" class="input" type="number" min="1" step="1" value="1" /></label>
          <label>Rest Between Sets Minutes <input id="meta-new-rest-between-minutes" class="input" type="number" min="0" step="1" value="0" /></label>
          <label>Rest Between Sets Seconds <input id="meta-new-rest-between-seconds" class="input" type="number" min="0" max="59" step="1" value="0" /></label>
        </div>
        <button class="btn primary" type="submit">Add Template</button>
      </form>
    `;
  }

  return `
    <form id="meta-create-form" class="editor-form compact">
      <label>Name <input id="meta-new-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" required /></label>
      <button class="btn primary" type="submit">Add</button>
    </form>
  `;
}

function renderEditForm(section, selected) {
  if (!selected) {
    return `<p class="muted">Select an item to edit or delete.</p>`;
  }

  if (section === "timer_templates") {
    const mode = timerTemplateMode(selected);
    const totalSeconds = Number(selected.total_time_seconds || 0);
    const totalMinutesPart = Math.floor(totalSeconds / 60);
    const totalSecondsPart = totalSeconds % 60;
    const restBetween = Number(selected.rest_time_between_intervals || 0);
    const restBetweenMinutes = Math.floor(restBetween / 60);
    const restBetweenSeconds = restBetween % 60;
    return `
      <form id="meta-edit-form" class="editor-form compact">
        <label>Name <input id="meta-edit-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(selected.name || "")}" required /></label>
        <label>Description <input id="meta-edit-description" class="input" type="text" maxlength="260" value="${escapeHTML(selected.template_description || "")}" /></label>
        <fieldset>
          <legend>Timer Type</legend>
          <div class="segmented-control">
            <label class="checkbox-row"><input id="meta-edit-mode-intervals" type="radio" name="meta-edit-mode" value="intervals" ${mode === "intervals" ? "checked" : ""} /> Intervals</label>
            <label class="checkbox-row"><input id="meta-edit-mode-total" type="radio" name="meta-edit-mode" value="total" ${mode === "total" ? "checked" : ""} /> Total Time</label>
          </div>
        </fieldset>
        <div data-mode-group="meta-edit-mode" data-mode-value="total" class="${mode === "total" ? "" : "hidden"}">
          <label>Total Minutes <input id="meta-edit-total-minutes" class="input" type="number" min="0" step="1" value="${escapeHTML(numberValue(totalMinutesPart))}" /></label>
          <label>Total Seconds <input id="meta-edit-total-seconds" class="input" type="number" min="0" max="59" step="1" value="${escapeHTML(numberValue(totalSecondsPart))}" /></label>
        </div>
        <div data-mode-group="meta-edit-mode" data-mode-value="intervals" class="${mode === "intervals" ? "" : "hidden"}">
          <label class="checkbox-row"><input id="meta-edit-repeating" type="checkbox" ${selected.is_repeating ? "checked" : ""} /> Repeat sets</label>
          <label data-repeat-for="meta-edit-repeating" class="${selected.is_repeating ? "" : "hidden"}">Repeat Count <input id="meta-edit-repeat-count" class="input" type="number" min="1" step="1" value="${escapeHTML(numberValue(selected.repeat_count || 1))}" /></label>
          <label>Rest Between Sets Minutes <input id="meta-edit-rest-between-minutes" class="input" type="number" min="0" step="1" value="${escapeHTML(numberValue(restBetweenMinutes))}" /></label>
          <label>Rest Between Sets Seconds <input id="meta-edit-rest-between-seconds" class="input" type="number" min="0" max="59" step="1" value="${escapeHTML(numberValue(restBetweenSeconds))}" /></label>
        </div>
        <div class="actions">
          <button class="btn primary" type="submit">Save</button>
          <button id="meta-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>
        </div>
      </form>
    `;
  }

  return `
    <form id="meta-edit-form" class="editor-form compact">
      <label>Name <input id="meta-edit-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(selected.name || "")}" required /></label>
      <div class="actions">
        <button class="btn primary" type="submit">Save</button>
        <button id="meta-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>
      </div>
    </form>
  `;
}

function renderTimerIntervalsList(store, template, selectedIntervalId) {
  if (!template) {
    return "";
  }
  const intervals = store
    .active("timer_intervals")
    .filter((item) => item.timer_template_id === template.id)
    .slice()
    .sort((a, b) => Number(a.display_order || 0) - Number(b.display_order || 0));

  return `
    <h3 style="margin-top: 16px;">Intervals</h3>
    ${intervals.length ? `<ul id="interval-list" class="select-list">${intervals
      .map(
        (interval) =>
          `<li><button class="list-btn${interval.id === selectedIntervalId ? " active" : ""}" type="button" data-id="${interval.id}">${escapeHTML(interval.name || "Interval")} (${interval.work_time_seconds || 0}s/${interval.rest_time_seconds || 0}s)</button></li>`
      )
      .join("")}</ul>` : `<p class="muted">No intervals yet.</p>`}
    <form id="new-interval-form" class="editor-form compact">
      <label>Name <input id="new-interval-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" required /></label>
      <label>Work (sec) <input id="new-interval-work" class="input" type="number" min="0" step="1" required /></label>
      <label>Rest (sec) <input id="new-interval-rest" class="input" type="number" min="0" step="1" required /></label>
      <label>Repetitions <input id="new-interval-repetitions" class="input" type="number" min="1" step="1" required /></label>
      <button class="btn" type="submit">Add Interval</button>
    </form>
  `;
}

function renderTimerIntervalEditor(store, timerIntervalId) {
  const interval = timerIntervalId ? store.get("timer_intervals", timerIntervalId) : null;
  if (!interval) {
    return `<p class="muted" style="margin-top: 16px;">Select an interval to edit.</p>`;
  }
  return `
    <h3 style="margin-top: 16px;">Interval Editor</h3>
    <form id="interval-editor" class="editor-form compact">
      <label>Name <input id="interval-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(interval.name || "")}" required /></label>
      <label>Work (sec) <input id="interval-work" class="input" type="number" min="0" step="1" value="${escapeHTML(numberValue(interval.work_time_seconds))}" required /></label>
      <label>Rest (sec) <input id="interval-rest" class="input" type="number" min="0" step="1" value="${escapeHTML(numberValue(interval.rest_time_seconds))}" required /></label>
      <label>Repetitions <input id="interval-repetitions" class="input" type="number" min="1" step="1" value="${escapeHTML(numberValue(interval.repetitions))}" required /></label>
      <label>Order <input id="interval-order" class="input" type="number" min="0" step="1" value="${escapeHTML(numberValue(interval.display_order))}" /></label>
      <div class="actions">
        <button class="btn primary" type="submit">Save Interval</button>
        <button id="interval-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>
      </div>
    </form>
  `;
}

function buildPayloadForSection(section, mode, store, current = null) {
  const idPrefix = mode === "create" ? "meta-new" : "meta-edit";
  const name = sanitizeText(String(document.getElementById(`${idPrefix}-name`)?.value || ""));
  if (!name) {
    return null;
  }

  if (section === "day_types") {
    const allRows = store.active("day_types");
    const key = current?.key || generateHiddenDayTypeKey(name, allRows, current?.id);
    const maxDisplayOrder =
      allRows
        .map((row) => Number(row.display_order ?? row.order ?? 0))
        .filter((value) => Number.isFinite(value))
        .sort((a, b) => a - b)
        .at(-1) ?? 0;
    return {
      name,
      key,
      color_key: current?.color_key || current?.colorKey || "gray",
      is_default: Boolean(current?.is_default),
      is_hidden: Boolean(current?.is_hidden),
      display_order: Number.isFinite(Number(current?.display_order ?? current?.order))
        ? Number(current.display_order ?? current.order)
        : maxDisplayOrder + 10
    };
  }

  if (section === "timer_templates") {
    const description = sanitizeText(String(document.getElementById(`${idPrefix}-description`)?.value || "")) || null;
    const timerMode = timerModeFromForm(`${idPrefix}-mode`);
    const totalMinutes = integerValue(`${idPrefix}-total-minutes`) ?? 0;
    const totalSeconds = integerValue(`${idPrefix}-total-seconds`) ?? 0;
    const totalTime = totalMinutes * 60 + clampInteger(totalSeconds, 0, 59);
    const isRepeating = timerMode === "intervals" ? Boolean(document.getElementById(`${idPrefix}-repeating`)?.checked) : false;
    const repeatCount = isRepeating ? Math.max(1, integerValue(`${idPrefix}-repeat-count`) ?? 1) : null;
    const restBetweenMinutes = integerValue(`${idPrefix}-rest-between-minutes`) ?? 0;
    const restBetweenSeconds = integerValue(`${idPrefix}-rest-between-seconds`) ?? 0;
    const restBetween = restBetweenMinutes * 60 + clampInteger(restBetweenSeconds, 0, 59);

    if (timerMode === "total" && totalTime <= 0) {
      return null;
    }

    return {
      name,
      template_description: description,
      total_time_seconds: timerMode === "total" ? totalTime : null,
      is_repeating: isRepeating,
      repeat_count: isRepeating ? repeatCount : null,
      rest_time_between_intervals: timerMode === "intervals" && restBetween > 0 ? restBetween : null,
      created_date: current?.created_date || new Date().toISOString(),
      last_used_date: current?.last_used_date || null,
      use_count: Number(current?.use_count || 0)
    };
  }

  if (section === "climb_styles") {
    return {
      name,
      is_default: Boolean(current?.is_default),
      is_hidden: Boolean(current?.is_hidden)
    };
  }

  if (section === "climb_gyms") {
    return {
      name,
      is_default: Boolean(current?.is_default)
    };
  }

  return { name };
}

function buildIntervalPayload(mode, templateID, current = null) {
  const idPrefix = mode === "create" ? "new" : "interval";
  const name = sanitizeText(String(document.getElementById(`${idPrefix}-interval-name`)?.value || document.getElementById("interval-name")?.value || ""));
  const work = integerValue(idPrefix === "new" ? "new-interval-work" : "interval-work");
  const rest = integerValue(idPrefix === "new" ? "new-interval-rest" : "interval-rest");
  const repetitions = integerValue(idPrefix === "new" ? "new-interval-repetitions" : "interval-repetitions");
  if (!name || work === null || rest === null || repetitions === null) {
    return null;
  }
  return {
    timer_template_id: templateID,
    name,
    work_time_seconds: work,
    rest_time_seconds: rest,
    repetitions,
    display_order: integerValue("interval-order") ?? Number(current?.display_order || 0)
  };
}

function rowsBySection(section, buckets) {
  switch (section) {
    case "climb_styles":
      return buckets.climbStyles;
    case "climb_gyms":
      return buckets.climbGyms;
    case "timer_templates":
      return buckets.timerTemplates;
    case "day_types":
    default:
      return buckets.dayTypes;
  }
}

function sectionLabel(section) {
  switch (section) {
    case "climb_styles":
      return "Styles";
    case "climb_gyms":
      return "Gyms";
    case "timer_templates":
      return "Timer Templates";
    case "day_types":
    default:
      return "Training Days";
  }
}

function sectionItemLabel(section) {
  switch (section) {
    case "climb_styles":
      return "Style";
    case "climb_gyms":
      return "Gym";
    case "timer_templates":
      return "Timer Template";
    case "day_types":
    default:
      return "Training Day";
  }
}

function hasNameConflict(rows, name, ignoreID = null) {
  const candidate = String(name || "").trim().toLocaleLowerCase();
  return rows.some((row) => {
    if (ignoreID && row.id === ignoreID) {
      return false;
    }
    return String(row.name || "").trim().toLocaleLowerCase() === candidate;
  });
}

function generateHiddenDayTypeKey(name, rows, ignoreID = null) {
  const base =
    name
      .trim()
      .toLocaleLowerCase()
      .replaceAll(/[^a-z0-9]+/g, "-")
      .replaceAll(/^-+|-+$/g, "") || "day-type";
  const keys = new Set(rows.filter((row) => row.id !== ignoreID).map((row) => String(row.key || "").toLocaleLowerCase()));
  if (!keys.has(base)) {
    return base;
  }
  let suffix = 2;
  while (keys.has(`${base}-${suffix}`)) {
    suffix += 1;
  }
  return `${base}-${suffix}`;
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

function timerTemplateMode(template) {
  return template && Number(template.total_time_seconds || 0) > 0 ? "total" : "intervals";
}

function timerModeFromForm(baseId) {
  const checked = document.querySelector(`input[name='${baseId}']:checked`);
  const value = String(checked?.value || "intervals");
  return value === "total" ? "total" : "intervals";
}

function clampInteger(value, min, max) {
  return Math.min(max, Math.max(min, Number(value || 0)));
}

function wireTimerTemplateModeUI() {
  wireModeGroup("meta-new-mode", "meta-new-repeating");
  wireModeGroup("meta-edit-mode", "meta-edit-repeating");
}

function wireModeGroup(modeGroupName, repeatingCheckboxId) {
  const modeInputs = [...document.querySelectorAll(`input[name='${modeGroupName}']`)];
  if (!modeInputs.length) {
    return;
  }
  const applyModeVisibility = () => {
    const mode = timerModeFromForm(modeGroupName);
    document.querySelectorAll(`[data-mode-group='${modeGroupName}']`).forEach((node) => {
      const nodeMode = node.getAttribute("data-mode-value");
      node.classList.toggle("hidden", nodeMode !== mode);
    });
  };
  modeInputs.forEach((input) => {
    input.addEventListener("change", applyModeVisibility);
  });
  applyModeVisibility();

  const repeatingCheckbox = document.getElementById(repeatingCheckboxId);
  if (!repeatingCheckbox) {
    return;
  }
  const applyRepeatVisibility = () => {
    document.querySelectorAll(`[data-repeat-for='${repeatingCheckboxId}']`).forEach((node) => {
      node.classList.toggle("hidden", !repeatingCheckbox.checked);
    });
  };
  repeatingCheckbox.addEventListener("change", applyRepeatVisibility);
  applyRepeatVisibility();
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
