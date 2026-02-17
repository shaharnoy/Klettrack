const REQUIRED_HEADERS = [
  "plan_name",
  "plan_kind",
  "plan_start_date",
  "day_date",
  "weekday",
  "day_type",
  "day_notes",
  "exercise_order",
  "exercise_name",
  "activity_name",
  "training_type_name",
  "exercise_id"
];

export function parsePlanCsv(text) {
  const csvText = String(text || "");
  if (!csvText.trim()) {
    return { planGroups: [], warnings: [], errors: ["CSV file is empty."] };
  }

  const rows = parseCsvRows(csvText);
  if (!rows.length) {
    return { planGroups: [], warnings: [], errors: ["CSV file is empty."] };
  }

  const headers = rows[0].map((value) => normalizeHeader(value));
  const indexByHeader = new Map(headers.map((header, index) => [header, index]));
  const missingHeaders = REQUIRED_HEADERS.filter((header) => !indexByHeader.has(header));
  if (missingHeaders.length > 0) {
    return {
      planGroups: [],
      warnings: [],
      errors: [
        `Missing required headers: ${missingHeaders.join(", ")}`
      ]
    };
  }

  const warnings = [];
  const groupMap = new Map();

  for (let rowIndex = 1; rowIndex < rows.length; rowIndex += 1) {
    const rowCells = rows[rowIndex];
    if (!rowCells.some((value) => String(value || "").trim().length > 0)) {
      continue;
    }

    const lineNumber = rowIndex + 1;
    const row = Object.fromEntries(
      REQUIRED_HEADERS.map((header) => [header, normalizeCell(rowCells[indexByHeader.get(header)] || "")])
    );

    const parsedDayDate = parseDateOnly(row.day_date);
    if (!parsedDayDate) {
      warnings.push(`Line ${lineNumber}: invalid day_date \"${row.day_date}\" (expected YYYY-MM-DD), row skipped.`);
      continue;
    }

    const parsedStartDate = parseDateOnly(row.plan_start_date);
    if (row.plan_start_date && !parsedStartDate) {
      warnings.push(
        `Line ${lineNumber}: invalid plan_start_date \"${row.plan_start_date}\" (expected YYYY-MM-DD), fallback will be used.`
      );
    }

    if (row.exercise_order) {
      const orderValue = Number.parseInt(row.exercise_order, 10);
      if (!Number.isInteger(orderValue) || orderValue <= 0) {
        warnings.push(`Line ${lineNumber}: invalid exercise_order \"${row.exercise_order}\" (using row order).`);
      }
    }

    const planName = row.plan_name || "Imported Plan";
    const groupKey = `${planName}::${parsedStartDate || ""}`;
    if (!groupMap.has(groupKey)) {
      groupMap.set(groupKey, {
        key: groupKey,
        planName,
        planKindName: row.plan_kind || "",
        planStartDate: parsedStartDate,
        rows: []
      });
    }

    groupMap.get(groupKey).rows.push({
      lineNumber,
      dayDate: parsedDayDate,
      dayTypeName: row.day_type || "",
      dayNotes: row.day_notes || "",
      exerciseOrderRaw: row.exercise_order || "",
      exerciseName: row.exercise_name || "",
      exerciseIdRaw: row.exercise_id || "",
      activityName: row.activity_name || "",
      trainingTypeName: row.training_type_name || "",
      weekday: row.weekday || ""
    });
  }

  const planGroups = [...groupMap.values()]
    .map((group) => buildGroupStructure(group))
    .filter((group) => group.days.length > 0)
    .sort((left, right) => {
      const leftStart = left.planStartDate || left.earliestDayDate || "";
      const rightStart = right.planStartDate || right.earliestDayDate || "";
      return `${left.planName}|${leftStart}`.localeCompare(`${right.planName}|${rightStart}`, undefined, {
        sensitivity: "base"
      });
    });

  if (planGroups.length === 0) {
    return {
      planGroups: [],
      warnings,
      errors: ["No valid day rows were found in this CSV file."]
    };
  }

  return {
    planGroups,
    warnings,
    errors: []
  };
}

export function buildPlanImportMutations({ group, store }) {
  if (!group) {
    throw new Error("Missing import group.");
  }

  const plans = store.active("plans");
  const planKinds = store.active("plan_kinds");
  const dayTypes = store.active("day_types");
  const activities = store.active("activities");
  const trainingTypes = store.active("training_types");
  const exercises = store.active("exercises");

  const existingPlanNames = new Set(plans.map((plan) => normalizeName(plan.name)));
  const nextPlanName = resolveUniquePlanName(group.planName || "Imported Plan", existingPlanNames);

  const mutations = [];
  const placeholderSummary = {
    planKinds: 0,
    dayTypes: 0,
    activities: 0,
    trainingTypes: 0,
    exercises: 0
  };

  const planKindByName = new Map(planKinds.map((item) => [normalizeName(item.name), item]));
  const dayTypeByName = new Map(dayTypes.map((item) => [normalizeName(item.name), item]));
  const activityByName = new Map(activities.map((item) => [normalizeName(item.name), item]));
  const trainingTypeByName = new Map(trainingTypes.map((item) => [normalizeName(item.name), item]));
  const exerciseById = new Map(exercises.map((item) => [String(item.id), item]));
  const exerciseByName = new Map(exercises.map((item) => [normalizeName(item.name), item]));

  const createdActivities = new Map();
  const createdTrainingTypes = new Map();
  const createdExercises = new Map();
  const createdDayTypes = new Map();

  const placeholderActivityName = "Imported Activity";
  const placeholderTrainingTypeName = "Imported Training Type";

  function ensurePlanKind(name) {
    const normalized = normalizeName(name);
    if (!normalized) {
      return null;
    }
    if (planKindByName.has(normalized)) {
      return planKindByName.get(normalized).id;
    }

    const id = crypto.randomUUID();
    const nextOrder = planKinds.length + placeholderSummary.planKinds + 1;
    mutations.push({
      entity: "plan_kinds",
      id,
      payload: {
        key: `imported-${slugify(name || `kind-${id.slice(0, 8)}`)}`,
        name,
        total_weeks: null,
        is_repeating: false,
        display_order: nextOrder
      }
    });
    const created = { id, name };
    planKindByName.set(normalized, created);
    placeholderSummary.planKinds += 1;
    return id;
  }

  function ensureDayType(name) {
    const normalized = normalizeName(name);
    if (!normalized) {
      return null;
    }
    if (dayTypeByName.has(normalized)) {
      return dayTypeByName.get(normalized).id;
    }
    if (createdDayTypes.has(normalized)) {
      return createdDayTypes.get(normalized);
    }

    const id = crypto.randomUUID();
    const nextOrder = dayTypes.length + placeholderSummary.dayTypes + 1;
    mutations.push({
      entity: "day_types",
      id,
      payload: {
        key: `imported-${slugify(name || `day-type-${id.slice(0, 8)}`)}`,
        name,
        display_order: nextOrder,
        color_key: "gray",
        is_default: false,
        is_hidden: false
      }
    });
    createdDayTypes.set(normalized, id);
    dayTypeByName.set(normalized, { id, name });
    placeholderSummary.dayTypes += 1;
    return id;
  }

  function ensureActivity(name) {
    const resolvedName = name || placeholderActivityName;
    const normalized = normalizeName(resolvedName);
    if (activityByName.has(normalized)) {
      return activityByName.get(normalized).id;
    }
    if (createdActivities.has(normalized)) {
      return createdActivities.get(normalized);
    }

    const id = crypto.randomUUID();
    mutations.push({
      entity: "activities",
      id,
      payload: {
        name: resolvedName
      }
    });
    createdActivities.set(normalized, id);
    activityByName.set(normalized, { id, name: resolvedName });
    placeholderSummary.activities += 1;
    return id;
  }

  function ensureTrainingType(activityId, name) {
    const resolvedName = name || placeholderTrainingTypeName;
    const key = `${activityId}|${normalizeName(resolvedName)}`;
    if (createdTrainingTypes.has(key)) {
      return createdTrainingTypes.get(key);
    }

    const existing = trainingTypes.find(
      (item) => String(item.activity_id || "") === String(activityId || "") && normalizeName(item.name) === normalizeName(resolvedName)
    );
    if (existing) {
      return existing.id;
    }

    const id = crypto.randomUUID();
    mutations.push({
      entity: "training_types",
      id,
      payload: {
        activity_id: activityId || null,
        name: resolvedName,
        area: null,
        type_description: "Imported placeholder"
      }
    });
    createdTrainingTypes.set(key, id);
    trainingTypeByName.set(normalizeName(resolvedName), { id, name: resolvedName, activity_id: activityId || null });
    placeholderSummary.trainingTypes += 1;
    return id;
  }

  function ensureExercise({ rawExerciseId, exerciseName, trainingTypeName, activityName, fallbackCounter }) {
    const trimmedId = String(rawExerciseId || "").trim();
    if (trimmedId && exerciseById.has(trimmedId)) {
      return exerciseById.get(trimmedId).id;
    }

    const normalizedName = normalizeName(exerciseName);
    if (normalizedName && exerciseByName.has(normalizedName)) {
      return exerciseByName.get(normalizedName).id;
    }

    const resolvedName = exerciseName || `Imported Exercise ${fallbackCounter}`;
    const activityId = ensureActivity(activityName || placeholderActivityName);
    const trainingTypeId = ensureTrainingType(activityId, trainingTypeName || placeholderTrainingTypeName);
    const cacheKey = `${trainingTypeId}|${normalizeName(resolvedName)}`;
    if (createdExercises.has(cacheKey)) {
      return createdExercises.get(cacheKey);
    }

    const id = crypto.randomUUID();
    mutations.push({
      entity: "exercises",
      id,
      payload: {
        training_type_id: trainingTypeId,
        name: resolvedName,
        area: null,
        display_order: 0,
        exercise_description: "Imported placeholder",
        reps_text: null,
        duration_text: null,
        sets_text: null,
        rest_text: null,
        notes: "Imported placeholder"
      }
    });
    createdExercises.set(cacheKey, id);
    exerciseById.set(id, { id, name: resolvedName, training_type_id: trainingTypeId });
    exerciseByName.set(normalizeName(resolvedName), { id, name: resolvedName, training_type_id: trainingTypeId });
    placeholderSummary.exercises += 1;
    return id;
  }

  const earliestDayDate = group.earliestDayDate;
  const startDate = group.planStartDate || earliestDayDate;
  if (!startDate) {
    throw new Error("No valid day rows were found in this CSV file.");
  }

  const planId = crypto.randomUUID();
  const planKindId = ensurePlanKind(group.planKindName || "");
  mutations.push({
    entity: "plans",
    id: planId,
    payload: {
      name: nextPlanName,
      kind_id: planKindId,
      start_date: `${startDate}T00:00:00.000Z`,
      recurring_chosen_exercises_by_weekday: {},
      recurring_exercise_order_by_weekday: {},
      recurring_day_type_id_by_weekday: {}
    }
  });

  let fallbackExerciseCounter = 1;
  let exerciseRowCount = 0;

  for (const day of group.days) {
    const chosenExerciseIds = [];
    const exerciseOrderById = {};
    const exerciseRows = day.exerciseRows
      .slice()
      .sort((left, right) => {
        const leftRank = Number.isInteger(left.exerciseOrder) ? left.exerciseOrder : Number.MAX_SAFE_INTEGER;
        const rightRank = Number.isInteger(right.exerciseOrder) ? right.exerciseOrder : Number.MAX_SAFE_INTEGER;
        if (leftRank !== rightRank) {
          return leftRank - rightRank;
        }
        return left.lineNumber - right.lineNumber;
      });

    for (const exerciseRow of exerciseRows) {
      const hasExercise =
        Boolean(exerciseRow.exerciseName) ||
        Boolean(exerciseRow.exerciseIdRaw) ||
        Boolean(exerciseRow.trainingTypeName) ||
        Boolean(exerciseRow.activityName);
      if (!hasExercise) {
        continue;
      }
      const exerciseId = ensureExercise({
        rawExerciseId: exerciseRow.exerciseIdRaw,
        exerciseName: exerciseRow.exerciseName,
        trainingTypeName: exerciseRow.trainingTypeName,
        activityName: exerciseRow.activityName,
        fallbackCounter: fallbackExerciseCounter
      });
      fallbackExerciseCounter += 1;
      chosenExerciseIds.push(exerciseId);
      exerciseOrderById[exerciseId] = chosenExerciseIds.length - 1;
      exerciseRowCount += 1;
    }

    mutations.push({
      entity: "plan_days",
      id: crypto.randomUUID(),
      payload: {
        plan_id: planId,
        day_date: `${day.dayDate}T00:00:00.000Z`,
        day_type_id: ensureDayType(day.dayTypeName || ""),
        chosen_exercise_ids: chosenExerciseIds,
        exercise_order_by_id: exerciseOrderById,
        daily_notes: day.dayNotes || null
      }
    });
  }

  return {
    mutations,
    planId,
    summary: {
      planName: nextPlanName,
      dayCount: group.days.length,
      exerciseCount: exerciseRowCount,
      placeholders: placeholderSummary,
      warnings: Array.isArray(group.warnings) ? [...group.warnings] : []
    }
  };
}

function buildGroupStructure(group) {
  const warnings = [];
  const dayMap = new Map();

  for (const row of group.rows) {
    if (!dayMap.has(row.dayDate)) {
      dayMap.set(row.dayDate, {
        dayDate: row.dayDate,
        dayTypeName: row.dayTypeName,
        dayNotes: row.dayNotes,
        exerciseRows: []
      });
    }

    const day = dayMap.get(row.dayDate);
    if (!day.dayTypeName && row.dayTypeName) {
      day.dayTypeName = row.dayTypeName;
    }
    if (!day.dayNotes && row.dayNotes) {
      day.dayNotes = row.dayNotes;
    }

    const parsedOrder = parseExerciseOrder(row.exerciseOrderRaw);
    if (row.exerciseOrderRaw && parsedOrder === null) {
      warnings.push(`Line ${row.lineNumber}: invalid exercise_order \"${row.exerciseOrderRaw}\" (using row order).`);
    }

    day.exerciseRows.push({
      lineNumber: row.lineNumber,
      exerciseOrder: parsedOrder,
      exerciseName: row.exerciseName,
      exerciseIdRaw: row.exerciseIdRaw,
      activityName: row.activityName,
      trainingTypeName: row.trainingTypeName
    });
  }

  const days = [...dayMap.values()].sort((left, right) => left.dayDate.localeCompare(right.dayDate));

  return {
    key: group.key,
    planName: group.planName,
    planKindName: group.planKindName,
    planStartDate: group.planStartDate,
    earliestDayDate: days[0]?.dayDate || null,
    days,
    warnings
  };
}

function parseCsvRows(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let inQuotes = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];

    if (char === '"') {
      if (inQuotes && next === '"') {
        cell += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (!inQuotes && char === ",") {
      row.push(cell);
      cell = "";
      continue;
    }

    if (!inQuotes && (char === "\n" || char === "\r")) {
      if (char === "\r" && next === "\n") {
        index += 1;
      }
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
      continue;
    }

    cell += char;
  }

  if (cell.length > 0 || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }

  return rows;
}

function normalizeHeader(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replaceAll(/\s+/g, "_");
}

function normalizeCell(value) {
  return String(value || "").trim();
}

function parseDateOnly(value) {
  const raw = String(value || "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    return null;
  }
  const parsed = new Date(`${raw}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return raw;
}

function parseExerciseOrder(value) {
  if (!value) {
    return null;
  }
  const parsed = Number.parseInt(String(value).trim(), 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return null;
  }
  return parsed;
}

function resolveUniquePlanName(basePlanName, existingNames) {
  const base = `${basePlanName || "Imported Plan"} (Imported)`;
  if (!existingNames.has(normalizeName(base))) {
    existingNames.add(normalizeName(base));
    return base;
  }

  let suffix = 2;
  while (suffix < 5000) {
    const candidate = `${base} ${suffix}`;
    const normalized = normalizeName(candidate);
    if (!existingNames.has(normalized)) {
      existingNames.add(normalized);
      return candidate;
    }
    suffix += 1;
  }
  return `${base} ${Date.now()}`;
}

function slugify(value) {
  const slug = String(value || "")
    .toLowerCase()
    .replaceAll(/[^a-z0-9]+/g, "-")
    .replaceAll(/^-+|-+$/g, "");
  return slug || "imported";
}

function normalizeName(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replaceAll(/\s+/g, " ");
}
