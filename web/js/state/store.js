const ENTITY_NAMES = [
  "plan_kinds",
  "day_types",
  "plans",
  "plan_days",
  "activities",
  "training_types",
  "exercises",
  "boulder_combinations",
  "boulder_combination_exercises",
  "sessions",
  "session_items",
  "timer_templates",
  "timer_intervals",
  "timer_sessions",
  "timer_laps",
  "climb_entries",
  "climb_styles",
  "climb_gyms"
];

export function createSyncStore() {
  const records = Object.fromEntries(ENTITY_NAMES.map((name) => [name, new Map()]));

  function reset() {
    for (const name of ENTITY_NAMES) {
      records[name].clear();
    }
  }

  function applyPullChanges(changes) {
    for (const change of changes || []) {
      const bucket = records[change.entity];
      if (!bucket) {
        continue;
      }

      if (change.type === "delete") {
        const existing = bucket.get(change.entityId);
        if (existing) {
          existing.is_deleted = true;
          if (typeof change.version === "number") {
            existing.version = change.version;
          }
          bucket.set(change.entityId, existing);
        } else {
          bucket.set(change.entityId, {
            id: change.entityId,
            version: typeof change.version === "number" ? change.version : 0,
            is_deleted: true
          });
        }
        continue;
      }

      if (change.type === "upsert" && change.doc?.id) {
        bucket.set(change.doc.id, normalizeDoc(change.doc));
      }
    }
  }

  function upsertLocal(entity, doc) {
    const bucket = records[entity];
    if (!bucket || !doc?.id) {
      return;
    }
    const existing = bucket.get(doc.id) || {};
    bucket.set(doc.id, normalizeDoc({ ...existing, ...doc }));
  }

  function get(entity, id) {
    return records[entity]?.get(id) || null;
  }

  function active(entity) {
    const values = [...(records[entity]?.values() || [])].filter((row) => !row.is_deleted);
    return values.sort(sortByNameThenDate);
  }

  function all(entity) {
    return [...(records[entity]?.values() || [])].sort(sortByNameThenDate);
  }

  function version(entity, id) {
    return Number(get(entity, id)?.version || 0);
  }

  return {
    applyPullChanges,
    upsertLocal,
    get,
    active,
    all,
    version,
    reset
  };
}

function normalizeDoc(doc) {
  return {
    ...doc,
    version: Number(doc.version || 0),
    is_deleted: Boolean(doc.is_deleted)
  };
}

function sortByNameThenDate(left, right) {
  const leftName = String(left.name || "");
  const rightName = String(right.name || "");
  const byName = leftName.localeCompare(rightName, undefined, { sensitivity: "base" });
  if (byName !== 0) {
    return byName;
  }

  const leftDate = String(left.updated_at_server || "");
  const rightDate = String(right.updated_at_server || "");
  return leftDate.localeCompare(rightDate);
}
