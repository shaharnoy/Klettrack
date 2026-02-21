import { showToast } from "../components/toasts.js";
import { renderWorkspaceShell } from "../components/workspaceLayout.js";

const MAX_TEXT_LENGTH = 120;
const DELETE_ICON = `<span class="icon-trash" aria-hidden="true"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span>`;
const CHEVRON_UP_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5-5 5 5"/></svg>`;
const CHEVRON_DOWN_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 8l5 5 5-5"/></svg>`;
const PLUS_ICON = `<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 4v12"/><path d="M4 10h12"/></svg>`;
let comboSaveInFlightId = null;

export function renderCatalogView({ store, selection, onSelect, onSave, onSaveMany, onDelete }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  const activities = store.active("activities");
  const selectedActivity = store.get("activities", selection.activityId);
  const allowCombinations = isBoulderingActivity(selectedActivity);
  const trainingTypes = store
    .active("training_types")
    .filter((item) => item.activity_id === selection.activityId);
  const scopedExercises = store
    .active("exercises")
    .filter((item) => item.training_type_id === selection.trainingTypeId)
    .sort((a, b) => Number(a.display_order || 0) - Number(b.display_order || 0));
  const allExercises = store.active("exercises");
  const combinations = store
    .active("boulder_combinations")
    .filter((item) => item.training_type_id === selection.trainingTypeId);
  const selectedCombinationId = allowCombinations ? selection.comboId : null;
  const comboLinks = store
    .active("boulder_combination_exercises")
    .filter((row) => row.boulder_combination_id === selectedCombinationId)
    .sort((a, b) => Number(a.display_order || 0) - Number(b.display_order || 0));
  const exerciseById = Object.fromEntries(allExercises.map((exercise) => [exercise.id, exercise]));
  const exercises = selectedCombinationId
    ? comboLinks.map((link) => exerciseById[link.exercise_id]).filter(Boolean)
    : scopedExercises;
  if (selection.comboId && !allowCombinations) {
    onSelect({ comboId: null });
    return;
  }

  if (!selection.activityId && activities.length > 0) {
    onSelect({ activityId: activities[0].id, trainingTypeId: null, comboId: null });
    return;
  }
  if (!selection.trainingTypeId && trainingTypes.length > 0) {
    onSelect({ trainingTypeId: trainingTypes[0].id, comboId: null });
    return;
  }
  root.innerHTML = renderWorkspaceShell({
    title: "Catalog",
    description: "Browse activities, manage training structure, and edit exercise/combo details.",
    bodyHTML: `
    <div class="workspace-grid workspace-stage-grid catalog-grid">
      <section class="pane workspace-pane-list">
        <h2>Activities</h2>
        <form id="new-activity-form" class="inline-form">
          <input id="new-activity-name" class="input" type="text" placeholder="New activity" maxlength="${MAX_TEXT_LENGTH}" required />
          <button class="btn primary" type="submit">Add</button>
        </form>
        ${renderList("activity-list", activities, selection.activityId)}
      </section>

      <section class="pane workspace-pane-list">
        <h2>Training Types</h2>
        <form id="new-training-type-form" class="inline-form">
          <input id="new-training-type-name" class="input" type="text" placeholder="New training type" maxlength="${MAX_TEXT_LENGTH}" required ${selection.activityId ? "" : "disabled"} />
          <button class="btn primary" type="submit" ${selection.activityId ? "" : "disabled"}>Add</button>
        </form>
        ${renderList("training-type-list", trainingTypes, selection.trainingTypeId)}
      </section>

      <section class="pane workspace-pane-list">
        <h2>Boulder Combinations</h2>
        <form id="new-combination-form" class="inline-form">
          <input id="new-combination-name" class="input" type="text" placeholder="New combination" maxlength="${MAX_TEXT_LENGTH}" required ${
            selection.trainingTypeId && allowCombinations ? "" : "disabled"
          } />
          <button class="btn primary" type="submit" ${selection.trainingTypeId && allowCombinations ? "" : "disabled"}>Add</button>
        </form>
        ${allowCombinations ? renderList("combination-list", combinations, selectedCombinationId) : `<p class="muted">Boulder combinations are available only under bouldering activities.</p>`}

        <h2 style="margin-top: 14px;">${selectedCombinationId ? "Combination Exercises" : "Exercises"}</h2>
        <form id="new-exercise-form" class="inline-form">
          <input id="new-exercise-name" class="input" type="text" placeholder="New exercise" maxlength="${MAX_TEXT_LENGTH}" required ${selection.trainingTypeId ? "" : "disabled"} />
          <button class="btn primary" type="submit" ${selection.trainingTypeId ? "" : "disabled"}>Add</button>
        </form>
        ${renderList("exercise-list", exercises, selection.exerciseId)}
      </section>
    </div>

    <section class="pane workspace-pane-edit">
      ${renderCatalogEditorPane(store, selection, allExercises)}
    </section>
  `
  });

  bindListClicks("activity-list", "activityId", onSelect);
  bindListClicks("training-type-list", "trainingTypeId", onSelect);
  bindListClicks("exercise-list", "exerciseId", onSelect);
  bindListClicks("combination-list", "comboId", onSelect);

  bindCreateHandlers({ store, selection, onSave, allowCombinations });
  bindEditHandlers({ store, selection, onSave, onSaveMany, onDelete });
}

function bindCreateHandlers({ store, selection, onSave, allowCombinations }) {
  const newActivityForm = document.getElementById("new-activity-form");
  newActivityForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!beginFormSubmit(newActivityForm)) {
      return;
    }
    try {
    const name = sanitizedValue("new-activity-name");
    if (!name) {
      return;
    }
    if (hasNameConflict(store.active("activities"), name)) {
      showToast("Duplicate activity name", "error");
      return;
    }

    await onSave({
      entity: "activities",
      id: crypto.randomUUID(),
      payload: { name }
    });
    showToast("Activity saved", "success");
    } finally {
      endFormSubmit(newActivityForm);
    }
  });

  const newTrainingTypeForm = document.getElementById("new-training-type-form");
  newTrainingTypeForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!beginFormSubmit(newTrainingTypeForm)) {
      return;
    }
    try {
    const name = sanitizedValue("new-training-type-name");
    if (!name || !selection.activityId) {
      return;
    }
    if (hasNameConflict(trainingTypesForActivity(store, selection.activityId), name)) {
      showToast("Duplicate training type in activity", "error");
      return;
    }

    await onSave({
      entity: "training_types",
      id: crypto.randomUUID(),
      payload: {
        activity_id: selection.activityId,
        name,
        area: null,
        type_description: null
      }
    });
    showToast("Training type saved", "success");
    } finally {
      endFormSubmit(newTrainingTypeForm);
    }
  });

  const newExerciseForm = document.getElementById("new-exercise-form");
  newExerciseForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!beginFormSubmit(newExerciseForm)) {
      return;
    }
    try {
    const name = sanitizedValue("new-exercise-name");
    if (!name || !selection.trainingTypeId) {
      return;
    }
    if (hasNameConflict(exercisesForTrainingType(store, selection.trainingTypeId), name)) {
      showToast("Duplicate exercise in training type", "error");
      return;
    }

    await onSave({
      entity: "exercises",
      id: crypto.randomUUID(),
      payload: {
        training_type_id: selection.trainingTypeId,
        name,
        area: null,
        display_order: 0,
        exercise_description: null,
        reps_text: null,
        duration_text: null,
        sets_text: null,
        rest_text: null,
        notes: null
      }
    });
    showToast("Exercise saved", "success");
    } finally {
      endFormSubmit(newExerciseForm);
    }
  });

  const newCombinationForm = document.getElementById("new-combination-form");
  newCombinationForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!allowCombinations) {
      showToast("Boulder combinations can only be added under bouldering activity", "error");
      return;
    }
    if (!beginFormSubmit(newCombinationForm)) {
      return;
    }
    try {
    const name = sanitizedValue("new-combination-name");
    if (!name || !selection.trainingTypeId) {
      return;
    }
    if (hasNameConflict(combinationsForTrainingType(store, selection.trainingTypeId), name)) {
      showToast("Duplicate combination in training type", "error");
      return;
    }

    await onSave({
      entity: "boulder_combinations",
      id: crypto.randomUUID(),
      payload: {
        training_type_id: selection.trainingTypeId,
        name,
        combo_description: null
      }
    });
    showToast("Combination saved", "success");
    } finally {
      endFormSubmit(newCombinationForm);
    }
  });
}

function bindEditHandlers({ store, selection, onSave, onSaveMany, onDelete }) {
  const trainingForm = document.getElementById("training-type-editor");
  trainingForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const id = selection.trainingTypeId;
    if (!id) {
      return;
    }

    const current = store.get("training_types", id);
    if (hasNameConflict(trainingTypesForActivity(store, current?.activity_id || selection.activityId), sanitizedValue("training-type-name"), id)) {
      showToast("Duplicate training type in activity", "error");
      return;
    }
    await onSave({
      entity: "training_types",
      id,
      payload: {
        activity_id: current?.activity_id || selection.activityId,
        name: sanitizedValue("training-type-name"),
        area: optionalSanitizedValue("training-type-area"),
        type_description: optionalSanitizedValue("training-type-description")
      }
    });
    showToast("Training type updated", "success");
  });

  document.getElementById("training-type-delete")?.addEventListener("click", async () => {
    if (!selection.trainingTypeId) {
      return;
    }
    const row = store.get("training_types", selection.trainingTypeId);
    if (!confirmDelete("training type", row?.name || "this item")) {
      return;
    }
    await onDelete({ entity: "training_types", id: selection.trainingTypeId });
    showToast("Training type deleted", "info", {
      label: "Undo",
      onClick: async () => {
        await onSave({
          entity: "training_types",
          id: row?.id || selection.trainingTypeId,
          payload: {
            activity_id: row.activity_id || selection.activityId,
            name: row.name || "Recovered training type",
            area: row.area ?? null,
            type_description: row.type_description ?? null
          }
        });
        showToast("Training type restored", "success");
      }
    });
  });

  const exerciseForm = document.getElementById("exercise-editor");
  exerciseForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const id = selection.exerciseId;
    if (!id) {
      return;
    }

    const current = store.get("exercises", id);
    if (hasNameConflict(exercisesForTrainingType(store, current?.training_type_id || selection.trainingTypeId), sanitizedValue("exercise-name"), id)) {
      showToast("Duplicate exercise in training type", "error");
      return;
    }
    await onSave({
      entity: "exercises",
      id,
      payload: {
        training_type_id: current?.training_type_id || selection.trainingTypeId,
        name: sanitizedValue("exercise-name"),
        area: optionalSanitizedValue("exercise-area"),
        display_order: Number(document.getElementById("exercise-order")?.value || "0"),
        exercise_description: optionalSanitizedValue("exercise-description"),
        reps_text: optionalSanitizedValue("exercise-reps"),
        duration_text: optionalSanitizedValue("exercise-duration"),
        sets_text: optionalSanitizedValue("exercise-sets"),
        rest_text: optionalSanitizedValue("exercise-rest"),
        notes: optionalSanitizedValue("exercise-notes")
      }
    });
    showToast("Exercise updated", "success");
  });

  document.getElementById("exercise-delete")?.addEventListener("click", async () => {
    if (!selection.exerciseId) {
      return;
    }
    const row = store.get("exercises", selection.exerciseId);
    if (!confirmDelete("exercise", row?.name || "this item")) {
      return;
    }
    await onDelete({ entity: "exercises", id: selection.exerciseId });
    showToast("Exercise deleted", "info", {
      label: "Undo",
      onClick: async () => {
        await onSave({
          entity: "exercises",
          id: row?.id || selection.exerciseId,
          payload: {
            training_type_id: row.training_type_id || selection.trainingTypeId,
            name: row.name || "Recovered exercise",
            area: row.area ?? null,
            display_order: Number(row.display_order || 0),
            exercise_description: row.exercise_description ?? null,
            reps_text: row.reps_text ?? null,
            duration_text: row.duration_text ?? null,
            sets_text: row.sets_text ?? null,
            rest_text: row.rest_text ?? null,
            notes: row.notes ?? null
          }
        });
        showToast("Exercise restored", "success");
      }
    });
  });

  const comboForm = document.getElementById("combination-editor");
  wireCombinationExercisePicker();
  comboForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const comboId = selection.comboId;
    if (!comboId) {
      return;
    }
    if (comboSaveInFlightId === comboId) {
      return;
    }
    if (!beginFormSubmit(comboForm)) {
      return;
    }
    comboSaveInFlightId = comboId;
    setFormBusyLabel(comboForm, "Saving...");

    try {
      const combo = store.get("boulder_combinations", comboId);
      if (hasNameConflict(combinationsForTrainingType(store, combo?.training_type_id || selection.trainingTypeId), sanitizedValue("combo-name"), comboId)) {
        showToast("Duplicate combination in training type", "error");
        return;
      }
      const selectedOrderedIds = [...document.querySelectorAll("#combo-linked-order li[data-id]")]
        .map((item) => String(item.dataset.id || ""))
        .filter(Boolean);
      const selectedIds = new Set(selectedOrderedIds);

      const existingLinks = store
        .active("boulder_combination_exercises")
        .filter((row) => row.boulder_combination_id === comboId);

      const existingByExerciseId = new Map(existingLinks.map((row) => [row.exercise_id, row]));
      const mutations = [
        {
          entity: "boulder_combinations",
          id: comboId,
          payload: {
            training_type_id: combo?.training_type_id || selection.trainingTypeId,
            name: sanitizedValue("combo-name"),
            combo_description: optionalSanitizedValue("combo-description")
          }
        }
      ];

      for (let index = 0; index < selectedOrderedIds.length; index += 1) {
        const exerciseId = selectedOrderedIds[index];
        const currentLink = existingByExerciseId.get(exerciseId);
        mutations.push({
          entity: "boulder_combination_exercises",
          id: currentLink?.id || crypto.randomUUID(),
          payload: {
            boulder_combination_id: comboId,
            exercise_id: exerciseId,
            display_order: index
          }
        });
      }

      for (const link of existingLinks) {
        if (selectedIds.has(link.exercise_id)) {
          continue;
        }
        mutations.push({
          entity: "boulder_combination_exercises",
          id: link.id,
          type: "delete",
          payload: null
        });
      }

      if (typeof onSaveMany === "function" && mutations.length > 1) {
        await onSaveMany({ mutations });
      } else {
        for (const mutation of mutations) {
          if (mutation.type === "delete") {
            await onDelete({ entity: mutation.entity, id: mutation.id });
          } else {
            await onSave({ entity: mutation.entity, id: mutation.id, payload: mutation.payload });
          }
        }
      }

      showToast("Combination updated", "success");
    } finally {
      comboSaveInFlightId = null;
      const liveForm = document.getElementById("combination-editor");
      endFormSubmit(liveForm);
      setFormBusyLabel(liveForm, null);
    }
  });

  document.getElementById("combo-delete")?.addEventListener("click", async () => {
    if (!selection.comboId) {
      return;
    }
    const row = store.get("boulder_combinations", selection.comboId);
    if (!confirmDelete("combination", row?.name || "this item")) {
      return;
    }
    await onDelete({ entity: "boulder_combinations", id: selection.comboId });
    showToast("Combination deleted", "info", {
      label: "Undo",
      onClick: async () => {
        await onSave({
          entity: "boulder_combinations",
          id: row?.id || selection.comboId,
          payload: {
            training_type_id: row.training_type_id || selection.trainingTypeId,
            name: row.name || "Recovered combination",
            combo_description: row.combo_description ?? null
          }
        });
        showToast("Combination restored", "success");
      }
    });
  });
}

function renderList(id, rows, selectedId) {
  if (!rows.length) {
    return `<p class="muted">No items yet.</p>`;
  }

  return `
    <ul id="${id}" class="select-list">
      ${rows
        .map(
          (row) =>
            `<li><button type="button" data-id="${row.id}" class="list-btn${row.id === selectedId ? " active" : ""}">${escapeHTML(
              row.name || row.id
            )}</button></li>`
        )
        .join("")}
    </ul>
  `;
}

function renderTrainingEditor(trainingType) {
  if (!trainingType) {
    return `<p class="muted">Choose a training type.</p>`;
  }

  return `
    <form id="training-type-editor" class="editor-form">
      <label>Name <input id="training-type-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(
        trainingType.name || ""
      )}" required /></label>
      <label>Area <input id="training-type-area" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(
        trainingType.area || ""
      )}" /></label>
      <label>Description <textarea id="training-type-description" class="input" rows="3" maxlength="400">${escapeHTML(
        trainingType.type_description || ""
      )}</textarea></label>
      <div class="actions">
        <button class="btn primary" type="submit">Save</button>
        <button id="training-type-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>
      </div>
    </form>
  `;
}

function renderExerciseEditor(exercise) {
  if (!exercise) {
    return `<p class="muted">Choose an exercise.</p>`;
  }

  return `
    <form id="exercise-editor" class="editor-form">
      <label>Name <input id="exercise-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(exercise.name || "")}" required /></label>
      <label>Area <input id="exercise-area" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(exercise.area || "")}" /></label>
      <label>Order <input id="exercise-order" class="input" type="number" value="${Number(exercise.display_order || 0)}" /></label>
      <label>Description <textarea id="exercise-description" class="input" rows="2" maxlength="400">${escapeHTML(exercise.exercise_description || "")}</textarea></label>
      <label>Reps <input id="exercise-reps" class="input" type="text" maxlength="40" value="${escapeHTML(exercise.reps_text || "")}" /></label>
      <label>Duration <input id="exercise-duration" class="input" type="text" maxlength="40" value="${escapeHTML(exercise.duration_text || "")}" /></label>
      <label>Sets <input id="exercise-sets" class="input" type="text" maxlength="40" value="${escapeHTML(exercise.sets_text || "")}" /></label>
      <label>Rest <input id="exercise-rest" class="input" type="text" maxlength="40" value="${escapeHTML(exercise.rest_text || "")}" /></label>
      <label>Notes <textarea id="exercise-notes" class="input" rows="2" maxlength="400">${escapeHTML(exercise.notes || "")}</textarea></label>
      <div class="actions">
        <button class="btn primary" type="submit">Save</button>
        <button id="exercise-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>
      </div>
    </form>
  `;
}

function renderCombinationEditor(store, selection, exercises) {
  const combo = store.get("boulder_combinations", selection.comboId);
  if (!combo) {
    return `<p class="muted">Choose a combination to manage linked exercises.</p>`;
  }
  const isSaving = comboSaveInFlightId === combo.id;

  const links = store
    .active("boulder_combination_exercises")
    .filter((item) => item.boulder_combination_id === combo.id)
    .sort((a, b) => Number(a.display_order || 0) - Number(b.display_order || 0));
  const linkedExerciseIDs = new Set(links.map((item) => item.exercise_id));
  const exerciseById = Object.fromEntries(exercises.map((exercise) => [exercise.id, exercise]));
  const linkedExercises = links.map((link) => exerciseById[link.exercise_id]).filter(Boolean);
  const availableExercises = exercises.filter((exercise) => !linkedExerciseIDs.has(exercise.id));

  return `
    <form id="combination-editor" class="editor-form">
      <label>Name <input id="combo-name" class="input" type="text" maxlength="${MAX_TEXT_LENGTH}" value="${escapeHTML(combo.name || "")}" required /></label>
      <label>Description <textarea id="combo-description" class="input" rows="2" maxlength="400">${escapeHTML(combo.combo_description || "")}</textarea></label>
      <label>Search exercises
        <input id="combo-exercise-search" class="input" type="search" placeholder="Find exercise..." />
      </label>
      <div class="workspace-grid plans-exercise-grid">
        <section class="pane">
          <h4>Exercises</h4>
          <div id="combo-available-list" class="exercise-card-grid">
            ${availableExercises
              .map(
                (exercise) => `
                  <article class="exercise-card">
                    <div class="exercise-card-head">
                      <div class="exercise-card-copy">
                        <h5 title="${escapeHTML(exercise.name || "Exercise")}">${escapeHTML(exercise.name || "Exercise")}</h5>
                      </div>
                      <button class="icon-btn exercise-toggle-btn" type="button" data-combo-add="${exercise.id}" data-label="${escapeHTML(
                        exercise.name || "Exercise"
                      )}" aria-label="Add exercise">${PLUS_ICON}</button>
                    </div>
                  </article>
                `
              )
              .join("")}
          </div>
        </section>
        <section class="pane">
          <h4>Selected Order</h4>
          <ul id="combo-linked-order" class="select-list">
            ${linkedExercises
              .map(
                (exercise, index) => `
                  <li data-id="${exercise.id}">
                    <div class="row">
                      <span class="selection-pill">${index + 1}</span>
                      <strong title="${escapeHTML(exercise.name || "Exercise")}">${escapeHTML(exercise.name || "Exercise")}</strong>
                      <span style="margin-left:auto"></span>
                      <button class="icon-btn" type="button" data-combo-move="${exercise.id}" data-direction="up" aria-label="Move up">${CHEVRON_UP_ICON}</button>
                      <button class="icon-btn" type="button" data-combo-move="${exercise.id}" data-direction="down" aria-label="Move down">${CHEVRON_DOWN_ICON}</button>
                      <button class="icon-btn destructive" type="button" data-combo-remove="${exercise.id}" aria-label="Remove exercise">${DELETE_ICON}</button>
                    </div>
                  </li>
                `
              )
              .join("")}
          </ul>
        </section>
      </div>
      <div class="actions">
        <button class="btn primary" type="submit" ${isSaving ? "disabled" : ""}>${isSaving ? "Saving..." : "Save"}</button>
        <button id="combo-delete" class="btn destructive" type="button">${DELETE_ICON}<span>Delete</span></button>
      </div>
    </form>
  `;
}

function renderCatalogEditorPane(store, selection, exercises) {
  const selectedExercise = store.get("exercises", selection.exerciseId);
  const selectedTrainingType = store.get("training_types", selection.trainingTypeId);
  const selectedCombination = store.get("boulder_combinations", selection.comboId);

  let editorTitle = "Training Type Editor";
  let editorBody = renderTrainingEditor(selectedTrainingType);
  if (selectedCombination && !selectedExercise) {
    editorTitle = "Combination Editor";
    editorBody = renderCombinationEditor(store, selection, exercises);
  } else if (selectedExercise) {
    editorTitle = "Exercise Editor";
    editorBody = renderExerciseEditor(selectedExercise);
  }

  return `
    <h3>${editorTitle}</h3>
    ${editorBody}
  `;
}

function bindListClicks(listId, key, onSelect) {
  document.getElementById(listId)?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-id]");
    if (!button) {
      return;
    }

    const value = button.dataset.id;
    if (!value) {
      return;
    }

    if (key === "activityId") {
      onSelect({ activityId: value, trainingTypeId: null, exerciseId: null, comboId: null });
      return;
    }

    if (key === "trainingTypeId") {
      onSelect({ trainingTypeId: value, exerciseId: null, comboId: null });
      return;
    }

    if (key === "comboId") {
      onSelect({ comboId: value, exerciseId: null });
      return;
    }

    onSelect({ [key]: value });
  });
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

function hasNameConflict(rows, candidateName, ignoreID = null) {
  const normalizedCandidate = candidateName.trim().toLocaleLowerCase();
  return rows.some((row) => {
    if (ignoreID && row.id === ignoreID) {
      return false;
    }
    return String(row.name || "").trim().toLocaleLowerCase() === normalizedCandidate;
  });
}

function trainingTypesForActivity(store, activityId) {
  return store.active("training_types").filter((item) => item.activity_id === activityId);
}

function exercisesForTrainingType(store, trainingTypeId) {
  return store.active("exercises").filter((item) => item.training_type_id === trainingTypeId);
}

function combinationsForTrainingType(store, trainingTypeId) {
  return store.active("boulder_combinations").filter((item) => item.training_type_id === trainingTypeId);
}

function wireCombinationExercisePicker() {
  const searchInput = document.getElementById("combo-exercise-search");
  const availableList = document.getElementById("combo-available-list");
  const selectedList = document.getElementById("combo-linked-order");

  if (searchInput && availableList) {
    searchInput.addEventListener("input", () => {
      const needle = String(searchInput.value || "").trim().toLocaleLowerCase();
      for (const card of availableList.querySelectorAll(".exercise-card")) {
        const label = String(card.querySelector("h5")?.textContent || "").toLocaleLowerCase();
        card.classList.toggle("hidden", Boolean(needle && !label.includes(needle)));
      }
    });
  }

  availableList?.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-combo-add]");
    if (!button || !selectedList) {
      return;
    }
    const id = String(button.dataset.comboAdd || "");
    if (!id || selectedList.querySelector(`li[data-id='${id}']`)) {
      return;
    }
    const label = String(button.dataset.label || "Exercise");
    const item = document.createElement("li");
    item.dataset.id = id;
    item.innerHTML = `<div class="row"><span class="selection-pill"></span><strong title="${escapeHTML(label)}">${escapeHTML(
      label
    )}</strong><span style="margin-left:auto"></span><button class="icon-btn" type="button" data-combo-move="${id}" data-direction="up" aria-label="Move up">${CHEVRON_UP_ICON}</button><button class="icon-btn" type="button" data-combo-move="${id}" data-direction="down" aria-label="Move down">${CHEVRON_DOWN_ICON}</button><button class="icon-btn destructive" type="button" data-combo-remove="${id}" aria-label="Remove exercise">${DELETE_ICON}</button></div>`;
    selectedList.append(item);
    renumberComboLinkedExercises();
    button.closest(".exercise-card")?.remove();
  });

  selectedList?.addEventListener("click", (event) => {
    const removeButton = event.target.closest("button[data-combo-remove]");
    if (removeButton) {
      const row = removeButton.closest("li[data-id]");
      row?.remove();
      renumberComboLinkedExercises();
      return;
    }
    const moveButton = event.target.closest("button[data-combo-move]");
    if (!moveButton || !selectedList) {
      return;
    }
    const id = String(moveButton.dataset.comboMove || "");
    const direction = String(moveButton.dataset.direction || "");
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
    renumberComboLinkedExercises();
  });

  renumberComboLinkedExercises();
}

function renumberComboLinkedExercises() {
  const rows = [...document.querySelectorAll("#combo-linked-order li[data-id]")];
  rows.forEach((row, index) => {
    const pill = row.querySelector(".selection-pill");
    if (pill) {
      pill.textContent = String(index + 1);
    }
  });
}

function isBoulderingActivity(activity) {
  const name = String(activity?.name || "").toLocaleLowerCase();
  return name.includes("boulder");
}

function confirmDelete(typeLabel, name) {
  return window.confirm(`Delete ${typeLabel} "${name}"? This cannot be undone.`);
}

function beginFormSubmit(form) {
  if (!form) {
    return false;
  }
  if (form.dataset.submitting === "true") {
    return false;
  }
  form.dataset.submitting = "true";
  const submitButton = form.querySelector("button[type='submit']");
  if (submitButton instanceof HTMLButtonElement) {
    submitButton.disabled = true;
  }
  return true;
}

function endFormSubmit(form) {
  if (!form) {
    return;
  }
  form.dataset.submitting = "false";
  const submitButton = form.querySelector("button[type='submit']");
  if (submitButton instanceof HTMLButtonElement) {
    submitButton.disabled = false;
  }
}

function setFormBusyLabel(form, label) {
  if (!form) {
    return;
  }
  const submitButton = form.querySelector("button[type='submit']");
  if (!(submitButton instanceof HTMLButtonElement)) {
    return;
  }
  if (!submitButton.dataset.defaultLabel) {
    submitButton.dataset.defaultLabel = submitButton.textContent || "Save";
  }
  submitButton.textContent = label || submitButton.dataset.defaultLabel;
}
