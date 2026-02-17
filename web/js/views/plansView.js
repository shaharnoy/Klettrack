import { showToast } from "../components/toasts.js";
import { renderWorkspaceShell } from "../components/workspaceLayout.js";
import { buildCSV, downloadCSV } from "../utils/csvExport.js";
import { buildPlanImportMutations, parsePlanCsv } from "../utils/planCsvImport.js";

const MAX_TEXT_LENGTH = 120;
const DELETE_ICON = `<span class="icon-trash" aria-hidden="true"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span>`;
const CHEVRON_UP_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5-5 5 5"/></svg>`;
const CHEVRON_DOWN_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 8l5 5 5-5"/></svg>`;
const PLUS_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 4v12"/><path d="M4 10h12"/></svg>`;
const CHECK_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.5 10.5l3.2 3.2L15.5 6"/></svg>`;
const CHEVRON_LEFT_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.5 4.5L7 10l5.5 5.5"/></svg>`;
const CHEVRON_RIGHT_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7.5 4.5L13 10l-5.5 5.5"/></svg>`;
const PLUS_SMALL_ICON = `<svg viewBox="0 0 20 20" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 4.5v11"/><path d="M4.5 10h11"/></svg>`;
const PENCIL_ICON = `<svg viewBox="0 0 20 20" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.5 3.5l3 3"/><path d="M4 16l3.5-.8 8-8-2.7-2.7-8 8L4 16z"/></svg>`;
const EXPORT_ICON = `<svg viewBox="0 0 20 20" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 12V3"/><path d="M6.5 6.5L10 3l3.5 3.5"/><path d="M4 12.5v3h12v-3"/></svg>`;
const IMPORT_ICON = `<svg viewBox="0 0 20 20" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 3v9"/><path d="M6.5 8.5L10 12l3.5-3.5"/><path d="M4 13.5v3h12v-3"/></svg>`;
const CLONE_ICON = `<svg viewBox="0 0 20 20" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="6" width="9" height="9" rx="2"/><rect x="8" y="3" width="9" height="9" rx="2"/></svg>`;

const DAY_TYPE_COLORS = {
  green: "#22c55e",
  blue: "#2563eb",
  brown: "#8b5a2b",
  orange: "#f97316",
  cyan: "#06b6d4",
  purple: "#8b5cf6",
  yellow: "#eab308",
  red: "#ef4444",
  pink: "#ec4899",
  gray: "#64748b",
  black: "#0f172a",
  white: "#f8fafc",
  mint: "#10b981",
  indigo: "#4f46e5",
  teal: "#0d9488"
};

const WEEKDAYS = [
  { id: 1, short: "Sun", title: "Sunday" },
  { id: 2, short: "Mon", title: "Monday" },
  { id: 3, short: "Tue", title: "Tuesday" },
  { id: 4, short: "Wed", title: "Wednesday" },
  { id: 5, short: "Thu", title: "Thursday" },
  { id: 6, short: "Fri", title: "Friday" },
  { id: 7, short: "Sat", title: "Saturday" }
];
const CALENDAR_WEEK_HEADERS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const PLAN_EXPORT_COLUMNS = [
  { key: "planName", label: "plan_name" },
  { key: "planKind", label: "plan_kind" },
  { key: "planStartDate", label: "plan_start_date" },
  { key: "dayDate", label: "day_date" },
  { key: "weekday", label: "weekday" },
  { key: "dayType", label: "day_type" },
  { key: "dayNotes", label: "day_notes" },
  { key: "exerciseOrder", label: "exercise_order" },
  { key: "exerciseName", label: "exercise_name" },
  { key: "activityName", label: "activity_name" },
  { key: "trainingTypeName", label: "training_type_name" },
  { key: "exerciseId", label: "exercise_id" }
];

let exerciseAvailableScrollTop = 0;
let selectedExerciseScrollTop = 0;
let selectedExercisePinToBottom = false;
let pendingExerciseSearchFocus = null;
let planDayAutosaveTimer = null;
let planDayAutosavePayload = null;
let planDayAutosaveWaiters = [];
let planDayAutosaveInFlight = false;
let planDayAutosaveQueued = false;
const planDayExerciseDrafts = new Map();
const planDayTypeDrafts = new Map();
let pendingPlanImport = null;

export function renderPlansView({
  store,
  selection,
  onSelect,
  onSave,
  onSaveMany,
  onSaveWithOutcome,
  onDelete,
  onOpenPlan,
  onOpenPlans,
  onImportPlanCsvConfirm
}) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  const plans = store.active("plans");
  const activePlanByID = new Map(plans.map((plan) => [plan.id, plan]));
  const dayTypes = store.active("day_types");
  const planKinds = store.active("plan_kinds");
  const activities = store.active("activities");
  const trainingTypes = store.active("training_types");
  const exercises = store.active("exercises");
  const boulderCombinations = store.active("boulder_combinations");
  const boulderCombinationExercises = store.active("boulder_combination_exercises");

  if (selection.planId && !activePlanByID.has(selection.planId)) {
    const fallbackPlan = plans[0] || null;
    onSelect({ planId: fallbackPlan?.id || null, planDayId: null });
    if (fallbackPlan?.id) {
      onOpenPlan(fallbackPlan.id);
    } else if (typeof onOpenPlans === "function") {
      onOpenPlans();
    }
    return;
  }

  if (!selection.planId && plans.length > 0) {
    onSelect({ planId: plans[0].id, planDayId: null });
    return;
  }

  const selectedPlan = store.get("plans", selection.planId);
  const planDays = store
    .active("plan_days")
    .filter((item) => item.plan_id === selection.planId)
    .map((item) => reconcilePlanDayTypeDraft(item))
    .sort((a, b) => String(a.day_date || "").localeCompare(String(b.day_date || "")));
  const selectedDay = reconcilePlanDayExerciseDraft({
    selectedDay: reconcilePlanDayTypeDraft(store.get("plan_days", selection.planDayId)),
    planDayId: selection.planDayId
  });

  const calendarMode = selection.planCalendarMode || "month";
  const calendarAnchor =
    selection.planCalendarAnchor || selectedDay?.day_date || selectedPlan?.start_date || new Date().toISOString();
  const dayTypeByID = Object.fromEntries(dayTypes.map((type) => [type.id, type]));
  const calendarPeriodState = getCalendarPeriodState(planDays, calendarMode, calendarAnchor);

  root.innerHTML = renderWorkspaceShell({
    title: "Training Plans",
    description: "Plan by calendar, then refine each training day with fast catalog selection.",
    bodyHTML: `
      <div class="plans-workspace ${selection.planCloneBusy || selection.planImportBusy ? "is-busy" : ""}">
      <section class="pane plans-topbar">
        <div class="plans-topbar-row">
          <div class="plans-topbar-main">
            <label class="plans-topbar-label">Selected Plan
              <select id="plan-selector" class="input plans-topbar-select">
                <option value="">Choose a plan</option>
                ${plans
                  .map(
                    (plan) =>
                      `<option value="${plan.id}" ${plan.id === selection.planId ? "selected" : ""}>${escapeHTML(plan.name || "Plan")}</option>`
                  )
                  .join("")}
              </select>
            </label>
            <div class="plans-topbar-actions">
              <button id="plan-setup-create" class="btn btn-compact" type="button">${PLUS_SMALL_ICON}<span>Create Plan</span></button>
              <button id="plan-setup-edit" class="btn btn-compact" type="button" ${selectedPlan ? "" : "disabled"}>${PENCIL_ICON}<span>Edit Plan</span></button>
              <button id="plan-clone-open" class="btn btn-compact" type="button" ${selectedPlan ? "" : "disabled"}>${CLONE_ICON}<span>Clone Plan</span></button>
              <button id="plan-export-csv" class="btn btn-compact" type="button" ${selectedPlan ? "" : "disabled"}>${EXPORT_ICON}<span>Export Plan</span></button>
              <button id="plan-import-csv" class="btn btn-compact" type="button">${IMPORT_ICON}<span>Import Plan</span></button>
              <button id="plan-delete-top" class="btn btn-compact destructive" type="button" ${selectedPlan ? "" : "disabled"}>${DELETE_ICON}<span>Delete Plan</span></button>
              <input id="plan-import-file" type="file" accept=".csv,text/csv" hidden />
            </div>
          </div>
          ${renderPlanSetupPanel({ selectedPlan, selection, planKinds })}
          ${renderClonePlanPanel(selectedPlan, selection)}
          ${renderPlanImportPanel(selection, store)}
        </div>
      </section>

      <div class="workspace-grid plans-overview-grid workspace-stage-grid">
        <section class="pane workspace-pane-detail">
          <div class="calendar-controls-row">
            <div class="calendar-mode-toggle" role="tablist" aria-label="Calendar mode">
            ${renderCalendarModeButton("week", calendarMode)}
            ${renderCalendarModeButton("month", calendarMode)}
            </div>
          </div>
          ${renderCalendarFocus(planDays, selectedDay, calendarMode, calendarAnchor, dayTypeByID, dayTypes, calendarPeriodState, selection)}
          ${renderAddDayPanel(selection)}
          ${renderDayTypeLegend(dayTypes)}
        </section>
      </div>

      <section class="pane plans-day-editor-row">
        ${renderDayEditorArea({
          plan: selectedPlan,
          day: selectedDay,
          dayTypes,
          activities,
          trainingTypes,
          exercises,
          boulderCombinations,
          boulderCombinationExercises,
          selection,
          planDays
        })}
      </section>
      ${
        selection.planCloneBusy
          ? `<div class="plans-busy-overlay" role="status" aria-live="polite">Cloning plan...</div>`
          : selection.planImportBusy
            ? `<div class="plans-busy-overlay" role="status" aria-live="polite">Importing plan...</div>`
            : ""
      }
      </div>
    `
  });

  restoreExerciseListScroll();
  restoreSelectedExerciseListScroll();
  restoreExerciseSearchFocus();
  bindEvents({
    store,
    selection,
    onSelect,
    onSave,
    onSaveMany,
    onSaveWithOutcome,
    onDelete,
    onOpenPlan,
    onOpenPlans,
    onImportPlanCsvConfirm,
    planDays,
    selectedPlan,
    planKinds,
    dayTypes,
    activities,
    trainingTypes,
    exercises,
    boulderCombinations,
    boulderCombinationExercises
  });
}

function bindEvents({
  store,
  selection,
  onSelect,
  onSave,
  onSaveMany,
  onSaveWithOutcome,
  onDelete,
  onOpenPlan,
  onOpenPlans,
  onImportPlanCsvConfirm,
  planDays,
  selectedPlan,
  planKinds,
  dayTypes,
  activities,
  trainingTypes,
  exercises
}) {
  document.getElementById("plan-selector")?.addEventListener("change", async (event) => {
    await flushPlanDayAutosave();
    const nextPlanID = String(event.target?.value || "");
    if (!nextPlanID) {
      onSelect({ planId: null, planDayId: null });
      return;
    }
    onOpenPlan(nextPlanID);
  });

  document.querySelectorAll("button[data-calendar-mode]").forEach((button) => {
    button.addEventListener("click", async () => {
      await flushPlanDayAutosave();
      onSelect({ planCalendarMode: button.dataset.calendarMode || "month" });
    });
  });

  document.querySelectorAll("button[data-calendar-date]").forEach((button) => {
    button.addEventListener("click", async () => {
      await flushPlanDayAutosave();
      const date = String(button.dataset.calendarDate || "");
      if (!date) {
        return;
      }
      const existingDay = planDays.find((day) => String(day.day_date || "").slice(0, 10) === date);
      if (existingDay) {
        onSelect({ planDayId: existingDay.id, planCalendarAnchor: existingDay.day_date, planAddDayOpen: false });
        return;
      }
      onSelect({ planCalendarAnchor: `${date}T00:00:00.000Z`, planAddDayOpen: true, planAddDayDate: date });
      showToast("No day for this date yet. Use Add Day.", "info");
    });
  });

  document.getElementById("calendar-today")?.addEventListener("click", async () => {
    await flushPlanDayAutosave();
    const state = getCalendarPeriodState(planDays, selection.planCalendarMode || "month", new Date().toISOString());
    if (!state.activePeriod) {
      return;
    }
    onSelect({
      planCalendarAnchor: state.activePeriod.toISOString()
    });
  });

  document.getElementById("calendar-prev")?.addEventListener("click", async () => {
    await flushPlanDayAutosave();
    const state = getCalendarPeriodState(planDays, selection.planCalendarMode || "month", selection.planCalendarAnchor);
    if (!state.prevPeriod) {
      return;
    }
    onSelect({
      planCalendarAnchor: state.prevPeriod.toISOString()
    });
  });

  document.getElementById("calendar-next")?.addEventListener("click", async () => {
    await flushPlanDayAutosave();
    const state = getCalendarPeriodState(planDays, selection.planCalendarMode || "month", selection.planCalendarAnchor);
    if (!state.nextPeriod) {
      return;
    }
    onSelect({
      planCalendarAnchor: state.nextPeriod.toISOString()
    });
  });

  document.getElementById("plan-setup-create")?.addEventListener("click", async () => {
    await flushPlanDayAutosave();
    onSelect({ planSetupOpen: true, planSetupMode: "create" });
  });

  document.getElementById("plan-setup-edit")?.addEventListener("click", async () => {
    if (!selectedPlan) {
      return;
    }
    await flushPlanDayAutosave();
    onSelect({ planSetupOpen: true, planSetupMode: "edit" });
  });

  document.getElementById("plan-setup-cancel")?.addEventListener("click", () => {
    onSelect({ planSetupOpen: false });
  });

  document.getElementById("plan-setup-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const mode = selection.planSetupMode === "edit" ? "edit" : "create";
    const name = sanitizedValue("plan-setup-name");
    const startDate = document.getElementById("plan-setup-start")?.value;
    if (!name || !startDate) {
      return;
    }
    if (mode === "edit" && !selectedPlan) {
      return;
    }
    const id = mode === "edit" ? selectedPlan.id : crypto.randomUUID();
    const existingPlan = mode === "edit" ? store.get("plans", id) : null;
    await onSave({
      entity: "plans",
      id,
      payload: {
        name,
        kind_id: optionalValue("plan-setup-kind"),
        start_date: `${startDate}T00:00:00.000Z`,
        recurring_chosen_exercises_by_weekday: deepCopyObject(existingPlan?.recurring_chosen_exercises_by_weekday || {}),
        recurring_exercise_order_by_weekday: deepCopyObject(existingPlan?.recurring_exercise_order_by_weekday || {}),
        recurring_day_type_id_by_weekday: deepCopyObject(existingPlan?.recurring_day_type_id_by_weekday || {})
      }
    });
    onSelect({ planSetupOpen: false });
    onOpenPlan(id);
    showToast(mode === "edit" ? "Plan updated" : "Plan saved", "success");
  });

  document.getElementById("plan-setup-delete")?.addEventListener("click", async () => {
    if (!selectedPlan?.id) {
      return;
    }
    if (!confirmDelete("plan", selectedPlan.name || "this plan")) {
      return;
    }
    await onDelete({ entity: "plans", id: selectedPlan.id });
    const nextPlan = store
      .active("plans")
      .filter((plan) => plan.id !== selectedPlan.id)
      .sort((left, right) => String(left.name || "").localeCompare(String(right.name || ""), undefined, { sensitivity: "base" }))[0];
    onSelect({ planId: nextPlan?.id || null, planDayId: null, planSetupOpen: false });
    if (nextPlan?.id) {
      onOpenPlan(nextPlan.id);
    } else if (typeof onOpenPlans === "function") {
      onOpenPlans();
    }
    showToast("Plan deleted", "info");
  });

  document.getElementById("plan-delete-top")?.addEventListener("click", async () => {
    if (!selectedPlan?.id) {
      return;
    }
    if (!confirmDelete("plan", selectedPlan.name || "this plan")) {
      return;
    }
    await onDelete({ entity: "plans", id: selectedPlan.id });
    const nextPlan = store
      .active("plans")
      .filter((plan) => plan.id !== selectedPlan.id)
      .sort((left, right) => String(left.name || "").localeCompare(String(right.name || ""), undefined, { sensitivity: "base" }))[0];
    onSelect({ planId: nextPlan?.id || null, planDayId: null, planSetupOpen: false });
    if (nextPlan?.id) {
      onOpenPlan(nextPlan.id);
    } else if (typeof onOpenPlans === "function") {
      onOpenPlans();
    }
    showToast("Plan deleted", "info");
  });

  document.getElementById("plan-add-day-open")?.addEventListener("click", async () => {
    if (!selection.planId) {
      return;
    }
    await flushPlanDayAutosave();
    const defaultDate = formatDateKey(selection.planCalendarAnchor || new Date());
    onSelect({ planAddDayOpen: true, planAddDayDate: selection.planAddDayDate || defaultDate });
  });

  document.getElementById("plan-add-day-cancel")?.addEventListener("click", () => {
    onSelect({ planAddDayOpen: false });
  });

  document.getElementById("new-plan-day-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!selection.planId) {
      return;
    }
    const dayDate = document.getElementById("new-plan-day-date")?.value;
    if (!dayDate) {
      return;
    }
    const id = crypto.randomUUID();
    await onSave({
      entity: "plan_days",
      id,
      payload: {
        plan_id: selection.planId,
        day_date: `${dayDate}T00:00:00.000Z`,
        day_type_id: null,
        chosen_exercise_ids: [],
        exercise_order_by_id: {},
        daily_notes: null
      }
    });
    onSelect({ planDayId: id, planCalendarAnchor: `${dayDate}T00:00:00.000Z`, planAddDayOpen: false, planAddDayDate: "" });
    showToast("Day added", "success");
  });

  document.getElementById("plan-add-weeks")?.addEventListener("click", async () => {
    if (!selection.planId) {
      return;
    }
    await flushPlanDayAutosave();
    const raw = window.prompt("How many weeks do you want to add?", "1");
    if (raw === null) {
      return;
    }
    const weeks = Number.parseInt(String(raw).trim(), 10);
    if (!Number.isFinite(weeks) || weeks <= 0) {
      showToast("Enter a valid number of weeks", "error");
      return;
    }
    await appendWeeksToPlan({
      selectedPlan,
      planDays,
      weeks,
      onSave,
      onSaveMany
    });
    showToast(`Added ${weeks} week${weeks === 1 ? "" : "s"}`, "success");
  });

  document.getElementById("plan-day-notes")?.addEventListener("input", () => {
    if (!selection.planDayId || !selection.planId) {
      return;
    }
    const orderedIDs = getSelectedExerciseOrder();
    syncPlanDayExerciseDraft(selection.planDayId, orderedIDs);
    schedulePlanDayAutosave({ store, selection, onSave, orderedIDs });
  });

  document.querySelectorAll("select[data-calendar-day-id]").forEach((input) => {
    input.addEventListener("change", async () => {
      const dayId = String(input.dataset.calendarDayId || "");
      if (!dayId || !selection.planId) {
        return;
      }
      const day = store.get("plan_days", dayId);
      if (!day) {
        return;
      }
      const nextDayTypeId = String(input.value || "").trim() || null;
      planDayTypeDrafts.set(dayId, nextDayTypeId);
      updateCalendarDayDotColor(input, nextDayTypeId, dayTypes);
      setCalendarDayTypeMessage(dayId, "");
      setCalendarDayTypeSaveState(dayId, "saving");
      await flushPlanDayAutosave();
      const outcome =
        typeof onSaveWithOutcome === "function"
          ? await onSaveWithOutcome({
              entity: "plan_days",
              id: dayId,
              payload: {
                day_date: day.day_date || `${String(input.dataset.calendarDayDate || formatDateKey(new Date()))}T00:00:00.000Z`,
                day_type_id: nextDayTypeId
              }
            })
          : (await onSave({
              entity: "plan_days",
              id: dayId,
              payload: {
                day_date: day.day_date || `${String(input.dataset.calendarDayDate || formatDateKey(new Date()))}T00:00:00.000Z`,
                day_type_id: nextDayTypeId
              }
            }),
            { ok: true });
      if (!outcome?.ok) {
        setCalendarDayTypeSaveState(dayId, "idle");
        const reason = String(outcome.reason || outcome.message || "unknown_error");
        setCalendarDayTypeMessage(dayId, `Save failed: ${reason}`, "error");
        showToast(`Day type save failed: ${reason}`, "error");
        return;
      }
      const latestDay = reconcilePlanDayTypeDraft(store.get("plan_days", dayId));
      const persistedDayType = latestDay?.day_type_id ?? null;
      if (persistedDayType === nextDayTypeId) {
        planDayTypeDrafts.delete(dayId);
        setCalendarDayTypeSaveState(dayId, "saved");
        setCalendarDayTypeMessage(dayId, "Saved", "success");
        showToast("Day type saved", "success");
        setTimeout(() => setCalendarDayTypeMessage(dayId, ""), 900);
        return;
      }
      setCalendarDayTypeSaveState(dayId, "idle");
      setCalendarDayTypeMessage(dayId, "Save failed: value not persisted", "error");
      showToast("Day type save failed: value not persisted", "error");
    });
  });

  document.getElementById("plan-export-csv")?.addEventListener("click", () => {
    if (!selectedPlan) {
      return;
    }
    exportPlanCSV({ selectedPlan, planDays, planKinds, dayTypes, exercises, trainingTypes, activities });
    showToast("Training plan CSV exported", "success");
  });

  document.getElementById("plan-import-csv")?.addEventListener("click", () => {
    const fileInput = document.getElementById("plan-import-file");
    if (!(fileInput instanceof HTMLInputElement)) {
      return;
    }
    fileInput.value = "";
    fileInput.click();
  });

  document.getElementById("plan-import-file")?.addEventListener("change", async (event) => {
    const fileInput = event.currentTarget;
    if (!(fileInput instanceof HTMLInputElement) || !fileInput.files?.length) {
      return;
    }
    const file = fileInput.files[0];
    try {
      const text = await file.text();
      const parsed = parsePlanCsv(text);
      if (parsed.errors.length > 0) {
        pendingPlanImport = null;
        showToast(parsed.errors[0], "error");
        return;
      }
      if (!parsed.planGroups.length) {
        pendingPlanImport = null;
        showToast("No importable plan rows found in CSV", "error");
        return;
      }
      pendingPlanImport = {
        filename: file.name,
        parsed,
        selectedGroupKey: parsed.planGroups[0].key,
        draftsByGroupKey: Object.fromEntries(
          parsed.planGroups.map((group) => [group.key, createPlanImportDraft(group)])
        )
      };
      onSelect({ planImportOpen: true });
      if (parsed.warnings.length > 0) {
        showToast(`CSV parsed with ${parsed.warnings.length} warning(s)`, "info");
      }
    } catch (error) {
      pendingPlanImport = null;
      const message = error instanceof Error ? error.message : "Failed to read CSV file";
      showToast(message, "error");
    }
  });

  document.getElementById("plan-import-cancel")?.addEventListener("click", () => {
    pendingPlanImport = null;
    onSelect({ planImportOpen: false, planImportBusy: false });
  });

  document.getElementById("plan-import-group")?.addEventListener("change", (event) => {
    if (!pendingPlanImport) {
      return;
    }
    const currentGroup = pendingPlanImport.parsed.planGroups.find((group) => group.key === pendingPlanImport.selectedGroupKey);
    if (currentGroup) {
      pendingPlanImport.draftsByGroupKey[currentGroup.key] = readPlanImportDraftFromForm(currentGroup);
    }
    pendingPlanImport.selectedGroupKey = String(event.target?.value || "");
    onSelect({ planImportOpen: true });
  });

  document.getElementById("plan-import-name")?.addEventListener("input", () => {
    const selectedGroup = pendingPlanImport?.parsed?.planGroups?.find((group) => group.key === pendingPlanImport?.selectedGroupKey);
    if (!selectedGroup) {
      return;
    }
    pendingPlanImport.draftsByGroupKey[selectedGroup.key] = readPlanImportDraftFromForm(selectedGroup);
  });

  document.getElementById("plan-import-start")?.addEventListener("change", () => {
    const selectedGroup = pendingPlanImport?.parsed?.planGroups?.find((group) => group.key === pendingPlanImport?.selectedGroupKey);
    if (!selectedGroup) {
      return;
    }
    pendingPlanImport.draftsByGroupKey[selectedGroup.key] = readPlanImportDraftFromForm(selectedGroup);
  });

  document.getElementById("plan-import-kind")?.addEventListener("change", () => {
    const selectedGroup = pendingPlanImport?.parsed?.planGroups?.find((group) => group.key === pendingPlanImport?.selectedGroupKey);
    if (!selectedGroup) {
      return;
    }
    pendingPlanImport.draftsByGroupKey[selectedGroup.key] = readPlanImportDraftFromForm(selectedGroup);
  });

  document.getElementById("plan-import-confirm")?.addEventListener("click", async () => {
    if (!pendingPlanImport) {
      return;
    }
    const selectedGroup = pendingPlanImport.parsed.planGroups.find((group) => group.key === pendingPlanImport.selectedGroupKey);
    if (!selectedGroup) {
      showToast("No plan group selected for import", "error");
      return;
    }
    const draft = readPlanImportDraftFromForm(selectedGroup);
    pendingPlanImport.draftsByGroupKey[selectedGroup.key] = draft;

    await flushPlanDayAutosave();
    onSelect({ planImportBusy: true });
    try {
      const payload = buildPlanImportMutations({ group: selectedGroup, store, overrides: draft });
      if (typeof onImportPlanCsvConfirm === "function") {
        const outcome = await onImportPlanCsvConfirm(payload);
        if (!outcome?.ok) {
          const reason = String(outcome?.message || outcome?.reason || "Import failed");
          showToast(reason, "error");
          return;
        }
      } else if (typeof onSaveMany === "function") {
        await onSaveMany({ mutations: payload.mutations });
      } else {
        for (const mutation of payload.mutations) {
          await onSave(mutation);
        }
      }

      pendingPlanImport = null;
      onSelect({ planImportOpen: false, planImportBusy: false });
      onOpenPlan(payload.planId);
      showToast(
        `Imported ${payload.summary.dayCount} day(s), ${payload.summary.exerciseCount} exercise row(s)${
          totalPlaceholders(payload.summary.placeholders) > 0
            ? `, ${totalPlaceholders(payload.summary.placeholders)} placeholder(s)`
            : ""
        }`,
        "success"
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : "Import failed";
      showToast(message, "error");
    } finally {
      onSelect({ planImportBusy: false });
    }
  });

  document.getElementById("plan-clone-open")?.addEventListener("click", () => {
    if (!selectedPlan) {
      return;
    }
    const fallbackStart = dateInputValue(selectedPlan.start_date) || dateInputValue(new Date().toISOString());
    onSelect({
      planCloneOpen: !selection.planCloneOpen,
      planCloneName: selection.planCloneName || `${selectedPlan.name || "Plan"} copy`,
      planCloneStartDate: selection.planCloneStartDate || fallbackStart
    });
  });

  document.getElementById("plan-clone-cancel")?.addEventListener("click", () => {
    onSelect({ planCloneOpen: false });
  });

  document.getElementById("plan-clone-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!(form instanceof HTMLFormElement)) {
      return;
    }
    if (form.dataset.submitting === "true") {
      return;
    }
    if (!selectedPlan) {
      return;
    }
    const newName = sanitizedValue("plan-clone-name") || `${selectedPlan.name || "Plan"} copy`;
    const newStartDate = String(document.getElementById("plan-clone-start")?.value || "");
    if (!newStartDate) {
      showToast("Choose a start date", "error");
      return;
    }
    form.dataset.submitting = "true";
    setFormSubmittingState(form, true, "Cloning...");
    onSelect({ planCloneBusy: true });
    try {
      await clonePlanToNewDates({
        selectedPlan,
        planDays,
        newName,
        newStartDate,
        onSave,
        onSaveMany,
        onOpenPlan,
        onSelect
      });
    } finally {
      form.dataset.submitting = "false";
      setFormSubmittingState(form, false);
      onSelect({ planCloneBusy: false });
    }
  });

  document.getElementById("day-clone-toggle")?.addEventListener("click", async () => {
    if (!selection.planDayId) {
      return;
    }
    await flushPlanDayAutosave();
    const sourceDay = store.get("plan_days", selection.planDayId);
    if (!sourceDay) {
      return;
    }
    const weekday = weekdayIdFromDate(sourceDay.day_date);
    onSelect({
      planDayCloneOpen: !selection.planDayCloneOpen,
      planDayCloneMode: selection.planDayCloneMode || "clone",
      planDayCloneTargetDate: selection.planDayCloneTargetDate || dateInputValue(sourceDay.day_date),
      planDayCloneApplyRecurring: typeof selection.planDayCloneApplyRecurring === "boolean" ? selection.planDayCloneApplyRecurring : true,
      planDayRecurringWeekdays:
        Array.isArray(selection.planDayRecurringWeekdays) && selection.planDayRecurringWeekdays.length > 0
          ? selection.planDayRecurringWeekdays
          : [weekday]
    });
  });

  document.getElementById("day-clone-cancel")?.addEventListener("click", () => {
    onSelect({ planDayCloneOpen: false });
  });

  document.querySelectorAll("button[data-day-clone-mode]").forEach((button) => {
    button.addEventListener("click", () => {
      onSelect({ planDayCloneMode: button.dataset.dayCloneMode || "clone" });
    });
  });

  document.querySelectorAll("input[name='day-recurring-weekday']").forEach((input) => {
    input.addEventListener("change", () => {
      const selectedWeekdays = [...document.querySelectorAll("input[name='day-recurring-weekday']:checked")]
        .map((node) => Number(node.value || "0"))
        .filter((value) => Number.isFinite(value) && value >= 1 && value <= 7);
      onSelect({ planDayRecurringWeekdays: selectedWeekdays });
    });
  });

  document.getElementById("day-recurring-apply")?.addEventListener("change", (event) => {
    onSelect({ planDayCloneApplyRecurring: Boolean(event.target?.checked) });
  });

  document.getElementById("day-clone-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!(form instanceof HTMLFormElement)) {
      return;
    }
    if (form.dataset.submitting === "true") {
      return;
    }
    form.dataset.submitting = "true";
    setFormSubmittingState(form, true, "Saving...");
    await flushPlanDayAutosave();
    if (!selection.planDayId || !selection.planId) {
      form.dataset.submitting = "false";
      setFormSubmittingState(form, false);
      return;
    }

    try {
      const sourceDay = store.get("plan_days", selection.planDayId);
      if (!sourceDay) {
        showToast("Source day not found", "error");
        return;
      }
      const sourceDraft = readCurrentDayDraft({ store, selection });

      if ((selection.planDayCloneMode || "clone") === "clone") {
        const targetDateRaw = String(document.getElementById("day-clone-target-date")?.value || "");
        if (!targetDateRaw) {
          showToast("Choose a target date", "error");
          return;
        }
        const targetDay = planDays.find((day) => formatDateKey(day.day_date) === targetDateRaw);
        if (!targetDay) {
          showToast("Target date is not in this plan", "error");
          return;
        }
        await onSave({
          entity: "plan_days",
          id: targetDay.id,
          payload: {
            plan_id: targetDay.plan_id,
            day_date: targetDay.day_date,
            day_type_id: sourceDraft.day_type_id,
            chosen_exercise_ids: [...sourceDraft.chosen_exercise_ids],
            exercise_order_by_id: deepCopyObject(sourceDraft.exercise_order_by_id),
            daily_notes: sourceDraft.daily_notes
          }
        });
        onSelect({ planDayCloneOpen: false, planDayCloneMode: "clone" });
        showToast(`Cloned setup to ${targetDateRaw}`, "success");
        return;
      }

      const weekdays =
        Array.isArray(selection.planDayRecurringWeekdays) && selection.planDayRecurringWeekdays.length > 0
          ? selection.planDayRecurringWeekdays
          : [weekdayIdFromDate(sourceDay.day_date)];

      if (!selectedPlan) {
        showToast("Plan not found", "error");
        return;
      }

      const recurringChosen = deepCopyObject(selectedPlan.recurring_chosen_exercises_by_weekday || {});
      const recurringOrder = deepCopyObject(selectedPlan.recurring_exercise_order_by_weekday || {});
      const recurringDayType = deepCopyObject(selectedPlan.recurring_day_type_id_by_weekday || {});

      for (const weekday of weekdays) {
        recurringChosen[String(weekday)] = [...sourceDraft.chosen_exercise_ids];
        recurringOrder[String(weekday)] = deepCopyObject(sourceDraft.exercise_order_by_id);
        if (sourceDraft.day_type_id) {
          recurringDayType[String(weekday)] = sourceDraft.day_type_id;
        } else {
          delete recurringDayType[String(weekday)];
        }
      }

      const mutations = [
        {
          entity: "plans",
          id: selectedPlan.id,
          payload: {
            name: selectedPlan.name || "Plan",
            kind_id: selectedPlan.kind_id || null,
            start_date: selectedPlan.start_date,
            recurring_chosen_exercises_by_weekday: recurringChosen,
            recurring_exercise_order_by_weekday: recurringOrder,
            recurring_day_type_id_by_weekday: recurringDayType
          }
        }
      ];

      if (selection.planDayCloneApplyRecurring !== false) {
        const todayStart = startOfDay(new Date());
        for (const day of planDays) {
          const dayDate = safeDate(day.day_date);
          if (startOfDay(dayDate) < todayStart) {
            continue;
          }
          if (!weekdays.includes(weekdayIdFromDate(day.day_date))) {
            continue;
          }
          mutations.push({
            entity: "plan_days",
            id: day.id,
            payload: {
              plan_id: day.plan_id,
              day_date: day.day_date,
              day_type_id: sourceDraft.day_type_id,
              chosen_exercise_ids: [...sourceDraft.chosen_exercise_ids],
              exercise_order_by_id: deepCopyObject(sourceDraft.exercise_order_by_id),
              daily_notes: sourceDraft.daily_notes
            }
          });
        }
      }

      if (typeof onSaveMany === "function" && mutations.length > 1) {
        await onSaveMany({ mutations });
      } else {
        for (const mutation of mutations) {
          await onSave(mutation);
        }
      }

      onSelect({ planDayCloneOpen: false, planDayCloneMode: "clone" });
      showToast("Recurring setup saved", "success");
    } finally {
      form.dataset.submitting = "false";
      setFormSubmittingState(form, false);
    }
  });

  document.getElementById("exercise-search")?.addEventListener("input", (event) => {
    const input = event.target;
    if (input instanceof HTMLInputElement) {
      pendingExerciseSearchFocus = {
        value: String(input.value || ""),
        start: Number.isFinite(input.selectionStart) ? Number(input.selectionStart) : null,
        end: Number.isFinite(input.selectionEnd) ? Number(input.selectionEnd) : null
      };
    }
    onSelect({ planExerciseSearch: String(event.target?.value || "") });
  });

  document.getElementById("exercise-activity-filter")?.addEventListener("change", (event) => {
    onSelect({
      planExerciseActivityId: String(event.target?.value || "") || null,
      planExerciseTrainingTypeId: null
    });
  });

  document.getElementById("exercise-training-type-filter")?.addEventListener("change", (event) => {
    onSelect({
      planExerciseTrainingTypeId: String(event.target?.value || "") || null
    });
  });

  document.getElementById("exercise-available-list")?.addEventListener("click", (event) => {
    if (!selection.planDayId || !selection.planId) {
      return;
    }
    const button = event.target.closest("button[data-add-exercise]");
    if (!button) {
      return;
    }
    void (async () => {
      captureExerciseListScroll();
      const added = toggleExerciseSelection(button.dataset.addExercise, button.dataset.label || "");
      const orderedIDs = getSelectedExerciseOrder();
      syncPlanDayExerciseDraft(selection.planDayId, orderedIDs);
      if (added) {
        scrollSelectedExerciseListToBottom();
      } else {
        captureSelectedExerciseListScroll();
      }
      schedulePlanDayAutosave({ store, selection, onSave, orderedIDs });
    })();
  });

  document.getElementById("exercise-available-list")?.addEventListener("scroll", () => {
    captureExerciseListScroll();
  });

  document.getElementById("selected-exercise-order")?.addEventListener("scroll", () => {
    selectedExercisePinToBottom = false;
    captureSelectedExerciseListScroll();
  });

  document.getElementById("selected-exercise-order")?.addEventListener("click", (event) => {
    if (!selection.planDayId || !selection.planId) {
      return;
    }
    const removeButton = event.target.closest("button[data-remove-exercise]");
    if (removeButton) {
      void (async () => {
        captureExerciseListScroll();
        captureSelectedExerciseListScroll();
        removeExerciseFromSelection(removeButton.dataset.removeExercise);
        const orderedIDs = getSelectedExerciseOrder();
        syncPlanDayExerciseDraft(selection.planDayId, orderedIDs);
        captureSelectedExerciseListScroll();
        schedulePlanDayAutosave({ store, selection, onSave, orderedIDs });
      })();
      return;
    }

    const moveButton = event.target.closest("button[data-move-exercise]");
    if (!moveButton) {
      return;
    }
    void (async () => {
      captureExerciseListScroll();
      captureSelectedExerciseListScroll();
      moveExercise(moveButton.dataset.moveExercise, moveButton.dataset.direction);
      const orderedIDs = getSelectedExerciseOrder();
      syncPlanDayExerciseDraft(selection.planDayId, orderedIDs);
      captureSelectedExerciseListScroll();
      schedulePlanDayAutosave({ store, selection, onSave, orderedIDs });
    })();
  });
}

async function clonePlanToNewDates({ selectedPlan, planDays, newName, newStartDate, onSave, onSaveMany, onOpenPlan, onSelect }) {
  const newPlanId = crypto.randomUUID();
  const sourceStartDate = safeDate(selectedPlan.start_date || planDays[0]?.day_date || new Date().toISOString());
  const sourceStart = startOfDay(sourceStartDate);
  const targetStart = startOfDay(new Date(`${newStartDate}T00:00:00.000Z`));

  const mutations = [
    {
      entity: "plans",
      id: newPlanId,
      payload: {
        name: newName,
        kind_id: selectedPlan.kind_id || null,
        start_date: toISODateStart(targetStart),
        recurring_chosen_exercises_by_weekday: deepCopyObject(selectedPlan.recurring_chosen_exercises_by_weekday || {}),
        recurring_exercise_order_by_weekday: deepCopyObject(selectedPlan.recurring_exercise_order_by_weekday || {}),
        recurring_day_type_id_by_weekday: deepCopyObject(selectedPlan.recurring_day_type_id_by_weekday || {})
      }
    }
  ];

  for (const sourceDay of planDays) {
    const sourceDate = startOfDay(safeDate(sourceDay.day_date));
    const offsetDays = dayDiff(sourceStart, sourceDate);
    const targetDate = addDays(targetStart, offsetDays);

    mutations.push({
      entity: "plan_days",
      id: crypto.randomUUID(),
      payload: {
        plan_id: newPlanId,
        day_date: toISODateStart(targetDate),
        day_type_id: sourceDay.day_type_id || null,
        chosen_exercise_ids: [...(sourceDay.chosen_exercise_ids || [])],
        exercise_order_by_id: deepCopyObject(sourceDay.exercise_order_by_id || {}),
        daily_notes: sourceDay.daily_notes ?? null
      }
    });
  }
  if (typeof onSaveMany === "function") {
    await onSaveMany({ mutations });
  } else {
    for (const mutation of mutations) {
      await onSave(mutation);
    }
  }

  onSelect({ planCloneOpen: false, planCloneName: "", planCloneStartDate: "" });
  onOpenPlan(newPlanId);
  showToast("Plan cloned", "success");
}

async function appendWeeksToPlan({ selectedPlan, planDays, weeks, onSave, onSaveMany }) {
  if (!selectedPlan || weeks <= 0) {
    return;
  }

  const sortedDays = planDays
    .slice()
    .sort((left, right) => String(left.day_date || "").localeCompare(String(right.day_date || "")));
  const fallbackStart = selectedPlan.start_date || new Date().toISOString();
  const lastDate = sortedDays.length > 0 ? safeDate(sortedDays[sortedDays.length - 1].day_date) : safeDate(fallbackStart);
  const startNext = addDays(startOfDay(lastDate), 1);
  const recurringChosen = selectedPlan.recurring_chosen_exercises_by_weekday || {};
  const recurringOrder = selectedPlan.recurring_exercise_order_by_weekday || {};
  const recurringDayType = selectedPlan.recurring_day_type_id_by_weekday || {};
  const totalDays = weeks * 7;

  const mutations = [];
  for (let index = 0; index < totalDays; index += 1) {
    const nextDate = addDays(startNext, index);
    const weekday = weekdayIdFromDate(nextDate);
    const weekdayKey = String(weekday);
    mutations.push({
      entity: "plan_days",
      id: crypto.randomUUID(),
      payload: {
        plan_id: selectedPlan.id,
        day_date: toISODateStart(nextDate),
        day_type_id: recurringDayType[weekdayKey] || null,
        chosen_exercise_ids: Array.isArray(recurringChosen[weekdayKey]) ? [...recurringChosen[weekdayKey]] : [],
        exercise_order_by_id: recurringOrder[weekdayKey] ? deepCopyObject(recurringOrder[weekdayKey]) : {},
        daily_notes: null
      }
    });
  }
  if (typeof onSaveMany === "function") {
    await onSaveMany({ mutations });
    return;
  }
  for (const mutation of mutations) {
    await onSave(mutation);
  }
}

function exportPlanCSV({ selectedPlan, planDays, planKinds, dayTypes, exercises, trainingTypes, activities }) {
  const kindByID = Object.fromEntries(planKinds.map((kind) => [kind.id, kind]));
  const dayTypeByID = Object.fromEntries(dayTypes.map((type) => [type.id, type]));
  const exercisesByID = Object.fromEntries(exercises.map((exercise) => [exercise.id, exercise]));
  const trainingTypeByID = Object.fromEntries(trainingTypes.map((type) => [type.id, type]));
  const activityByID = Object.fromEntries(activities.map((activity) => [activity.id, activity]));

  const rows = [];
  const sortedDays = planDays.slice().sort((left, right) => String(left.day_date || "").localeCompare(String(right.day_date || "")));

  for (const day of sortedDays) {
    const chosenIDs = Array.isArray(day.chosen_exercise_ids) ? day.chosen_exercise_ids : [];
    const orderMap = day.exercise_order_by_id || {};
    const orderedIDs = chosenIDs
      .slice()
      .sort((left, right) => Number(orderMap[left] ?? Number.MAX_SAFE_INTEGER) - Number(orderMap[right] ?? Number.MAX_SAFE_INTEGER));

    const baseRow = {
      planName: selectedPlan?.name || "",
      planKind: kindByID[selectedPlan?.kind_id]?.name || "",
      planStartDate: formatDateKey(selectedPlan?.start_date || ""),
      dayDate: formatDateKey(day.day_date || ""),
      weekday: weekdayNameFromDate(day.day_date),
      dayType: dayTypeByID[day.day_type_id]?.name || "",
      dayNotes: day.daily_notes || "",
      exerciseOrder: "",
      exerciseName: "",
      activityName: "",
      trainingTypeName: "",
      exerciseId: ""
    };

    if (orderedIDs.length === 0) {
      rows.push(baseRow);
      continue;
    }

    for (let index = 0; index < orderedIDs.length; index += 1) {
      const exerciseId = orderedIDs[index];
      const exercise = exercisesByID[exerciseId] || null;
      const trainingType = exercise ? trainingTypeByID[exercise.training_type_id] : null;
      const activity = trainingType ? activityByID[trainingType.activity_id] : null;

      rows.push({
        ...baseRow,
        exerciseOrder: String(index + 1),
        exerciseName: exercise?.name || "",
        activityName: activity?.name || "",
        trainingTypeName: trainingType?.name || "",
        exerciseId: exerciseId || ""
      });
    }
  }

  const csvText = buildCSV(PLAN_EXPORT_COLUMNS, rows);
  const filename = `klettrack-training-plan-${selectedPlan?.name || "plan"}-${new Date().toISOString().slice(0, 10)}.csv`;
  downloadCSV({ filename, csvText });
}

function renderClonePlanPanel(selectedPlan, selection) {
  if (!selectedPlan || !selection.planCloneOpen) {
    return "";
  }

  const defaultName = selection.planCloneName || `${selectedPlan.name || "Plan"} copy`;
  const defaultStart = selection.planCloneStartDate || dateInputValue(selectedPlan.start_date);

  return `
    <section class="inline-panel" aria-label="Clone plan panel">
      <h4>Clone Plan</h4>
      <form id="plan-clone-form" class="editor-form compact">
        <label>New Plan Name <input id="plan-clone-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(defaultName)}" required /></label>
        <label>Start Date <input id="plan-clone-start" class="input" type="date" value="${escapeHTML(defaultStart)}" required /></label>
        <div class="actions">
          <button class="btn primary" type="submit">Create Clone</button>
          <button id="plan-clone-cancel" class="btn" type="button">Cancel</button>
        </div>
      </form>
    </section>
  `;
}

function renderPlanImportPanel(selection, store) {
  if (!selection.planImportOpen || !pendingPlanImport) {
    return "";
  }

  const parsed = pendingPlanImport.parsed;
  const groups = parsed.planGroups;
  const selectedGroup = groups.find((group) => group.key === pendingPlanImport.selectedGroupKey) || groups[0];
  const draft = getPlanImportDraft(selectedGroup);
  const preview = buildImportPreview(selectedGroup, draft, store);
  const planKinds = store.active("plan_kinds");
  if (!selectedGroup) {
    return "";
  }

  return `
    <section class="inline-panel plans-import-panel" aria-label="Import plan panel">
      <h4>Import Plan CSV</h4>
      <p class="muted">File: ${escapeHTML(pendingPlanImport.filename || "plan.csv")}</p>
      ${
        groups.length > 1
          ? `<label>Plan group
               <select id="plan-import-group" class="input">
                 ${groups
                   .map((group) => {
                     const start = group.planStartDate || group.earliestDayDate || "unknown";
                     return `<option value="${group.key}" ${group.key === selectedGroup.key ? "selected" : ""}>${escapeHTML(
                       `${group.planName} (${start})`
                     )}</option>`;
                   })
                   .join("")}
               </select>
             </label>`
          : ""
      }
      <div class="plans-import-preview">
        <label>Plan name
          <input id="plan-import-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(draft.planName)}" />
        </label>
        <label>Start date
          <input id="plan-import-start" class="input" type="date" value="${escapeHTML(draft.planStartDate)}" />
        </label>
        <label>Plan kind
          <select id="plan-import-kind" class="input">
            <option value="__auto__" ${draft.planKindSelection === "__auto__" ? "selected" : ""}>${
              selectedGroup.planKindName
                ? `Auto from CSV (${escapeHTML(selectedGroup.planKindName)})`
                : "Auto from CSV (none)"
            }</option>
            <option value="" ${draft.planKindSelection === "" ? "selected" : ""}>None</option>
            ${planKinds
              .map((kind) => `<option value="${kind.id}" ${kind.id === draft.planKindSelection ? "selected" : ""}>${escapeHTML(kind.name)}</option>`)
              .join("")}
          </select>
        </label>
        <p><strong>Days:</strong> ${preview.dayCount}</p>
        <p><strong>Exercise rows:</strong> ${preview.exerciseCount}</p>
        <p><strong>Placeholders:</strong> ${preview.placeholderText}</p>
        ${
          preview.warningCount > 0
            ? `<p class="plans-import-warning">${preview.warningCount} warning(s) will be carried with this import.</p>`
            : ""
        }
      </div>
      <div class="actions">
        <button id="plan-import-confirm" class="btn primary" type="button" ${selection.planImportBusy ? "disabled" : ""}>
          ${selection.planImportBusy ? `<span class="btn-spinner" aria-hidden="true"></span><span>Importing...</span>` : "Import"}
        </button>
        <button id="plan-import-cancel" class="btn" type="button" ${selection.planImportBusy ? "disabled" : ""}>Cancel</button>
      </div>
      ${selection.planImportBusy ? `<p class="plans-import-processing" role="status" aria-live="polite">Processing import. Please wait…</p>` : ""}
    </section>
  `;
}

function buildImportPreview(group, draft, store) {
  const exerciseCount = group.days.reduce((total, day) => {
    return total + day.exerciseRows.filter((row) => row.exerciseName || row.exerciseIdRaw || row.trainingTypeName || row.activityName).length;
  }, 0);
  const warnings = Array.isArray(group.warnings) ? group.warnings.length : 0;
  const groupForPreview = applyGroupImportOverrides(group, draft);
  let placeholderText = "0";
  try {
    const dryRun = buildPlanImportMutations({ group: groupForPreview, store, overrides: draft });
    const placeholders = dryRun.summary.placeholders || {};
    const placeholderParts = Object.entries(placeholders)
      .filter(([, count]) => Number(count || 0) > 0)
      .map(([name, count]) => `${name}: ${count}`);
    placeholderText = placeholderParts.length ? placeholderParts.join(", ") : "0";
  } catch {
    placeholderText = "Unable to calculate";
  }
  return {
    planName: `${groupForPreview.planName || "Imported Plan"} (Imported)`,
    planStartDate: groupForPreview.planStartDate || groupForPreview.earliestDayDate || "Fallback from day rows",
    dayCount: group.days.length,
    exerciseCount,
    placeholderText,
    warningCount: warnings
  };
}

function createPlanImportDraft(group) {
  return {
    planName: String(group?.planName || "Imported Plan"),
    planStartDate: normalizePlanImportDate(String(group?.planStartDate || group?.earliestDayDate || "")),
    planKindName: String(group?.planKindName || ""),
    planKindSelection: "__auto__"
  };
}

function getPlanImportDraft(group) {
  if (!group || !pendingPlanImport) {
    return createPlanImportDraft(group);
  }
  const existing = pendingPlanImport.draftsByGroupKey?.[group.key];
  return existing ? { ...existing } : createPlanImportDraft(group);
}

function readPlanImportDraftFromForm(group) {
  const fallback = getPlanImportDraft(group);
  const planName = sanitizeText(String(document.getElementById("plan-import-name")?.value || "")) || fallback.planName;
  const planStartDate = normalizePlanImportDate(String(document.getElementById("plan-import-start")?.value || "")) || fallback.planStartDate;
  const planKindSelection = String(document.getElementById("plan-import-kind")?.value || fallback.planKindSelection || "__auto__");
  return {
    planName,
    planStartDate,
    planKindName: fallback.planKindName,
    planKindSelection
  };
}

function applyGroupImportOverrides(group, draft) {
  return {
    ...group,
    planName: String(draft?.planName || group?.planName || "Imported Plan"),
    planStartDate: String(draft?.planStartDate || group?.planStartDate || group?.earliestDayDate || ""),
    planKindName: String(draft?.planKindName || group?.planKindName || "")
  };
}

function normalizePlanImportDate(value) {
  const raw = String(value || "").trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(raw) ? raw : "";
}

function totalPlaceholders(placeholders) {
  if (!placeholders || typeof placeholders !== "object") {
    return 0;
  }
  return Object.values(placeholders).reduce((total, value) => total + Number(value || 0), 0);
}

function renderPlanSetupPanel({ selectedPlan, selection, planKinds }) {
  if (!selection.planSetupOpen) {
    return "";
  }
  const mode = selection.planSetupMode === "edit" ? "edit" : "create";
  const defaults =
    mode === "edit" && selectedPlan
      ? {
          name: selectedPlan.name || "",
          start: dateInputValue(selectedPlan.start_date),
          kindId: selectedPlan.kind_id || ""
        }
      : {
          name: "",
          start: dateInputValue(new Date().toISOString()),
          kindId: ""
        };

  return `
    <section class="inline-panel plans-setup-panel" aria-label="Plan setup panel">
      <h4>${mode === "edit" ? "Edit Plan" : "Create Plan"}</h4>
      <form id="plan-setup-form" class="editor-form compact">
        <label>Name <input id="plan-setup-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(defaults.name)}" required /></label>
        <label>Start Date <input id="plan-setup-start" class="input" type="date" value="${escapeHTML(defaults.start)}" required /></label>
        <label>Plan Kind
          <select id="plan-setup-kind" class="input">
            <option value="">None</option>
            ${planKinds
              .map((kind) => `<option value="${kind.id}" ${kind.id === defaults.kindId ? "selected" : ""}>${escapeHTML(kind.name)}</option>`)
              .join("")}
          </select>
        </label>
        <div class="actions">
          <button class="btn primary" type="submit">${mode === "edit" ? "Save Plan" : "Create Plan"}</button>
          ${
            mode === "edit" && selectedPlan
              ? `<button id="plan-setup-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>`
              : ""
          }
          <button id="plan-setup-cancel" class="btn" type="button">Cancel</button>
        </div>
      </form>
    </section>
  `;
}

function renderCalendarModeButton(mode, selectedMode) {
  return `<button class="calendar-mode-btn ${mode === selectedMode ? "active" : ""}" type="button" data-calendar-mode="${mode}" aria-pressed="${
    mode === selectedMode ? "true" : "false"
  }">${mode[0].toUpperCase()}${mode.slice(1)}</button>`;
}

function renderCalendarFocus(days, selectedDay, mode, anchorISO, dayTypeByID, dayTypes, periodState, selection) {
  const anchor = periodState.activePeriod || safeDate(anchorISO);
  const dayMap = new Map(days.map((day) => [formatDateKey(day.day_date), day]));
  const selectedDayKey = selectedDay ? formatDateKey(selectedDay.day_date) : "";
  const todayKey = formatDateKey(new Date());

  const weekdayHeader = "";
  const cells = [];
  let title = "";

  if (!periodState.hasPeriods) {
    return `<p class="muted" style="margin-top: 12px;">No days in this plan yet.</p>`;
  }

  if (mode === "week") {
    const weekStart = startOfWeek(anchor);
    title = `Week of ${weekStart.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" })}`;
    for (let index = 0; index < 7; index += 1) {
      const date = addDays(weekStart, index);
      cells.push(renderCalendarCell({ date, inCurrentPeriod: true, dayMap, selectedDayKey, todayKey, dayTypeByID, dayTypes, mode }));
    }
  } else {
    const monthStart = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
    const monthEnd = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0);
    title = monthStart.toLocaleDateString(undefined, { month: "long", year: "numeric" });
    for (let dayNumber = 1; dayNumber <= monthEnd.getDate(); dayNumber += 1) {
      const current = new Date(monthStart.getFullYear(), monthStart.getMonth(), dayNumber);
      cells.push(renderCalendarCell({ date: current, inCurrentPeriod: true, dayMap, selectedDayKey, todayKey, dayTypeByID, dayTypes, mode }));
    }
  }

  return `<div class="plans-calendar-focus" data-mode="${escapeHTML(mode)}" style="margin-top:12px;">
    <div class="calendar-shell">
      <div class="calendar-header-row">
        <h4>${escapeHTML(title)}</h4>
        <div class="calendar-header-actions">
          <button id="day-clone-toggle" class="btn primary btn-compact" type="button" ${selectedDay ? "" : "disabled"}>Clone Day</button>
          <button id="calendar-prev" class="icon-btn" type="button" aria-label="Previous ${escapeHTML(mode)}" ${
            periodState.prevPeriod ? "" : "disabled"
          }>${CHEVRON_LEFT_ICON}</button>
          <button id="calendar-today" class="btn btn-compact" type="button" ${periodState.hasPeriods ? "" : "disabled"}>Today</button>
          <button id="calendar-next" class="icon-btn" type="button" aria-label="Next ${escapeHTML(mode)}" ${
            periodState.nextPeriod ? "" : "disabled"
          }>${CHEVRON_RIGHT_ICON}</button>
          <button id="plan-add-day-open" class="btn btn-compact" type="button" ${selection.planId ? "" : "disabled"}>Add Day</button>
          <button id="plan-add-weeks" class="btn btn-compact" type="button" ${selection.planId ? "" : "disabled"}>Add Weeks</button>
        </div>
      </div>
      <div class="plans-calendar-grid plans-calendar-grid-${escapeHTML(mode)}">
        ${weekdayHeader}
        ${cells.join("")}
      </div>
    </div>
  </div>`;
}

function renderAddDayPanel(selection) {
  if (!selection.planAddDayOpen) {
    return "";
  }
  const defaultDate = selection.planAddDayDate || formatDateKey(new Date());
  return `
    <form id="new-plan-day-form" class="inline-form plans-add-day-inline" style="margin-top: 12px;">
      <input id="new-plan-day-date" class="input" type="date" value="${escapeHTML(defaultDate)}" required />
      <button class="btn primary" type="submit">Add Day</button>
      <button id="plan-add-day-cancel" class="btn" type="button">Cancel</button>
    </form>
  `;
}

function renderCalendarCell({ date, inCurrentPeriod, dayMap, selectedDayKey, todayKey, dayTypeByID, dayTypes, mode }) {
  const dayKey = formatDateKey(date);
  const planDay = dayMap.get(dayKey) || null;
  const dayType = planDay ? dayTypeByID[planDay.day_type_id] || null : null;
  const color = resolveDayTypeColor(dayType);
  const dayTypeOptions = dayTypes
    .filter((type) => !type?.is_hidden)
    .map(
      (type) =>
        `<option value="${type.id}" ${planDay && type.id === planDay.day_type_id ? "selected" : ""}>${escapeHTML(dayTypeLabel(type))}</option>`
    )
    .join("");
  const classes = [
    "calendar-cell",
    inCurrentPeriod ? "" : "outside-period",
    planDay ? "has-plan-day" : "empty-day",
    selectedDayKey === dayKey ? "active" : "",
    todayKey === dayKey ? "today" : ""
  ]
    .filter(Boolean)
    .join(" ");
  return `<div class="${classes}">
    <button class="calendar-cell-open-btn" type="button" data-calendar-date="${dayKey}">
      <span class="calendar-cell-top">
        <span class="calendar-cell-date">${escapeHTML(`${weekdayShortFromDate(date)} ${String(date.getDate())}`)}</span>
        ${planDay ? `<span class="day-dot" style="background:${escapeHTML(color)}"></span>` : ""}
      </span>
      ${!planDay && mode === "week" ? `<span class="calendar-day-meta">No day</span>` : ""}
    </button>
    ${
      planDay
        ? `<div class="calendar-day-type-row">
             <select class="input calendar-day-type-select" data-calendar-day-id="${planDay.id}" data-calendar-day-date="${dayKey}" aria-label="Day type for ${escapeHTML(dayKey)}">
               <option value="">None</option>
               ${dayTypeOptions}
             </select>
             <span class="calendar-day-type-status" data-calendar-day-status-for="${planDay.id}" aria-live="polite"></span>
           </div>`
        : ""
    }
  </div>`;
}

function renderDayTypeLegend(dayTypes) {
  const normalized = dayTypes
    .filter((type) => !type?.is_hidden)
    .map((type) => ({
      ...type,
      label: dayTypeLabel(type)
    }))
    .sort((a, b) => String(a.label || "").localeCompare(String(b.label || ""), undefined, { sensitivity: "base" }));

  if (!normalized.length) {
    return "";
  }

  return `
    <div class="plans-day-legend">
      ${normalized
        .map(
          (type) =>
            `<span class="selection-pill"><span class="day-dot" style="background:${escapeHTML(resolveDayTypeColor(type))}"></span>${escapeHTML(type.label)}</span>`
        )
        .join("")}
    </div>
  `;
}

function renderDayEditorArea({
  plan,
  day,
  dayTypes,
  activities,
  trainingTypes,
  exercises,
  boulderCombinations,
  boulderCombinationExercises,
  selection,
  planDays
}) {
  if (!plan) {
    return `<p class="muted">Choose a plan to start editing.</p>`;
  }

  if (!day) {
    return `
      <p class="muted">Select a day from the calendar to edit details and exercises.</p>
    `;
  }

  const cloneOpen = Boolean(selection.planDayCloneOpen);
  return `
    <div class="workspace-grid plans-day-wide-grid">
      <section class="plans-day-main-panel">
        ${cloneOpen ? renderDayClonePanel(day, planDays, selection) : renderPlanDayEditor(day)}
      </section>
      <section class="plans-exercise-row">
        ${renderExercisePicker(day, activities, trainingTypes, exercises, boulderCombinations, boulderCombinationExercises, selection)}
      </section>
    </div>
  `;
}

function renderPlanDayEditor(day) {
  return `
    <form id="plan-day-editor" class="editor-form compact plans-day-editor-form" style="margin-top: 12px;">
      <label>Notes <textarea id="plan-day-notes" class="input" rows="2" maxlength="1000">${escapeHTML(day.daily_notes || "")}</textarea></label>
    </form>
  `;
}

function renderDayClonePanel(day, planDays, selection) {
  const weekdayDefault = weekdayIdFromDate(day.day_date);
  const mode = selection.planDayCloneMode || "clone";
  const selectedWeekdays =
    Array.isArray(selection.planDayRecurringWeekdays) && selection.planDayRecurringWeekdays.length > 0
      ? selection.planDayRecurringWeekdays
      : [weekdayDefault];
  const rangeMin = planDays.length > 0 ? dateInputValue(planDays[0].day_date) : "";
  const rangeMax = planDays.length > 0 ? dateInputValue(planDays.at(-1)?.day_date) : "";
  const targetDate = selection.planDayCloneTargetDate || dateInputValue(day.day_date);
  const applyRecurring = selection.planDayCloneApplyRecurring !== false;

  return `
    <section class="inline-panel" aria-label="Clone or recurring panel">
      <h4>Clone / Recurring</h4>
      <form id="day-clone-form" class="editor-form compact" style="margin-top:10px;">
              <div class="segmented-control" role="tablist" aria-label="Clone mode">
                <button class="btn ${mode === "clone" ? "primary" : ""}" type="button" data-day-clone-mode="clone">Clone</button>
                <button class="btn ${mode === "recurring" ? "primary" : ""}" type="button" data-day-clone-mode="recurring">Recurring</button>
              </div>
              ${
                mode === "clone"
                  ? `<label>Target Date <input id="day-clone-target-date" class="input" type="date" value="${escapeHTML(targetDate)}" min="${escapeHTML(
                      rangeMin
                    )}" max="${escapeHTML(rangeMax)}" required /></label>`
                  : `<label class="checkbox-row"><input id="day-recurring-apply" type="checkbox" ${
                      applyRecurring ? "checked" : ""
                    } /> Apply to existing future days</label>
                     <fieldset>
                       <legend>Weekdays</legend>
                       <div class="weekday-grid">
                         ${WEEKDAYS.map(
                           (weekday) =>
                             `<label class="checkbox-row"><input type="checkbox" name="day-recurring-weekday" value="${weekday.id}" ${
                               selectedWeekdays.includes(weekday.id) ? "checked" : ""
                             } /> ${escapeHTML(weekday.title)}</label>`
                         ).join("")}
                       </div>
                     </fieldset>`
              }
              <div class="actions">
                <button class="btn primary" type="submit">Save</button>
                <button id="day-clone-cancel" class="btn" type="button">Close</button>
              </div>
            </form>
    </section>
  `;
}

function renderExercisePicker(day, activities, trainingTypes, exercises, boulderCombinations, boulderCombinationExercises, selection) {
  const chosenIDs = Array.isArray(day.chosen_exercise_ids) ? day.chosen_exercise_ids : [];
  const activityID = selection.planExerciseActivityId || "";
  const availableTrainingTypes = activityID
    ? trainingTypes.filter((type) => type.activity_id === activityID)
    : trainingTypes;
  const trainingTypeID = selection.planExerciseTrainingTypeId || "";
  const search = String(selection.planExerciseSearch || "").trim().toLocaleLowerCase();
  const typeIdsForFilter = trainingTypeID
    ? [trainingTypeID]
    : activityID
      ? availableTrainingTypes.map((type) => type.id)
      : [];
  const comboIdsForFilter = typeIdsForFilter.length
    ? boulderCombinations.filter((combo) => typeIdsForFilter.includes(combo.training_type_id)).map((combo) => combo.id)
    : [];
  const comboExerciseIdSet = new Set(
    comboIdsForFilter.length
      ? boulderCombinationExercises
          .filter((link) => comboIdsForFilter.includes(link.boulder_combination_id))
          .map((link) => link.exercise_id)
      : []
  );

  let filteredExercises = exercises.slice();
  if (trainingTypeID) {
    filteredExercises = filteredExercises.filter(
      (exercise) => exercise.training_type_id === trainingTypeID || comboExerciseIdSet.has(exercise.id)
    );
  } else if (activityID) {
    const typeSet = new Set(availableTrainingTypes.map((type) => type.id));
    filteredExercises = filteredExercises.filter(
      (exercise) => typeSet.has(exercise.training_type_id) || comboExerciseIdSet.has(exercise.id)
    );
  }
  if (search) {
    filteredExercises = filteredExercises.filter((exercise) =>
      String(exercise.name || "").toLocaleLowerCase().includes(search)
    );
  }

  filteredExercises.sort((a, b) =>
    String(a.name || "").localeCompare(String(b.name || ""), undefined, { sensitivity: "base" })
  );
  const trainingTypeByID = Object.fromEntries(trainingTypes.map((type) => [type.id, type]));
  const activityByID = Object.fromEntries(activities.map((activity) => [activity.id, activity]));

  const selectedOrderedExercises = chosenIDs
    .map((exerciseID) => exercises.find((exercise) => exercise.id === exerciseID))
    .filter(Boolean);

  return `
    <h3>Exercise Catalog</h3>
    <div class="plans-filter-row">
      <input id="exercise-search" class="input" type="search" value="${escapeHTML(selection.planExerciseSearch || "")}" placeholder="Find exercise..." />
      <select id="exercise-activity-filter" class="input">
        <option value="">All activities</option>
        ${activities
          .map(
            (activity) =>
              `<option value="${activity.id}" ${activity.id === activityID ? "selected" : ""}>${escapeHTML(activity.name || "")}</option>`
          )
          .join("")}
      </select>
      <select id="exercise-training-type-filter" class="input">
        <option value="">All training types</option>
        ${availableTrainingTypes
          .map(
            (type) =>
              `<option value="${type.id}" ${type.id === trainingTypeID ? "selected" : ""}>${escapeHTML(type.name || "")}</option>`
          )
          .join("")}
      </select>
    </div>

    <div class="workspace-grid plans-exercise-grid">
      <section class="pane">
        <h4>Exercises</h4>
        <div id="exercise-available-list" class="exercise-card-grid">
          ${filteredExercises
            .map((exercise) => {
              const isSelected = chosenIDs.includes(exercise.id);
              const guidance = buildExerciseGuidance(exercise);
              const trainingType = trainingTypeByID[exercise.training_type_id] || null;
              const activity = trainingType ? activityByID[trainingType.activity_id] : null;
              const navPath = [activity?.name || "", trainingType?.name || ""].filter(Boolean).join(" / ");
              return `<article class="exercise-card${isSelected ? " selected" : ""}">
                  <div class="exercise-card-head">
                    <div class="exercise-card-copy">
                      <h5 title="${escapeHTML(exercise.name || "Exercise")}">${escapeHTML(exercise.name || "Exercise")}</h5>
                      ${
                        guidance.metrics || guidance.note || navPath
                          ? `<div class="exercise-guidance">
                               ${
                                 guidance.metrics
                                   ? `<span title="${escapeHTML(guidance.metrics)}">${escapeHTML(guidance.metrics)}</span>`
                                   : ""
                               }
                               ${
                                 navPath
                                   ? `${guidance.metrics ? `<span class="exercise-guidance-sep" aria-hidden="true">|</span>` : ""}<span class="exercise-context-inline" title="${escapeHTML(
                                       navPath
                                     )}">${escapeHTML(navPath)}</span>`
                                   : ""
                               }
                               ${guidance.note ? renderTextWithHttpsLink(guidance.note) : ""}
                             </div>`
                          : ""
                      }
                    </div>
                    <button class="icon-btn exercise-toggle-btn" type="button" data-add-exercise="${exercise.id}" data-label="${escapeHTML(
                      exercise.name || "Exercise"
                    )}" aria-label="${isSelected ? "Exercise selected" : "Add exercise"}">
                      ${isSelected ? CHECK_ICON : PLUS_ICON}
                    </button>
                  </div>
                </article>`;
            })
            .join("")}
        </div>
      </section>

      <section class="pane">
        <h4>Selected Order</h4>
        <ul id="selected-exercise-order" class="select-list">
          ${selectedOrderedExercises
            .map(
              (exercise, index) =>
                `<li data-id="${exercise.id}"><div class="row"><span class="selection-pill">${index + 1}</span><strong title="${escapeHTML(
                  exercise.name || "Exercise"
                )}">${escapeHTML(
                  exercise.name || "Exercise"
                )}</strong><span style="margin-left:auto"></span><button class="icon-btn" type="button" data-move-exercise="${exercise.id}" data-direction="up" aria-label="Move up">${CHEVRON_UP_ICON}</button><button class="icon-btn" type="button" data-move-exercise="${exercise.id}" data-direction="down" aria-label="Move down">${CHEVRON_DOWN_ICON}</button><button class="icon-btn destructive" type="button" data-remove-exercise="${exercise.id}" aria-label="Remove exercise">${DELETE_ICON}</button></div></li>`
            )
            .join("")}
        </ul>
      </section>
    </div>
  `;
}

function toggleExerciseSelection(id, label) {
  if (!id) {
    return false;
  }
  const selectedList = document.getElementById("selected-exercise-order");
  if (!selectedList) {
    return false;
  }
  const existing = selectedList.querySelector(`li[data-id='${id}']`);
  if (existing) {
    existing.remove();
    syncExerciseToggleState(id, false);
    renumberSelectedExercises();
    return false;
  }
  const nextIndex = selectedList.querySelectorAll("li[data-id]").length + 1;
  const item = document.createElement("li");
  item.dataset.id = id;
  item.innerHTML = `<div class="row"><span class="selection-pill">${nextIndex}</span><strong title="${escapeHTML(
    label || "Exercise"
  )}">${escapeHTML(
    label || "Exercise"
  )}</strong><span style="margin-left:auto"></span><button class="icon-btn" type="button" data-move-exercise="${id}" data-direction="up" aria-label="Move up">${CHEVRON_UP_ICON}</button><button class="icon-btn" type="button" data-move-exercise="${id}" data-direction="down" aria-label="Move down">${CHEVRON_DOWN_ICON}</button><button class="icon-btn destructive" type="button" data-remove-exercise="${id}" aria-label="Remove exercise">${DELETE_ICON}</button></div>`;
  selectedList.append(item);
  syncExerciseToggleState(id, true);
  return true;
}

function removeExerciseFromSelection(id) {
  if (!id) {
    return;
  }
  const node = document.querySelector(`#selected-exercise-order li[data-id='${id}']`);
  node?.remove();
  syncExerciseToggleState(id, false);
  renumberSelectedExercises();
}

function moveExercise(id, direction) {
  if (!id || !direction) {
    return;
  }
  const selectedList = document.getElementById("selected-exercise-order");
  if (!selectedList) {
    return;
  }
  const currentRow = selectedList.querySelector(`li[data-id='${id}']`);
  if (!currentRow) {
    return;
  }
  if (direction === "up" && currentRow.previousElementSibling) {
    currentRow.parentElement?.insertBefore(currentRow, currentRow.previousElementSibling);
  }
  if (direction === "down" && currentRow.nextElementSibling) {
    currentRow.parentElement?.insertBefore(currentRow.nextElementSibling, currentRow);
  }
  renumberSelectedExercises();
}

function renumberSelectedExercises() {
  const nodes = [...document.querySelectorAll("#selected-exercise-order li[data-id]")];
  nodes.forEach((node, index) => {
    const pill = node.querySelector(".selection-pill");
    if (pill) {
      pill.textContent = String(index + 1);
    }
  });
}

function syncExerciseToggleState(id, isSelected) {
  if (!id) {
    return;
  }
  const button = document.querySelector(`#exercise-available-list button[data-add-exercise='${id}']`);
  const card = button?.closest(".exercise-card");
  if (button) {
    button.innerHTML = isSelected ? CHECK_ICON : PLUS_ICON;
    button.setAttribute("aria-label", isSelected ? "Exercise selected" : "Add exercise");
  }
  card?.classList.toggle("selected", Boolean(isSelected));
}

async function persistSelectedExercises({ store, selection, onSave, orderedIDs: orderedIDsSnapshot }) {
  if (!selection.planId || !selection.planDayId) {
    return;
  }
  const currentDay = reconcilePlanDayTypeDraft(store.get("plan_days", selection.planDayId));
  if (!currentDay) {
    return;
  }
  const orderedIDs = Array.isArray(orderedIDsSnapshot) ? orderedIDsSnapshot.slice() : getSelectedExerciseOrder();
  const orderMap = Object.fromEntries(orderedIDs.map((id, index) => [id, index]));
  await onSave({
    entity: "plan_days",
    id: selection.planDayId,
      payload: {
        plan_id: selection.planId,
        day_date: normalizeDateInput("plan-day-date", currentDay.day_date),
        day_type_id: currentDay.day_type_id ?? null,
        chosen_exercise_ids: orderedIDs,
        exercise_order_by_id: orderMap,
        daily_notes: optionalSanitizedValue("plan-day-notes") ?? currentDay.daily_notes ?? null
      }
  });
}

function schedulePlanDayAutosave({ store, selection, onSave, orderedIDs }) {
  clearTimeout(planDayAutosaveTimer);
  planDayAutosavePayload = {
    store,
    selection: {
      planId: selection.planId,
      planDayId: selection.planDayId
    },
    onSave,
    orderedIDs: Array.isArray(orderedIDs) ? orderedIDs.slice() : undefined
  };
  return new Promise((resolve, reject) => {
    planDayAutosaveWaiters.push({ resolve, reject });
    planDayAutosaveTimer = setTimeout(() => {
      void runPlanDayAutosave();
    }, 450);
  });
}

function clearPlanDayAutosave() {
  if (planDayAutosaveTimer) {
    clearTimeout(planDayAutosaveTimer);
    planDayAutosaveTimer = null;
  }
  planDayAutosavePayload = null;
  const waiters = planDayAutosaveWaiters.splice(0, planDayAutosaveWaiters.length);
  for (const waiter of waiters) {
    waiter.resolve();
  }
}

async function flushPlanDayAutosave() {
  if (!planDayAutosaveTimer) {
    if (planDayAutosaveInFlight || planDayAutosavePayload) {
      await waitForAutosaveIdle();
    }
    return;
  }
  clearTimeout(planDayAutosaveTimer);
  planDayAutosaveTimer = null;
  await runPlanDayAutosave();
  await waitForAutosaveIdle();
}

async function runPlanDayAutosave() {
  if (planDayAutosaveInFlight) {
    planDayAutosaveQueued = true;
    return;
  }
  const payload = planDayAutosavePayload;
  if (!payload) {
    return;
  }
  planDayAutosaveInFlight = true;
  planDayAutosavePayload = null;
  const waiters = planDayAutosaveWaiters.splice(0, planDayAutosaveWaiters.length);
  try {
    await persistSelectedExercises(payload);
    for (const waiter of waiters) {
      waiter.resolve();
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to save day changes";
    showToast(message, "error");
    for (const waiter of waiters) {
      waiter.reject(error);
    }
  } finally {
    planDayAutosaveInFlight = false;
    if (planDayAutosaveQueued || planDayAutosavePayload) {
      planDayAutosaveQueued = false;
      void runPlanDayAutosave();
    }
  }
}

function readCurrentDayDraft({ store, selection }) {
  const currentDay = reconcilePlanDayTypeDraft(store.get("plan_days", selection.planDayId));
  const hasSelectionList = Boolean(document.getElementById("selected-exercise-order"));
  const orderedIDs = getSelectedExerciseOrder();
  const exerciseOrderByID = Object.fromEntries(orderedIDs.map((id, index) => [id, index]));
  return {
    day_type_id: currentDay?.day_type_id ?? null,
    chosen_exercise_ids: hasSelectionList ? orderedIDs : [...(currentDay?.chosen_exercise_ids || [])],
    exercise_order_by_id: hasSelectionList ? exerciseOrderByID : deepCopyObject(currentDay?.exercise_order_by_id || {}),
    daily_notes: optionalSanitizedValue("plan-day-notes") ?? currentDay?.daily_notes ?? null
  };
}

function captureExerciseListScroll() {
  const node = document.getElementById("exercise-available-list");
  if (!node) {
    return;
  }
  exerciseAvailableScrollTop = node.scrollTop;
}

function restoreExerciseListScroll() {
  const node = document.getElementById("exercise-available-list");
  if (!node) {
    return;
  }
  node.scrollTop = Math.max(0, Number(exerciseAvailableScrollTop || 0));
}

function restoreExerciseSearchFocus() {
  const pending = pendingExerciseSearchFocus;
  if (!pending) {
    return;
  }
  const node = document.getElementById("exercise-search");
  if (!(node instanceof HTMLInputElement)) {
    return;
  }
  if (String(node.value || "") !== pending.value) {
    return;
  }
  const applyFocus = () => {
    node.focus({ preventScroll: true });
    const length = node.value.length;
    const start = Number.isFinite(pending.start) ? Math.max(0, Math.min(length, Number(pending.start))) : length;
    const end = Number.isFinite(pending.end) ? Math.max(start, Math.min(length, Number(pending.end))) : start;
    node.setSelectionRange(start, end);
    pendingExerciseSearchFocus = null;
  };
  applyFocus();
  requestAnimationFrame(() => {
    if (document.activeElement !== node) {
      applyFocus();
    }
  });
}

function captureSelectedExerciseListScroll() {
  const node = document.getElementById("selected-exercise-order");
  if (!node) {
    return;
  }
  selectedExerciseScrollTop = node.scrollTop;
}

function restoreSelectedExerciseListScroll() {
  const node = document.getElementById("selected-exercise-order");
  if (!node) {
    return;
  }
  if (selectedExercisePinToBottom) {
    node.scrollTop = node.scrollHeight;
    selectedExerciseScrollTop = node.scrollTop;
    selectedExercisePinToBottom = false;
    return;
  }
  node.scrollTop = Math.max(0, Number(selectedExerciseScrollTop || 0));
}

function scrollSelectedExerciseListToBottom() {
  const node = document.getElementById("selected-exercise-order");
  selectedExercisePinToBottom = true;
  if (!node) {
    return;
  }
  node.scrollTop = node.scrollHeight;
  selectedExerciseScrollTop = node.scrollTop;
}

function syncPlanDayExerciseDraft(planDayId, orderedIDs) {
  const dayId = String(planDayId || "");
  if (!dayId) {
    return;
  }
  if (!Array.isArray(orderedIDs)) {
    planDayExerciseDrafts.delete(dayId);
    return;
  }
  const normalized = orderedIDs.map((id) => String(id || "")).filter(Boolean);
  planDayExerciseDrafts.set(dayId, normalized);
}

function reconcilePlanDayExerciseDraft({ selectedDay, planDayId }) {
  const dayId = String(planDayId || "");
  if (!dayId || !selectedDay) {
    return selectedDay;
  }
  const draftOrderedIDs = planDayExerciseDrafts.get(dayId);
  if (!Array.isArray(draftOrderedIDs)) {
    return selectedDay;
  }
  const serverOrderedIDs = Array.isArray(selectedDay.chosen_exercise_ids)
    ? selectedDay.chosen_exercise_ids.map((id) => String(id || "")).filter(Boolean)
    : [];
  if (arraysEqual(serverOrderedIDs, draftOrderedIDs)) {
    planDayExerciseDrafts.delete(dayId);
    return selectedDay;
  }
  return {
    ...selectedDay,
    chosen_exercise_ids: [...draftOrderedIDs],
    exercise_order_by_id: Object.fromEntries(draftOrderedIDs.map((id, index) => [id, index]))
  };
}

function reconcilePlanDayTypeDraft(day) {
  if (!day || typeof day !== "object") {
    return day;
  }
  const dayId = String(day.id || "");
  if (!dayId) {
    return day;
  }
  if (!planDayTypeDrafts.has(dayId)) {
    return day;
  }
  const draftDayTypeId = planDayTypeDrafts.get(dayId) || null;
  const storedDayTypeId = day.day_type_id ?? null;
  if (draftDayTypeId === storedDayTypeId) {
    planDayTypeDrafts.delete(dayId);
    return day;
  }
  return {
    ...day,
    day_type_id: draftDayTypeId
  };
}

function arraysEqual(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) {
    return false;
  }
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}

function getSelectedExerciseOrder() {
  return [...document.querySelectorAll("#selected-exercise-order li[data-id]")]
    .map((item) => String(item.dataset.id || ""))
    .filter(Boolean);
}

function getCalendarPeriodState(days, mode, anchorISO) {
  const periods = buildAvailablePeriods(days, mode || "month");
  if (!periods.length) {
    return {
      hasPeriods: false,
      activePeriod: null,
      prevPeriod: null,
      nextPeriod: null
    };
  }

  const anchorDate = toPeriodStart(safeDate(anchorISO || new Date().toISOString()), mode || "month");
  const anchorKey = formatDateKey(anchorDate);
  let index = periods.findIndex((period) => formatDateKey(period) === anchorKey);
  if (index === -1) {
    index = nearestPeriodIndex(periods, anchorDate);
  }

  return {
    hasPeriods: true,
    activePeriod: periods[index],
    prevPeriod: periods[index - 1] || null,
    nextPeriod: periods[index + 1] || null
  };
}

function buildAvailablePeriods(days, mode) {
  const seen = new Set();
  const periods = [];
  for (const day of days) {
    const periodDate = toPeriodStart(safeDate(day.day_date), mode || "month");
    const key = formatDateKey(periodDate);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    periods.push(periodDate);
  }
  periods.sort((left, right) => left.getTime() - right.getTime());
  return periods;
}

function toPeriodStart(date, mode) {
  if (mode === "week") {
    return startOfWeek(date);
  }
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function nearestPeriodIndex(periods, targetDate) {
  let bestIndex = 0;
  let bestDelta = Number.POSITIVE_INFINITY;
  for (let index = 0; index < periods.length; index += 1) {
    const delta = Math.abs(periods[index].getTime() - targetDate.getTime());
    if (delta < bestDelta) {
      bestDelta = delta;
      bestIndex = index;
    }
  }
  return bestIndex;
}

function startOfWeek(date) {
  const next = new Date(date);
  const day = (next.getDay() + 6) % 7;
  next.setDate(next.getDate() - day);
  next.setHours(0, 0, 0, 0);
  return next;
}

function safeDate(value) {
  const date = new Date(value || "");
  return Number.isNaN(date.getTime()) ? new Date() : date;
}

function startOfDay(date) {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  return next;
}

function toISODateStart(date) {
  const normalized = startOfDay(date);
  return `${formatDateKey(normalized.toISOString())}T00:00:00.000Z`;
}

function weekdayIdFromDate(value) {
  const date = safeDate(value);
  return date.getDay() + 1;
}

function weekdayNameFromDate(value) {
  const date = safeDate(value);
  return WEEKDAYS[weekdayIdFromDate(date) - 1]?.title || "";
}

function weekdayShortFromDate(value) {
  const date = safeDate(value);
  const shortByDay = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return shortByDay[date.getDay()] || "";
}

function dayDiff(leftDate, rightDate) {
  const delta = startOfDay(rightDate).getTime() - startOfDay(leftDate).getTime();
  return Math.round(delta / 86400000);
}

function addDays(date, count) {
  const next = new Date(date);
  next.setDate(next.getDate() + Number(count || 0));
  return next;
}

function resolveDayTypeColor(dayType) {
  if (!dayType) {
    return DAY_TYPE_COLORS.gray;
  }
  const key = String(dayType.color_key || dayType.colorKey || "gray").toLocaleLowerCase();
  return DAY_TYPE_COLORS[key] || DAY_TYPE_COLORS.gray;
}

function dayTypeLabel(dayType) {
  const name = String(dayType?.name || "").trim();
  if (name) {
    return name;
  }
  const key = String(dayType?.key || "").trim();
  if (key) {
    return key
      .replaceAll(/[_-]+/g, " ")
      .replaceAll(/\s+/g, " ")
      .trim()
      .replaceAll(/\b\w/g, (char) => char.toUpperCase());
  }
  return "Training Day";
}

function buildExerciseGuidance(exercise) {
  const reps = String(exercise.reps_text || exercise.repsText || "").trim();
  const sets = String(exercise.sets_text || exercise.setsText || "").trim();
  const duration = String(exercise.duration_text || exercise.durationText || "").trim();
  const rest = String(exercise.rest_text || exercise.restText || "").trim();
  const note = String(exercise.exercise_description || exercise.exerciseDescription || exercise.notes || "").trim();
  const metrics = [
    reps ? `Reps ${reps}` : "",
    sets ? `Sets ${sets}` : "",
    duration ? `Duration ${duration}` : "",
    rest ? `Rest ${rest}` : ""
  ]
    .filter(Boolean)
    .join(" · ");
  return {
    metrics,
    note
  };
}

function renderTextWithHttpsLink(value) {
  const text = String(value || "").trim();
  if (!text) {
    return "";
  }
  const isHttps = /^https:\/\/\S+$/i.test(text);
  const safeTitle = escapeHTML(text);
  if (isHttps) {
    const safeHref = escapeHTML(text);
    return `<a class="exercise-guidance-note external-link" href="${safeHref}" target="_blank" rel="noopener noreferrer" title="${safeTitle}">${safeTitle}</a>`;
  }
  return `<span class="exercise-guidance-note" title="${safeTitle}">${safeTitle}</span>`;
}

function updateCalendarDayDotColor(selectNode, dayTypeId, dayTypes) {
  if (!(selectNode instanceof HTMLElement)) {
    return;
  }
  const cell = selectNode.closest(".calendar-cell");
  if (!cell) {
    return;
  }
  const dot = cell.querySelector(".day-dot");
  if (!(dot instanceof HTMLElement)) {
    return;
  }
  const dayType = dayTypes.find((type) => type.id === dayTypeId) || null;
  dot.style.background = resolveDayTypeColor(dayType);
}

function setCalendarDayTypeSaveState(dayId, state) {
  const select = document.querySelector(`select[data-calendar-day-id='${dayId}']`);
  if (!(select instanceof HTMLSelectElement)) {
    return;
  }
  select.classList.remove("is-saving", "is-saved");
  if (state === "idle") {
    return;
  }
  if (state === "saving") {
    select.classList.add("is-saving");
    return;
  }
  if (state === "saved") {
    select.classList.add("is-saved");
    setTimeout(() => {
      const live = document.querySelector(`select[data-calendar-day-id='${dayId}']`);
      if (live instanceof HTMLSelectElement) {
        live.classList.remove("is-saved");
      }
    }, 900);
  }
}

function setCalendarDayTypeMessage(dayId, message, tone = "info") {
  const node = document.querySelector(`[data-calendar-day-status-for='${dayId}']`);
  if (!(node instanceof HTMLElement)) {
    return;
  }
  node.textContent = String(message || "");
  node.dataset.tone = tone;
}

async function waitForAutosaveIdle() {
  while (planDayAutosaveInFlight || Boolean(planDayAutosavePayload) || Boolean(planDayAutosaveTimer)) {
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

function setFormSubmittingState(form, isSubmitting, busyText = "Saving...") {
  const controls = [...form.querySelectorAll("button, input, select, textarea")];
  for (const control of controls) {
    if (!(control instanceof HTMLElement)) {
      continue;
    }
    if (control.dataset.keepEnabled === "true") {
      continue;
    }
    control.toggleAttribute("disabled", Boolean(isSubmitting));
  }
  const submitButton = form.querySelector("button[type='submit']");
  if (submitButton instanceof HTMLButtonElement) {
    if (!submitButton.dataset.defaultLabel) {
      submitButton.dataset.defaultLabel = submitButton.textContent || "Save";
    }
    submitButton.textContent = isSubmitting ? busyText : submitButton.dataset.defaultLabel;
  }
}

function formatDateKey(value) {
  if (value instanceof Date) {
    return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, "0")}-${String(value.getDate()).padStart(2, "0")}`;
  }
  return String(value || "").slice(0, 10);
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

function normalizeDateInput(id, fallback) {
  const raw = document.getElementById(id)?.value;
  if (!raw) {
    return fallback || null;
  }
  return `${raw}T00:00:00.000Z`;
}

function optionalValue(id) {
  const value = document.getElementById(id)?.value || "";
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
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

function deepCopyObject(value) {
  return JSON.parse(JSON.stringify(value || {}));
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
