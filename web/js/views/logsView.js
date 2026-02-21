import { showToast } from "../components/toasts.js";
import { renderWorkspaceShell } from "../components/workspaceLayout.js";
import { buildCSV, downloadCSV } from "../utils/csvExport.js";
import { buildLogRows, collectFilterOptions, filterLogRows, sortLogRows } from "../utils/logTransforms.js";

const MODE_LABELS = {
  all: "All Logs",
  sessions: "Sessions",
  climbs: "Climbs"
};

const EXPORT_ALL_COLUMNS = [
  { key: "dateOnly", label: "date" },
  { key: "sourceLabel", label: "type" },
  { key: "exerciseName", label: "exercise_name" },
  { key: "climbType", label: "climb_type" },
  { key: "grade", label: "grade" },
  { key: "feelsLikeGrade", label: "feels_like_grade" },
  { key: "angle", label: "angle" },
  { key: "holdColor", label: "hold_color" },
  { key: "ropeType", label: "rope_type" },
  { key: "style", label: "style" },
  { key: "attempts", label: "attempts" },
  { key: "isWip", label: "wip" },
  { key: "isPreviouslyClimbed", label: "is_previously_climbed" },
  { key: "gym", label: "gym" },
  { key: "reps", label: "reps" },
  { key: "sets", label: "sets" },
  { key: "duration", label: "duration" },
  { key: "weightKg", label: "weight_kg" },
  { key: "planId", label: "plan_id" },
  { key: "planName", label: "plan_name" },
  { key: "dayType", label: "day_type" },
  { key: "notes", label: "notes" }
];

const EXPORT_SESSION_COLUMNS = [
  { key: "dateOnly", label: "date" },
  { key: "exerciseName", label: "exercise_name" },
  { key: "grade", label: "grade" },
  { key: "reps", label: "reps" },
  { key: "sets", label: "sets" },
  { key: "duration", label: "duration" },
  { key: "weightKg", label: "weight_kg" },
  { key: "planName", label: "plan_name" },
  { key: "notes", label: "notes" }
];

const EXPORT_CLIMB_COLUMNS = [
  { key: "dateOnly", label: "date" },
  { key: "climbType", label: "climb_type" },
  { key: "grade", label: "grade" },
  { key: "feelsLikeGrade", label: "feels_like_grade" },
  { key: "style", label: "style" },
  { key: "gym", label: "gym" },
  { key: "attempts", label: "attempts" },
  { key: "isWip", label: "wip" },
  { key: "isPreviouslyClimbed", label: "is_previously_climbed" },
  { key: "notes", label: "notes" }
];

const DISPLAY_ALL_COLUMNS = [
  { key: "dateOnly", label: "Date", sortable: true },
  { key: "sourceLabel", label: "Type", sortable: true },
  { key: "exerciseName", label: "Exercise", sortable: true },
  { key: "climbType", label: "Climb Type", sortable: true },
  { key: "grade", label: "Grade", sortable: true },
  { key: "style", label: "Style", sortable: true },
  { key: "gym", label: "Gym", sortable: true },
  { key: "reps", label: "Reps", sortable: true },
  { key: "sets", label: "Sets", sortable: true },
  { key: "duration", label: "Duration", sortable: true },
  { key: "weightKg", label: "Weight", sortable: true },
  { key: "notes", label: "Notes", sortable: false }
];

const DISPLAY_SESSION_COLUMNS = [
  { key: "dateOnly", label: "Date", sortable: true },
  { key: "exerciseName", label: "Exercise", sortable: true },
  { key: "grade", label: "Grade", sortable: true },
  { key: "reps", label: "Reps", sortable: true },
  { key: "sets", label: "Sets", sortable: true },
  { key: "duration", label: "Duration", sortable: true },
  { key: "weightKg", label: "Weight", sortable: true },
  { key: "planName", label: "Plan", sortable: true },
  { key: "notes", label: "Notes", sortable: false }
];

const DISPLAY_CLIMB_COLUMNS = [
  { key: "dateOnly", label: "Date", sortable: true },
  { key: "climbType", label: "Climb Type", sortable: true },
  { key: "grade", label: "Grade", sortable: true },
  { key: "feelsLikeGrade", label: "Feels Like", sortable: true },
  { key: "style", label: "Style", sortable: true },
  { key: "gym", label: "Gym", sortable: true },
  { key: "attempts", label: "Attempts", sortable: true },
  { key: "isWip", label: "WIP", sortable: true },
  { key: "isPreviouslyClimbed", label: "Previously Climbed", sortable: true },
  { key: "notes", label: "Notes", sortable: false }
];

export function renderLogsView({ store, filters, onFiltersChange }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  const allRows = buildLogRows(store, "all");
  const modeRows = buildLogRows(store, filters.mode);
  const options = collectFilterOptions(allRows);
  const filteredRows = filterLogRows(modeRows, filters);
  const sortedRows = sortLogRows(filteredRows, filters.sortColumn, filters.sortDirection);

  root.innerHTML = renderWorkspaceShell({
    title: "Logs",
    description: "Read-only session and climb history with filters and CSV export.",
    bodyHTML: `
      <section class="pane logs-controls">
        <div class="segmented-control" role="tablist" aria-label="Logs mode">
          ${["all", "sessions", "climbs"]
            .map(
              (mode) =>
                `<button class="btn ${filters.mode === mode ? "primary" : ""}" type="button" data-mode="${mode}">${MODE_LABELS[mode]}</button>`
            )
            .join("")}
        </div>
        <form id="logs-filters-form" class="logs-filter-grid">
          <label>Search
            <input id="logs-search" class="input" type="search" value="${escapeHTML(filters.search || "")}" placeholder="Exercise, grade, gym, notes..." />
          </label>
          <label>From
            <input id="logs-from" class="input" type="date" value="${escapeHTML(filters.fromDate || "")}" />
          </label>
          <label>To
            <input id="logs-to" class="input" type="date" value="${escapeHTML(filters.toDate || "")}" />
          </label>
          <label>Source
            <select id="logs-source" class="input">
              ${renderOptionList(["all", "sessions", "climbs"], filters.source, { all: "All", sessions: "Sessions", climbs: "Climbs" })}
            </select>
          </label>
          <label>Gym
            <select id="logs-gym" class="input">
              <option value="">All gyms</option>
              ${renderOptionList(options.gyms, filters.gym)}
            </select>
          </label>
          <label>Style
            <select id="logs-style" class="input">
              <option value="">All styles</option>
              ${renderOptionList(options.styles, filters.style)}
            </select>
          </label>
          <label>Grade
            <select id="logs-grade" class="input">
              <option value="">All grades</option>
              ${renderOptionList(options.grades, filters.grade)}
            </select>
          </label>
          <label>Climb Type
            <select id="logs-climb-type" class="input">
              <option value="">All types</option>
              ${renderOptionList(options.climbTypes, filters.climbType)}
            </select>
          </label>
          <label class="logs-checkbox">
            <input id="logs-only-wip" type="checkbox" ${filters.onlyWip ? "checked" : ""} /> Only WIP
          </label>
        </form>
        <div class="row">
          <button id="logs-export" class="btn" type="button">Export CSV</button>
          <button id="logs-reset" class="btn" type="button">Reset Filters</button>
          <span class="muted">${sortedRows.length} row${sortedRows.length === 1 ? "" : "s"}</span>
        </div>
      </section>

      <section class="pane">
        ${renderTable(sortedRows, filters)}
      </section>
    `
  });

  bindEvents({ filters, sortedRows, onFiltersChange });
}

function bindEvents({ filters, sortedRows, onFiltersChange }) {
  document.querySelectorAll("button[data-mode]").forEach((button) => {
    button.addEventListener("click", () => {
      onFiltersChange({ mode: button.dataset.mode || "all" });
    });
  });

  document.getElementById("logs-filters-form")?.addEventListener("input", () => {
    onFiltersChange(readFilters(filters));
  });

  document.querySelectorAll("button[data-sort-column]").forEach((button) => {
    button.addEventListener("click", () => {
      const column = button.dataset.sortColumn || "dateOnly";
      const nextDirection =
        filters.sortColumn === column && filters.sortDirection === "asc" ? "desc" : "asc";
      onFiltersChange({ sortColumn: column, sortDirection: nextDirection });
    });
  });

  document.getElementById("logs-export")?.addEventListener("click", () => {
    const columns = exportColumnsForMode(filters.mode);
    const csvText = buildCSV(columns, sortedRows.map((row) => normalizeRowForExport(row)));
    const filename = `klettrack-logs-${filters.mode}-${new Date().toISOString().slice(0, 10)}.csv`;
    downloadCSV({ filename, csvText });
    showToast("CSV exported", "success");
  });

  document.getElementById("logs-reset")?.addEventListener("click", () => {
    onFiltersChange({
      mode: filters.mode,
      source: "all",
      search: "",
      fromDate: "",
      toDate: "",
      gym: "",
      style: "",
      grade: "",
      climbType: "",
      onlyWip: false,
      sortColumn: "dateOnly",
      sortDirection: "desc"
    });
  });
}

function readFilters(filters) {
  return {
    mode: filters.mode,
    source: String(document.getElementById("logs-source")?.value || "all"),
    search: String(document.getElementById("logs-search")?.value || ""),
    fromDate: String(document.getElementById("logs-from")?.value || ""),
    toDate: String(document.getElementById("logs-to")?.value || ""),
    gym: String(document.getElementById("logs-gym")?.value || ""),
    style: String(document.getElementById("logs-style")?.value || ""),
    grade: String(document.getElementById("logs-grade")?.value || ""),
    climbType: String(document.getElementById("logs-climb-type")?.value || ""),
    onlyWip: Boolean(document.getElementById("logs-only-wip")?.checked),
    sortColumn: filters.sortColumn || "dateOnly",
    sortDirection: filters.sortDirection || "desc"
  };
}

function exportColumnsForMode(mode) {
  if (mode === "sessions") {
    return EXPORT_SESSION_COLUMNS;
  }
  if (mode === "climbs") {
    return EXPORT_CLIMB_COLUMNS;
  }
  return EXPORT_ALL_COLUMNS;
}

function displayColumnsForMode(mode) {
  if (mode === "sessions") {
    return DISPLAY_SESSION_COLUMNS;
  }
  if (mode === "climbs") {
    return DISPLAY_CLIMB_COLUMNS;
  }
  return DISPLAY_ALL_COLUMNS;
}

function normalizeRowForExport(row) {
  return {
    ...row,
    isWip: row.isWip ? "true" : "false",
    isPreviouslyClimbed: row.isPreviouslyClimbed ? "true" : "false"
  };
}

function displayCellValue(row, columnKey) {
  if (columnKey === "isWip") {
    return row.isWip ? "Yes" : "No";
  }
  if (columnKey === "isPreviouslyClimbed") {
    return row.isPreviouslyClimbed ? "Yes" : "No";
  }
  return String(row[columnKey] ?? "");
}

function renderTable(rows, filters) {
  const columns = displayColumnsForMode(filters.mode);
  if (rows.length === 0) {
    return `<p class="muted">No rows match your filters.</p>`;
  }

  return `
    <div class="table-wrap">
      <table class="data-table">
        <thead>
          <tr>
            ${columns
              .map((column) => {
                if (!column.sortable) {
                  return `<th>${escapeHTML(column.label)}</th>`;
                }
                const isActive = filters.sortColumn === column.key;
                const directionIcon = isActive
                  ? filters.sortDirection === "asc"
                    ? '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14"/><path d="M7 10l5-5 5 5"/></svg>'
                    : '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14"/><path d="M17 14l-5 5-5-5"/></svg>'
                  : '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 4v16"/><path d="M7 9l5-5 5 5"/><path d="M17 15l-5 5-5-5"/></svg>';
                return `<th><button class="table-sort-btn" type="button" data-sort-column="${column.key}">${escapeHTML(
                  column.label
                )} <span class="sort-indicator" aria-hidden="true">${directionIcon}</span></button></th>`;
              })
              .join("")}
          </tr>
        </thead>
        <tbody>
          ${rows
            .map(
              (row) =>
                `<tr>${columns
                  .map((column) => `<td>${escapeHTML(displayCellValue(row, column.key))}</td>`)
                  .join("")}</tr>`
            )
            .join("")}
        </tbody>
      </table>
    </div>
  `;
}

function renderOptionList(values, selected, labels = {}) {
  return values
    .map(
      (value) =>
        `<option value="${escapeHTML(value)}" ${selected === value ? "selected" : ""}>${escapeHTML(
          labels[value] || value
        )}</option>`
    )
    .join("");
}

function escapeHTML(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
