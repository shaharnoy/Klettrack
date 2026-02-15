function normalizeDateOnly(value) {
  if (!value) {
    return "";
  }
  return String(value).slice(0, 10);
}

function safeDateValue(value) {
  const date = new Date(value || "");
  if (Number.isNaN(date.getTime())) {
    return 0;
  }
  return date.getTime();
}

function includesNeedle(haystack, needle) {
  if (!needle) {
    return true;
  }
  return haystack.toLocaleLowerCase().includes(needle);
}

function sessionRows(store) {
  const sessionsById = new Map(store.active("sessions").map((session) => [session.id, session]));
  return store
    .active("session_items")
    .map((item) => {
      const session = sessionsById.get(item.session_id);
      return {
        id: item.id,
        recordType: "session",
        dateISO: session?.session_date || "",
        dateOnly: normalizeDateOnly(session?.session_date),
        exerciseName: item.exercise_name || "",
        climbType: "",
        grade: item.grade || "",
        feelsLikeGrade: "",
        angle: "",
        holdColor: "",
        ropeType: "",
        style: "",
        attempts: "",
        isWip: false,
        isPreviouslyClimbed: false,
        gym: "",
        reps: numberValue(item.reps),
        sets: numberValue(item.sets),
        duration: numberValue(item.duration),
        weightKg: numberValue(item.weight_kg),
        planId: item.plan_source_id || "",
        planName: item.plan_name || "",
        dayType: "",
        notes: item.notes || "",
        sourceLabel: "Exercise"
      };
    })
    .sort((left, right) => safeDateValue(right.dateISO) - safeDateValue(left.dateISO));
}

function climbRows(store) {
  return store
    .active("climb_entries")
    .map((entry) => ({
      id: entry.id,
      recordType: "climb",
      dateISO: entry.date_logged || "",
      dateOnly: normalizeDateOnly(entry.date_logged),
      exerciseName: "",
      climbType: entry.climb_type || "",
      grade: entry.grade || "",
      feelsLikeGrade: entry.feels_like_grade || "",
      angle: numberValue(entry.angle_degrees),
      holdColor: entry.hold_color || "",
      ropeType: entry.rope_climb_type || "",
      style: entry.style || "",
      attempts: numberValue(entry.attempts),
      isWip: Boolean(entry.is_work_in_progress),
      isPreviouslyClimbed: Boolean(entry.is_previously_climbed),
      gym: entry.gym || "",
      reps: "",
      sets: "",
      duration: "",
      weightKg: "",
      planId: "",
      planName: "",
      dayType: "",
      notes: entry.notes || "",
      sourceLabel: "Climb"
    }))
    .sort((left, right) => safeDateValue(right.dateISO) - safeDateValue(left.dateISO));
}

export function buildLogRows(store, mode) {
  const sessions = sessionRows(store);
  const climbs = climbRows(store);

  if (mode === "sessions") {
    return sessions;
  }
  if (mode === "climbs") {
    return climbs;
  }

  return [...sessions, ...climbs].sort((left, right) => safeDateValue(right.dateISO) - safeDateValue(left.dateISO));
}

export function filterLogRows(rows, filters) {
  const normalizedSearch = String(filters.search || "").trim().toLocaleLowerCase();
  const fromDate = String(filters.fromDate || "").trim();
  const toDate = String(filters.toDate || "").trim();
  const source = String(filters.source || "all");
  const gym = String(filters.gym || "");
  const style = String(filters.style || "");
  const grade = String(filters.grade || "");
  const climbType = String(filters.climbType || "");
  const onlyWip = Boolean(filters.onlyWip);

  return rows.filter((row) => {
    if (source !== "all" && row.recordType !== source) {
      return false;
    }

    if (fromDate && row.dateOnly < fromDate) {
      return false;
    }
    if (toDate && row.dateOnly > toDate) {
      return false;
    }

    if (onlyWip && !row.isWip) {
      return false;
    }

    if (gym && row.gym !== gym) {
      return false;
    }
    if (style && row.style !== style) {
      return false;
    }
    if (grade && row.grade !== grade) {
      return false;
    }
    if (climbType && row.climbType !== climbType) {
      return false;
    }

    if (!normalizedSearch) {
      return true;
    }

    const haystack = [
      row.sourceLabel,
      row.exerciseName,
      row.climbType,
      row.grade,
      row.feelsLikeGrade,
      row.style,
      row.gym,
      row.notes,
      row.planName
    ]
      .filter(Boolean)
      .join(" ")
      .toLocaleLowerCase();

    return includesNeedle(haystack, normalizedSearch);
  });
}

export function sortLogRows(rows, sortColumn = "dateOnly", sortDirection = "desc") {
  const direction = sortDirection === "asc" ? 1 : -1;
  return rows.slice().sort((left, right) => compareValues(left, right, sortColumn) * direction);
}

function compareValues(left, right, column) {
  if (column === "dateOnly") {
    return safeDateValue(left.dateISO) - safeDateValue(right.dateISO);
  }
  const leftValue = String(left[column] ?? "");
  const rightValue = String(right[column] ?? "");
  return leftValue.localeCompare(rightValue, undefined, { sensitivity: "base", numeric: true });
}

export function collectFilterOptions(rows) {
  return {
    gyms: uniqueSorted(rows.map((row) => row.gym)),
    styles: uniqueSorted(rows.map((row) => row.style)),
    grades: uniqueSorted(rows.map((row) => row.grade)),
    climbTypes: uniqueSorted(rows.map((row) => row.climbType))
  };
}

function uniqueSorted(values) {
  return [...new Set(values.filter((value) => String(value || "").trim().length > 0))].sort((left, right) =>
    String(left).localeCompare(String(right), undefined, { sensitivity: "base" })
  );
}

function numberValue(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? String(parsed) : "";
}
