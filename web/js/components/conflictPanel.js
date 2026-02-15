export function renderConflictPanel(conflicts, { onKeepMine, onKeepServer } = {}) {
  const root = document.getElementById("conflict-panel");
  if (!root) {
    return;
  }

  const entries = Array.isArray(conflicts) ? conflicts.map(normalizeConflict) : [];
  if (entries.length === 0) {
    root.innerHTML = "";
    root.classList.add("hidden");
    return;
  }

  root.classList.remove("hidden");
  root.innerHTML = `
    <h3>Sync Conflicts</h3>
    <p>Latest push returned ${entries.length} conflict${entries.length === 1 ? "" : "s"}.</p>
    <ul class="conflicts">
      ${entries
        .map(
          (conflict) =>
            `<li class="conflict-item">
              <div><strong>${escapeHTML(conflict.entityLabel)}</strong> · ${escapeHTML(conflict.entityIdLabel)}</div>
              <div class="muted">${escapeHTML(conflict.reasonLabel)}${renderServerVersion(conflict.serverVersion)}</div>
              <div class="actions">
                <button class="btn primary" type="button" data-action="keep-mine" data-op-id="${escapeHTML(conflict.opId)}">Keep Mine</button>
                <button class="btn" type="button" data-action="keep-server" data-op-id="${escapeHTML(conflict.opId)}">Keep Server</button>
              </div>
            </li>`
        )
        .join("")}
    </ul>
  `;

  root.onclick = async (event) => {
    const button = event.target.closest("button[data-action][data-op-id]");
    if (!button) {
      return;
    }
    if (button.disabled) {
      return;
    }

    const conflict = entries.find((entry) => entry.opId === button.dataset.opId);
    if (!conflict) {
      return;
    }

    try {
      button.disabled = true;
      if (button.dataset.action === "keep-mine") {
        await onKeepMine?.(conflict);
        return;
      }

      if (button.dataset.action === "keep-server") {
        await onKeepServer?.(conflict);
      }
    } finally {
      button.disabled = false;
    }
  };
}

function normalizeConflict(raw) {
  const opId = normalizeIdentifier(raw?.opId);
  const entity = normalizeEntity(raw?.entity);
  const entityId = normalizeIdentifier(raw?.entityId);
  const serverVersion = Number.isFinite(raw?.serverVersion) ? Number(raw.serverVersion) : null;
  const reason = normalizeReason(raw?.reason);

  return {
    opId,
    entity,
    entityId,
    serverVersion,
    reason,
    entityLabel: humanizeEntity(entity),
    entityIdLabel: entityId.length > 8 ? entityId : "invalid-id",
    reasonLabel: humanizeReason(reason)
  };
}

function normalizeIdentifier(value) {
  const text = String(value || "").trim().toLowerCase();
  return text.length > 128 ? text.slice(0, 128) : text;
}

function normalizeEntity(value) {
  const normalized = normalizeIdentifier(value);
  const known = new Set([
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
  ]);
  return known.has(normalized) ? normalized : "unknown_entity";
}

function normalizeReason(value) {
  const normalized = normalizeIdentifier(value);
  return normalized.length > 0 ? normalized : "unknown_conflict";
}

function humanizeEntity(entity) {
  const labels = {
    unknown_entity: "Unknown Item",
    plan_kinds: "Plan Kinds",
    day_types: "Training Days",
    plans: "Training Plans",
    plan_days: "Plan Days",
    activities: "Activities",
    training_types: "Training Types",
    exercises: "Exercises",
    boulder_combinations: "Combinations",
    boulder_combination_exercises: "Combination Exercises",
    sessions: "Sessions",
    session_items: "Session Entries",
    timer_templates: "Timer Templates",
    timer_intervals: "Timer Intervals",
    timer_sessions: "Timer Sessions",
    timer_laps: "Timer Laps",
    climb_entries: "Climb Entries",
    climb_styles: "Climbing Styles",
    climb_gyms: "Gyms"
  };
  return labels[entity] || "Unknown Item";
}

function humanizeReason(reason) {
  switch (reason) {
    case "version_mismatch":
      return "This item changed on another device.";
    case "invalid_payload":
      return "The update payload is invalid.";
    case "update_failed":
      return "Server rejected the update.";
    case "insert_failed":
      return "Server rejected the new record.";
    case "fetch_failed":
      return "Unable to load current server data.";
    default:
      return "A sync conflict needs your decision.";
  }
}

function escapeHTML(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function renderServerVersion(version) {
  if (typeof version !== "number") {
    return "";
  }
  return ` · server v${version}`;
}
